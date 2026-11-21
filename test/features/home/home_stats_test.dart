/// 首页数据整理：继续阅读 / 今年读完 / 时长与百分比文案。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/home/home_stats.dart';

Book _book(
  String id, {
  int? opened,
  int updated = 0,
  int? finishedAt,
  BookReadStatus status = BookReadStatus.unread,
}) =>
    Book(
      id: id,
      title: '书$id',
      format: BookFormat.epub,
      filePath: '/tmp/$id.epub',
      fileSha256: id,
      fileSize: 1,
      addedAt: 0,
      updatedAt: updated,
      finishedAt: finishedAt,
      lastOpenedAt: opened,
      readStatus: status,
      hlc: '0000000000000-00000-aaaaaaaa',
      deviceId: 'aaaaaaaa',
    );

ShelfItem _item(
  String id, {
  int? opened,
  int updated = 0,
  int? finishedAt,
  double percent = 0,
  BookReadStatus status = BookReadStatus.unread,
}) =>
    ShelfItem(
      book: _book(
        id,
        opened: opened,
        updated: updated,
        finishedAt: finishedAt,
        status: status,
      ),
      percent: percent,
    );

void main() {
  group('continueReadingItems', () {
    test('只取打开过、没读完的书，按最近打开时间倒序', () {
      final items = [
        _item('a', opened: 100, percent: 0.2),
        _item('b', opened: 300, percent: 0.5),
        _item('c', opened: 200, percent: 0.1),
        _item('done', opened: 999, percent: 1, status: BookReadStatus.finished),
        _item('dropped', opened: 999, percent: 0.3, status: BookReadStatus.dropped),
        _item('never'),
      ];
      expect(
        continueReadingItems(items).map((it) => it.book.id),
        ['b', 'c', 'a'],
      );
    });

    test('进度满 1 但状态还没切换时不算继续阅读', () {
      final items = [_item('a', opened: 10, percent: 1)];
      expect(continueReadingItems(items), isEmpty);
    });

    test('打开过但 0% 也算「继续阅读」（刚翻开还没读）', () {
      final items = [_item('a', opened: 10, percent: 0)];
      expect(continueReadingItems(items).single.book.id, 'a');
    });
  });

  group('finishedBooks / finishedThisYear', () {
    test('阅读状态已读或进度满格都算读完', () {
      final items = [
        _item('a', status: BookReadStatus.finished),
        _item('b', percent: 1),
        _item('c', percent: 0.9),
      ];
      expect(finishedBooks(items).map((it) => it.book.id), ['a', 'b']);
    });

    test('只保留今年更新的已读书，最近更新的在前', () {
      final now = DateTime(2026, 11, 12);
      final thisYear = DateTime(2026, 3, 1).millisecondsSinceEpoch;
      final lastYear = DateTime(2025, 12, 31).millisecondsSinceEpoch;
      final items = [
        _item(
          'old',
          updated: lastYear,
          status: BookReadStatus.finished,
        ),
        _item(
          'spring',
          updated: thisYear,
          status: BookReadStatus.finished,
        ),
        _item(
          'winter',
          updated: DateTime(2026, 10, 1).millisecondsSinceEpoch,
          percent: 1,
        ),
      ];
      expect(
        finishedThisYear(items, now: now).map((it) => it.book.id),
        ['winter', 'spring'],
      );
    });

    test('微信读书导入的书：finishedAt 是往年就不算今年读完', () {
      final now = DateTime(2026, 11, 18);
      final items = [
        // 2024 年读完的微信读书书：今天同步刷新过 updatedAt，
        // 但读完时间还是 2024，不应混进「今年读完」。
        _item(
          'wr2024',
          updated: DateTime(2026, 11, 18).millisecondsSinceEpoch,
          finishedAt: DateTime(2024, 6, 1).millisecondsSinceEpoch,
          percent: 1,
          status: BookReadStatus.finished,
        ),
        // finishedAt 在今年：算。
        _item(
          'wr2026',
          updated: DateTime(2026, 11, 1).millisecondsSinceEpoch,
          finishedAt: DateTime(2026, 5, 5).millisecondsSinceEpoch,
          status: BookReadStatus.finished,
        ),
        // 没有 finishedAt 的旧本机数据：退回 updatedAt 近似。
        _item(
          'local',
          updated: DateTime(2026, 2, 2).millisecondsSinceEpoch,
          status: BookReadStatus.finished,
        ),
      ];
      expect(
        finishedThisYear(items, now: now).map((it) => it.book.id),
        ['wr2026', 'local'],
      );
    });
  });

  group('文案', () {
    test('累计时长', () {
      expect(formatTotalReadingDuration(0), '0 秒');
      expect(formatTotalReadingDuration(12000), '12 秒');
      expect(formatTotalReadingDuration(38 * 60000), '38 分钟');
      expect(
        formatTotalReadingDuration(500 * 3600000 + 38 * 60000),
        '500 小时 38 分钟',
      );
      expect(formatTotalReadingDuration(-1), '0 秒');
    });

    test('今日计时（不到 1 小时为分:秒）', () {
      expect(formatReadingClock(0), '0:00');
      expect(formatReadingClock(133000), '2:13');
      expect(formatReadingClock(3661000), '1:01:01');
    });

    test('百分比去掉多余小数', () {
      expect(formatPercent(0), '0%');
      expect(formatPercent(0.0718), '7.18%');
      expect(formatPercent(0.075), '7.5%');
      expect(formatPercent(1), '100%');
      expect(formatPercent(1.2), '100%');
    });
  });
}
