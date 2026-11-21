/// 底栏胶囊：切换 Tab 时胶囊滑过去（不是原地淡入）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/home/home_tabs.dart';
import 'package:qy_reader/features/home/widgets/floating_nav_bar.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 390, child: child)),
  ),
);

void main() {
  testWidgets('选中胶囊从第 1 格滑到第 2 格', (tester) async {
    var index = 0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _host(
          FloatingNavBar(
            index: index,
            onSelect: (i) => setState(() => index = i),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.byKey(const ValueKey('nav-bar')));
    final itemWidth = bar.width / kHomeTabs.length;
    final pill = find.byKey(const ValueKey('nav-pill'));

    final before = tester.getRect(pill);
    expect(before.left, closeTo(bar.left + 10, 0.5));
    expect(before.width, closeTo(itemWidth - 20, 0.5));

    await tester.tap(find.text('书架'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final middle = tester.getRect(pill);
    expect(middle.left, greaterThan(before.left), reason: '动画中胶囊应已在路上');
    expect(middle.left, lessThan(bar.left + 10 + itemWidth));

    await tester.pumpAndSettle();
    final after = tester.getRect(pill);
    expect(after.left, closeTo(bar.left + 10 + itemWidth, 0.5));
  });

  testWidgets('点 Tab 回传下标', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(
      _host(FloatingNavBar(index: 0, onSelect: picked.add)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置'));
    expect(picked, [3]);
  });

  testWidgets('宽屏底栏居中且限宽，不拉满整屏', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 1400,
              child: FloatingNavBar(index: 0, onSelect: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.byKey(const ValueKey('nav-bar')));
    expect(bar.width, closeTo(600, 0.5), reason: '限宽 640 再左右各留 20');
    expect(bar.center.dx, closeTo(700, 0.5), reason: '底栏应水平居中');
  });

  testWidgets('作为 bottomNavigationBar 时只占自身高度，body 不被挤没', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(key: ValueKey('page-body')),
          bottomNavigationBar: FloatingNavBar(index: 0, onSelect: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final body = tester.getRect(find.byKey(const ValueKey('page-body')));
    final bar = tester.getRect(find.byKey(const ValueKey('nav-bar')));
    expect(body.height, closeTo(844 - 76, 1), reason: 'body 应占满底栏以上');
    expect(bar.bottom, closeTo(844 - 10, 1), reason: '底栏贴底（留 10dp）');
    expect(bar.top, greaterThan(700), reason: '底栏不能浮到屏幕中间');
  });
}
