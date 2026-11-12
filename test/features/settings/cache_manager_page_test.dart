/// 清除缓存页：只列本地有书源的书籍，逐本 / 全部清除。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/providers.dart';
import 'package:qy_reader/core/result.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/domain/repositories/book_repository.dart';
import 'package:qy_reader/domain/repositories/sync_repository.dart';
import 'package:qy_reader/domain/sync/sync_status.dart';
import 'package:qy_reader/features/settings/cache_manager_page.dart';

ShelfItem _item(String id, String filePath, {String? coverPath}) => ShelfItem(
  book: Book(
    id: id,
    title: '书$id',
    format: BookFormat.epub,
    filePath: filePath,
    fileSha256: id,
    fileSize: 1,
    coverPath: coverPath,
    addedAt: 0,
    updatedAt: 0,
    hlc: '0000000000000-00000-aaaaaaaa',
    deviceId: 'aaaaaaaa',
  ),
);

class _FakeBookRepository implements BookRepository {
  _FakeBookRepository(this.items);

  final List<ShelfItem> items;

  @override
  Stream<List<ShelfItem>> watchShelf() => Stream.value(items);

  @override
  Future<Book?> getById(String bookId) async {
    for (final item in items) {
      if (item.book.id == bookId) return item.book;
    }
    return null;
  }

  @override
  Future<int> renameTag(String from, String to) => throw UnimplementedError();

  @override
  Future<int> deleteTag(String tag) => throw UnimplementedError();

  @override
  Future<void> deleteBook(String bookId, {required bool deleteAnnotations}) =>
      throw UnimplementedError();

  @override
  Future<void> flushOpened(String bookId) => throw UnimplementedError();

  @override
  Future<List<BookChapter>> getChapters(String bookId) =>
      throw UnimplementedError();

  @override
  Future<Result<Book>> importFromFile(
    String sourcePath, {
    bool returnExistingOnDuplicate = false,
  }) => throw UnimplementedError();

  @override
  Future<void> setPersonalization(
    String bookId, {
    int? rating,
    String? review,
    List<String>? tags,
    String? category,
    BookReadStatus? readStatus,
  }) => throw UnimplementedError();

  @override
  Future<void> setPinned(String bookId, bool pinned) =>
      throw UnimplementedError();

  @override
  Future<void> touchOpened(String bookId) => throw UnimplementedError();

  @override
  Future<void> updateBookMeta(String bookId, {String? title, String? author}) =>
      throw UnimplementedError();
}

class _FakeSyncRepository implements SyncRepository {
  final List<String> cleared = [];

  @override
  Future<bool> clearLocalBookCache(String bookId) async {
    cleared.add(bookId);
    return true;
  }

  @override
  Future<void> deleteCloudBook(String bookId, {String? fileSha256}) async {}

  @override
  Future<bool> ensureBookFileLocal(String bookId) async => true;

  @override
  Future<bool> isBookBackedUp(String bookId) async => true;

  @override
  Future<List<String>> pendingShardBooks() async => const [];

  @override
  Future<SyncStatus> status() async => const SyncStatus();

  @override
  Future<SyncResult> syncNow({
    void Function(SyncProgress progress)? onProgress,
  }) async => const SyncResult();

  @override
  Future<bool> uploadBookBlobNow(String bookId) async => true;
}

void main() {
  late Directory tempDir;
  late List<ShelfItem> items;
  late _FakeBookRepository books;
  late _FakeSyncRepository sync;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('qy_cache_page');
    final aFile = File('${tempDir.path}/a.epub')
      ..writeAsBytesSync(List.filled(2048, 1));
    final bFile = File('${tempDir.path}/b.epub')
      ..writeAsBytesSync(List.filled(1024, 2));
    items = [
      // 封面路径留空：避免测试进程锁住临时图片文件（Windows 删除会失败）
      _item('a', aFile.path),
      _item('b', bFile.path),
      // 云端有、本地已清缓存的书籍：不出现在列表里
      _item('c', '${tempDir.path}/missing.epub'),
    ];
    books = _FakeBookRepository(items);
    sync = _FakeSyncRepository();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    // 页面用真实 File.exists()/length() 做异步 IO；fake async 下需要
    // runAsync 给它跑真实事件循环的机会。
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  Future<void> pumpPage(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWith((ref) async => books),
        syncRepositoryProvider.overrideWith((ref) async => sync),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: BookCacheView())),
      ),
    );
    await settle(tester);
  }

  testWidgets('只列本地有书源的书籍，显示本数与占用', (tester) async {
    await pumpPage(tester);

    expect(find.text('书a'), findsOneWidget);
    expect(find.text('书b'), findsOneWidget);
    expect(find.text('书c'), findsNothing);
    expect(find.textContaining('2 本'), findsOneWidget);
    // 2048 + 1024 = 3 KB
    expect(find.textContaining('3 KB'), findsWidgets);
    expect(find.textContaining('封面保留'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('单本清除调用仓储并提示封面与云端保留', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('cache-clear-a')));
    await settle(tester);

    expect(sync.cleared, ['a']);
    expect(find.textContaining('封面与云端保留'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('全部清除需要确认，逐本调用仓储', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('cache-clear-all')));
    await tester.pumpAndSettle();
    expect(find.text('清除全部本地书籍'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('全部清除'),
      ),
    );
    await settle(tester);

    expect(sync.cleared.toSet(), {'a', 'b'});
    expect(find.textContaining('已清除 2 本书'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
