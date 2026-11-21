/// 划线跳转后的进度选择条：返回原位置 / 设为阅读进度。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/features/reader/widgets/reader_jump_actions.dart';

void main() {
  testWidgets('显示两个选择，点击分别回调', (tester) async {
    var returned = 0;
    var saved = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ReaderJumpActions(
              theme: ReadingTheme.paper,
              onReturn: () => returned++,
              onSetProgress: () => saved++,
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('reader-annotation-jump-actions')),
      findsOneWidget,
    );
    expect(find.text('返回原位置'), findsOneWidget);
    expect(find.text('设为阅读进度'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('reader-annotation-jump-return')),
    );
    expect(returned, 1);
    expect(saved, 0);

    await tester.tap(find.byKey(const ValueKey('reader-annotation-jump-set')));
    expect(saved, 1);
  });
}
