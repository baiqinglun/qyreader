/// 打开 / 关闭书籍转场单测：位置登记 + 动画相位。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/transitions/book_open_transition.dart';

const _coverKey = ValueKey('book-open-cover');

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('BookCoverRegistry', () {
    tearDown(() {
      BookCoverRegistry.remove(BookLaunchKind.card, 'b1');
      BookCoverRegistry.remove(BookLaunchKind.spine, 'b1');
    });

    test('登记 / 查询 / 注销；同一本书的卡片与书脊互不干扰', () {
      const cardRect = Rect.fromLTWH(16, 100, 160, 220);
      const spineRect = Rect.fromLTWH(40, 300, 34, 140);
      BookCoverRegistry.report(BookLaunchKind.card, 'b1', cardRect);
      BookCoverRegistry.report(
        BookLaunchKind.spine,
        'b1',
        spineRect,
        gradient: const LinearGradient(colors: [Colors.red, Colors.blue]),
      );
      expect(BookCoverRegistry.spotOf(BookLaunchKind.card, 'b1')!.rect, cardRect);
      expect(BookCoverRegistry.spotOf(BookLaunchKind.spine, 'b1')!.rect, spineRect);
      expect(
        BookCoverRegistry.spotOf(BookLaunchKind.spine, 'b1')!.gradient,
        isNotNull,
      );

      BookCoverRegistry.remove(BookLaunchKind.spine, 'b1');
      expect(BookCoverRegistry.spotOf(BookLaunchKind.spine, 'b1'), isNull);
      expect(BookCoverRegistry.spotOf(BookLaunchKind.card, 'b1')!.rect, cardRect);
    });
  });

  testWidgets('定位探针把子组件的位置登记进来，销毁时注销', (tester) async {
    await tester.pumpWidget(_host(
      Center(
        child: BookCoverRectProbe(
          kind: BookLaunchKind.card,
          bookId: 'probe',
          solid: Colors.grey,
          child: const SizedBox(width: 100, height: 80),
        ),
      ),
    ));
    await tester.pump();

    final spot = BookCoverRegistry.spotOf(BookLaunchKind.card, 'probe');
    expect(spot, isNotNull);
    expect(spot!.rect.size, const Size(100, 80));

    await tester.pumpWidget(_host(const SizedBox.shrink()));
    expect(BookCoverRegistry.spotOf(BookLaunchKind.card, 'probe'), isNull);
  });

  group('BookOpenTransition', () {
    testWidgets('起点：书封盖在书架上那本书的矩形上，阅读页被裁到该矩形', (tester) async {
      const rect = Rect.fromLTWH(24, 200, 120, 170);
      BookCoverRegistry.report(BookLaunchKind.card, 't1', rect);
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 400),
        value: 0,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(
        BookOpenTransition(
          animation: controller,
          launch: const BookLaunch(
            bookId: 't1',
            kind: BookLaunchKind.card,
            coverPath: '/nonexistent/cover.jpg',
          ),
          child: const ColoredBox(color: Colors.white),
        ),
      ));
      await tester.pump();

      // 书封存在，且矩形等于登记位置（屏幕坐标）
      expect(find.byKey(_coverKey), findsOneWidget);
      final box = tester.getRect(find.byKey(_coverKey));
      expect(box.left, closeTo(rect.left, 0.5));
      expect(box.top, closeTo(rect.top, 0.5));
      expect(box.width, closeTo(rect.width, 0.5));
      expect(box.height, closeTo(rect.height, 0.5));

      // 阅读页被 ClipRect 包住（转场外面露出书架）
      expect(find.byType(ClipRect), findsWidgets);
    });

    testWidgets('终点：书封消失，阅读页完整显示', (tester) async {
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 400),
        value: 1,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(
        BookOpenTransition(
          animation: controller,
          launch: const BookLaunch(
            bookId: 't2',
            kind: BookLaunchKind.spine,
            rect: Rect.fromLTWH(30, 320, 34, 140),
          ),
          child: const ColoredBox(color: Colors.white),
        ),
      ));
      await tester.pump();

      expect(find.byKey(_coverKey), findsNothing);
      // 书脊没有封面图，用登记渐变兜底；不应抛异常
      expect(tester.takeException(), isNull);
    });

    testWidgets('无来源（深链 / 统计页）走淡入淡出，不渲染书封', (tester) async {
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 400),
        value: 0.5,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(
        BookOpenTransition(
          animation: controller,
          launch: null,
          child: const ColoredBox(color: Colors.white),
        ),
      ));
      await tester.pump();
      expect(find.byKey(_coverKey), findsNothing);
      expect(find.byType(FadeTransition), findsWidgets);
    });

    testWidgets('退出半程：书封重新盖上来，阅读页随矩形缩小', (tester) async {
      const rect = Rect.fromLTWH(24, 200, 120, 170);
      BookCoverRegistry.report(BookLaunchKind.card, 't3', rect);
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 400),
        value: 1,
      )..reverse();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(
        BookOpenTransition(
          animation: controller,
          launch: const BookLaunch(
            bookId: 't3',
            kind: BookLaunchKind.card,
          ),
          child: const ColoredBox(color: Colors.white),
        ),
      ));
      // 推到反向动画约一半（书封已出现、矩形已缩回一半）
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 100));

      final cover = find.byKey(_coverKey);
      expect(cover, findsOneWidget);
      final box = tester.getRect(cover);
      // 书封已出现，矩形在全屏与书架原位之间
      expect(box.width, greaterThan(rect.width));
      expect(box.width, lessThan(800));
      // 收回方向：顶部仍从书封左侧开始收（不是整屏淡出）
      expect(box.left, greaterThan(0));
      expect(tester.takeException(), isNull);

      // 收尾：把反向动画跑完，避免测试结束时还有活动 Ticker
      await tester.pump(const Duration(milliseconds: 400));
    });
    testWidgets('退出刚开始书封就浮现，一路缩回书架原位', (tester) async {
      const rect = Rect.fromLTWH(24, 200, 120, 170);
      BookCoverRegistry.report(BookLaunchKind.card, 't4', rect);
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 1000),
        value: 1,
      )..reverse();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(
        BookOpenTransition(
          animation: controller,
          launch: const BookLaunch(
            bookId: 't4',
            kind: BookLaunchKind.card,
          ),
          child: const ColoredBox(color: Colors.white),
        ),
      ));
      // 反向动画刚开始（v≈0.9）：旧实现这时书封还完全透明，新实现已开始浮现。
      await tester.pump(const Duration(milliseconds: 100));
      final cover = find.byKey(_coverKey);
      expect(cover, findsOneWidget);
      expect(tester.getRect(cover).width, greaterThan(rect.width));

      // 封面正朝观众「抬」起来：有轻微放大（不是一上来就往回缩）。
      final lift = tester.widget<Transform>(
        find.byKey(const ValueKey('book-open-cover-lift')),
      );
      expect(lift.transform.getMaxScaleOnAxis(), greaterThan(1.0));

      // 收尾：矩形缩回书架原位（书封盖住那一格），放大回落到 1。
      await tester.pump(const Duration(milliseconds: 900));
      final end = tester.getRect(cover);
      expect(end.width, closeTo(rect.width, 1));
      expect(end.left, closeTo(rect.left, 1));
      expect(end.top, closeTo(rect.top, 1));
      final settledLift = tester.widget<Transform>(
        find.byKey(const ValueKey('book-open-cover-lift')),
      );
      expect(settledLift.transform.getMaxScaleOnAxis(), closeTo(1.0, 0.001));

      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
