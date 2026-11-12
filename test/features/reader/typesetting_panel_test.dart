/// 排版面板交互单测：选项型设置统一走下拉框，选中后真的写进设置。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/reader/reader_settings.dart';
import 'package:qy_reader/features/reader/reader_themes.dart';
import 'package:qy_reader/features/reader/widgets/typesetting_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pumpPanel(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);

  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: TypesettingPanel())),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// 点开一个下拉框并选中某个选项。
Future<void> _pick(WidgetTester tester, Finder dropdown, String option) async {
  await tester.scrollUntilVisible(dropdown, 80,
      scrollable: find.byType(Scrollable).last);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('页眉右侧选「章节页」写入设置（下拉框）', (tester) async {
    final container = await _pumpPanel(tester);

    await tester.tap(find.text('页眉页脚'));
    await tester.pumpAndSettle();

    // 页眉左/中/右、页脚左/中/右 → 第 3 个下拉框是页眉右槽。
    final dropdown = find.byType(DropdownButton<RunningContent>).at(2);
    await _pick(tester, dropdown, '章节页');

    expect(
      container.read(readingSettingsControllerProvider).headerRight,
      RunningContent.chapterPages,
    );
  });

  testWidgets('正文缩进/字重可改（下拉框）', (tester) async {
    final container = await _pumpPanel(tester);

    await tester.tap(find.text('正文'));
    await tester.pumpAndSettle();

    await _pick(tester, find.byType(DropdownButton<ParagraphIndent>), '四字');
    expect(
      container.read(readingSettingsControllerProvider).bodyIndent,
      ParagraphIndent.four,
    );

    await _pick(tester, find.byType(DropdownButton<BodyFontWeight>), '半粗');
    expect(
      container.read(readingSettingsControllerProvider).bodyWeight,
      BodyFontWeight.semiBold,
    );
  });

  testWidgets('页面页签：翻页方式用下拉框选，选项齐全', (tester) async {
    final container = await _pumpPanel(tester);

    await tester.tap(find.text('页面'));
    await tester.pumpAndSettle();

    final dropdown = find.byType(DropdownButton<PageTurnMode>);
    await _pick(tester, dropdown, PageTurnMode.curl.label);

    expect(
      container.read(readingSettingsControllerProvider).pageTurnMode,
      PageTurnMode.curl,
    );
  });

  testWidgets('主题页签：加号复制当前主题、减号删除自定义主题', (tester) async {
    final container = await _pumpPanel(tester);

    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();

    // 内置主题：减号禁用、加号可用。
    final remove = tester.widget<IconButton>(
      find.byKey(const ValueKey('typeset-theme-remove')),
    );
    expect(remove.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('typeset-theme-add')));
    await tester.pumpAndSettle();

    // 复制后弹出改名弹窗；改成「我的副本」并保存。
    expect(find.text('主题名称'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('typeset-theme-name')),
      '我的副本',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final state = container.read(readerThemesControllerProvider);
    expect(state.custom, hasLength(1));
    expect(state.active.name, '我的副本');
    expect(state.active.snapshot, isNotNull);

    // 现在减号可用：删掉刚建的主题，回退内置主题。
    await tester.tap(find.byKey(const ValueKey('typeset-theme-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    final after = container.read(readerThemesControllerProvider);
    expect(after.custom, isEmpty);
    expect(after.active.builtIn, isTrue);
  });
}