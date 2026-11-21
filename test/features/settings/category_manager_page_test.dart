/// 分类管理页（层级）：建树渲染 / 折叠展开 / 搜索 / 新建（含空分类）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/settings/category_manager_page.dart';
import 'package:qy_reader/features/shelf/shelf_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

ShelfItem _item(String id, String category) => ShelfItem(
  book: Book(
    id: id,
    title: '书$id',
    format: BookFormat.epub,
    filePath: '/tmp/$id.epub',
    fileSha256: id,
    fileSize: 1,
    addedAt: 0,
    updatedAt: 0,
    category: category,
    hlc: '0000000000000-00000-aaaaaaaa',
    deviceId: 'aaaaaaaa',
  ),
  percent: 0,
);

Future<void> _pump(WidgetTester tester, {List<Override> overrides = const []}) async {
  await tester.pumpWidget(
    ProviderScope(overrides: overrides, child: const MaterialApp(home: CategoryManagerPage())),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('层级渲染：小说行可折叠，子分类缩进显示且计数含后代', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      overrides: [
        shelfItemsProvider.overrideWith((ref) => Stream.value([
          _item('b1', '小说'),
          _item('b2', '小说/科幻'),
          _item('b3', '文学'),
        ])),
      ],
    );

    // 头部：分类总数（小说/科幻/文学 = 3）+ 收起全部
    expect(find.text('3 个分类'), findsOneWidget);
    expect(find.text('小说'), findsOneWidget);
    expect(find.text('科幻'), findsOneWidget);
    expect(find.text('文学'), findsOneWidget);
    expect(find.text('收起全部'), findsOneWidget);

    // 折叠小说：科幻隐藏
    await tester.tap(find.text('收起全部'));
    await tester.pumpAndSettle();
    expect(find.text('科幻'), findsNothing);
    expect(find.text('展开全部'), findsOneWidget);

    await tester.tap(find.text('展开全部'));
    await tester.pumpAndSettle();
    expect(find.text('科幻'), findsOneWidget);
  });

  testWidgets('搜索：只显示匹配的分类', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      overrides: [
        shelfItemsProvider.overrideWith((ref) => Stream.value([
          _item('b1', '小说'),
          _item('b2', '文学'),
        ])),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('category-search-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('category-search-field')),
      '文学',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('category-row-文学')), findsOneWidget);
    expect(find.byKey(const ValueKey('category-row-小说')), findsNothing);
  });

  testWidgets('新建分类（含层级路径）与空分类计数 0', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      overrides: [
        shelfItemsProvider.overrideWith((ref) => Stream.value([
          _item('b1', '小说'),
        ])),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('category-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '待读/书单');
    await tester.tap(find.byKey(const ValueKey('category-name-confirm')));
    await tester.pumpAndSettle();

    // 顶层出现「待读」（空分类 0 本），初始展开可见子分类「书单」
    expect(find.byKey(const ValueKey('category-row-待读')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('category-row-待读/书单')),
      findsOneWidget,
    );
    // 折叠后隐藏
    await tester.tap(find.byKey(const ValueKey('category-toggle-待读')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('category-row-待读/书单')), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('categories.extra'), contains('待读/书单'));
  });
}
