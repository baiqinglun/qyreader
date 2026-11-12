/// 书架首屏布局：分类卡和书卡排在同一套格子里（分类在前、一行 3 格）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/shelf/shelf_controller.dart';
import 'package:qy_reader/features/shelf/shelf_page.dart';
import 'package:qy_reader/features/shelf/widgets/book_card.dart';
import 'package:qy_reader/features/shelf/widgets/category_card.dart';
import 'package:qy_reader/features/settings/appearance_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ShelfItem _item(
  String id, {
  String? category,
  double percent = 0,
  int? rating,
  List<String> tags = const [],
}) =>
    ShelfItem(
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
        rating: rating,
        tags: tags,
        hlc: '0000000000000-00000-aaaaaaaa',
        deviceId: 'aaaaaaaa',
      ),
      percent: percent,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpShelf(WidgetTester tester, List<ShelfItem> items) async {
    // 360~430dp 的手机宽度：一行 3 格。
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        shelfItemsProvider.overrideWith((ref) => Stream.value(items)),
      ],
      child: const MaterialApp(home: ShelfPage()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('分类在前、没有分类的书散在后面，一行 3 格', (tester) async {
    await pumpShelf(tester, [
      _item('a', category: '小说'),
      _item('b', category: '历史'),
      _item('c'),
      _item('d'),
      _item('e'),
    ]);

    // 两个分类卡 + 三本没有分类的书；有分类的书只在分类里，不单独占格。
    expect(find.byType(CategoryCard), findsNWidgets(2));
    expect(find.byType(BookCard), findsNWidgets(3));
    expect(find.text('书a'), findsNothing);
    expect(find.text('书b'), findsNothing);

    final history = tester.getTopLeft(
      find.byKey(const ValueKey('category-历史')),
    );
    final novel = tester.getTopLeft(
      find.byKey(const ValueKey('category-小说')),
    );
    final first = tester.getTopLeft(find.byKey(const ValueKey('book-c')));

    // 分类按名字排序，并且排在散落的书前面。
    expect(history.dx, lessThan(novel.dx));
    expect(novel.dx, lessThan(first.dx));
    // 第一行就是「分类、分类、没有分类的书」三个。
    expect(history.dy, novel.dy);
    expect(first.dy, history.dy);
    // 第四本（书d）落到第二行。
    final second = tester.getTopLeft(find.byKey(const ValueKey('book-d')));
    expect(second.dy, greaterThan(first.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('点分类卡进入分类，返回书架首屏', (tester) async {
    await pumpShelf(tester, [
      _item('a', category: '小说'),
      _item('b', category: '历史'),
      _item('c'),
    ]);

    await tester.tap(find.byKey(const ValueKey('category-小说')));
    await tester.pumpAndSettle();

    // 只看到这个分类里的书，标题换成分类名。
    expect(find.byType(CategoryCard), findsNothing);
    expect(find.byType(BookCard), findsOneWidget);
    expect(find.byKey(const ValueKey('book-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('book-c')), findsNothing);
    expect(find.text('小说'), findsOneWidget); // AppBar 标题

    await tester.tap(find.byTooltip('返回书架'));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryCard), findsNWidgets(2));
    expect(find.byKey(const ValueKey('book-c')), findsOneWidget);
    expect(find.text('书架'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索书名：只显示命中的书，清空后恢复', (tester) async {
    await pumpShelf(tester, [
      _item('a', category: '小说'),
      _item('b', category: '历史'),
      _item('c'),
    ]);
    expect(find.byType(CategoryCard), findsNWidgets(2));

    await tester.enterText(find.byType(TextField), '书c');
    await tester.pumpAndSettle();

    // 搜索时压平展示：只剩命中的书，分类卡和别的书都不出现。
    expect(find.byType(CategoryCard), findsNothing);
    expect(find.byType(BookCard), findsOneWidget);
    expect(find.byKey(const ValueKey('book-c')), findsOneWidget);
    expect(find.byKey(const ValueKey('book-a')), findsNothing);

    await tester.enterText(find.byType(TextField), '不存在的书');
    await tester.pumpAndSettle();
    expect(find.textContaining('没有找到'), findsOneWidget);

    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(CategoryCard), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('导入入口在右上角展开菜单里，书架不再有悬浮按钮', (tester) async {
    await pumpShelf(tester, [_item('a'), _item('b')]);

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('导入书籍'), findsNothing);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('导入书籍'), findsOneWidget);
    expect(find.text('书架设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('「⋯」菜单里的书架设置能打开弹窗', (tester) async {
    await pumpShelf(tester, [_item('a'), _item('b')]);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书架设置'));
    await tester.pumpAndSettle();

    // 弹窗顶部是「网格 / 列表」分段胶囊，默认停在网格页。
    expect(find.text('网格'), findsOneWidget);
    expect(find.text('列表'), findsOneWidget);
    expect(find.byKey(const ValueKey('shelf-cover-radius')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置弹窗选「列表」书架跟着切列表，选「网格」切回', (tester) async {
    await pumpShelf(tester, [_item('a'), _item('b')]);
    expect(find.byType(BookCard), findsNWidgets(2));
    expect(find.byType(BookListTile), findsNothing);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书架设置'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('列表'));
    await tester.pumpAndSettle();
    expect(find.byType(BookListTile), findsNWidgets(2));
    expect(find.byType(BookCard), findsNothing);

    await tester.tap(find.text('网格'));
    await tester.pumpAndSettle();
    expect(find.byType(BookCard), findsNWidgets(2));
    expect(find.byType(BookListTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统返回键一次就退出分类', (tester) async {
    await pumpShelf(tester, [
      _item('a', category: '小说'),
      _item('b', category: '历史'),
      _item('c'),
    ]);

    await tester.tap(find.byKey(const ValueKey('category-小说')));
    await tester.pumpAndSettle();
    expect(find.byType(CategoryCard), findsNothing);
    expect(find.text('小说'), findsOneWidget); // AppBar 标题

    // 模拟 Android 系统返回键（flutter/navigation 的 popRoute）
    final message = const JSONMethodCodec()
        .encodeMethodCall(const MethodCall('popRoute'));
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.navigation.name,
      message,
      (_) {},
    );
    await tester.pumpAndSettle();

    // 一次返回就回到书架首屏，不会退出 App。
    expect(find.byType(CategoryCard), findsNWidgets(2));
    expect(find.text('书架'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('网格封面右上角显示圆形进度', (tester) async {
    await pumpShelf(tester, [_item('a', percent: 0.42)]);
    expect(find.byKey(const ValueKey('book-progress-a')), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
  });

  testWidgets('书架设置可关闭封面进度', (tester) async {
    SharedPreferences.setMockInitialValues({'shelf.grid.showProgress': false});
    await pumpShelf(tester, [_item('a', percent: 0.42)]);
    expect(find.byType(BookProgressBadge), findsNothing);
  });

  testWidgets('筛选：星级 + 标签，并在筛选范围内搜索', (tester) async {
    await pumpShelf(tester, [
      _item('a', rating: 5, tags: ['心理学']),
      _item('b', rating: 2, tags: ['小说']),
      _item('c', rating: 4, tags: ['心理学', '哲学']),
      _item('d'),
    ]);

    await tester.tap(find.byKey(const ValueKey('shelf-filter-button')));
    await tester.pumpAndSettle();
    expect(find.text('筛选'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('shelf-filter-rating-4')));
    await tester.tap(find.byKey(const ValueKey('shelf-filter-tag-心理学')));
    await tester.tap(find.byKey(const ValueKey('shelf-filter-apply')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('book-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('book-c')), findsOneWidget);
    expect(find.byKey(const ValueKey('book-b')), findsNothing);
    expect(find.byKey(const ValueKey('book-d')), findsNothing);

    await tester.enterText(find.byType(TextField), '书c');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('book-c')), findsOneWidget);
    expect(find.byKey(const ValueKey('book-a')), findsNothing);
  });

  testWidgets('多选：根目录只选没有分类的书，勾选后打开批量操作面板', (tester) async {
    await pumpShelf(tester, [
      _item('a', category: '小说', tags: ['心理学']),
      _item('b', category: '历史'),
      _item('c', tags: ['心理学']),
      _item('d', tags: ['心理学']),
    ]);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();

    expect(find.text('已选择 0 本'), findsOneWidget);
    // 根目录多选只铺没有分类的书：分类卡消失，分类里的书也不出现。
    expect(find.byType(CategoryCard), findsNothing);
    expect(find.byType(BookCard), findsNWidgets(2));
    expect(find.byKey(const ValueKey('book-a')), findsNothing);
    expect(find.byKey(const ValueKey('book-b')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('book-c')));
    await tester.tap(find.byKey(const ValueKey('book-d')));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 本'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('batch-tag-button')));
    await tester.pumpAndSettle();
    expect(find.text('给 2 本书加标签'), findsOneWidget);
    expect(find.byKey(const ValueKey('batch-tag-known-心理学')), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('batch-shelf-button')));
    await tester.pumpAndSettle();
    expect(find.text('把 2 本书添加到分组'), findsOneWidget);
    expect(find.byKey(const ValueKey('batch-shelf-小说')), findsOneWidget);
    expect(find.byKey(const ValueKey('batch-shelf-历史')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 批量删除走确认弹窗（测试里不真正删库）。
    await tester.tap(find.byKey(const ValueKey('batch-delete-button')));
    await tester.pumpAndSettle();
    expect(find.text('删除 2 本书'), findsOneWidget);
    // 「删除全部」要再过一次危险确认；取消后什么都不会删。
    await tester.tap(find.byKey(const ValueKey('batch-delete-all')));
    await tester.pumpAndSettle();
    expect(find.text('危险操作'), findsOneWidget);
    expect(find.byKey(const ValueKey('danger-delete-confirm')), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    expect(find.text('书架'), findsOneWidget);
    expect(find.byType(CategoryCard), findsNWidgets(2));
  });

  testWidgets('分类里多选只选该分类的书', (tester) async {
    await pumpShelf(tester, [
      _item('a', category: '小说'),
      _item('b', category: '小说'),
      _item('c'),
    ]);

    await tester.tap(find.byKey(const ValueKey('category-小说')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();

    // 只摆「小说」分类的两本书，分类外的 c 不出现。
    expect(find.byType(BookCard), findsNWidgets(2));
    expect(find.byKey(const ValueKey('book-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('book-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('book-c')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('book-a')));
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 本'), findsOneWidget);
  });

  testWidgets('右上角有直接同步按钮与亮暗切换按钮，点切换会改主题模式', (tester) async {
    await pumpShelf(tester, [_item('a')]);

    expect(find.byKey(const ValueKey('shelf-sync-button')), findsOneWidget);
    final modeButton = find.byKey(const ValueKey('shelf-theme-mode-button'));
    expect(modeButton, findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShelfPage)),
    );
    expect(
      container.read(appThemeModeControllerProvider),
      AppThemeMode.system,
    );

    // 测试环境是亮色：点一次应切成暗色（按钮按当前 Theme 亮度决定方向）
    await tester.tap(modeButton);
    await tester.pumpAndSettle();
    expect(container.read(appThemeModeControllerProvider), AppThemeMode.dark);
  });
}