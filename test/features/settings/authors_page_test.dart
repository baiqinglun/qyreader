/// 作者管理页：分组卡片、搜索、作者书籍页与批量重命名。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qy_reader/app/providers.dart';
import 'package:qy_reader/app/router.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/domain/repositories/book_repository.dart';
import 'package:qy_reader/features/settings/authors_page.dart';

ShelfItem _item(String id, String title, {String? author}) {
  return ShelfItem(
    book: Book(
      id: id,
      title: title,
      author: author,
      format: BookFormat.epub,
      filePath: '/books/$id.epub',
      fileSha256: 'sha-$id',
      fileSize: 1000,
      chapterCount: 1,
      wordCount: 100,
      addedAt: DateTime(2026, 1, 1).millisecondsSinceEpoch,
      updatedAt: DateTime(2026, 1, 1).millisecondsSinceEpoch,
      hlc: 'hlc',
      deviceId: 'dev',
    ),
  );
}

class _FakeBookRepository implements BookRepository {
  List<ShelfItem> _items = const [];
  final _controller = StreamController<List<ShelfItem>>.broadcast();

  /// 记录 updateBookMeta 调用：(bookId, 新作者名)。
  final List<(String, String)> updates = [];

  /// 广播流不会缓存无监听期间的事件，这里先回放当前列表再接后续更新。
  void emit(List<ShelfItem> items) {
    _items = items;
    _controller.add(items);
  }

  void close() => _controller.close();

  @override
  Stream<List<ShelfItem>> watchShelf() async* {
    yield _items;
    yield* _controller.stream;
  }

