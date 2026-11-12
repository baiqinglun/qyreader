/// 边距直调覆盖层：三页切换、数字步进、参考框、复位与完成。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/reader/reader_settings.dart';
import 'package:qy_reader/features/reader/widgets/margin_editor_overlay.dart';

void main() {
  late ReadingSettings settings;
  late List<ReadingSettings> previews;
  late List<ReadingSettings> commits;
  late bool closed;

  setUp(() {
    settings = const ReadingSettings();
    previews = [];
    commits = [];
    closed = false;
  });

  Future<void> pumpOverlay(
    WidgetTester tester, {
    MarginGroup group = MarginGroup.body,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 390,
              height: 844,
              child: MarginEditorOverlay(
                settings: settings,
                textScale: 1,
                initialGroup: group,
                onPreview: previews.add,
                onCommit: commits.add,
                onClose: () => closed = true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('正文页：四边数字、工具栏与初始选中', (tester) async {
    await pumpOverlay(tester);

    expect(find.text('正文边距'), findsOneWidget);
    expect(find.byKey(const ValueKey('margin-toolbar')), findsOneWidget);
    expect(find.byKey(const ValueKey('margin-value-top')), findsOneWidget);
    expect(find.byKey(const ValueKey('margin-value-bottom')), findsOneWidget);
    expect(find.byKey(const ValueKey('margin-value-left')), findsOneWidget);
    expect(find.byKey(const ValueKey('margin-value-right')), findsOneWidget);
    // 默认正文边距：顶 12、底 12、左 16、右 16。
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('margin-value-top'))).data,
      '12',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('margin-value-left'))).data,
      '16',
    );
    // 选中项才有 −/+。
    expect(find.byKey(const ValueKey('margin-plus-top')), findsOneWidget);
    expect(find.byKey(const ValueKey('margin-plus-bottom')), findsNothing);
  });

  testWidgets('点 + 实时预览并提交，数值跟随', (tester) async {
    await pumpOverlay(tester);

    await tester.tap(find.byKey(const ValueKey('margin-plus-top')));
    await tester.pump();

    expect(previews.last.marginTop, 13);
    expect(commits.last.marginTop, 13);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('margin-value-top'))).data,
      '13',
    );
  });

  testWidgets('切换到页眉/页脚页显示各自边距', (tester) async {
    await pumpOverlay(tester);

    await tester.tap(find.byKey(const ValueKey('margin-group')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('页眉边距').last);
    await tester.pumpAndSettle();

    expect(find.text('页眉边距'), findsOneWidget);
    // 页眉：上边距 6、与正文之间的上边距 12。
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('margin-value-top'))).data,
      '6',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('margin-value-bottom'))).data,
      '12',
    );

    await tester.tap(find.byKey(const ValueKey('margin-group')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('页脚边距').last);
    await tester.pumpAndSettle();

    expect(find.text('页脚边距'), findsOneWidget);
    // 页脚：下边距 6、正文下边距 12。
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('margin-value-bottom'))).data,
      '6',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('margin-value-top'))).data,
      '12',
    );
  });

  testWidgets('复位恢复该组默认值并提交', (tester) async {
    await pumpOverlay(tester);

    await tester.tap(find.byKey(const ValueKey('margin-plus-top')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('margin-plus-top')));
    await tester.pump();
    expect(commits.last.marginTop, 14);

    await tester.tap(find.byKey(const ValueKey('margin-reset')));
    await tester.pump();

    expect(commits.last.marginTop, 12);
    expect(commits.last.marginLeft, 16);
    expect(commits.last.marginBottom, 12);
    expect(commits.last.marginRight, 16);
  });

  testWidgets('眼睛按钮隐藏参考框与数字，勾选回调关闭', (tester) async {
    await pumpOverlay(tester);

    await tester.tap(find.byKey(const ValueKey('margin-guides')));
    await tester.pump();
    expect(find.byKey(const ValueKey('margin-value-top')), findsNothing);
    expect(find.byKey(const ValueKey('margin-toolbar')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('margin-check')));
    await tester.pump();
    expect(closed, isTrue);
  });
}
