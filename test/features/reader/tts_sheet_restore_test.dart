/// 听书弹窗引擎显示：保存 → 恢复循环；设置控制器的冷启动恢复屏障。
///
/// 回归背景：设置是异步恢复的，冷启动后第一次读拿到的是默认值——
/// 弹窗会先闪「系统默认」，期间任何读取/写入都会用错值（引擎被抹成
/// 系统默认）。修复后：恢复完成前 UI 显示读取中，写入与 start 都等恢复。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/features/reader/tts/tts_playback.dart';
import 'package:qy_reader/features/reader/tts/tts_settings.dart';
import 'package:qy_reader/features/reader/widgets/tts_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _openSheet(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              captured = context;
              return Center(
                child: ElevatedButton(
                  onPressed: () => showTtsSheet(
                    captured,
                    theme: ReadingTheme.paper,
                    loadEngines: () async => const [
                      TtsEngine(name: kMimoTtsEngine, label: '小米 MiMo · 云端'),
                    ],
                  ),
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('弹窗显示上次保存的云端 MiMo 引擎', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tts.settings': jsonEncode(<String, dynamic>{
        'engine': kMimoTtsEngine,
        'voiceName': '冰糖',
        'voiceLocale': '中文 · 女',
      }),
    });

    await _openSheet(tester);
    expect(find.text('小米 MiMo · 云端'), findsOneWidget);
  });

  testWidgets('弹窗里选 MiMo 后，重开弹窗仍显示 MiMo（保存 → 恢复循环）', (
    tester,
  ) async {
    await _openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('tts-engine')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('小米 MiMo · 云端').last);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tts.settings'), contains('cloud.xiaomi.mimo'));

    // 关掉弹窗再重开：应显示上次选的 MiMo
    await tester.tap(find.text('开始朗读'));
    await tester.pumpAndSettle();
    await _openSheet(tester);
    expect(find.text('小米 MiMo · 云端'), findsOneWidget);
  });

  test('冷启动竞态：恢复完成前的写入不会被恢复覆盖，读取等恢复完成', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tts.settings': jsonEncode(<String, dynamic>{
        'engine': 'com.google.android.tts',
      }),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(ttsSettingsControllerProvider.notifier);
    // 恢复还没完成：此时保存 MiMo（用户动作先于异步恢复完成）
    final updating = notifier.update(
      const TtsSettings(engine: kMimoTtsEngine, voiceName: '冰糖'),
    );
    await updating;
    await notifier.waitRestored();

    // 恢复不能把刚保存的 MiMo 覆盖回旧引擎
    expect(container.read(ttsSettingsControllerProvider).engine,
        kMimoTtsEngine);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tts.settings'), contains('cloud.xiaomi.mimo'));
  });
}
