/// 书架设置偏好：默认值、落盘、旧值兜底与列数解析。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/shelf/shelf_controller.dart';
import 'package:qy_reader/features/shelf/shelf_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('书架设置默认值', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('圆角 20 / 自动列数 / 木纹架板；列表四项默认关闭、各 2 行', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final prefs = container.read(shelfPrefsControllerProvider);
      expect(prefs.coverRadius, 20);
      expect(prefs.columns, ShelfColumnCount.auto);
      expect(prefs.plankStyle, ShelfPlankStyle.wood);
      expect(prefs.sortField, ShelfSortField.lastOpened);
      expect(prefs.sortAscending, isFalse);
      expect(prefs.showRating, isFalse);
      expect(prefs.showTags, isFalse);
      expect(prefs.showDescription, isFalse);
      expect(prefs.descriptionLines, 2);
      expect(prefs.showReview, isFalse);
      expect(prefs.reviewLines, 2);
    });

    test('每一项都落 shared_preferences，重新读取能恢复', () async {
      SharedPreferences.setMockInitialValues({});
      final first = ProviderContainer();
      addTearDown(first.dispose);
      final controller = first.read(shelfPrefsControllerProvider.notifier);

      await controller.setCoverRadius(6);
      await controller.setColumns(ShelfColumnCount.four);
      await controller.setPlankStyle(ShelfPlankStyle.solid);
      await controller.setSortField(ShelfSortField.title);
      await controller.setSortAscending(true);
      await controller.setShowRating(true);
      await controller.setShowTags(true);
      await controller.setShowDescription(true);
      await controller.setDescriptionLines(4);
      await controller.setShowReview(true);
      await controller.setReviewLines(3);

      final stored = await SharedPreferences.getInstance();
      expect(stored.getInt('shelf.coverRadius'), 6);
      expect(stored.getString('shelf.columns'), 'four');
      expect(stored.getString('shelf.plankStyle'), 'solid');
      expect(stored.getString('shelf.sortField'), 'title');
      expect(stored.getBool('shelf.sortAsc'), isTrue);
      expect(stored.getBool('shelf.list.showRating'), isTrue);
      expect(stored.getBool('shelf.list.showTags'), isTrue);
      expect(stored.getBool('shelf.list.showDescription'), isTrue);
      expect(stored.getInt('shelf.list.descriptionLines'), 4);
      expect(stored.getBool('shelf.list.showReview'), isTrue);
      expect(stored.getInt('shelf.list.reviewLines'), 3);

      // 新容器模拟重启：异步恢复后读到保存值。
      final second = ProviderContainer();
      addTearDown(second.dispose);
      second.read(shelfPrefsControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final restored = second.read(shelfPrefsControllerProvider);
      expect(restored.coverRadius, 6);
      expect(restored.columns, ShelfColumnCount.four);
      expect(restored.plankStyle, ShelfPlankStyle.solid);
      expect(restored.sortField, ShelfSortField.title);
      expect(restored.sortAscending, isTrue);
      expect(restored.showRating, isTrue);
      expect(restored.showTags, isTrue);
      expect(restored.showDescription, isTrue);
      expect(restored.descriptionLines, 4);
      expect(restored.showReview, isTrue);
      expect(restored.reviewLines, 3);
    });

    test('越界/未知的旧值回退默认或夹到范围内', () async {
      SharedPreferences.setMockInitialValues({
        'shelf.coverRadius': 99,
        'shelf.columns': 'six',
        'shelf.plankStyle': 'marble',
        'shelf.list.descriptionLines': 0,
        'shelf.list.reviewLines': 99,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(shelfPrefsControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final prefs = container.read(shelfPrefsControllerProvider);
      expect(prefs.coverRadius, 24); // 上限 24
      expect(prefs.columns, ShelfColumnCount.auto);
      expect(prefs.plankStyle, ShelfPlankStyle.wood);
      expect(prefs.descriptionLines, 1); // 下限 1
      expect(prefs.reviewLines, 4); // 上限 4
    });

    test('setter 写入时也会夹取范围', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(shelfPrefsControllerProvider.notifier);

      await controller.setCoverRadius(-5);
      await controller.setDescriptionLines(9);
      await controller.setReviewLines(0);

      final prefs = container.read(shelfPrefsControllerProvider);
      expect(prefs.coverRadius, 0);
      expect(prefs.descriptionLines, 4);
      expect(prefs.reviewLines, 1);
    });
  });

  group('每行格数', () {
    test('自动：手机 3 格，宽屏按 140dp 加列', () {
      expect(shelfColumns(200), 3);
      expect(shelfColumns(328), 3);
      expect(shelfColumns(568), 4);
      expect(shelfColumns(736), 5);
    });

    test('固定 3/4/5 格：不再按屏宽变化', () {
      expect(
        shelfColumns(200, columns: ShelfColumnCount.three),
        3,
      );
      expect(
        shelfColumns(900, columns: ShelfColumnCount.three),
        3,
      );
      expect(
        shelfColumns(200, columns: ShelfColumnCount.four),
        4,
      );
      expect(
        shelfColumns(900, columns: ShelfColumnCount.five),
        5,
      );
    });
  });
}
