/// 书架分类与首屏排版单测：分类提取、按分类过滤、分类在前书在后、一行几格。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/shelf/shelf_controller.dart';
import 'package:qy_reader/features/shelf/shelf_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

ShelfItem _item(String id, {String? category}) => ShelfItem(
      book: Book(
        id: id,
        title: '书$id',
        format: BookFormat.epub,
        filePath: '/tmp/$id.epub',
        fileSha256: id,
        fileSize: 1,
        addedAt: 0,
        updatedAt: 0,
        category: category,
        hlc: '0000000000000-00000-aaaaaaaa',
        deviceId: 'aaaaaaaa',
      ),
    );

void main() {
  final items = [
    _item('a', category: '小说'),
    _item('b', category: '历史'),
    _item('c'),
    _item('d', category: '小说'),
  ];

  group('分类提取', () {
    test('去重排序，忽略空分类', () {
      expect(shelfCategories(items), ['历史', '小说']);
      expect(shelfCategories([_item('x')]), isEmpty);
      expect(shelfCategories([_item('x', category: '   ')]), isEmpty);
    });
  });

  group('按分类筛选', () {
    test('空筛选 = 全部', () {
      expect(filterShelfByCategory(items, ''), hasLength(4));
    });

    test('按分类名过滤', () {
      expect(
        filterShelfByCategory(items, '小说').map((e) => e.book.id),
        ['a', 'd'],
      );
    });

    test('分类名首尾空格不影响归属', () {
      final padded = [_item('x', category: ' 小说 ')];
      expect(shelfCategories(padded), ['小说']);
      expect(
        filterShelfByCategory(padded, '小说').map((e) => e.book.id),
        ['x'],
      );
    });
  });

  group('书架首屏排版', () {
    test('分类在前（按名字排序），没有分类的书散在后面', () {
      final cells = shelfCells(items);
      expect(cells, hasLength(3));

      final categories = cells.whereType<ShelfCategoryCell>().toList();
      expect(categories.map((c) => c.title), ['历史', '小说']);
      expect(
        categories[1].books.map((e) => e.book.id),
        ['a', 'd'],
      );

      final loose = cells.whereType<ShelfBookCell>().toList();
      expect(loose.map((c) => c.item.book.id), ['c']);
      // 分类格整段排在书格前面。
      expect(cells.indexOf(loose.first), greaterThan(cells.indexOf(categories.last)));
    });

    test('有分类的书不单独占格', () {
      final loose = shelfCells(items)
          .whereType<ShelfBookCell>()
          .map((c) => c.item.book.id);
      expect(loose, ['c']);
    });

    test('全都没有分类时只剩书格', () {
      final cells = shelfCells([_item('x'), _item('y')]);
      expect(cells.whereType<ShelfCategoryCell>(), isEmpty);
      expect(
        cells.whereType<ShelfBookCell>().map((c) => c.item.book.id),
        ['x', 'y'],
      );
    });
  });

  group('一行几格', () {
    test('手机一行 3 格，宽屏自动加列', () {
      expect(shelfColumns(200), 3); // 再窄也不少于 3
      expect(shelfColumns(328), 3); // 360dp 手机
      expect(shelfColumns(358), 3); // 390dp 手机
      expect(shelfColumns(448), 3); // 480dp 折叠屏
      expect(shelfColumns(568), 4); // 600dp 平板
      expect(shelfColumns(736), 5); // 768dp 平板
    });
  });

  group('筛选偏好', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('默认首屏；切换后落盘', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(shelfCategoryFilterProvider), '');
      await container
          .read(shelfCategoryFilterProvider.notifier)
          .set('小说');
      expect(container.read(shelfCategoryFilterProvider), '小说');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('shelf.categoryFilter'), '小说');
    });
  });

  group('书籍 JSON', () {
    test('category 往返一致；未分类不写字段', () {
      final b = _item('x', category: '小说').book;
      final map = bookToJson(b);
      expect(map['category'], '小说');
      expect(bookFromJson(map).category, '小说');

      final plain = bookToJson(_item('y').book);
      expect(plain.containsKey('category'), isFalse);
      expect(bookFromJson(plain).category, isNull);
    });
  });
}
