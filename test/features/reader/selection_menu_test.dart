/// 选区菜单：复制 / 划线 / 高亮 / 笔记 / 从此听 五个入口。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/features/reader/reader_bridge_events.dart';
import 'package:qy_reader/features/reader/widgets/selection_menu.dart';

void main() {
  testWidgets('五个动作都能点击并回调', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final taps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              SelectionMenu(
                rect: const SelectionRect(
                  left: 20,
                  top: 300,
                  width: 1,
                  height: 1,
                ),
                theme: ReadingTheme.paper,
                onCopy: () => taps.add('copy'),
                onUnderline: () => taps.add('underline'),
                onHighlight: () => taps.add('highlight'),
                onNote: () => taps.add('note'),
                onListen: () => taps.add('listen'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('selection-menu')), findsOneWidget);
    expect(find.text('跨页'), findsNothing);
    for (final label in ['复制', '划线', '高亮', '笔记', '从此听']) {
      expect(find.text(label), findsOneWidget);
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(taps, ['copy', 'underline', 'highlight', 'note', 'listen']);
  });

  testWidgets('有未定位笔记时多一个「定位」入口', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var locateTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              SelectionMenu(
                rect: const SelectionRect(
                  left: 20,
                  top: 300,
                  width: 1,
                  height: 1,
                ),
                theme: ReadingTheme.paper,
                onCopy: () {},
                onUnderline: () {},
                onHighlight: () {},
                onNote: () {},
                onLocateNote: () => locateTaps++,
                onListen: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('定位'), findsOneWidget);
    await tester.tap(find.text('定位'));
    await tester.pump();
    expect(locateTaps, 1);
  });
}
