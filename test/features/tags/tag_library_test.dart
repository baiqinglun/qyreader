/// 标签库偏好 + 标签摘要测试。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/shelf/shelf_controller.dart';
import 'package:qy_reader/features/tags/tag_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

ShelfItem _item(String id, List<String> tags) => ShelfItem(
      book: Book(
        id: id,
        title: '书$id',
        format: BookFormat.epub,
        filePath: '/tmp/$id.epub',
        fileSha256: id,
        fileSize: 1,
        addedAt: 0,
        updatedAt: 0,
        tags: tags,
        hlc: '0000000000000-00000-aaaaaaaa',
        deviceId: 'aaaaaaaa',
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('标签库偏好', () {
    test('新增去重/改名/删除，全部落盘并可重新恢复', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(tagLibraryControllerProvider.notifier);

      await controller.add(' 科幻 ');
      await controller.add('科幻');
      await controller.add('历史');
      await controller.add('   ');
      expect(container.read(tagLibraryControllerProvider), ['科幻', '历史']);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('tags.library'), ['科幻', '历史']);

      await controller.rename('科幻', 'SciFi');
      expect(container.read(tagLibraryControllerProvider), ['SciFi', '历史']);

      await controller.remove('历史');
      expect(container.read(tagLibraryControllerProvider), ['SciFi']);

      final restored = ProviderContainer();
      addTearDown(restored.dispose);
      restored.read(tagLibraryControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(restored.read(tagLibraryControllerProvider), ['SciFi']);
    });

    test('改名合并重名标签、超长名截到 20 字', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(tagLibraryControllerProvider.notifier);

      await controller.add('A');
      await controller.add('B');
      await controller.rename('A', 'B');
      expect(container.read(tagLibraryControllerProvider), ['B']);

      await controller.add(List.filled(30, '超').join());
      expect(
        container.read(tagLibraryControllerProvider).last,
        hasLength(20),
      );
    });
  });

  group('标签摘要', () {
    test('合并书上的标签与标签库空标签，按使用数降序', () async {
      final items = [
        _item('a', const ['科幻', '经典']),
        _item('b', const ['科幻']),
        _item('c', const []),
      ];
      final container = ProviderContainer(overrides: [
        shelfItemsProvider.overrideWith((ref) => Stream.value(items)),
      ]);
      addTearDown(container.dispose);
      final sub = container.listen(tagSummariesProvider, (_, __) {});
      addTearDown(sub.close);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await container.read(tagLibraryControllerProvider.notifier).add('空标签');

      final summaries = container.read(tagSummariesProvider);
      expect(
        [for (final s in summaries) '${s.name}:${s.count}'],
        ['科幻:2', '经典:1', '空标签:0'],
      );
    });

    test('同数量按名称排序；书名标签去空白后计入', () async {
      final items = [
        _item('a', const ['B', 'A']),
        _item('b', const [' A ']),
      ];
      final container = ProviderContainer(overrides: [
        shelfItemsProvider.overrideWith((ref) => Stream.value(items)),
      ]);
      addTearDown(container.dispose);
      final sub = container.listen(tagSummariesProvider, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        [for (final s in container.read(tagSummariesProvider)) s.name],
        ['A', 'B'],
      );
      expect(
        container.read(tagSummariesProvider).first.count,
        2,
      );
    });
  });
}
