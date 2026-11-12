/// 按压组件：只有缩放反馈，点按/长按都不震动。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/widgets/pressable_scale.dart';

void main() {
  testWidgets('点按和长按都不触发 HapticFeedback', (tester) async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    var taps = 0;
    var longs = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: PressableScale(
            onTap: () => taps++,
            onLongPress: () => longs++,
            // 必须有可命中的绘制内容：GestureDetector 默认 deferToChild。
            child: Container(width: 120, height: 80, color: Colors.amber),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PressableScale));
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(PressableScale));
    await tester.pumpAndSettle();

    expect(taps, 1);
    expect(longs, 1);
    expect(
      calls.where((c) => c.method == 'HapticFeedback.vibrate'),
      isEmpty,
      reason: '点按/长按都只做缩放，不震动',
    );
  });
}
