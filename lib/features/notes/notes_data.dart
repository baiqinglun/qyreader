/// 「笔记回顾」数据整理：按书汇总、漫游卡片、搜索与格式化。
///
/// 划线来自 `Annotation`，书签来自 `Bookmark`；阅读时长 / 字数复用
/// `StatsRepository.bookTotals()` 的汇总结果。
library;

import 'dart:convert';

import '../../domain/entities/annotation.dart';
import '../../domain/entities/book.dart';
import '../../domain/entities/bookmark.dart';
import '../../domain/entities/reading_stats.dart';
import '../my_reading/my_reading_data.dart';

/// 笔记类型（漫游页顶部筛选）。
enum NoteKind {
  /// 划线 / 下划线 / 依附于划线的笔记。
  highlight('划线'),

  /// 书签。
  bookmark('书签');

  const NoteKind(this.label);

  /// 展示名。
  final String label;
}

/// 书目列表排序。
enum NotesBookSort {
  /// 最近有笔记的在前。
  recent('最近笔记'),

  /// 笔记条数多的在前。
  count('笔记数量'),

  /// 按书名。
  title('书名');

  const NotesBookSort(this.label);

  /// 展示名。
  final String label;
}

/// 有笔记的一本书（概览卡片）。
class NotesBookSummary {
  const NotesBookSummary({
    required this.item,
    required this.highlightCount,
    required this.bookmarkCount,
    required this.latestAt,
    required this.durationMs,
    required this.charsRead,
  });

  /// 书架条目（书籍 + 进度）。
  final ShelfItem item;

  /// 划线数。
  final int highlightCount;

  /// 书签数。
  final int bookmarkCount;

  /// 最近一条笔记时间。
  final DateTime latestAt;

  /// 累计阅读时长（ms）。
  final int durationMs;

  /// 累计字符数。
  final int charsRead;

  /// 总笔记条数。
  int get count => highlightCount + bookmarkCount;

  Book get book => item.book;
}

/// 漫游里的一张笔记卡片。
class NoteEntry {
  const NoteEntry({
    required this.id,
    required this.kind,
    required this.bookId,
    required this.createdAt,
    this.quote,
    this.note,
    this.label,
    this.chapterIndex,
    this.colorToken,
  });

  /// 标注 / 书签 id。
  final String id;

  /// 类型。
  final NoteKind kind;

  /// 所属书。
  final String bookId;

  /// 创建时间。
  final DateTime createdAt;

  /// 划线原文 / 书签标签。
  final String? quote;

  /// 用户写的想法。
  final String? note;

  /// 标注色 token（yellow / green / blue / rose；书签为 null，分享卡片用）。
  final String? colorToken;

  /// 书签标签。
  final String? label;

  /// 章索引（书签定位兜底）。
  final int? chapterIndex;
}

/// 有笔记的书（默认按最近笔记倒序）。
List<NotesBookSummary> notesBookSummaries({
  required List<ShelfItem> items,
  required List<Annotation> annotations,
  required List<Bookmark> bookmarks,
  required Map<String, BookReadingTotal> totals,
  NotesBookSort sort = NotesBookSort.recent,
  String query = '',
}) {
  final byBook = <String, List<int>>{};
  for (final a in annotations) {
    byBook.putIfAbsent(a.bookId, () => []).add(a.createdAt);
  }
  final bookmarkByBook = <String, List<int>>{};
  for (final b in bookmarks) {
    bookmarkByBook.putIfAbsent(b.bookId, () => []).add(b.createdAt);
  }
  final q = query.trim().toLowerCase();
  final out = <NotesBookSummary>[];
  for (final item in items) {
    final id = item.book.id;
    final highlights = byBook[id] ?? const <int>[];
    final marks = bookmarkByBook[id] ?? const <int>[];
    if (highlights.isEmpty && marks.isEmpty) continue;
    if (q.isNotEmpty && !_bookMatches(item.book, q, annotations, bookmarks)) {
      continue;
    }
    final times = [...highlights, ...marks]..sort();
    final total = totals[id];
    out.add(
      NotesBookSummary(
        item: item,
        highlightCount: highlights.length,
        bookmarkCount: marks.length,
        latestAt: DateTime.fromMillisecondsSinceEpoch(times.last),
        durationMs: total?.durationMs ?? 0,
        charsRead: total?.charsRead ?? 0,
      ),
    );
  }
  out.sort((a, b) {
    switch (sort) {
      case NotesBookSort.recent:
        return b.latestAt.compareTo(a.latestAt);
      case NotesBookSort.count:
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : b.latestAt.compareTo(a.latestAt);
      case NotesBookSort.title:
        return a.book.title.compareTo(b.book.title);
    }
  });
  return out;
}

