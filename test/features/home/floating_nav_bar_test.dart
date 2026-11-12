/// 底栏胶囊：切换 Tab 时胶囊滑过去（不是原地淡入）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/home/widgets/floating_nav_bar.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 390, child: child),
        ),
      ),
    );

void main() {
  testWidgets('选中胶囊从第 1 格滑到第 2 格', (tester) async {
    var index = 0;
    await tester.pumpWidget(StatefulBuilder(
      builder: (context, setState) => _host(FloatingNavBar(
        index: index,
        onSelect: (i) => setState(() => index = i),
      )),
    ));
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.byKey(const ValueKey('nav-bar')));
    final itemWidth = bar.width / kHomeTabs.length;
    final pill = find.byKey(const ValueKey('nav-pill'));

    final before = tester.getRect(pill);
    expect(before.left, closeTo(bar.left + 10, 0.5));
    expect(before.width, closeTo(itemWidth - 20, 0.5));

    await tester.tap(find.text('统计'));
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
    expect(picked, [2]);
  });
}
