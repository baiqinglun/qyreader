/// 全屏听书页（文稿式）：文稿视图 / 功能行 / 运输排 / 设置面板。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/reader/tts/tts_page.dart';
import 'package:qy_reader/features/reader/tts/tts_playback.dart';
import 'package:qy_reader/features/reader/tts/tts_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 伪造「正在朗读」的全局控制器状态（真实控制器需要平台通道）。
class _FakePlayingTts extends TtsPlayback {
  @override
  TtsPlaybackState build() => const TtsPlaybackState(
    status: TtsPlaybackStatus.playing,
    bookId: 'b1',
    bookTitle: '测试的书',
    index: 1,
    total: 3,
    currentText: '第二句话。',
    sentences: <String>['第一句话。', '第二句话。', '第三句话。'],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // flutter_tts 通道兜底（FakeAsync 下未 mock 的平台调用会挂起）
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(home: TtsPage(bookId: 'b1')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('空闲态：空文稿提示 + 播放键 + 无回到书籍按钮', (tester) async {
    await pumpPage(tester);

    expect(find.text('听书'), findsOneWidget);
    expect(find.text('点下方播放键开始听书'), findsOneWidget);
    expect(find.byKey(const ValueKey('tts-page-play')), findsOneWidget);
    expect(find.byKey(const ValueKey('tts-page-back-to-book')), findsNothing);

    // 功能行五个入口
    expect(find.text('原文'), findsOneWidget);
    expect(find.text('语速'), findsOneWidget);
    expect(find.text('音色'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);

    // 上一句在未播放时禁用
    final prev = tester.widget<IconButton>(
      find.byKey(const ValueKey('tts-page-prev')),
    );
    expect(prev.onPressed, isNull);
  });

  testWidgets('朗读中：文稿渲染整章句子，当前句高亮，回到书籍可见', (tester) async {
    await pumpPage(
      tester,
      overrides: [ttsPlaybackProvider.overrideWith(_FakePlayingTts.new)],
    );

    expect(find.text('测试的书'), findsWidgets); // 页头
    expect(find.text('第一句话。'), findsOneWidget);
    expect(find.text('第二句话。'), findsOneWidget);
    expect(find.text('第三句话。'), findsOneWidget);
    expect(find.byKey(const ValueKey('tts-page-back-to-book')), findsOneWidget);

    // 播放中显示暂停键
    final play = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('tts-page-play')),
    );
    expect(play.onTap, isNotNull);
  });

  testWidgets('设置面板：引擎 / 定时 / 背景音乐可选（选内置雨声写入设置）', (
    tester,
  ) async {
    await pumpPage(tester);

    // 打开设置面板（底栏「设置」或 ⏰）
    await tester.tap(find.byKey(const ValueKey('tts-page-timer')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tts-settings-engine')), findsOneWidget);
    expect(find.text('定时'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tts-settings-bgm')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('雨声 · 内置').last);
    await tester.pump(const Duration(milliseconds: 300));

    final context = tester.element(
      find.byKey(const ValueKey('tts-settings-bgm')),
    );
    final state = ProviderScope.containerOf(
      context,
    ).read(ttsSettingsControllerProvider);
    expect(state.bgmId, 'builtin-rain');
    // 选中后出现音量行
    expect(find.byKey(const ValueKey('tts-settings-bgm-volume')), findsOneWidget);
  });
}
