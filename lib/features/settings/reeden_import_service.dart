/// Reeden 导入服务：解析后的书籍数据 → 差异对比 + 落库。
///
/// - 对比（[compareReedenBooks]）：逐本算出「新增 / 更新 / 一致」与具体
///   差异（书评 / 评分 / 状态 / 进度 / 划线新增数 / 阅读天数），供导入页
///   逐本展示「哪些信息需要更新」；
/// - 落库（[importReedenData]）只处理选中的书：
///   - 新书：生成占位 EPUB（复用微信读书导入的 [buildWeReadEpub]）走
///     `importFromFile` 入库；已有书：按书名（去书名号 / 空白）+ 作者
///     （双方非空才比）匹配合并，个人化字段只在本地为空时补；
///   - 阅读状态按最近阅读时间 LWW；进度只在本地更低时写；
///   - 划线 → annotations，按原文去重，**位置用原文全文搜索定位**
///     （复用微信读书的 `locateWeReadNote`，找不到时退章首兜底）；
///   - 每日时长 → reading_sessions（同天已有累计 ≥ 导入值跳过，
///     低于 10 秒的天跳过）；重复导入整体幂等。
library;

import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import '../../domain/entities/annotation.dart';
import '../../domain/entities/book.dart';
import '../../domain/repositories/annotation_repository.dart';
import '../../domain/repositories/book_repository.dart';
import '../../domain/repositories/progress_repository.dart';
import '../../domain/repositories/stats_repository.dart';
import '../../features/reader/native/native_chapter_source.dart';
import 'reeden_import.dart';
import 'weread/weread_anchor.dart';
import 'weread/weread_epub.dart';
import 'weread/weread_models.dart';

/// 一本书的对比结果（导入页逐本展示）。
class ReedenBookDiff {
  ReedenBookDiff({
    required this.data,
    required this.local,
    required this.reviewDiff,
    required this.ratingDiff,
    required this.statusDiff,
    required this.progressDiff,
    required this.tagsDiff,
    required this.categoryDiff,
    required this.notesNew,
    required this.daysNew,
  });

  /// 导入数据。
  final ReedenBookData data;

  /// 本地匹配到的书；null = 新增。
  final ShelfItem? local;

  final bool reviewDiff;
  final bool ratingDiff;
  final bool statusDiff;
  final bool progressDiff;
  final bool tagsDiff;
  final bool categoryDiff;

  /// 本机还没有的划线条数。
  final int notesNew;

  /// 本机还没有记录的阅读天数。
  final int daysNew;

  /// 对比状态：新增 / 更新 / 一致。
  ReedenDiffState get state => local == null
      ? ReedenDiffState.create
      : (hasUpdates ? ReedenDiffState.update : ReedenDiffState.same);

  /// 是否有要更新的内容。
  bool get hasUpdates =>
      reviewDiff ||
      ratingDiff ||
      statusDiff ||
      progressDiff ||
      tagsDiff ||
      categoryDiff ||
      notesNew > 0 ||
      daysNew > 0;

  /// 摘要（导入页副标题）。
  List<String> get updateLines {
    final lines = <String>[];
    if (reviewDiff && data.reviews.isNotEmpty) lines.add('书评 ${data.reviews.length} 条');
    if (ratingDiff && data.rating != null) lines.add('评分 ${data.rating}');
    if (statusDiff && data.state != null) {
      lines.add('状态 ${_statusLabel(data.state!.statusRaw)}');
    }
    if (progressDiff && data.state != null) {
      lines.add('进度 ${(data.state!.progress * 100).toStringAsFixed(1)}%');
    }
    if (tagsDiff && data.tags.isNotEmpty) lines.add('标签 ${data.tags.length} 个');
    if (categoryDiff && data.category.isNotEmpty) lines.add('分类 ${data.category}');
    if (notesNew > 0) lines.add('划线 $notesNew 条');
    if (daysNew > 0) lines.add('阅读记录 $daysNew 天');
    return lines;
  }
}

/// 对比状态。
enum ReedenDiffState { create, update, same }

/// 对比状态文案。
String reedenDiffLabel(ReedenDiffState state) =>
    switch (state) { ReedenDiffState.create => '新增', ReedenDiffState.update => '更新', ReedenDiffState.same => '一致' };

