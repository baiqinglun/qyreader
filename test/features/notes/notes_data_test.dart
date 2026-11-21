/// 「笔记回顾」数据整理：按书汇总、搜索、排序、漫游卡片。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/annotation.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/domain/entities/bookmark.dart';
import 'package:qy_reader/domain/entities/reading_stats.dart';
import 'package:qy_reader/features/notes/notes_data.dart';

Book _book(String id, String title, {String? author}) => Book(
  id: id,
  title: title,
  author: author,
  format: BookFormat.epub,
  filePath: '/tmp/$id.epub',
  fileSha256: id,
  fileSize: 1,
  addedAt: 0,
  updatedAt: 0,
  readStatus: BookReadStatus.reading,
  hlc: '0000000000000-00000-aaaaaaaa',
  deviceId: 'aaaaaaaa',
);

Annotation _annotation(
  String id,
  String bookId, {
  String? quote,
  String? note,
  required DateTime at,
  int? chapterIndex,
}) => Annotation(
  id: id,
  bookId: bookId,
  type: AnnotationType.highlight,
  color: AnnotationColor.yellow,
  locatorStart: '{}',
  locatorEnd: '{}',
  quotedText: quote,
  note: note,
  chapterIndex: chapterIndex,
  createdAt: at.millisecondsSinceEpoch,
  updatedAt: at.millisecondsSinceEpoch,
);

void main() {
  final b1 = ShelfItem(book: _book('b1', '苏东坡全传', author: '秦晓'), percent: 0.4);
  final b2 = ShelfItem(book: _book('b2', '沉默的大多数', author: '王小波'), percent: 1);
  final items = [b1, b2];
  final annotations = [
    _annotation(
      'a1',
      'b1',
      quote: '苏东坡就是有一种让自己开心的能力',
      at: DateTime(2025, 3, 4, 14, 1),
    ),
    _annotation(
      'a2',
      'b1',
      quote: '人间有味是清欢',
      note: '喜欢这句',
      at: DateTime(2025, 3, 3, 10),
    ),
    _annotation('a3', 'b2', quote: '沉默是一种生活方式', at: DateTime(2025, 3, 5, 9)),
  ];
  final bookmarks = [
    Bookmark(
      id: 'bm1',
      bookId: 'b1',
      locator: '{"chapterIndex":2}',
      label: '这里',
      createdAt: DateTime(2025, 3, 2, 8).millisecondsSinceEpoch,
    ),
  ];
  final totals = {
    'b1': const BookReadingTotal(
      bookId: 'b1',
      durationMs: 94 * 60 * 1000,
      charsRead: 42000,
    ),
    'b2': const BookReadingTotal(
      bookId: 'b2',
      durationMs: 36 * 60 * 1000,
      charsRead: 18000,
    ),
  };

  test('按书汇总笔记数与最近时间，默认最近笔记在前', () {
    final summaries = notesBookSummaries(
      items: items,
      annotations: annotations,
      bookmarks: bookmarks,
      totals: totals,
    );
    expect(summaries, hasLength(2));
    expect(summaries.first.book.id, 'b2');
    expect(summaries.first.count, 1);
    final s1 = summaries.firstWhere((s) => s.book.id == 'b1');
    expect(s1.highlightCount, 2);
    expect(s1.bookmarkCount, 1);
    expect(s1.count, 3);
    expect(s1.latestAt, DateTime(2025, 3, 4, 14, 1));
    expect(
      notesReadLabel(s1.durationMs, s1.charsRead),
      '已读 1 小时 34 分钟 · 4.2 万字',
    );
  });

  test('按笔记数量 / 书名排序', () {
    final byCount = notesBookSummaries(
      items: items,
      annotations: annotations,
      bookmarks: bookmarks,
      totals: totals,
      sort: NotesBookSort.count,
    );
    expect(byCount.first.book.id, 'b1');
    final byTitle = notesBookSummaries(
      items: items,
      annotations: annotations,
      bookmarks: bookmarks,
      totals: totals,
      sort: NotesBookSort.title,
    );
    expect(byTitle.first.book.id, 'b2'); // Unicode 排序「沉」<「苏」
  });

  test('搜索书名 / 作者 / 原文 / 想法', () {
    List<NotesBookSummary> search(String q) => notesBookSummaries(
      items: items,
      annotations: annotations,
      bookmarks: bookmarks,
      totals: totals,
      query: q,
    );
    expect(search('苏东坡').map((s) => s.book.id), ['b1']);
    expect(search('王小波').map((s) => s.book.id), ['b2']);
    expect(search('清欢').map((s) => s.book.id), ['b1']);
    expect(search('喜欢这句').map((s) => s.book.id), ['b1']);
    expect(search('这里').map((s) => s.book.id), ['b1']);
  });

  test('漫游卡片：类型筛选、书籍筛选、时间倒序', () {
    expect(
      noteEntries(
        items: items,
        annotations: annotations,
        bookmarks: bookmarks,
      ).map((e) => e.id),
      ['a3', 'a1', 'a2', 'bm1'],
    );
    expect(
      noteEntries(
        items: items,
        annotations: annotations,
        bookmarks: bookmarks,
        kind: NoteKind.bookmark,
      ).single.id,
      'bm1',
    );
    expect(
      noteEntries(
        items: items,
        annotations: annotations,
        bookmarks: bookmarks,
        bookId: 'b2',
      ).single.id,
      'a3',
    );
    final bookmark = noteEntries(
      items: items,
      annotations: annotations,
      bookmarks: bookmarks,
      kind: NoteKind.bookmark,
    ).single;
    expect(bookmark.chapterIndex, 2);
    expect(bookmark.quote, '这里');
  });

  test('时间格式 yy/MM/dd HH:mm', () {
    expect(noteTimeLabel(DateTime(2025, 3, 4, 14, 1)), '25/03/04 14:01');
    expect(noteTimeLabel(DateTime(2026, 11, 3, 9, 8)), '26/11/03 09:08');
  });
}
