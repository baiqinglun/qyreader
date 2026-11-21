/// 书架「最近在读」排序单测。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/shelf/shelf_controller.dart';
import 'package:qy_reader/features/shelf/widgets/recent_shelf.dart';

Book _book(String id, {int? opened, int pinned = 0}) => Book(
  id: id,
  title: '书$id',
  format: BookFormat.epub,
  filePath: '/tmp/$id.epub',
  fileSha256: id,
  fileSize: 1,
  addedAt: 0,
  updatedAt: 0,
  lastOpenedAt: opened,
  pinnedAt: pinned == 0 ? null : pinned,
  hlc: '0000000000000-00000-aaaaaaaa',
  deviceId: 'aaaaaaaa',
);

ShelfItem _item(String id, {int? opened, int pinned = 0, double percent = 0}) =>
    ShelfItem(
      book: _book(id, opened: opened, pinned: pinned),
      percent: percent,
    );

void main() {
  group('recentlyReadItems', () {
    test('只保留打开过的书', () {
      final items = [
        _item('a', opened: 100),
        _item('b'),
        _item('c', opened: 300),
      ];
      expect(recentlyReadItems(items).map((it) => it.book.id), ['c', 'a']);
    });

    test('置顶优先，其余按最近打开时间倒序', () {
      final items = [
        _item('pinned', opened: 10, pinned: 999),
        _item('newest', opened: 500),
        _item('middle', opened: 200),
      ];
      expect(recentlyReadItems(items).map((it) => it.book.id), [
        'pinned',
        'newest',
        'middle',
      ]);
    });

    test('超过上限只保留最近的 N 本', () {
      final items = [for (var i = 0; i < 30; i++) _item('b$i', opened: i)];
      final recent = recentlyReadItems(items, limit: 20);
      expect(recent.length, 20);
      expect(recent.first.book.id, 'b29');
      expect(recent.last.book.id, 'b10');
    });

    test('默认不再按固定本数截断', () {
      final items = [for (var i = 0; i < 20; i++) _item('b$i', opened: i)];
      final recent = recentlyReadItems(items);
      expect(recent.length, 20);
      expect(recent.first.book.id, 'b19');
    });

    test('空列表 / 全部未读 → 空', () {
      expect(recentlyReadItems(const []), isEmpty);
      expect(recentlyReadItems([_item('a'), _item('b')]), isEmpty);
    });

    test('进度不影响入选（读过即进入，哪怕 0%）', () {
      final items = [_item('a', opened: 1, percent: 0)];
      expect(recentlyReadItems(items).single.book.id, 'a');
    });
  });

  group('recentShelfVisibleItems', () {
    /// 当前书目占用的总宽度（含书间 3dp）。
    double usedWidth(List<ShelfItem> items) {
      var total = 0.0;
      for (var i = 0; i < items.length; i++) {
        total += recentShelfSpineWidth(items[i]);
        if (i > 0) total += 3;
      }
      return total;
    }

    test('宽屏比窄屏多摆，且都不超出可用宽度（左右各留 20）', () {
      final items = [for (var i = 0; i < 20; i++) _item('b$i', opened: i)];
      final sorted = recentlyReadItems(items);
      final narrow = recentShelfVisibleItems(sorted, 390);
      final wide = recentShelfVisibleItems(sorted, 1200);
      expect(narrow.length, lessThan(wide.length));
      expect(usedWidth(narrow), lessThanOrEqualTo(390 - 40));
      expect(usedWidth(wide), lessThanOrEqualTo(1200 - 40));
      expect(narrow.first.book.id, 'b19', reason: '顺序不变，仍从最近打开开始');
    });

    test('书少时全部展示（由 Row 居中排版）', () {
      final items = [_item('a', opened: 1), _item('b', opened: 2)];
      expect(recentShelfVisibleItems(items, 390).length, 2);
    });

    test('空列表返回空', () {
      expect(recentShelfVisibleItems(const [], 390), isEmpty);
    });
  });
}
