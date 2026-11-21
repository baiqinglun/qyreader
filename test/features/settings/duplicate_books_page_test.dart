/// 重复书籍整理页：分组展示、忽略、批量删除保护。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/providers.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/domain/repositories/book_repository.dart';
import 'package:qy_reader/features/settings/duplicate_books_page.dart';

ShelfItem _item(
  String id,
  String title, {
  String? author,
  int fileSize = 1000,
  int wordCount = 100,
}) {
  return ShelfItem(
    book: Book(
      id: id,
      title: title,
      author: author,
      format: BookFormat.epub,
      filePath: '/books/$id.epub',
      fileSha256: 'sha-$id',
      fileSize: fileSize,
      chapterCount: 1,
      wordCount: wordCount,
      addedAt: DateTime(2026, 1, 1).millisecondsSinceEpoch,
      updatedAt: DateTime(2026, 1, 1).millisecondsSinceEpoch,
      hlc: 'hlc',
      deviceId: 'dev',
    ),
  );
}

class _FakeBookRepository implements BookRepository {
  _FakeBookRepository(this.items);

  final List<ShelfItem> items;
  final List<String> deleted = [];

  @override
  Stream<List<ShelfItem>> watchShelf() => Stream.value(items);

  @override
  Future<void> deleteBook(
    String bookId, {
    required bool deleteAnnotations,
  }) async {
    deleted.add(bookId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(_FakeBookRepository repo) {
  return ProviderScope(
    overrides: [bookRepositoryProvider.overrideWith((ref) async => repo)],
    child: const MaterialApp(home: DuplicateBooksPage()),
  );
}

void main() {
  testWidgets('展示重复分组，忽略后消失', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _FakeBookRepository([
      _item('1', '三体'),
      _item('2', '三体（全3册）', fileSize: 2000),
      _item('3', '无关书'),
    ]);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.text('书籍重名整理'), findsOneWidget);
    expect(find.text('三体'), findsWidgets);
    expect(find.text('疑似匹配'), findsOneWidget);
    expect(find.textContaining('共有 2 本'), findsOneWidget);

    await tester.tap(find.text('忽略'));
    await tester.pumpAndSettle();
    expect(find.text('三体'), findsNothing);
    expect(find.textContaining('已忽略 1 组'), findsOneWidget);
  });

  testWidgets('批量删除至少保留一本，单本删除生效', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _FakeBookRepository([
      _item('1', '三体'),
      _item('2', '三体', fileSize: 2000),
    ]);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('duplicate-check-1')));
    await tester.tap(find.byKey(const ValueKey('duplicate-check-2')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('duplicate-delete-selected')));
    await tester.pumpAndSettle();
    expect(find.textContaining('每组至少保留一本'), findsOneWidget);

    // 取消选中一本后，删除另一本。
    await tester.tap(find.byKey(const ValueKey('duplicate-check-2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('duplicate-delete-selected')));
    await tester.pumpAndSettle();
    expect(find.text('删除选中的重复书籍？'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(repo.deleted, ['1']);
    expect(find.text('没有发现重复书籍'), findsOneWidget);
  });

  testWidgets('匹配范围切到强匹配后隐藏疑似分组', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _FakeBookRepository([_item('1', '三体'), _item('2', '三体（全3册）')]);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('匹配范围'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('duplicate-option-强匹配')));
    await tester.pumpAndSettle();

    expect(find.text('三体'), findsNothing);
    expect(find.text('没有发现重复书籍'), findsOneWidget);
  });
}
