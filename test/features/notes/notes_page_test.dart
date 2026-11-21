/// 「笔记回顾」两个页面：按书概览 + 卡片漫游。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/annotation.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/domain/entities/bookmark.dart';
import 'package:qy_reader/domain/entities/reading_stats.dart';
import 'package:qy_reader/features/my_reading/my_reading_page.dart';
import 'package:qy_reader/features/notes/notes_overview_page.dart';
import 'package:qy_reader/features/notes/notes_providers.dart';
import 'package:qy_reader/features/notes/notes_wander_page.dart';
import 'package:qy_reader/features/shelf/shelf_controller.dart';

Book _book(String id, String title, String author, String cover) => Book(
  id: id,
  title: title,
  author: author,
  format: BookFormat.epub,
  filePath: '/tmp/$id.epub',
  fileSha256: id,
  fileSize: 1,
  addedAt: 0,
  updatedAt: 0,
  coverPath: cover,
  readStatus: BookReadStatus.reading,
  hlc: '0000000000000-00000-aaaaaaaa',
  deviceId: 'aaaaaaaa',
);

Annotation _annotation(
  String id,
  String bookId, {
  required String quote,
  String? note,
  required DateTime at,
}) => Annotation(
  id: id,
  bookId: bookId,
  type: AnnotationType.highlight,
  color: AnnotationColor.yellow,
  locatorStart: '{}',
  locatorEnd: '{}',
  quotedText: quote,
  note: note,
  createdAt: at.millisecondsSinceEpoch,
  updatedAt: at.millisecondsSinceEpoch,
);

void main() {
  final b1 = ShelfItem(
    book: _book('b1', '苏东坡全传', '秦晓', '/tmp/b1.jpg'),
    percent: 0.4,
  );
  final b2 = ShelfItem(
    book: _book('b2', '沉默的大多数', '王小波', '/tmp/b2.jpg'),
    percent: 1,
  );
  final items = [b1, b2];
  final annotations = [
    _annotation(
      'a1',
      'b1',
      quote: '苏东坡就是有一种让自己开心的能力',
      at: DateTime(2025, 3, 4, 14, 1),
    ),
    _annotation(
      'a2',
      'b1',
      quote: '人间有味是清欢',
      note: '喜欢这句',
      at: DateTime(2025, 3, 3, 10),
    ),
    _annotation('a3', 'b2', quote: '沉默是一种生活方式', at: DateTime(2025, 3, 5, 9)),
  ];
  final bookmarks = [
    Bookmark(
      id: 'bm1',
      bookId: 'b1',
      locator: '{"chapterIndex":2}',
      label: '这里',
      createdAt: DateTime(2025, 3, 2, 8).millisecondsSinceEpoch,
    ),
  ];
  final totals = {
    'b1': const BookReadingTotal(
      bookId: 'b1',
      durationMs: 94 * 60 * 1000,
      charsRead: 42000,
    ),
    'b2': const BookReadingTotal(
      bookId: 'b2',
      durationMs: 36 * 60 * 1000,
      charsRead: 18000,
    ),
  };

  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shelfItemsProvider.overrideWith((ref) => Stream.value(items)),
          allAnnotationsProvider.overrideWith(
            (ref) => Stream.value(annotations),
          ),
          allBookmarksProvider.overrideWith((ref) => Stream.value(bookmarks)),
          myReadingTotalsProvider.overrideWith((ref) async => totals),
        ],
        child: MaterialApp(home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('笔记概览：按书汇总，搜索书名过滤', (tester) async {
    await pump(tester, const NotesOverviewPage());

    expect(find.text('笔记'), findsOneWidget);
    expect(find.text('搜索 4 条笔记'), findsOneWidget);
    expect(find.text('3 条笔记'), findsOneWidget);
    expect(find.text('1 条笔记'), findsOneWidget);
    expect(find.text('已读 1 小时 34 分钟 · 4.2 万字'), findsOneWidget);
    expect(find.text('苏东坡全传'), findsOneWidget);
    expect(find.text('沉默的大多数'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('notes-search')), '王小波');
    await tester.pumpAndSettle();
    expect(find.text('沉默的大多数'), findsOneWidget);
    expect(find.text('苏东坡全传'), findsNothing);
  });

  testWidgets('笔记漫游：类型切换、卡片翻页与页码', (tester) async {
    await pump(tester, const NotesWanderPage());

    expect(find.text('笔记漫游'), findsOneWidget);
    expect(find.byKey(const ValueKey('notes-kind-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('notes-kind-highlight')), findsOneWidget);
    expect(find.byKey(const ValueKey('notes-kind-bookmark')), findsOneWidget);
    expect(find.text('沉默是一种生活方式'), findsOneWidget);
    expect(find.text('1 / 4'), findsOneWidget);
    expect(find.text('25/03/05 09:00'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notes-kind-bookmark')));
    await tester.pumpAndSettle();
    expect(find.text('这里'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notes-kind-highlight')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
  });
}
