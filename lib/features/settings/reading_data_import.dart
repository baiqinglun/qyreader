/// 阅读数据 JSON 导入（单本）。
///
/// 从「导出阅读数据」生成的 `qyreader-reading-data` JSON 里找到目标书的
/// 条目，把进度 / 划线笔记 / 书签 / 每日阅读时长合并进本机这本书：
/// - 进度只在本地更低时写（locator 原样保留，重新打开能回到原位置）；
/// - 划线按原文收敛空白去重，note 走 `setNote`；
/// - 书签按 locator JSON 原文去重；
/// - 每日时长当天已有累计 ≥ 导入值就跳过，低于 10 秒的天跳过；
///   整体幂等，重复导入不会产生重复数据。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/entities/annotation.dart';
import '../../domain/entities/book.dart';
import '../../domain/repositories/annotation_repository.dart';
import '../../domain/repositories/progress_repository.dart';
import '../../domain/repositories/stats_repository.dart';

/// 一本书的导入数据（从 JSON 解析出来）。
class ReadingDataBookEntry {
  ReadingDataBookEntry._({
    required this.title,
    required this.author,
    required this.progressMap,
    required this.annotations,
    required this.bookmarks,
    required this.dailyDurations,
  });

  /// 书名。
  final String title;

  /// 作者（可能为空）。
  final String author;

  /// `progress` 原始对象（含 percent / locator / furthest…）。
  final Map<String, dynamic>? progressMap;

  /// `annotations` 原始数组。
  final List<Map<String, dynamic>> annotations;

  /// `bookmarks` 原始数组。
  final List<Map<String, dynamic>> bookmarks;

  /// `reading.dailyDurations`（day → durationMs）。
  final Map<String, int> dailyDurations;

  /// 进度百分比 0..1；没有进度返回 null。
  double? get percent =>
      (progressMap?['percent'] as num?)?.toDouble().clamp(0.0, 1.0);
}

/// 解析 `qyreader-reading-data` JSON；格式不对抛 [FormatException]。
List<ReadingDataBookEntry> parseReadingDataJson(String raw) {
  final root = jsonDecode(raw);
  if (root is! Map<String, dynamic>) {
    throw const FormatException('不是 JSON 对象');
  }
  if (root['format'] != 'qyreader-reading-data') {
    throw const FormatException('不是 QYReader 导出的阅读数据');
  }
  final books = root['books'];
  if (books is! List) {
    throw const FormatException('缺少 books 数组');
  }
  return [
    for (final item in books)
      if (item is Map<String, dynamic>)
        _parseEntry(item)
      else
        throw const FormatException('books 里有非对象条目'),
  ];
}

ReadingDataBookEntry _parseEntry(Map<String, dynamic> item) {
  final title = (item['title'] as String?)?.trim() ?? '';
  if (title.isEmpty) {
    throw const FormatException('书籍条目缺少书名');
  }
  final reading = item['reading'];
  final daily = <String, int>{};
  if (reading is Map<String, dynamic>) {
    final list = reading['dailyDurations'];
    if (list is List) {
      for (final row in list) {
        if (row is! Map<String, dynamic>) continue;
        final day = row['day'] as String?;
        final ms = (row['durationMs'] as num?)?.toInt() ?? 0;
        if (day != null && day.isNotEmpty && ms > 0) daily[day] = ms;
      }
    }
  }
  return ReadingDataBookEntry._(
    title: title,
    author: (item['author'] as String?)?.trim() ?? '',
    progressMap: item['progress'] is Map<String, dynamic>
        ? item['progress'] as Map<String, dynamic>
        : null,
    annotations: [
      for (final a in item['annotations'] ?? const [])
        if (a is Map<String, dynamic>) a,
    ],
    bookmarks: [
      for (final b in item['bookmarks'] ?? const [])
        if (b is Map<String, dynamic>) b,
    ],
    dailyDurations: daily,
  );
}

/// 书名规范化（去书名号 / 空白），跨设备匹配用。
String normalizeReadingDataTitle(String title) =>
    title.replaceAll(RegExp(r'[《》\s]'), '').trim();