/// 逐本对比：本地已有 / 差异字段 / 新增划线与天数。
Future<List<ReedenBookDiff>> compareReedenBooks(
  List<ReedenBookData> books, {
  required BookRepository bookRepo,
  required AnnotationRepository annotationRepo,
  required StatsRepository statsRepo,
}) async {
  final shelf = await bookRepo.watchShelf().first;
  final out = <ReedenBookDiff>[];
  for (final data in books) {
    final local = _matchShelf(shelf, data.title, data.author);
    var reviewDiff = false;
    var ratingDiff = false;
    var statusDiff = false;
    var progressDiff = false;
    var tagsDiff = false;
    var categoryDiff = false;
    var notesNew = 0;
    var daysNew = 0;
    if (local == null) {
      reviewDiff = data.reviews.isNotEmpty;
      ratingDiff = data.rating != null;
      statusDiff = data.state != null;
      progressDiff = data.state != null && data.state!.progress > 0.001;
      tagsDiff = data.tags.isNotEmpty;
      categoryDiff = data.category.isNotEmpty;
      notesNew = data.notes.length;
      daysNew = data.records.where((r) => r.seconds >= 10).length;
    } else {
      final book = local.book;
      reviewDiff =
          data.reviews.isNotEmpty && (book.review ?? '').trim().isEmpty;
      final importedRating = data.rating;
      ratingDiff =
          importedRating != null &&
          importedRating >= 1 &&
          book.rating == null;
      final state = data.state;
      if (state != null) {
        statusDiff =
            _statusOf(state.statusRaw) != null &&
            (state.lastReadMs > (book.lastOpenedAt ?? 0) ||
                book.readStatus != _statusOf(state.statusRaw));
        progressDiff =
            state.progress > 0.001 &&
            state.progress > (local.percent + 0.001);
      }
      tagsDiff = book.tags.isEmpty && data.tags.isNotEmpty;
      categoryDiff = (book.category ?? '').isEmpty && data.category.isNotEmpty;
      final existingNotes = {
        for (final a in await annotationRepo.listForBook(book.id))
          _noteKey(a.quotedText ?? ''),
      };
      notesNew = data.notes
          .where((n) => !existingNotes.contains(_noteKey(n.content)))
          .length;
      final daily = await statsRepo.bookDailyDurations(book.id, days: 3660);
      daysNew = data.records
          .where(
            (r) => r.seconds >= 10 && (daily[_normalizeDay(r.day)] ?? 0) < r.seconds,
          )
          .length;
    }
    out.add(
      ReedenBookDiff(
        data: data,
        local: local,
        reviewDiff: reviewDiff,
        ratingDiff: ratingDiff,
        statusDiff: statusDiff,
        progressDiff: progressDiff,
        tagsDiff: tagsDiff,
        categoryDiff: categoryDiff,
        notesNew: notesNew,
        daysNew: daysNew,
      ),
    );
  }
  return out;
}

/// 导入结果（给导入完成提示）。
class ReedenImportSummary {
  ReedenImportSummary({
    this.created = 0,
    this.merged = 0,
    this.reviews = 0,
    this.notes = 0,
    this.notesSkipped = 0,
    this.notesLocated = 0,
    this.notesFallback = 0,
    this.days = 0,
    this.daysSkipped = 0,
  });

  /// 新建的书数。
  int created = 0;

  /// 合并进已有书的数量。
  int merged = 0;

  /// 导入的书评条数。
  int reviews = 0;

  /// 导入的划线 / 笔记条数。
  int notes = 0;

  /// 因本地已有同原文而跳过的笔记条数。
  int notesSkipped = 0;

  /// 按原文在本机定位到精确位置的笔记条数。
  int notesLocated = 0;

  /// 没找到原文、退章首兜底的笔记条数。
  int notesFallback = 0;

  /// 导入的阅读天数。
  int days = 0;

  /// 因当天已有累计时长而跳过的天数。
  int daysSkipped = 0;

  @override
  String toString() =>
      '新建 $created 本 · 合并 $merged 本 · 书评 $reviews 条 · 划线 $notes 条'
      '（定位 $notesLocated · 章首兜底 $notesFallback）· 阅读记录 $days 天';
}

