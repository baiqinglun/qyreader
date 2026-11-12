/// 书架展示形式（平铺/列表/封面）与列表、封面组件单测。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/shelf/shelf_prefs.dart';
import 'package:qy_reader/features/shelf/widgets/book_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

ShelfItem _item() => ShelfItem(
      book: Book(
        id: 'b1',
        title: '被讨厌的勇气',
        author: '岸见一郎',
        format: BookFormat.epub,
        filePath: '/tmp/b1.epub',
        fileSha256: 'sha',
        fileSize: 1,
        addedAt: 0,
        updatedAt: 0,
        rating: 4,
        tags: const ['心理学', '哲学'],
        hlc: '0000000000000-00000-aaaaaaaa',
        deviceId: 'aaaaaaaa',
      ),
      percent: 0.42,
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('展示形式偏好', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('默认平铺；切换列表后落盘', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(shelfViewModeControllerProvider),
        ShelfViewMode.grid,
      );
      await container
          .read(shelfViewModeControllerProvider.notifier)
          .set(ShelfViewMode.list);
      expect(
        container.read(shelfViewModeControllerProvider),
        ShelfViewMode.list,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('shelf.viewMode'), 'list');
    });

    test('未知值回退平铺', () async {
      SharedPreferences.setMockInitialValues({'shelf.viewMode': 'mosaic'});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(shelfViewModeControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        container.read(shelfViewModeControllerProvider),
        ShelfViewMode.grid,
      );
    });
  });

  group('列表行', () {
    testWidgets('显示书名/作者/标签/评分，点击打开、长按管理', (tester) async {
      var opened = 0;
      var managed = 0;
      await tester.pumpWidget(_host(BookListTile(
        item: _item(),
        showRating: true,
        showTags: true,
        onOpen: () => opened++,
        onManage: () => managed++,
      )));
      await tester.pumpAndSettle();

      expect(find.text('被讨厌的勇气'), findsOneWidget);
      expect(find.text('岸见一郎'), findsOneWidget);
      expect(find.text('心理学'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsWidgets);

      await tester.tap(find.text('被讨厌的勇气'));
      expect(opened, 1);

      await tester.longPress(find.text('被讨厌的勇气'));
      expect(managed, 1);
    });

    testWidgets('开关默认关闭：星级和标签不出现', (tester) async {
      await tester.pumpWidget(_host(BookListTile(
        item: _item(),
        onOpen: () {},
        onManage: () {},
      )));
      await tester.pumpAndSettle();

      expect(find.text('心理学'), findsNothing);
      expect(find.text('哲学'), findsNothing);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('封面格', () {
    testWidgets('只显示封面，不显示书名；点击打开、长按管理', (tester) async {
      var opened = 0;
      var managed = 0;
      await tester.pumpWidget(_host(SizedBox(
        width: 120,
        height: 168,
        child: BookCoverTile(
          item: _item(),
          onOpen: () => opened++,
          onManage: () => managed++,
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.text('被讨厌的勇气'), findsNothing);
      expect(find.text('岸见一郎'), findsNothing);
      // 无封面文件 → 占位图标
      expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu_book_outlined));
      expect(opened, 1);

      await tester.longPress(find.byIcon(Icons.menu_book_outlined));
      expect(managed, 1);
    });
  });

  group('阅读进度', () {
    testWidgets('网格卡片：封面右上角圆形进度 + 百分比', (tester) async {
      await tester.pumpWidget(_host(SizedBox(
        width: 160,
        height: 220,
        child: BookCard(
          item: _item().copyWith(percent: 0.42),
          onOpen: () {},
          onManage: () {},
        ),
      )));
      await tester.pumpAndSettle();

      final badge = find.byKey(const ValueKey('book-progress-b1'));
      expect(badge, findsOneWidget);
      final ring = tester.widget<CircularProgressIndicator>(
        find.descendant(
          of: badge,
          matching: find.byType(CircularProgressIndicator),
        ),
      );
      expect(ring.value, closeTo(0.42, 1e-9));
      expect(find.text('42%'), findsOneWidget);
    });

    testWidgets('网格卡片未读：不画进度，不出现不定值动画', (tester) async {
      await tester.pumpWidget(_host(SizedBox(
        width: 160,
        height: 220,
        child: BookCard(
          item: _item().copyWith(percent: 0),
          onOpen: () {},
          onManage: () {},
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.byType(BookProgressBadge), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('列表行未读时进度条为确定值 0', (tester) async {
      await tester.pumpWidget(_host(BookListTile(
        item: _item().copyWith(percent: 0),
        onOpen: () {},
        onManage: () {},
      )));
      await tester.pumpAndSettle();

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0);
      expect(find.text('未读'), findsOneWidget);
    });
  });
}
