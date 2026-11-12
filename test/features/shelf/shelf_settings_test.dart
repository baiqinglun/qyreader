/// 书架设置弹窗 + 架板/圆角/列表开关的组件测试。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/shelf/shelf_controller.dart';
import 'package:qy_reader/features/shelf/shelf_prefs.dart';
import 'package:qy_reader/features/shelf/widgets/book_card.dart';
import 'package:qy_reader/features/shelf/widgets/category_card.dart';
import 'package:qy_reader/features/shelf/widgets/shelf_flow.dart';
import 'package:qy_reader/features/shelf/widgets/shelf_plank.dart';
import 'package:qy_reader/features/shelf/widgets/shelf_settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

ShelfItem _item(
  String id, {
  String? description,
  String? review,
  List<String> tags = const [],
  int? rating,
}) =>
    ShelfItem(
      book: Book(
        id: id,
        title: '书$id',
        author: '作者$id',
        description: description,
        review: review,
        rating: rating,
        tags: tags,
        format: BookFormat.epub,
        filePath: '/tmp/$id.epub',
        fileSha256: 'sha$id',
        fileSize: 1,
        addedAt: 0,
        updatedAt: 0,
        hlc: '0000000000000-00000-aaaaaaaa',
        deviceId: 'aaaaaaaa',
      ),
      percent: 0.42,
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('书架设置弹窗', () {
    Future<ProviderContainer> pumpSheet(
      WidgetTester tester, {
      ProviderContainer? container,
    }) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scope = container ?? ProviderContainer();
      if (container == null) addTearDown(scope.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: scope,
        child: const MaterialApp(home: Scaffold(body: ShelfSettingsSheet())),
      ));
      await tester.pumpAndSettle();
      return scope;
    }

    testWidgets('网格页：圆角滑杆 + 单行数量 + 架板样式 + 进度开关', (tester) async {
      await pumpSheet(tester);

      expect(find.text('书架设置'), findsOneWidget);
      expect(find.text('网格'), findsOneWidget);
      expect(find.text('列表'), findsOneWidget);
      expect(find.byKey(const ValueKey('shelf-cover-radius')), findsOneWidget);
      expect(find.byKey(const ValueKey('shelf-columns')), findsOneWidget);
      expect(find.byKey(const ValueKey('shelf-plank-style')), findsOneWidget);
      expect(find.byKey(const ValueKey('shelf-show-progress')), findsOneWidget);
      expect(find.byKey(const ValueKey('shelf-sort-field')), findsOneWidget);
      expect(find.byKey(const ValueKey('shelf-sort-direction')), findsOneWidget);
      expect(find.text('最近阅读'), findsOneWidget);
      expect(find.text('降序'), findsOneWidget);
      expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('shelf-show-progress')))
            .value,
        isTrue,
      );
      expect(find.text('20'), findsOneWidget); // 默认圆角
      expect(tester.takeException(), isNull);
    });

    testWidgets('排序：字段下拉与升 / 降序切换', (tester) async {
      final container = await pumpSheet(tester);

      await tester.tap(find.byKey(const ValueKey('shelf-sort-direction')));
      await tester.pumpAndSettle();
      expect(find.text('升序'), findsOneWidget);
      expect(
        container.read(shelfPrefsControllerProvider).sortAscending,
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('shelf-sort-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('书名').last);
      await tester.pumpAndSettle();
      expect(
        container.read(shelfPrefsControllerProvider).sortField,
        ShelfSortField.title,
      );
    });

    testWidgets('列表页：六个控件齐全，开关默认关闭、行数 2', (tester) async {
      await pumpSheet(tester);

      await tester.tap(find.text('列表'));
      await tester.pumpAndSettle();

      for (final key in const [
        'shelf-show-rating',
        'shelf-show-tags',
        'shelf-show-description',
        'shelf-description-lines',
        'shelf-show-review',
        'shelf-review-lines',
      ]) {
        expect(
          find.byKey(ValueKey(key)),
          findsOneWidget,
          reason: '列表页缺少控件 $key',
        );
      }
      expect(find.text('2 行'), findsNWidgets(2));
      for (final key in const [
        'shelf-show-rating',
        'shelf-show-tags',
        'shelf-show-description',
        'shelf-show-review',
      ]) {
        expect(tester.widget<Switch>(find.byKey(ValueKey(key))).value, isFalse);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('选「列表」页签把书架切成列表，选「网格」切回网格', (tester) async {
      final container = await pumpSheet(tester);
      expect(
        container.read(shelfViewModeControllerProvider),
        ShelfViewMode.grid,
      );

      await tester.tap(find.text('列表'));
      await tester.pumpAndSettle();
      expect(
        container.read(shelfViewModeControllerProvider),
        ShelfViewMode.list,
      );
      expect(find.byKey(const ValueKey('shelf-show-rating')), findsOneWidget);

      await tester.tap(find.text('网格'));
      await tester.pumpAndSettle();
      expect(
        container.read(shelfViewModeControllerProvider),
        ShelfViewMode.grid,
      );
      expect(find.byKey(const ValueKey('shelf-show-rating')), findsNothing);
    });

    testWidgets('书架已在列表模式时，弹窗默认停在列表页', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(shelfViewModeControllerProvider.notifier)
          .set(ShelfViewMode.list);

      await pumpSheet(tester, container: container);
      expect(find.byKey(const ValueKey('shelf-show-rating')), findsOneWidget);
      expect(find.byKey(const ValueKey('shelf-cover-radius')), findsNothing);
    });

    testWidgets('改圆角/列数/开关会即时生效并落盘', (tester) async {
      final container = await pumpSheet(tester);

      // 圆角滑杆：从 20 往左拖，值变小。
      await tester.drag(
        find.byKey(const ValueKey('shelf-cover-radius')),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(shelfPrefsControllerProvider).coverRadius,
        lessThan(20),
      );

      // 单行数量下拉选 5。
      await tester.tap(find.byKey(const ValueKey('shelf-columns')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5').last);
      await tester.pumpAndSettle();
      expect(
        container.read(shelfPrefsControllerProvider).columns,
        ShelfColumnCount.five,
      );

      // 列表页打开星级，行数调到 3。
      await tester.tap(find.text('列表'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shelf-show-rating')));
      await tester.pumpAndSettle();
      expect(
        container.read(shelfPrefsControllerProvider).showRating,
        isTrue,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('shelf.columns'), 'five');
      expect(prefs.getBool('shelf.list.showRating'), isTrue);
      expect(
        prefs.getInt('shelf.coverRadius'),
        container.read(shelfPrefsControllerProvider).coverRadius,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('网格架板与圆角', () {
    Future<void> pumpFlow(
      WidgetTester tester, {
      int columns = 3,
      double coverRadius = 20,
      ShelfPlankStyle plankStyle = ShelfPlankStyle.wood,
      int count = 5,
      Size size = const Size(400, 900),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final items = [for (var i = 0; i < count; i++) _item('b$i')];
      await tester.pumpWidget(_host(CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: ShelfFlow(
              cells: [for (final item in items) ShelfBookCell(item)],
              mode: ShelfViewMode.grid,
              columns: columns,
              coverRadius: coverRadius,
              plankStyle: plankStyle,
              onOpenBook: (_) {},
              onManageBook: (_) {},
              onOpenCategory: (_) {},
            ),
          ),
        ],
      )));
      await tester.pumpAndSettle();
    }

    testWidgets('每一行书下面一条木纹架板', (tester) async {
      await pumpFlow(tester);
      // 5 本书、一行 3 格 → 两行，两行各一条架板。
      expect(find.byType(BookCard), findsNWidgets(5));
      expect(find.byType(ShelfPlank), findsNWidgets(2));
      for (final plank in tester.widgetList<ShelfPlank>(
        find.byType(ShelfPlank),
      )) {
        expect(plank.style, ShelfPlankStyle.wood);
      }
      // 架板必须横贯整行（0 宽度是回归过的 bug：Column 没有 stretch）。
      expect(
        tester.getSize(find.byType(ShelfPlank).first).width,
        greaterThan(0),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('架板样式「无」时不画架板', (tester) async {
      await pumpFlow(tester, plankStyle: ShelfPlankStyle.none);
      expect(find.byType(BookCard), findsNWidgets(5));
      expect(find.byType(ShelfPlank), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('固定 4 列：第一行摆 4 本', (tester) async {
      await pumpFlow(tester, columns: 4, count: 5);
      final cards = find.byType(BookCard);
      final y0 = tester.getTopLeft(cards.at(0)).dy;
      for (var i = 1; i < 4; i++) {
        expect(tester.getTopLeft(cards.at(i)).dy, y0);
      }
      expect(tester.getTopLeft(cards.at(4)).dy, greaterThan(y0));
      expect(find.byType(ShelfPlank), findsNWidgets(2));
    });

    testWidgets('窄屏固定 5 列：只显示封面，不溢出', (tester) async {
      await pumpFlow(
        tester,
        columns: 5,
        count: 6,
        size: const Size(360, 800),
      );
      expect(find.byType(BookCard), findsNWidgets(6));
      // 网格只留封面 + 右上角进度，书名/作者/评分/标签都不出现。
      expect(find.text('作者b0'), findsNothing);
      expect(find.text('书b0'), findsNothing);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      expect(find.text('未读'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('圆角传给书卡/封面格/分类卡', (tester) async {
      await pumpFlow(tester, coverRadius: 6);
      final cardClip = tester.widget<ClipRRect>(
        find
            .descendant(
              of: find.byType(BookCard).first,
              matching: find.byType(ClipRRect),
            )
            .first,
      );
      expect((cardClip.borderRadius as BorderRadius).topLeft.x, 6);

      await tester.pumpWidget(_host(SizedBox(
        width: 120,
        height: 168,
        child: BookCoverTile(
          item: _item('c'),
          coverRadius: 4,
          onOpen: () {},
          onManage: () {},
        ),
      )));
      await tester.pumpAndSettle();
      final clip = tester.widget<ClipRRect>(find.byType(ClipRRect).first);
      expect((clip.borderRadius as BorderRadius).topLeft.x, 4);

      await tester.pumpWidget(_host(SizedBox(
        width: 120,
        height: 168,
        child: CategoryCard(
          title: '文学',
          items: [_item('d')],
          coverRadius: 7,
          onOpen: () {},
        ),
      )));
      await tester.pumpAndSettle();
      final categoryCard = tester.widget<Card>(find.byType(Card));
      final categoryShape =
          categoryCard.shape! as RoundedRectangleBorder;
      expect(
        (categoryShape.borderRadius as BorderRadius).topLeft.x,
        7,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('列表行内容开关', () {
    const description = '这是一段用来验证简介开关与行数的文字。';
    const review = '这是一段用来验证书评开关与行数的书评文字。';

    testWidgets('四组内容按开关显示，行数跟随设置', (tester) async {
      await tester.pumpWidget(_host(BookListTile(
        item: _item(
          'x',
          description: description,
          review: review,
          tags: const ['心理学', '哲学'],
          rating: 4,
        ),
        showRating: true,
        showTags: true,
        showDescription: true,
        descriptionLines: 1,
        showReview: true,
        reviewLines: 3,
        onOpen: () {},
        onManage: () {},
      )));
      await tester.pumpAndSettle();

      expect(find.text('心理学'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsWidgets);
      expect(find.text(description), findsOneWidget);
      expect(find.text(review), findsOneWidget);
      expect(find.byIcon(Icons.format_quote_rounded), findsOneWidget);
      expect(tester.widget<Text>(find.text(description)).maxLines, 1);
      expect(tester.widget<Text>(find.text(review)).maxLines, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('全部关掉后不再插入简介/书评，行高收紧', (tester) async {
      await tester.pumpWidget(_host(BookListTile(
        item: _item('x', description: description, review: review),
        showDescription: true,
        descriptionLines: 4,
        showReview: true,
        reviewLines: 4,
        onOpen: () {},
        onManage: () {},
      )));
      await tester.pumpAndSettle();
      final tall = tester.getSize(find.byType(BookListTile)).height;

      await tester.pumpWidget(_host(BookListTile(
        item: _item('x', description: description, review: review),
        onOpen: () {},
        onManage: () {},
      )));
      await tester.pumpAndSettle();
      final compact = tester.getSize(find.byType(BookListTile)).height;

      expect(find.text(description), findsNothing);
      expect(find.text(review), findsNothing);
      expect(compact, lessThan(tall));
      expect(tester.takeException(), isNull);
    });
  });
}