/// 执行导入。抛出的异常由调用方提示。
Future<ReedenImportSummary> importReedenData(
  List<ReedenBookData> books, {
  required BookRepository bookRepo,
  required AnnotationRepository annotationRepo,
  required StatsRepository statsRepo,
  required ProgressRepository progressRepo,
  required String tempDir,

  /// 加载某本书的本机章节文本（原文全文搜索定位用）；失败返回空表。
  required Future<List<NativeChapter>> Function(Book book) loadChapters,
}) async {
  final summary = ReedenImportSummary();
  final shelf = await bookRepo.watchShelf().first;
  for (final data in books) {
    final match = _matchShelf(shelf, data.title, data.author);
    final Book book;
    if (match == null) {
      final created = await _createPlaceholderBook(bookRepo, tempDir, data);
      if (created == null) continue;
      book = created;
      summary.created++;
    } else {
      book = match.book;
      summary.merged++;
    }
    final isNew = match == null;

    // 个人化：新书全量写入；已有书只在本地为空时补，不覆盖用户自己写的。
    final reviewText = data.reviews.map((r) => r.content).join('\n\n');
    final targetRating = data.rating?.round().clamp(1, 5).toInt();
    if (targetRating != null && (isNew || book.rating == null)) {
      await bookRepo.setPersonalization(book.id, rating: targetRating);
    }
    if ((isNew || (book.review ?? '').trim().isEmpty) && reviewText.isNotEmpty) {
      await bookRepo.setPersonalization(book.id, review: reviewText);
      summary.reviews += data.reviews.length;
    }
    if (isNew || book.tags.isEmpty) {
      final tags = [...data.tags];
      if (data.category.isNotEmpty && !tags.contains(data.category)) {
        tags.add(data.category);
      }
      if (tags.isNotEmpty) {
        await bookRepo.setPersonalization(
          book.id,
          tags: {...book.tags, ...tags}.toList(),
        );
      }
    }
    if ((isNew || (book.category ?? '').isEmpty) && data.category.isNotEmpty) {
      await bookRepo.setPersonalization(book.id, category: data.category);
    }

    // 阅读状态：按最近阅读时间 LWW（本地更晚保留本地）。
    final state = data.state;
    if (state != null) {
      final localMs = book.lastOpenedAt ?? 0;
      final status = _statusOf(state.statusRaw);
      if (state.lastReadMs > localMs) {
        await bookRepo.applyReadingState(
          book.id,
          readStatus: status,
          lastOpenedAt: state.lastReadMs,
          finishedAt: state.finishMs > 0 ? state.finishMs : null,
        );
      } else if (state.finishMs > 0 && (book.finishedAt ?? 0) < state.finishMs) {
        await bookRepo.applyReadingState(book.id, finishedAt: state.finishMs);
      }
      if (state.progress > 0.001) {
        final local = await progressRepo.getProgress(book.id);
        final localPercent = local?.percent ?? 0;
        if (state.progress > localPercent + 0.001) {
          await progressRepo.saveExternalProgress(
            bookId: book.id,
            percent: state.progress,
          );
        }
      }
    }

    // 划线 / 笔记：按原文去重；位置用原文全文搜索定位，找不到退章首。
    if (data.notes.isNotEmpty) {
      List<NativeChapter> chapters = const <NativeChapter>[];
      try {
        chapters = await loadChapters(book);
      } catch (_) {
        chapters = const <NativeChapter>[];
      }
      final existing = {
        for (final a in await annotationRepo.listForBook(book.id))
          _noteKey(a.quotedText ?? ''),
      };
      for (final note in data.notes) {
        final key = _noteKey(note.content);
        if (key.isEmpty || existing.contains(key)) {
          summary.notesSkipped++;
          continue;
        }
        var anchor = locateWeReadNote(
          chapters,
          WeReadNote(
            id: 'reeden-note',
            bookId: book.id,
            quote: note.content,
            chapterIdx: note.sectionIndex,
            chapterName: note.sectionName,
          ),
        );
        anchor ??= locateWeReadNoteFallback(
          chapters,
          WeReadNote(id: 'reeden-note', bookId: book.id, quote: note.content),
        );
        if (anchor == null) {
          summary.notesSkipped++;
          continue;
        }
        if (anchor.end > anchor.start) {
          summary.notesLocated++;
        } else {
          summary.notesFallback++;
        }
        final created = await annotationRepo.addHighlight(
          bookId: book.id,
          cfiRange: '@${anchor.chapterIndex}:${anchor.start}:${anchor.end}',
          color: _colorOf(note.color),
          quotedText: note.content,
          href: anchor.href,
          chapterIndex: anchor.chapterIndex,
          offset: anchor.start,
          offsetEnd: anchor.end,
          type: note.type == 'highlight'
              ? AnnotationType.highlight
              : AnnotationType.underline,
        );
        final comment = (note.comment ?? '').trim();
        if (comment.isNotEmpty) {
          await annotationRepo.setNote(created.id, comment);
        }
        existing.add(key);
        summary.notes++;
      }
    }

    // 每日阅读时长：当天已有累计 ≥ 导入值就跳过（重复导入不叠加）。
    if (data.records.isNotEmpty) {
      final existing = await statsRepo.bookDailyDurations(book.id, days: 3660);
      for (final record in data.records) {
        if (record.seconds < 10) {
          summary.daysSkipped++;
          continue;
        }
        final day = _normalizeDay(record.day);
        if (day == null) {
          summary.daysSkipped++;
          continue;
        }
        if ((existing[day] ?? 0) >= record.seconds) {
          summary.daysSkipped++;
          continue;
        }
        final dayDate = DateTime(
          int.parse(day.substring(0, 4)),
          int.parse(day.substring(5, 7)),
          int.parse(day.substring(8, 10)),
          12,
        );
        await statsRepo.recordSession(
          bookId: book.id,
          startedAt: dayDate.millisecondsSinceEpoch,
          endedAt: dayDate.millisecondsSinceEpoch + record.seconds * 1000,
          charsRead: record.words,
          countedDurationMs: record.seconds * 1000,
        );
        summary.days++;
      }
    }
  }
  return summary;
}

