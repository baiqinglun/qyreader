/// 手动定位悬浮条：取消 / 设为当前页。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/features/reader/widgets/manual_locate_bar.dart';

void main() {
  testWidgets('显示待定位原文，取消与设为当前页各自回调', (tester) async {
    var cancels = 0;
    var confirms = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManualLocateBar(
            theme: ReadingTheme.paper,
            quote: '轻舟已过万重山',
            onCancel: () => cancels++,
            onConfirm: () => confirms++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('「轻舟已过万重山」'), findsOneWidget);
    expect(find.text('设为当前页'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(cancels, 1);
    expect(confirms, 0);

    await tester.tap(find.byKey(const ValueKey('manual-locate-confirm')));
    await tester.pumpAndSettle();
    expect(confirms, 1);
  });
}
