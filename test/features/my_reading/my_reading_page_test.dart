/// 「我的阅读」页面与分享面板的组件回归。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/providers.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/domain/entities/reading_stats.dart';
import 'package:qy_reader/domain/repositories/stats_repository.dart';
import 'package:qy_reader/features/my_reading/my_reading_data.dart';
import 'package:qy_reader/features/my_reading/my_reading_page.dart';
import 'package:qy_reader/features/my_reading/reading_share_sheet.dart';
import 'package:qy_reader/features/shelf/shelf_controller.dart';

class _FakeStats implements StatsRepository {
  const _FakeStats(this.totals);

  final List<BookReadingTotal> totals;

  @override
  Future<List<BookReadingTotal>> bookTotals() async => totals;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Book _book({
  required String id,
  required String title,
  String? author,
  BookReadStatus status = BookReadStatus.reading,
  int? lastOpenedAt,
  int updatedAt = 0,
}) {
  return Book(
    id: id,
    title: title,
    author: author,
    format: BookFormat.epub,
    filePath: '/tmp/$id.epub',
    fileSha256: id,
    fileSize: 1,
    addedAt: 0,
    updatedAt: updatedAt,
    lastOpenedAt: lastOpenedAt,
    readStatus: status,
    hlc: '0000000000000-00000-aaaaaaaa',
    deviceId: 'aaaaaaaa',
  );
}

Future<void> _pumpPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final books = [
    _book(
      id: 'r',
      title: '我要活下去',
      author: '金琸桓',
      lastOpenedAt: DateTime(2026, 11, 2).millisecondsSinceEpoch,
    ),
    _book(
      id: 'f',
      title: '被讨厌的勇气',
      author: '岸见一郎',
      status: BookReadStatus.finished,
      lastOpenedAt: DateTime(2026, 10, 29).millisecondsSinceEpoch,
    ),
  ];
  final items = [
    ShelfItem(book: books[0], percent: 0.008),
    ShelfItem(book: books[1], percent: 1),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        shelfItemsProvider.overrideWith((ref) => Stream.value(items)),
        statsRepositoryProvider.overrideWith(
          (ref) async => const _FakeStats([
            BookReadingTotal(bookId: 'r', durationMs: 38000, charsRead: 519),
            BookReadingTotal(
              bookId: 'f',
              durationMs: 3300000,
              charsRead: 42000,
            ),
          ]),
        ),
      ],
      child: const MaterialApp(home: MyReadingPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('时间线展示年月与阅读卡片，筛选和搜索生效', (tester) async {
    await _pumpPage(tester);

    expect(find.text('我的阅读'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('在读'), findsOneWidget);
    expect(find.text('搁置'), findsOneWidget);
    expect(find.text('读完'), findsOneWidget);
    expect(find.text('搜索 2 本书'), findsOneWidget);
    expect(find.text('2026年'), findsOneWidget);
    expect(find.text('11月'), findsOneWidget);
    expect(find.text('读到 0.8%'), findsOneWidget);
    expect(find.text('11月开始阅读 · 519 字 · 38 秒'), findsOneWidget);
    expect(find.text('2026年10月读完'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('my-reading-filter-reading')));
    await tester.pumpAndSettle();
    expect(find.text('我要活下去'), findsOneWidget);
    expect(find.text('被讨厌的勇气'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('my-reading-search')),
      '不存在',
    );
    await tester.pumpAndSettle();
    expect(find.text('没有找到匹配的书'), findsOneWidget);
  });

  testWidgets('分享面板：模板 / 保存 / 分享 / 取消四个动作', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final item = ShelfItem(
      book: _book(
        id: 'r',
        title: '我要活下去',
        author: '金琸桓',
        lastOpenedAt: DateTime(2026, 11, 2).millisecondsSinceEpoch,
      ),
      percent: 0.008,
    );
    final entries = myReadingBooks(
      items: [item],
      totals: const {
        'r': BookReadingTotal(bookId: 'r', durationMs: 38000, charsRead: 519),
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showReadingShareSheet(context, entries),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(ReadingShareSheet), findsOneWidget);
    expect(find.text('模板'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('QYReader 读者'), findsOneWidget);

    await tester.tap(find.text('模板'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(ReadingShareSheet), findsNothing);
  });
}