  @override
  Future<void> updateBookMeta(
    String bookId, {
    String? title,
    String? author,
  }) async {
    updates.add((bookId, author ?? ''));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GoRouter _router() => GoRouter(
  initialLocation: kAuthorsPath,
  routes: [
    GoRoute(
      path: kAuthorsPath,
      builder: (_, __) => const AuthorsPage(),
    ),
    GoRoute(
      path: kAuthorBooksPath,
      builder: (_, state) => AuthorBooksPage(
        authorKey: state.extra is String ? state.extra! as String : '',
      ),
    ),
    GoRoute(
      path: kBookDetailPath,
      builder: (_, state) => Scaffold(
        body: Text(
          'book-detail-${state.pathParameters['bookId']}',
          key: const ValueKey('book-detail-route'),
        ),
      ),
    ),
  ],
);

Future<void> _pump(WidgetTester tester, _FakeBookRepository repo) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(repo.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [bookRepositoryProvider.overrideWith((ref) async => repo)],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  List<ShelfItem> sample() => [
    _item('1', '三体', author: '刘慈欣'),
    _item('2', '球状闪电', author: '刘慈欣'),
    _item('3', '黑暗森林', author: '刘慈欣'),
    _item('4', '嫌疑人X的献身', author: '东野圭吾'),
    _item('5', '无名之书'),
    _item('6', '又一本无名书'),
  ];

  testWidgets('作者卡片：未知作者最前带补全提示，其余按书数排序', (tester) async {
    final repo = _FakeBookRepository()..emit(sample());
    await _pump(tester, repo);

    expect(find.text('作者管理'), findsOneWidget);
    expect(find.text('搜索 3 位作者'), findsOneWidget);
    expect(find.text('未知作者'), findsOneWidget);
    expect(find.text('这些书没有作者信息，点击查看并补全'), findsOneWidget);
    expect(find.text('刘慈欣'), findsOneWidget);
    expect(find.text('东野圭吾'), findsOneWidget);
    expect(find.text('3 本'), findsOneWidget);
    expect(find.text('1 本'), findsOneWidget);
    expect(find.text('2 本'), findsOneWidget);
    // 未知作者没有重命名菜单，其余作者有。
    expect(find.byKey(const ValueKey('author-menu-刘慈欣')), findsOneWidget);
    expect(find.byKey(const ValueKey('author-menu-东野圭吾')), findsOneWidget);
  });

  testWidgets('搜索：作者名或书名命中才保留分组', (tester) async {
    final repo = _FakeBookRepository()..emit(sample());
    await _pump(tester, repo);

    // 按作者名搜。
    await tester.enterText(find.byKey(const ValueKey('authors-search')), '东野');
    await tester.pumpAndSettle();
    expect(find.text('刘慈欣'), findsNothing);
    expect(find.text('未知作者'), findsNothing);
    expect(find.text('东野圭吾'), findsOneWidget);

    // 按书名搜：带出该作者整组。
    await tester.enterText(find.byKey(const ValueKey('authors-search')), '球状');
    await tester.pumpAndSettle();
    expect(find.text('刘慈欣'), findsOneWidget);
    expect(find.text('3 本'), findsOneWidget);
    expect(find.text('东野圭吾'), findsNothing);

    // 无命中。
    await tester.enterText(
      find.byKey(const ValueKey('authors-search')),
      '不存在的作者',
    );
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的作者'), findsOneWidget);
  });

  testWidgets('点作者卡进作者书籍页，列出名下全部书籍；点书进书籍详情', (tester) async {
    final repo = _FakeBookRepository()..emit(sample());
    await _pump(tester, repo);

    await tester.tap(find.text('刘慈欣'));
    await tester.pumpAndSettle();

    // 书籍页 AppBar 显示作者名，正文列出全部书。
    expect(find.text('刘慈欣'), findsOneWidget);
    expect(find.text('共 3 本'), findsOneWidget);
    expect(find.text('三体'), findsOneWidget);
    expect(find.text('球状闪电'), findsOneWidget);
    expect(find.text('黑暗森林'), findsOneWidget);
    expect(find.text('这些书没有作者信息'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('author-book-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('book-detail-route')), findsOneWidget);
    expect(find.text('book-detail-1'), findsOneWidget);
  });

  testWidgets('未知作者组：书籍页带补全提示', (tester) async {
    final repo = _FakeBookRepository()..emit(sample());
    await _pump(tester, repo);

    await tester.tap(find.text('未知作者'));
    await tester.pumpAndSettle();

    expect(find.text('未知作者'), findsOneWidget);
    expect(find.text('共 2 本'), findsOneWidget);
    expect(
      find.text('这些书没有作者信息，点开书籍详情可在「编辑信息」里补全'),
      findsOneWidget,
    );
    expect(find.text('无名之书'), findsOneWidget);
    expect(find.text('又一本无名书'), findsOneWidget);
  });

  testWidgets('重命名作者：批量更新组内全部书籍，可清空成未知作者', (tester) async {
    final repo = _FakeBookRepository()..emit(sample());
    await _pump(tester, repo);

    await tester.tap(find.byKey(const ValueKey('author-menu-刘慈欣')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名作者'));
    await tester.pumpAndSettle();

    // 预填当前作者名，清空后输入新名字。
    expect(find.byKey(const ValueKey('author-rename-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('author-rename-field')),
      '刘慈欣（中）',
    );
    await tester.tap(find.byKey(const ValueKey('author-rename-save')));
    await tester.pumpAndSettle();

    expect(repo.updates, hasLength(3));
    expect(
      repo.updates.every((u) => u.$2 == '刘慈欣（中）'),
      isTrue,
    );
    expect(find.textContaining('已把 3 本书籍的作者改为'), findsOneWidget);

    // 清空作者名 = 全部进未知作者组。
    await tester.tap(find.byKey(const ValueKey('author-menu-东野圭吾')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名作者'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('author-rename-field')), '');
    await tester.tap(find.byKey(const ValueKey('author-rename-save')));
    await tester.pumpAndSettle();

    expect(repo.updates.last, ('4', ''));
    expect(find.textContaining('已清空 1 本书籍的作者'), findsOneWidget);
  });
}
