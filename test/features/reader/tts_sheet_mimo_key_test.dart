/// 听书弹窗：选中 MiMo 云端引擎时可直接配置 API Key（secure storage）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/features/reader/tts/mimo_tts_client.dart';
import 'package:qy_reader/features/reader/tts/tts_playback.dart';
import 'package:qy_reader/features/reader/widgets/tts_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final store = <String, String>{};

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async {
      final args = call.arguments as Map;
      switch (call.method) {
        case 'read':
          return store[args['key'] as String];
        case 'write':
          store[args['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          store.remove(args['key'] as String);
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: TtsSheet(
              theme: ReadingTheme.paper,
              loadEngines: () async => const [
                TtsEngine(name: kMimoTtsEngine, label: '小米 MiMo · 云端'),
                TtsEngine(name: 'com.google.android.tts', label: 'Google 语音'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('选中云端引擎后弹窗内出现 API Key 配置卡，保存落 secure storage', (
    tester,
  ) async {
    await pumpSheet(tester);

    // 默认引擎（系统默认）没有 Key 卡
    expect(find.byKey(const ValueKey('mimo-key-field')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tts-engine')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('小米 MiMo · 云端').last);
    await tester.pumpAndSettle();

    // Key 卡出现，初始未配置
    expect(find.byKey(const ValueKey('mimo-key-field')), findsOneWidget);
    expect(find.text('还没有配置 API Key（mimo.mi.com 开放平台获取）'), findsOneWidget);
    expect(find.byKey(const ValueKey('mimo-key-clear')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('mimo-key-field')),
      'sk-mimo-test-key',
    );
    await tester.tap(find.byKey(const ValueKey('mimo-key-save')));
    await tester.pumpAndSettle();

    // secure storage 里有了 Key；卡片显示已配置 + 清除按钮
    final credentials = MimoTtsCredentials();
    expect(await credentials.read(), 'sk-mimo-test-key');
    expect(find.text('MiMo API Key 已配置'), findsOneWidget);
    expect(find.byKey(const ValueKey('mimo-key-clear')), findsOneWidget);

    // 清除后 secure storage 同步清空
    await tester.tap(find.byKey(const ValueKey('mimo-key-clear')));
    await tester.pumpAndSettle();
    expect(await credentials.read(), isNull);
    expect(find.text('还没有配置 API Key（mimo.mi.com 开放平台获取）'), findsOneWidget);
  });
}