/// 已读状态映射。
BookReadStatus? _statusOf(String raw) => switch (raw.toLowerCase()) {
  'reading' || 'readingnow' || 'in_progress' => BookReadStatus.reading,
  'finished' || 'finish' || 'completed' => BookReadStatus.finished,
  'unread' || 'not_started' => BookReadStatus.unread,
  'dropped' || 'abandoned' || 'give_up' => BookReadStatus.dropped,
  _ => null,
};

/// 状态文案。
String _statusLabel(String raw) => switch (_statusOf(raw)) {
  BookReadStatus.reading => '在读',
  BookReadStatus.finished => '已读',
  BookReadStatus.dropped => '弃读',
  BookReadStatus.unread => '未读',
  _ => raw,
};

/// Reeden 颜色 → 语义色（red 系映射 rose，未知回退 yellow）。
AnnotationColor _colorOf(String raw) => switch (raw.toLowerCase()) {
  'red' || 'rose' || 'pink' => AnnotationColor.rose,
  'green' => AnnotationColor.green,
  'blue' => AnnotationColor.blue,
  'yellow' || 'orange' => AnnotationColor.yellow,
  _ => AnnotationColor.yellow,
};

/// 笔记去重键：原文收敛空白。
String _noteKey(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// 书名规范化：去书名号 / 空白，便于匹配。
String _normalizeTitle(String title) =>
    title.replaceAll(RegExp(r'[《》\s]'), '').trim();

/// 在书架上找同书：书名规范化相等，作者双方非空时需相等。
ShelfItem? _matchShelf(List<ShelfItem> shelf, String title, String author) {
  final want = _normalizeTitle(title);
  if (want.isEmpty) return null;
  for (final item in shelf) {
    if (_normalizeTitle(item.book.title) != want) continue;
    final have = (item.book.author ?? '').trim();
    final wantAuthor = author.trim();
    if (have.isNotEmpty && wantAuthor.isNotEmpty && have != wantAuthor) {
      continue;
    }
    return item;
  }
  return null;
}

/// 生成占位 EPUB 并入库（无书源文件的「记录型」书：书评 / 笔记 / 时长的载体）。
Future<Book?> _createPlaceholderBook(
  BookRepository bookRepo,
  String tempDir,
  ReedenBookData data,
) async {
  final key = crypto.sha256
      .convert('reeden|${data.title}|${data.author}'.codeUnits)
      .toString()
      .substring(0, 16);
  final bytes = buildWeReadEpub(
    bookId: 'reeden-$key',
    title: data.title,
    author: data.author.isEmpty ? null : data.author,
    description: data.description.isEmpty ? null : data.description,
    category: data.category.isEmpty ? null : data.category,
  );
  final file = File('$tempDir/reeden-$key.epub');
  await file.writeAsBytes(bytes);
  final result = await bookRepo.importFromFile(
    file.path,
    returnExistingOnDuplicate: true,
  );
  return result.when(ok: (book) => book, failure: (_) => null);
}

/// 补零日期键（容错 2026-1-5 这类非标准日期）。
String? _normalizeDay(String day) {
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(day.trim());
  if (m == null) return null;
  final y = m.group(1)!;
  final mo = m.group(2)!.padLeft(2, '0');
  final d = m.group(3)!.padLeft(2, '0');
  return '$y-$mo-$d';
}
