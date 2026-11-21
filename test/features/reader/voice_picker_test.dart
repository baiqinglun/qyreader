/// 「选择声音」面板：按语言分组、选中音色写入设置（朗读中从当前句重读）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/reader/tts/tts_playback.dart';
import 'package:qy_reader/features/reader/tts/tts_settings.dart';
import 'package:qy_reader/features/reader/tts/voice_picker_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // flutter_tts 通道：无 mock 的平台调用在 FakeAsync 下会挂起，统一给兜底
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
  });

  test('availableEngines 不挂起（无通道 mock 时立即降级）', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final engines = await container
        .read(ttsPlaybackProvider.notifier)
        .availableEngines()
        .timeout(const Duration(seconds: 3));
    // ignore: avoid_print
    print('DEBUG engines=${engines.length}');
    expect(engines, isNotEmpty);
  });

  Future<void> pumpPicker(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: const MaterialApp(home: Scaffold(body: VoicePickerSheet())),
      ),
    );
    await tester.pumpAndSettle();
    // 平台通道回调/微任务链需要额外的泵推进（FakeAsync 环境）
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  testWidgets('MiMo 云端音色按语言分组，选中写入设置', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tts.settings': '{"engine":"cloud.xiaomi.mimo","voiceName":"冰糖"}',
    });
    await pumpPicker(tester);

    // 分组标题：中文 5 个（含默认）/ 英文 4 个（懒加载，滚动到才构建）
    expect(find.text('中文 · 5'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('英文 · 4'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('英文 · 4'), findsOneWidget);

    // 当前音色已勾选（冰糖行内的勾图标）
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    // 点茉莉 → 设置更新
    await tester.tap(find.text('茉莉'));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('选择声音'));
    final state = ProviderScope.containerOf(
      context,
    ).read(ttsSettingsControllerProvider);
    expect(state.voiceName, '茉莉');
    expect(state.engine, 'cloud.xiaomi.mimo');
  });

  testWidgets('引擎行可进入引擎视图切引擎', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tts.settings': '{"engine":"cloud.xiaomi.mimo"}',
    });
    await pumpPicker(tester);

    await tester.tap(find.text('朗读引擎'));
    await tester.pumpAndSettle();
    expect(find.text('选择引擎'), findsOneWidget);

    // 切回系统默认
    await tester.tap(find.text('系统默认'));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('选择声音'));
    final state = ProviderScope.containerOf(
      context,
    ).read(ttsSettingsControllerProvider);
    expect(state.engine, isNull);
  });
}
