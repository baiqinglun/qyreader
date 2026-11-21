/// 朗读控制条：信息区点击进全屏听书页。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/features/reader/tts/tts_playback.dart';
import 'package:qy_reader/features/reader/widgets/tts_bar.dart';

void main() {
  testWidgets('点信息区打开听书页；暂停/停止按钮独立响应', (tester) async {
    var opened = false;
    var paused = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TtsBar(
            state: const TtsPlaybackState(
              status: TtsPlaybackStatus.playing,
              index: 2,
              total: 10,
              currentText: '正在朗读的句子',
            ),
            theme: ReadingTheme.paper,
            onOpen: () => opened = true,
            onPause: () => paused = true,
            onResume: () {},
            onStop: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('正在朗读的句子'));
    expect(opened, isTrue);
    expect(paused, isFalse);

    await tester.tap(find.byTooltip('暂停'));
    expect(paused, isTrue);
  });
}
