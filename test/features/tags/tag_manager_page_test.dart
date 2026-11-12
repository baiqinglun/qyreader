/// 标签管理页：展示 / 搜索 / 新增 / 重命名 / 删除。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/providers.dart';
import 'package:qy_reader/core/result.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/domain/repositories/book_repository.dart';
import 'package:qy_reader/features/shelf/shelf_controller.dart';
import 'package:qy_reader/features/shelf/widgets/tag_capsule.dart';
import 'package:qy_reader/features/tags/tag_library.dart';
import 'package:qy_reader/features/tags/tag_manager_page.dart';
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

class _FakeBookRepository implements BookRepository {
  String? renamedFrom;
  String? renamedTo;
  String? deletedTag;
  int renameCalls = 0;
  int deleteCalls = 0;
  int renameResult = 0;
  int deleteResult = 0;

  @override
  Future<int> renameTag(String from, String to) async {
    renameCalls++;
    renamedFrom = from;
    renamedTo = to;
    return renameResult;
  }

  @override
  Future<int> deleteTag(String tag) async {
    deleteCalls++;
    deletedTag = tag;
    return deleteResult;
  }

  @override
  Future<void> deleteBook(
    String bookId, {
    required bool deleteAnnotations,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> flushOpened(String bookId) => throw UnimplementedError();

  @override
  Future<Book?> getById(String bookId) => throw UnimplementedError();

  @override
  Future<List<BookChapter>> getChapters(String bookId) =>
      throw UnimplementedError();

  @override
  Future<Result<Book>> importFromFile(
    String sourcePath, {
    bool returnExistingOnDuplicate = false,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> setPersonalization(
    String bookId, {
    int? rating,
    String? review,
    List<String>? tags,
    String? category,
    BookReadStatus? readStatus,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> setPinned(String bookId, bool pinned) =>
      throw UnimplementedError();

  @override
  Future<void> touchOpened(String bookId) => throw UnimplementedError();

  @override
  Future<void> updateBookMeta(
    String bookId, {
    String? title,
    String? author,
  }) =>
      throw UnimplementedError();

  @override
  Stream<List<ShelfItem>> watchShelf() => throw UnimplementedError();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pumpPage(
    WidgetTester tester, {
    required List<ShelfItem> items,
    _FakeBookRepository? repo,
  }) async {
    final container = ProviderContainer(overrides: [
      shelfItemsProvider.overrideWith((ref) => Stream.value(items)),
      bookRepositoryProvider.overrideWith(
        (ref) async => repo ?? _FakeBookRepository(),
      ),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: TagManagerPage()),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('展示标签与使用数，可搜索', (tester) async {
    await pumpPage(tester, items: [
      _item('a', const ['科幻', '经典']),
      _item('b', const ['科幻', '历史']),
    ]);

    expect(find.widgetWithText(TagCapsule, '科幻'), findsOneWidget);
    expect(find.widgetWithText(TagCapsule, '经典'), findsOneWidget);
    expect(
      tester.widget<TagCapsule>(find.widgetWithText(TagCapsule, '科幻')).count,
      2,
    );
    expect(find.text('从 3 个标签中搜索'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '经典');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TagCapsule, '科幻'), findsNothing);
    expect(find.widgetWithText(TagCapsule, '经典'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('新增标签落标签库并出现在列表里', (tester) async {
    final container = await pumpPage(tester, items: [_item('a', const ['科幻'])]);

    await tester.tap(find.byTooltip('新建标签'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '  新标签  ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(
      container.read(tagLibraryControllerProvider),
      contains('新标签'),
    );
    expect(find.text('新标签'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('重命名标签：批量改书并提示更新本数', (tester) async {
    final repo = _FakeBookRepository()..renameResult = 2;
    await pumpPage(
      tester,
      items: [_item('a', const ['科幻'])],
      repo: repo,
    );

    await tester.tap(find.text('科幻'));
    await tester.pumpAndSettle();
    expect(find.text('编辑标签'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'SciFi');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(repo.renamedFrom, '科幻');
    expect(repo.renamedTo, 'SciFi');
    expect(find.textContaining('更新 2 本书'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('删除标签需要二次确认', (tester) async {
    final repo = _FakeBookRepository()..deleteResult = 3;
    await pumpPage(
      tester,
      items: [_item('a', const ['科幻'])],
      repo: repo,
    );

    await tester.tap(find.text('科幻'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除标签'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(repo.deletedTag, '科幻');
    expect(repo.deleteCalls, 1);
    expect(find.textContaining('更新 3 本书'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
