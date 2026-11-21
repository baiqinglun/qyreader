/// 朗读引擎：包名展示 + 弹窗切引擎；音色行走「选择声音」面板。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/features/reader/tts/tts_playback.dart';
import 'package:qy_reader/features/reader/tts/tts_settings.dart';
import 'package:qy_reader/features/reader/widgets/tts_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('引擎包名映射成可读名称', () {
    expect(ttsEngineLabel('com.xiaomi.mimo.tts'), '小米 MiMo');
    expect(ttsEngineLabel('com.xiaomi.voiceassistant'), '小米语音引擎');
    expect(ttsEngineLabel('com.google.android.tts'), 'Google 语音服务');
    expect(ttsEngineLabel('com.iflytek.speechcloud'), '讯飞语音');
    expect(ttsEngineLabel('com.example.voice'), 'voice');
  });

  testWidgets('选择引擎后写入设置；音色行打开选择声音面板选音色', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const systemEngine = 'com.xiaomi.mimo.tts';

    // flutter_tts 通道：getVoices 返回系统音色（选择声音面板读取）
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      if (call.method == 'getVoices') {
        return [
          {'name': 'cmn-cn-x-ssa-server', 'locale': 'zh-CN'},
        ];
      }
      if (call.method == 'setLanguage') return 1;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
    });

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                final settings = ref.watch(ttsSettingsControllerProvider);
                return Column(
                  children: [
                    Text('engine=${settings.engine ?? 'null'}'),
                    Text('voice=${settings.voiceName ?? 'null'}'),
                    Expanded(
                      child: TtsSheet(
                        theme: ReadingTheme.paper,
                        loadEngines: () async => const [
                          TtsEngine(name: systemEngine, label: '小米 MiMo'),
                          TtsEngine(
                            name: 'com.google.android.tts',
                            label: 'Google 语音服务',
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 切引擎
    await tester.tap(find.byKey(const ValueKey('tts-engine')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('小米 MiMo').last);
    await tester.pumpAndSettle();
    expect(find.text('engine=$systemEngine'), findsOne);

    // 音色行显示「系统默认」→ 点开「选择声音」面板 → 选音色
    expect(find.text('voice=null'), findsOne);
    await tester.tap(find.byKey(const ValueKey('tts-voice')));
    await tester.pumpAndSettle();
    expect(find.text('选择声音'), findsOneWidget);

    await tester.tap(find.text('cmn-cn-x-ssa-server'));
    await tester.pumpAndSettle();
    expect(find.text('voice=cmn-cn-x-ssa-server'), findsOne);

    // 保存到 prefs
    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(prefs.getString('tts.settings')!)['voiceName'],
      'cmn-cn-x-ssa-server',
    );
  });
}