/// 在导入数据里找目标书的条目：书名规范化相等，作者双方非空时需相等。
ReadingDataBookEntry? matchReadingDataEntry(
  List<ReadingDataBookEntry> entries,
  Book book,
) {
  final want = normalizeReadingDataTitle(book.title);
  if (want.isEmpty) return null;
  for (final entry in entries) {
    if (normalizeReadingDataTitle(entry.title) != want) continue;
    final have = book.author?.trim() ?? '';
    final wantAuthor = entry.author.trim();
    if (have.isNotEmpty && wantAuthor.isNotEmpty && have != wantAuthor) {
      continue;
    }
    return entry;
  }
  return null;
}

/// 导入结果（给完成提示）。
class ReadingDataImportSummary {
  /// 创建。
  ReadingDataImportSummary({
    this.notesAdded = 0,
    this.notesSkipped = 0,
    this.bookmarksAdded = 0,
    this.bookmarksSkipped = 0,
    this.progressApplied = false,
    this.daysAdded = 0,
    this.daysSkipped = 0,
  });

  /// 新增的划线 / 笔记条数。
  int notesAdded = 0;

  /// 因本地已有同原文而跳过的笔记条数。
  int notesSkipped = 0;

  /// 新增的书签数。
  int bookmarksAdded = 0;

  /// 因本地已有同位置书签而跳过的书签数。
  int bookmarksSkipped = 0;

  /// 是否写入了阅读进度。
  bool progressApplied = false;

  /// 导入的阅读天数。
  int daysAdded = 0;

  /// 跳过的天数（当天已有更长记录 / 低于会话门槛）。
  int daysSkipped = 0;

  /// 是否有任何变化。
  bool get hasChanges =>
      notesAdded > 0 || bookmarksAdded > 0 || progressApplied || daysAdded > 0;

  /// 摘要文案。
  String get label {
    final parts = <String>[
      if (progressApplied) '进度',
      if (notesAdded > 0) '笔记 $notesAdded 条',
      if (bookmarksAdded > 0) '书签 $bookmarksAdded 个',
      if (daysAdded > 0) '阅读记录 $daysAdded 天',
    ];
    return parts.isEmpty ? '本机数据已是最新，没有变化' : parts.join(' · ');
  }
}

String locatorJsonOf(Object? raw) => switch (raw) {
  Map<String, dynamic>() => jsonEncode(raw),
  Map() => jsonEncode(Map<String, dynamic>.from(raw)),
  String() => raw.trim(),
  _ => '',
};

int? _intOf(Object? raw) => (raw as num?)?.toInt();

