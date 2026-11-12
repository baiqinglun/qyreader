/// 分类卡片：2×2 书位（前 4 本封面，其余留空白书）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/shelf/widgets/category_card.dart';

ShelfItem _item(String id, {String? category, String? cover}) => ShelfItem(
      book: Book(
        id: id,
        title: '书$id',
        format: BookFormat.epub,
        filePath: '/tmp/$id.epub',
        fileSha256: 'sha$id',
        fileSize: 1,
        addedAt: 0,
        updatedAt: 0,
        category: category,
        coverPath: cover,
        hlc: '0000000000000-00000-aaaaaaaa',
        deviceId: 'aaaaaaaa',
      ),
      percent: 0,
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// 一张书架格子的尺寸（360dp 手机、一行 3 格）。
Widget _cell(Widget child) => SizedBox(width: 106, height: 147, child: child);

void main() {
  group('CategoryCard', () {
    testWidgets('两本书：2 个书位有封面、2 个是空白书', (tester) async {
      await tester.pumpWidget(_host(_cell(CategoryCard(
        title: '文学',
        items: [_item('a0', category: '文学'), _item('a1', category: '文学')],
        onOpen: () {},
      ))));
      await tester.pumpAndSettle();

      for (var i = 0; i < kCategorySlots; i++) {
        final filled = find.byKey(ValueKey('category-slot-$i-filled'));
        final empty = find.byKey(ValueKey('category-slot-$i-empty'));
        expect(filled.evaluate().length + empty.evaluate().length, 1,
            reason: '书位 $i 必须占一格');
        if (i < 2) {
          expect(filled, findsOneWidget, reason: '前两格应是封面');
        } else {
          expect(empty, findsOneWidget, reason: '后两格应是空白书');
        }
      }
      // 卡面不写分类名 / 本数（名称只给读屏）。
      expect(find.text('文学'), findsNothing);
      expect(find.textContaining('本'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('只摆前 4 本', (tester) async {
      await tester.pumpWidget(_host(_cell(CategoryCard(
        title: '文学',
        items: [
          for (var i = 0; i < 6; i++) _item('a$i', category: '文学'),
        ],
        onOpen: () {},
      ))));
      await tester.pumpAndSettle();

      for (var i = 0; i < kCategorySlots; i++) {
        expect(find.byKey(ValueKey('category-slot-$i-filled')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('category-slot-4-filled')), findsNothing);
      expect(find.text('6 本'), findsNothing);
    });

    testWidgets('空分类：4 个书位全是空白书', (tester) async {
      await tester.pumpWidget(_host(_cell(CategoryCard(
        title: '历史',
        items: const [],
        onOpen: () {},
      ))));
      await tester.pumpAndSettle();

      for (var i = 0; i < kCategorySlots; i++) {
        expect(
          find.byKey(ValueKey('category-slot-$i-empty')),
          findsOneWidget,
          reason: '空分类第 $i 格必须是空白书',
        );
        expect(find.byKey(ValueKey('category-slot-$i-filled')), findsNothing);
      }
      expect(find.text('0 本'), findsNothing);
    });

    testWidgets('点卡片打开分类', (tester) async {
      var opened = 0;
      await tester.pumpWidget(_host(_cell(CategoryCard(
        title: '文学',
        items: [_item('a0', category: '文学')],
        onOpen: () => opened++,
      ))));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CategoryCard));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });
  });

  group('CategoryListTile', () {
    testWidgets('显示分类名和本数，点击打开', (tester) async {
      var opened = 0;
      await tester.pumpWidget(_host(CategoryListTile(
        title: '历史',
        items: [_item('b0', category: '历史'), _item('b1', category: '历史')],
        onOpen: () => opened++,
      )));
      await tester.pumpAndSettle();

      expect(find.text('历史'), findsOneWidget);
      expect(find.text('2 本'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('历史'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });
  });
}
