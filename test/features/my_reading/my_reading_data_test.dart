/// 「我的阅读」纯函数：筛选、搜索、年月分组、文案。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/domain/entities/reading_stats.dart';
import 'package:qy_reader/features/my_reading/my_reading_data.dart';

Book _book({
  required String id,
  required String title,
  String? author,
  BookReadStatus status = BookReadStatus.reading,
  int? lastOpenedAt,
  int updatedAt = 0,
}) {
  return Book(
    id: id,
    title: title,
    author: author,
    format: BookFormat.epub,
    filePath: '/tmp/$id.epub',
    fileSha256: id,
    fileSize: 1,
    addedAt: 0,
    updatedAt: updatedAt,
    lastOpenedAt: lastOpenedAt,
    readStatus: status,
    hlc: '0000000000000-00000-aaaaaaaa',
    deviceId: 'aaaaaaaa',
  );
}

ShelfItem _item(Book book, {double percent = 0}) =>
    ShelfItem(book: book, percent: percent);

DateTime _at(int year, int month, int day) => DateTime(year, month, day);

void main() {
  final now = DateTime(2026, 11, 13);
  final reading = _item(
    _book(
      id: 'r',
      title: '我要活下去',
      author: '金琸桓',
      lastOpenedAt: _at(2026, 11, 2).millisecondsSinceEpoch,
    ),
    percent: 0.008,
  );
  final finished = _item(
    _book(
      id: 'f',
      title: '被讨厌的勇气',
      author: '岸见一郎',
      status: BookReadStatus.finished,
      lastOpenedAt: _at(2026, 10, 29).millisecondsSinceEpoch,
    ),
    percent: 1,
  );
  final dropped = _item(
    _book(
      id: 'd',
      title: '搁置的书',
      status: BookReadStatus.dropped,
      lastOpenedAt: _at(2026, 10, 10).millisecondsSinceEpoch,
    ),
    percent: 0.2,
  );
  final unread = _item(
    _book(
      id: 'u',
      title: '未读的书',
      status: BookReadStatus.unread,
      updatedAt: _at(2026, 9, 1).millisecondsSinceEpoch,
    ),
  );
  final items = [reading, finished, dropped, unread];
  final totals = {
    'r': const BookReadingTotal(bookId: 'r', durationMs: 38000, charsRead: 519),
    'f': const BookReadingTotal(
      bookId: 'f',
      durationMs: 55 * 60 * 1000,
      charsRead: 42000,
    ),
  };

  test('按状态筛选，全部包含未读', () {
    int count(MyReadingFilter filter) =>
        myReadingBooks(items: items, totals: totals, filter: filter).length;
    expect(count(MyReadingFilter.all), 4);
    expect(count(MyReadingFilter.reading), 1);
    expect(count(MyReadingFilter.finished), 1);
    expect(count(MyReadingFilter.dropped), 1);
  });

  test('搜索书名 / 作者', () {
    final byTitle = myReadingBooks(items: items, totals: totals, query: '活下去');
    expect(byTitle.single.book.id, 'r');
    final byAuthor = myReadingBooks(items: items, totals: totals, query: '岸见');
    expect(byAuthor.single.book.id, 'f');
  });

  test('按年 / 月分组并倒序', () {
    final groups = groupMyReading(
      myReadingBooks(items: items, totals: totals, filter: MyReadingFilter.all),
    );
    expect(groups.single.year, 2026);
    expect(groups.single.count, 4);
    expect(groups.single.months.map((m) => m.month), [11, 10, 9]);
    expect(groups.single.months[0].books.single.book.id, 'r');
    expect(groups.single.months[1].books.length, 2);
  });

  test('卡片标题 / 副标题文案', () {
    final books = myReadingBooks(items: items, totals: totals);
    final byId = {for (final b in books) b.book.id: b};
    expect(myReadingHeadline(byId['r']!), '读到 0.8%');
    expect(myReadingHeadline(byId['f']!), '55 分钟');
    expect(myReadingHeadline(byId['u']!), '未开始');
    expect(myReadingMeta(byId['r']!, now: now), '11月开始阅读 · 519 字 · 38 秒');
    expect(myReadingMeta(byId['f']!, now: now), '2026年10月读完');
    expect(myReadingMeta(byId['d']!, now: now), '2026年10月搁置');
    expect(myReadingMeta(byId['u']!, now: now), '9月加入书架');
  });

  test('时长 / 字数格式化', () {
    expect(formatReadingDuration(38000), '38 秒');
    expect(formatReadingDuration(55 * 60 * 1000), '55 分钟');
    expect(formatReadingDuration(94 * 60 * 1000), '1 小时 34 分钟');
    expect(formatReadingChars(519), '519 字');
    expect(formatReadingChars(42000), '4.2 万字');
    expect(formatReadingChars(10000), '1 万字');
  });
}
