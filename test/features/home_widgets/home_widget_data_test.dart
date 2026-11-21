/// 桌面组件数据快照：最近阅读 / 今日阅读 / 最近三本。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/domain/entities/reading_stats.dart';
import 'package:qy_reader/features/home_widgets/home_widget_data.dart';

Book _book(String id, {int? opened, String? author, String? coverPath}) => Book(
  id: id,
  title: '书$id',
  author: author,
  coverPath: coverPath,
  format: BookFormat.epub,
  filePath: '/tmp/$id.epub',
  fileSha256: id,
  fileSize: 1,
  addedAt: 0,
  updatedAt: 0,
  lastOpenedAt: opened,
  hlc: '0000000000000-00000-aaaaaaaa',
  deviceId: 'aaaaaaaa',
);

ShelfItem _item(
  String id, {
  int? opened,
  double percent = 0,
  String? author,
  String? coverPath,
}) => ShelfItem(
  book: _book(id, opened: opened, author: author, coverPath: coverPath),
  percent: percent,
);

ReadingStats _stats({int todayMs = 0, int goal = 30}) => ReadingStats(
  todayDurationMs: todayMs,
  todayChars: 0,
  totalDurationMs: 0,
  totalChars: 0,
  totalDays: 0,
  streakDays: 0,
  recentDays: const [],
  dailyGoalMinutes: goal,
);

void main() {
  final now = DateTime(2026, 11, 14, 2, 30);

  group('buildHomeWidgetData', () {
    test('最近阅读取 lastOpenedAt 最大的一本，书架取最近三本', () {
      final data = buildHomeWidgetData(
        items: [
          _item('a', opened: 100, percent: 0.2),
          _item('b', opened: 300, percent: 0.55, author: '作者B'),
          _item('c', opened: 200, percent: 0.1),
          _item('d', opened: 50, percent: 0.9),
          _item('never'),
        ],
        stats: _stats(todayMs: 30 * 60000, goal: 30),
        now: now,
      );

      expect(data.date, '2026-11-14');
      expect(data.recentBook?.id, 'b');
      expect(data.recentBook?.title, '书b');
      expect(data.recentBook?.author, '作者B');
      expect(data.recentBook?.percent, 0.55);
      expect(data.shelf.map((book) => book.id), ['b', 'c', 'a']);
      expect(data.today.durationMs, 30 * 60000);
      expect(data.today.goalMinutes, 30);
      expect(data.today.progress, 1.0);
    });

    test('没有打开过的书：最近阅读为空，书架用最近入库的书补齐三本', () {
      final data = buildHomeWidgetData(
        items: [_item('a'), _item('b'), _item('c'), _item('d')],
        stats: _stats(goal: 0),
        now: now,
      );

      expect(data.recentBook, isNull);
      expect(data.shelf.map((book) => book.id), ['a', 'b', 'c']);
      expect(data.today.progress, 0);
      expect(data.today.goalMinutes, 0);
      expect(homeWidgetJson(data), contains('"version":1'));
    });

    test('进度夹到 0..1，今日完成比例按目标封顶', () {
      final data = buildHomeWidgetData(
        items: [
          _item('a', opened: 1, percent: 1.4),
          _item('b', opened: 2, percent: -0.3),
        ],
        stats: _stats(todayMs: 90 * 60000, goal: 30),
        now: now,
      );

      expect(data.shelf.first.percent, 0);
      expect(data.shelf.last.percent, 1);
      expect(data.today.progress, 1.0);
    });

    test('payload 可直接 JSON 解码（原生侧按 key 读）', () {
      final data = buildHomeWidgetData(
        items: [_item('a', opened: 1, coverPath: '/tmp/a.jpg')],
        stats: _stats(todayMs: 60000, goal: 30),
        now: now,
      );
      final payload = jsonDecode(homeWidgetJson(data)) as Map<String, dynamic>;
      expect(payload['date'], '2026-11-14');
      expect(
        (payload['recentBook'] as Map<String, dynamic>)['coverPath'],
        '/tmp/a.jpg',
      );
      expect((payload['today'] as Map<String, dynamic>)['durationMs'], 60000);
      expect((payload['shelf'] as List<dynamic>), hasLength(1));
    });
  });
}
