/// 全局听书控制器：选区起点 / 句级跳转 / 续章 / MiMo 云端 / restart。
///
/// flutter_tts 的完成回调走通道（`speak.onComplete`）；测试里用
/// `handlePlatformMessage` 模拟原生回调，驱动句循环推进。控制器是
/// Riverpod keepAlive 单例，测试用 ProviderContainer 承载。
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/reader/native/native_chapter_source.dart';
import 'package:qy_reader/features/reader/tts/mimo_tts_client.dart';
import 'package:qy_reader/features/reader/tts/mimo_voice_player.dart';
import 'package:qy_reader/features/reader/tts/tts_playback.dart';
import 'package:qy_reader/features/reader/tts/tts_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _chapter = '第一句话。第二句话。第三句话。';

NativeChapter _chapterOf(String text, int idx) => NativeChapter.fromCompact(
  idx: idx,
  title: '章$idx',
  href: 'c$idx',
  text: text,
  paragraphStarts: const <int>[0],
  paragraphLevels: const <int>[0],
  paragraphCentered: const <bool>[false],
);

class _FakeMimoClient implements MimoTtsClient {
  _FakeMimoClient(this.requests);

  final List<String> requests;

  @override
  Future<Uint8List> synthesize(String text, {required String voice}) async {
    requests.add('$voice|$text');
    return Uint8List.fromList(
      <int>[0x52, 0x49, 0x46, 0x46, ...List<int>.filled(16, 1)],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('flutter_tts');
  final List<String> spoken = <String>[];
  bool autoComplete = true;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    spoken.clear();
    autoComplete = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'speak') {
        spoken.add(call.arguments as String);
        if (autoComplete) {
          // 模拟原生播报完成回调
          scheduleMicrotask(() async {
            await TestDefaultBinaryMessengerBinding
                .instance.defaultBinaryMessenger
                .handlePlatformMessage(
              'flutter_tts',
              channel.codec
                  .encodeMethodCall(const MethodCall('speak.onComplete')),
              (_) {},
            );
          });
        }
      }
      if (call.method == 'setLanguage') return 1; // zh-CN 可用
      if (call.method == 'isLanguageAvailable') return true;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    MimoVoicePlayer.debugPlayOverride = null;
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  TtsPlayback controller(ProviderContainer container) =>
      container.read(ttsPlaybackProvider.notifier);

  /// 等句循环推进完（纯微任务链，几十毫秒足够）。
  Future<void> pumpLoop() =>
      Future<void>.delayed(const Duration(milliseconds: 80));

  Future<void> startSystem(
    ProviderContainer container, {
    int? startOffset,
  }) async {
    await controller(container).start(
      settings: const TtsSettings(),
      bookId: 'b1',
      bookTitle: '测试的书',
      chapters: [_chapterOf(_chapter, 0)],
      chapterIdx: 0,
      startOffset: startOffset,
    );
  }

  test('start 带选区起点：从包含该偏移的句子开始读', () async {
    final container = makeContainer();
    await startSystem(container, startOffset: 7);
    await pumpLoop();

    // 第一句是「第二句话。」（7 落在 5..10 区间），页首句被跳过
    expect(spoken.first, '第二句话。');
    // 三句读完 → 章末没有下一章 → 停止
    expect(container.read(ttsPlaybackProvider).status, TtsPlaybackStatus.idle);
    expect(container.read(ttsPlaybackProvider).error, isNull);
  });

  test('start 不带起点：从章首开始读', () async {
    final container = makeContainer();
    await startSystem(container);
    await pumpLoop();

    expect(spoken.first, '第一句话。');
  });

  test('章末自动续章：两章全读完并回调 finishedAll', () async {
    final container = makeContainer();
    var finished = false;
    controller(container).bindReader(
      onJump: (_, __) {},
      onFinishedAll: () => finished = true,
    );
    await controller(container).start(
      settings: const TtsSettings(),
      bookId: 'b1',
      bookTitle: '测试的书',
      chapters: [
        _chapterOf('第一章。内容。', 0),
        _chapterOf('第二章。结尾。', 1),
      ],
      chapterIdx: 0,
    );
    await pumpLoop();

    expect(spoken, ['第一章。', '内容。', '第二章。', '结尾。']);
    expect(container.read(ttsPlaybackProvider).status, TtsPlaybackStatus.idle);
    expect(finished, isTrue);
  });

  test('暂停中 goToSentence：从该句继续朗读', () async {
    autoComplete = false; // 播报挂起，保持 playing
    final container = makeContainer();
    await startSystem(container);
    await pumpLoop();
    expect(
      container.read(ttsPlaybackProvider).status,
      TtsPlaybackStatus.playing,
    );
    expect(container.read(ttsPlaybackProvider).index, 0);

    await controller(container).pause();
    expect(
      container.read(ttsPlaybackProvider).status,
      TtsPlaybackStatus.paused,
    );

    await controller(container).goToSentence(2);
    await pumpLoop();
    expect(
      container.read(ttsPlaybackProvider).status,
      TtsPlaybackStatus.playing,
    );
    expect(container.read(ttsPlaybackProvider).index, 2);
    expect(container.read(ttsPlaybackProvider).currentText, '第三句话。');
    expect(spoken.last, '第三句话。');

    await controller(container).previousSentence();
    await pumpLoop();
    expect(container.read(ttsPlaybackProvider).index, 1);

    await controller(container).nextSentence();
    await pumpLoop();
    expect(container.read(ttsPlaybackProvider).index, 2);
  });

  test('goToSentence 越界被夹紧；未激活时不动', () async {
    autoComplete = false;
    final container = makeContainer();
    // 未开始：goToSentence 是 no-op
    await controller(container).goToSentence(1);
    expect(
      container.read(ttsPlaybackProvider).status,
      TtsPlaybackStatus.idle,
    );

    await startSystem(container);
    await pumpLoop();
    expect(container.read(ttsPlaybackProvider).index, 0);

    await controller(container).goToSentence(99);
    await pumpLoop();
    expect(container.read(ttsPlaybackProvider).index, 2); // 夹到最后一句
  });

  test('stop 后 restart：从停下的句子继续', () async {
    autoComplete = false;
    final container = makeContainer();
    await startSystem(container);
    await pumpLoop();
    expect(container.read(ttsPlaybackProvider).index, 0);

    // 跳到第二句再停
    await controller(container).goToSentence(1);
    await pumpLoop();
    await controller(container).stop();
    expect(
      container.read(ttsPlaybackProvider).status,
      TtsPlaybackStatus.idle,
    );

    expect(controller(container).canRestart, isTrue);
    autoComplete = true;
    await controller(container).restart();
    await pumpLoop();
    // 从停下的那句（第二句）重新开始，把剩下的读完
    expect(spoken.sublist(spoken.length - 2), ['第二句话。', '第三句话。']);
  });

  test('启动窗口期暂停：开读即停，不丢用户点击', () async {
    final requests = <String>[];
    final container = makeContainer();
    controller(container).debugInjectMimo(
      client: _FakeMimoClient(requests),
      // 人为拉长启动窗口（恢复屏障），制造「准备中点暂停」的场景
      apiKeyLoader: () async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return 'test-key';
      },
    );
    final starting = controller(container).start(
      settings: const TtsSettings(engine: kMimoTtsEngine, voiceName: '冰糖'),
      bookId: 'b1',
      bookTitle: '测试的书',
      chapters: [_chapterOf(_chapter, 0)],
      chapterIdx: 0,
    );
    // 启动窗口期内点暂停
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(
      container.read(ttsPlaybackProvider).status,
      TtsPlaybackStatus.preparing,
    );
    await controller(container).pause();
    await starting;
    await pumpLoop();

    // 开读即停：没有合成、没有朗读，状态回到空闲
    expect(requests, isEmpty);
    expect(container.read(ttsPlaybackProvider).status, TtsPlaybackStatus.idle);
  });