/// 执行导入（只处理一本书的条目）。抛出的异常由调用方提示。
Future<ReadingDataImportSummary> importReadingDataIntoBook({
  required ReadingDataBookEntry entry,
  required Book book,
  required AnnotationRepository annotationRepo,
  required ProgressRepository progressRepo,
  required StatsRepository statsRepo,
}) async {
  final summary = ReadingDataImportSummary();

  // ---- 阅读进度：只在本地更低时写，locator 原样保留 ----
  final percent = entry.percent;
  if (percent != null && percent > 0.001) {
    final local = await progressRepo.getProgress(book.id);
    final localPercent = local?.percent ?? 0;
    if (percent > localPercent + 0.001) {
      final locatorJson = locatorJsonOf(entry.progressMap?['locator']);
      if (locatorJson.isNotEmpty) {
        await progressRepo.saveProgress(
          bookId: book.id,
          locator: locatorJson,
          percent: percent,
        );
        summary.progressApplied = true;
      }
    }
  }

  // ---- 划线 / 笔记：按原文收敛空白去重 ----
  final existingNotes = {
    for (final a in await annotationRepo.listForBook(book.id))
      _noteKey(a.quotedText ?? ''),
  };
  for (final row in entry.annotations) {
    final quote = (row['quote'] as String?) ?? '';
    final key = _noteKey(quote);
    if (key.isEmpty || existingNotes.contains(key)) {
      summary.notesSkipped++;
      continue;
    }
    final startMap = row['locatorStart'];
    final chapterIndex = startMap is Map
        ? _intOf(startMap['chapterIndex'])
        : null;
    final offset = startMap is Map ? _intOf(startMap['offset']) : null;
    final offsetEnd = startMap is Map ? _intOf(startMap['offsetEnd']) : null;
    if (chapterIndex == null || offset == null) {
      // 没有可用的原生锚点（如纯 CFI / 损坏数据），跳过避免落进错误位置。
      summary.notesSkipped++;
      continue;
    }
    final href = startMap is Map ? startMap['href'] as String? : null;
    final created = await annotationRepo.addHighlight(
      bookId: book.id,
      cfiRange: '@$chapterIndex:$offset:${offsetEnd ?? offset}',
      color: AnnotationColor.fromToken((row['color'] as String?) ?? 'yellow'),
      quotedText: quote,
      href: href,
      chapterIndex: chapterIndex,
      offset: offset,
      offsetEnd: offsetEnd,
      type: AnnotationType.fromToken((row['type'] as String?) ?? 'highlight'),
    );
    final note = (row['note'] as String?)?.trim();
    if (note != null && note.isNotEmpty) {
      await annotationRepo.setNote(created.id, note);
    }
    existingNotes.add(key);
    summary.notesAdded++;
  }

  // ---- 书签：按 locator JSON 原文去重 ----
  final existingBookmarks = {
    for (final b in await annotationRepo.listBookmarks(book.id))
      b.locator.trim(),
  };
  for (final row in entry.bookmarks) {
    final locatorJson = locatorJsonOf(row['locator']);
    if (locatorJson.isEmpty) {
      summary.bookmarksSkipped++;
      continue;
    }
    if (existingBookmarks.contains(locatorJson.trim())) {
      summary.bookmarksSkipped++;
      continue;
    }
    final label = (row['label'] as String?)?.trim();
    await annotationRepo.addBookmark(
      bookId: book.id,
      locatorJson: locatorJson,
      label: (label == null || label.isEmpty) ? null : label,
    );
    existingBookmarks.add(locatorJson.trim());
    summary.bookmarksAdded++;
  }

  // ---- 每日阅读时长：当天已有累计 ≥ 导入值就跳过（重复导入不叠加） ----
  if (entry.dailyDurations.isNotEmpty) {
    final existing = await statsRepo.bookDailyDurations(book.id, days: 3660);
    for (final dayEntry in entry.dailyDurations.entries) {
      final seconds = dayEntry.value ~/ 1000;
      if (seconds < 10) {
        summary.daysSkipped++;
        continue;
      }
      final dayDate = _dayDate(dayEntry.key);
      if (dayDate == null) {
        summary.daysSkipped++;
        continue;
      }
      // bookDailyDurations 返回的是毫秒，与导入值同一单位比较。
      if ((existing[dayEntry.key] ?? 0) >= dayEntry.value) {
        summary.daysSkipped++;
        continue;
      }
      final noon = dayDate.millisecondsSinceEpoch;
      await statsRepo.recordSession(
        bookId: book.id,
        startedAt: noon,
        endedAt: noon + seconds * 1000,
        charsRead: 0,
        countedDurationMs: seconds * 1000,
      );
      summary.daysAdded++;
    }
  }
  return summary;
}

DateTime? _dayDate(String day) {
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(day.trim());
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    12,
  );
}

/// 笔记去重键：原文收敛空白。
String _noteKey(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// 长按 → 导入阅读数据：选 JSON → 找到这本书的条目 → 确认 → 合并落库。
Future<void> importBookReadingData(
  BuildContext context,
  WidgetRef ref,
  Book book,
) async {
  final picked = await _pickJsonFile();
  if (picked == null || picked.isEmpty) return;
  final List<ReadingDataBookEntry> entries;
  try {
    entries = parseReadingDataJson(utf8.decode(picked, allowMalformed: true));
  } on FormatException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('文件格式不对：${e.message}')));
    return;
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('文件读取失败')));
    return;
  }
  final entry = matchReadingDataEntry(entries, book);
  if (entry == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('文件里没有找到《${book.title}》的数据')));
    return;
  }

  final annotationRepo = await ref.read(annotationRepositoryProvider.future);
  final progressRepo = await ref.read(progressRepositoryProvider.future);
  final statsRepo = await ref.read(statsRepositoryProvider.future);
  final summary = await importReadingDataIntoBook(
    entry: entry,
    book: book,
    annotationRepo: annotationRepo,
    progressRepo: progressRepo,
    statsRepo: statsRepo,
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('《${book.title}》：${summary.label}')));
}

/// 挑选 JSON 文件，返回字节；取消返回 null。
Future<Uint8List?> _pickJsonFile() async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['json'],
    withData: true,
  );
  return picked?.files.single.bytes;
}