bool _bookMatches(
  Book book,
  String q,
  List<Annotation> annotations,
  List<Bookmark> bookmarks,
) {
  if (book.title.toLowerCase().contains(q)) return true;
  if ((book.author ?? '').toLowerCase().contains(q)) return true;
  for (final a in annotations) {
    if (a.bookId != book.id) continue;
    if ((a.quotedText ?? '').toLowerCase().contains(q)) return true;
    if ((a.note ?? '').toLowerCase().contains(q)) return true;
  }
  for (final b in bookmarks) {
    if (b.bookId != book.id) continue;
    if ((b.label ?? '').toLowerCase().contains(q)) return true;
  }
  return false;
}

/// 当前筛选下的漫游卡片（新在前）；书不在书架里的笔记跳过。
List<NoteEntry> noteEntries({
  required List<ShelfItem> items,
  required List<Annotation> annotations,
  required List<Bookmark> bookmarks,
  NoteKind? kind,
  String? bookId,
}) {
  final ids = {for (final item in items) item.book.id};
  final out = <NoteEntry>[];
  if (kind == null || kind == NoteKind.highlight) {
    for (final a in annotations) {
      if (!ids.contains(a.bookId)) continue;
      if (bookId != null && a.bookId != bookId) continue;
      final quote = (a.quotedText ?? '').trim();
      final note = (a.note ?? '').trim();
      if (quote.isEmpty && note.isEmpty) continue;
      out.add(
        NoteEntry(
          id: a.id,
          kind: NoteKind.highlight,
          bookId: a.bookId,
          createdAt: DateTime.fromMillisecondsSinceEpoch(a.createdAt),
          quote: quote.isEmpty ? null : quote,
          note: note.isEmpty ? null : note,
          chapterIndex: a.chapterIndex,
          colorToken: a.color.token,
        ),
      );
    }
  }
  if (kind == null || kind == NoteKind.bookmark) {
    for (final b in bookmarks) {
      if (!ids.contains(b.bookId)) continue;
      if (bookId != null && b.bookId != bookId) continue;
      final label = (b.label ?? '').trim();
      out.add(
        NoteEntry(
          id: b.id,
          kind: NoteKind.bookmark,
          bookId: b.bookId,
          createdAt: DateTime.fromMillisecondsSinceEpoch(b.createdAt),
          quote: label.isEmpty ? '书签' : label,
          label: label.isEmpty ? null : label,
          chapterIndex: _chapterIndexOf(b.locator),
        ),
      );
    }
  }
  out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return out;
}

int? _chapterIndexOf(String locator) {
  try {
    final raw = jsonDecode(locator);
    if (raw is Map && raw['chapterIndex'] is num) {
      return (raw['chapterIndex'] as num).toInt();
    }
  } catch (_) {
    // 旧数据 / 非 JSON locator：不显示章号。
  }
  return null;
}

/// 卡片上的时间：`25/03/04 14:01`。
String noteTimeLabel(DateTime time) {
  final yy = (time.year % 100).toString().padLeft(2, '0');
  final mm = time.month.toString().padLeft(2, '0');
  final dd = time.day.toString().padLeft(2, '0');
  final hh = time.hour.toString().padLeft(2, '0');
  final min = time.minute.toString().padLeft(2, '0');
  return '$yy/$mm/$dd $hh:$min';
}

/// 概览卡片副标题：`已读 1 小时 34 分钟 · 4.2 万字`。
String notesReadLabel(int durationMs, int charsRead) =>
    '已读 ${formatReadingDuration(durationMs)} · '
    '${formatReadingChars(charsRead)}';