  test('暂停后恢复：从暂停时的句子继续（不丢句、不重头）', () async {
    autoComplete = false;
    final container = makeContainer();
    await startSystem(container);
    await pumpLoop();
    expect(container.read(ttsPlaybackProvider).index, 0);

    // 第一句挂起时暂停（状态 paused），再恢复
    await controller(container).pause();
    final pausedIndex = container.read(ttsPlaybackProvider).index;
    autoComplete = true;
    await controller(container).resume();
    await pumpLoop();

    // 恢复后第一句仍是暂停时的那句
    expect(pausedIndex, 0);
    expect(container.read(ttsPlaybackProvider).status, TtsPlaybackStatus.idle);
    expect(container.read(ttsPlaybackProvider).error, isNull);
  });

  test('云端引擎：availableEngines 含 MiMo 入口、音色走预置表', () async {
    final container = makeContainer();
    final engines = await controller(container).availableEngines();
    expect(engines.any((e) => e.name == kMimoTtsEngine), isTrue);
    final voices = await controller(container).availableVoices(
      engine: kMimoTtsEngine,
    );
    expect(voices.map((v) => v.name), contains('冰糖'));
    expect(voices.map((v) => v.name), contains('mimo_default'));
  });

  test('云端引擎：逐句经 MiMo 合成并播放（含预取）', () async {
    final requests = <String>[];
    final played = <int>[];
    MimoVoicePlayer.debugPlayOverride = (wav) async {
      played.add(wav.length);
      await Future<void>.delayed(Duration.zero);
      return true;
    };
    final container = makeContainer();
    controller(container).debugInjectMimo(
      client: _FakeMimoClient(requests),
      apiKeyLoader: () async => 'test-key',
    );
    await controller(container).start(
      settings: const TtsSettings(engine: kMimoTtsEngine, voiceName: '冰糖'),
      bookId: 'b1',
      bookTitle: '测试的书',
      chapters: [_chapterOf(_chapter, 0)],
      chapterIdx: 0,
    );
    await pumpLoop();

    // 三句全部合成（voice=冰糖），播放了三次
    expect(requests, hasLength(3));
    expect(requests.first, '冰糖|第一句话。');
    expect(played, hasLength(3));
    expect(container.read(ttsPlaybackProvider).status, TtsPlaybackStatus.idle);
    expect(container.read(ttsPlaybackProvider).error, isNull);
  });

