/// 书架「最近在读」排序单测。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/shelf/shelf_controller.dart';

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
      expect(
        recentlyReadItems(items).map((it) => it.book.id),
        ['c', 'a'],
      );
    });

    test('置顶优先，其余按最近打开时间倒序', () {
      final items = [
        _item('pinned', opened: 10, pinned: 999),
        _item('newest', opened: 500),
        _item('middle', opened: 200),
      ];
      expect(
        recentlyReadItems(items).map((it) => it.book.id),
        ['pinned', 'newest', 'middle'],
      );
    });

    test('超过上限只保留最近的 N 本', () {
      final items = [
        for (var i = 0; i < 30; i++) _item('b$i', opened: i),
      ];
      final recent = recentlyReadItems(items, limit: 20);
      expect(recent.length, 20);
      expect(recent.first.book.id, 'b29');
      expect(recent.last.book.id, 'b10');
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
}
