/// 页面布局：九宫格动作、页眉页脚跟随、持久化与编辑器交互。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/reader/page_layout.dart';
import 'package:qy_reader/features/reader/widgets/page_layout_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('默认布局：左列上一页、中列菜单、右列下一页', () {
    const layout = PageLayoutSettings.defaults;
    const size = Size(300, 600);
    expect(
      layout.actionAt(const Offset(20, 300), size),
      TapZoneAction.previousPage,
    );
    expect(layout.actionAt(const Offset(150, 300), size), TapZoneAction.menu);
    expect(
      layout.actionAt(const Offset(280, 300), size),
      TapZoneAction.nextPage,
    );
    // 三行同一列动作一致。
    expect(
      layout.actionAt(const Offset(20, 40), size),
      TapZoneAction.previousPage,
    );
    expect(
      layout.actionAt(const Offset(280, 580), size),
      TapZoneAction.nextPage,
    );
  });

  test('自定义九宫格与页眉页脚覆盖', () {
    final layout = PageLayoutSettings.defaults
        .withZone(0, TapZoneAction.nextPage)
        .copyWith(
          headerLeft: EdgeZoneAction.menu,
          footerRight: EdgeZoneAction.previousPage,
        );
    const size = Size(300, 600);
    expect(
      layout.actionAt(const Offset(20, 10), size, headerHeight: 30),
      TapZoneAction.menu,
    );
    expect(
      layout.actionAt(const Offset(20, 100), size),
      TapZoneAction.nextPage,
    );
    expect(
      layout.actionAt(const Offset(280, 590), size, footerHeight: 40),
      TapZoneAction.previousPage,
    );
    // 未覆盖的一侧仍跟随九宫格。
    expect(
      layout.actionAt(const Offset(280, 10), size, headerHeight: 30),
      TapZoneAction.nextPage,
    );
  });

  test('JSON 往返与坏数据回退', () {
    final layout = PageLayoutSettings.defaults
        .withZone(4, TapZoneAction.previousPage)
        .copyWith(headerRight: EdgeZoneAction.nextPage);
    final restored = PageLayoutSettings.fromJson(layout.toJson());
    expect(restored, layout);
    expect(
      PageLayoutSettings.fromJson('not json').zones,
      PageLayoutSettings.defaults.zones,
    );
  });

  testWidgets('页面布局编辑器：点区域改动作', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: PageLayoutEditor()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('page-layout-zone-0')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('page-layout-zone-option-nextPage')),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('page-layout-zone-0')),
        matching: find.text('下一页'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('page-layout-header-left')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('page-layout-edge-option-menu')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('菜单 页眉左侧'),
      findsOneWidget,
    );
  });

  test('控制器保存后立即生效并写入 prefs', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final custom = PageLayoutSettings.defaults
        .withZone(8, TapZoneAction.previousPage);
    await container.read(pageLayoutControllerProvider.notifier).save(custom);
    expect(container.read(pageLayoutControllerProvider), custom);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('reader.pageLayout'), isNotNull);
  });
}