  test('云端引擎：切音色从当前句重新读', () async {
    final requests = <String>[];
    MimoVoicePlayer.debugPlayOverride = (wav) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return true;
    };
    final container = makeContainer();
    controller(container).debugInjectMimo(
      client: _FakeMimoClient(requests),
      apiKeyLoader: () async => 'test-key',
    );
    await controller(container).start(
      settings: const TtsSettings(engine: kMimoTtsEngine, voiceName: '冰糖'),
      bookId: 'b1',
      bookTitle: '测试的书',
      chapters: [_chapterOf(_chapter, 0)],
      chapterIdx: 0,
    );
    // 第一句播到一半切音色（茉莉）
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await controller(container).changeVoice(name: '茉莉', locale: '中文');
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    // 从当前句（第一句）用新音色重新合成，并把剩余读完
    expect(requests.contains('茉莉|第一句话。'), isTrue);
    expect(requests.contains('茉莉|第三句话。'), isTrue);
    expect(container.read(ttsPlaybackProvider).status, TtsPlaybackStatus.idle);
  });

  test('云端引擎未配 API Key：start 失败并提示配置', () async {
    final container = makeContainer();
    controller(container).debugInjectMimo(apiKeyLoader: () async => null);
    await controller(container).start(
      settings: const TtsSettings(engine: kMimoTtsEngine),
      bookId: 'b1',
      bookTitle: '测试的书',
      chapters: [_chapterOf(_chapter, 0)],
      chapterIdx: 0,
    );
    expect(container.read(ttsPlaybackProvider).status, TtsPlaybackStatus.idle);
    expect(container.read(ttsPlaybackProvider).error, contains('API Key'));
  });

  test('云端引擎：当前句播放时预取后续句子，句间不重复请求', () async {
    final requests = <String>[];
    // 模拟「音频较长」：每句播 300ms，给预取留观察窗口
    MimoVoicePlayer.debugPlayOverride = (wav) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return true;
    };
    final container = makeContainer();
    controller(container).debugInjectMimo(
      client: _FakeMimoClient(requests),
      apiKeyLoader: () async => 'test-key',
    );
    await controller(container).start(
      settings: const TtsSettings(engine: kMimoTtsEngine, voiceName: '冰糖'),
      bookId: 'b1',
      bookTitle: '测试的书',
      chapters: [_chapterOf(_chapter, 0)],
      chapterIdx: 0,
    );

    // 第一句还在播（300ms）时，第二句应该已经被预取请求了
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(requests, contains('冰糖|第二句话。'));

    // 播完全章：三句各合成一次，没有重复请求
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(container.read(ttsPlaybackProvider).status, TtsPlaybackStatus.idle);
    expect(requests, hasLength(3));
  });
}
