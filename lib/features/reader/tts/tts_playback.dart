/// TTS 播放控制器：**全局单例**（Riverpod keepAlive），句级朗读 → 高亮 →
/// 自动翻页/续章 → 定时停止，退出阅读页后继续朗读。
///
/// flutter_tts 的完成/取消回调是全局的（无 utterance id），用「代次」
/// 令牌丢弃过期回调：每次 stop/pause 递增代次，旧播报的迟到回调不再
/// 推进队列。
///
/// 与阅读页的关系（v2.52.0 起）：控制器自己持有整本书的章节表（start 时
/// 由阅读页传入 `NativeChapter` 列表），切句、切章、高亮都不依赖阅读页；
/// 阅读页通过 [bindReader] 绑定「跳转执行器」（高亮句不在当前页时翻页），
/// 退出后解绑——朗读照常继续（高亮/翻页自然失效），回到书籍重新绑定。
/// 背景音乐跟随朗读起停也在这里协调（[_syncBgm]），与阅读页无关。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../native/native_chapter_source.dart';
import '../native/native_tts_surface.dart' show splitSentences, TtsHighlight;
import 'audio_library.dart';
import 'bgm_player.dart';
import 'mimo_tts_client.dart';
import 'mimo_voice_player.dart';
import 'tts_settings.dart';

export '../native/native_tts_surface.dart' show TtsHighlight;

part 'tts_playback.g.dart';

/// 小米 MiMo 云端引擎的伪引擎 id（存进 `TtsSettings.engine`；系统引擎存
/// Android 包名，云端引擎是这个保留值）。
const String kMimoTtsEngine = 'cloud.xiaomi.mimo';

/// MiMo 预置音色（官方文档列表；locale 列只用于展示，不参与 setVoice）。
const List<TtsVoice> kMimoVoices = <TtsVoice>[
  TtsVoice(name: 'mimo_default', locale: '中文', tags: <String>['默认', '中文']),
  TtsVoice(name: '冰糖', locale: '中文', tags: <String>['女声', '中文']),
  TtsVoice(name: '茉莉', locale: '中文', tags: <String>['女声', '中文']),
  TtsVoice(name: '苏打', locale: '中文', tags: <String>['男声', '中文']),
  TtsVoice(name: '白桦', locale: '中文', tags: <String>['男声', '中文']),
  TtsVoice(name: 'Mia', locale: '英文', tags: <String>['女声', '英文']),
  TtsVoice(name: 'Chloe', locale: '英文', tags: <String>['女声', '英文']),
  TtsVoice(name: 'Milo', locale: '英文', tags: <String>['男声', '英文']),
  TtsVoice(name: 'Dean', locale: '英文', tags: <String>['男声', '英文']),
];

/// 当前设置是否选中了 MiMo 云端引擎。
bool isMimoEngine(String? engine) => engine == kMimoTtsEngine;

/// 播放状态。
enum TtsPlaybackStatus {
  /// 未朗读。
  idle,

  /// 初始化中（取句子/设音色）。
  preparing,

  /// 正在朗读。
  playing,

  /// 已暂停（保留进度）。
  paused,
}

/// 控制器对外快照。
class TtsPlaybackState {
  const TtsPlaybackState({
    this.status = TtsPlaybackStatus.idle,
    this.index = 0,
    this.total = 0,
    this.currentText = '',
    this.remaining,
    this.error,
    this.bookId,
    this.bookTitle,
    this.highlight,
    this.sentences = const <String>[],
  });

  /// 状态。
  final TtsPlaybackStatus status;

  /// 当前句序号（0 基）。
  final int index;

  /// 本章句数。
  final int total;

  /// 当前句文本（控制条展示）。
  final String currentText;

  /// 定时停止剩余时间（null = 未定时）。
  final Duration? remaining;

  /// 错误信息（引擎不可用等）。
  final String? error;

  /// 正在听的书 id（null = 没有会话）。
  final String? bookId;

  /// 正在听的书名（控制条 / 听书页展示）。
  final String? bookTitle;

  /// 当前句高亮（章内区间；阅读页据此画高亮）。
  final TtsHighlight? highlight;

  /// 当前章的全部句子文本（听书页「文稿」视图展示）。
  final List<String> sentences;

  /// 是否在朗读（含准备中）。
  bool get active =>
      status == TtsPlaybackStatus.preparing ||
      status == TtsPlaybackStatus.playing ||
      status == TtsPlaybackStatus.paused;

  /// 拷贝。
  TtsPlaybackState copyWith({
    TtsPlaybackStatus? status,
    int? index,
    int? total,
    String? currentText,
    Object? remaining = _sentinel,
    Object? error = _sentinel,
    String? bookId,
    String? bookTitle,
    Object? highlight = _sentinel,
    List<String>? sentences,
  }) => TtsPlaybackState(
    status: status ?? this.status,
    index: index ?? this.index,
    total: total ?? this.total,
    currentText: currentText ?? this.currentText,
    remaining: remaining == _sentinel ? this.remaining : remaining as Duration?,
    error: error == _sentinel ? this.error : error as String?,
    bookId: bookId ?? this.bookId,
    bookTitle: bookTitle ?? this.bookTitle,
    highlight: highlight == _sentinel
        ? this.highlight
        : highlight as TtsHighlight?,
    sentences: sentences ?? this.sentences,
  );

  static const Object _sentinel = Object();
}

/// 全局听书控制器（keepAlive 单例；退出阅读页后继续朗读）。
@Riverpod(keepAlive: true)
class TtsPlayback extends _$TtsPlayback {
  final FlutterTts _tts = FlutterTts();

  // ---- 会话数据 ----

  /// 整本书的章节表（start 时由阅读页传入，控制器自此自足）。
  List<NativeChapter> _chapters = const [];

  /// 当前章序号。
  int _chapterIdx = 0;

  /// 当前章节句子。
  List<({int start, int end, String text})> _segments = const [];

  /// 阅读页绑定的跳转执行器（高亮句不在当前页时翻页；阅读页退出后为
  /// null，朗读照常继续）。
  void Function(int chapterIdx, int offset)? _jumpExecutor;

  /// 全书读完回调（阅读页绑定，用来弹「已朗读到全书末尾」提示）。
  void Function()? _onFinishedAll;

  // ---- 上次会话记忆（stop 后从原句重新开始；听书页用） ----
  String? _lastBookId;
  String? _lastBookTitle;
  int _lastChapterIdx = 0;
  int _lastResumeOffset = 0;

  /// 是否可以重启上次会话（有章节表且知道是哪本书）。
  bool get canRestart => _chapters.isNotEmpty && _lastBookId != null;

  /// 上次会话的书 id（听书页判断「开始朗读」能否接上本书）。
  String? get lastBookId => _lastBookId;

  // ---- MiMo 云端引擎 ----
  MimoTtsClient? _injectedMimoClient;
  MimoVoicePlayer? _injectedMimoPlayer;
  Future<String?> Function()? _mimoApiKeyLoader;

  /// 测试注入：假客户端 / 假播放器 / 假 Key 加载器（正常流程走真实实现）。
  @visibleForTesting
  void debugInjectMimo({
    MimoTtsClient? client,
    MimoVoicePlayer? player,
    Future<String?> Function()? apiKeyLoader,
  }) {
    _injectedMimoClient = client;
    _injectedMimoPlayer = player;
    _mimoApiKeyLoader = apiKeyLoader;
  }

  MimoTtsClient? _mimoClient;
  String? _mimoClientKey;
  MimoVoicePlayer? _mimoPlayer;

  /// 句子合成结果缓存（换曲/回听/暂停续播不重复请求；32 条 FIFO）。
  final Map<String, Uint8List> _mimoCache = <String, Uint8List>{};

  /// 预取中的句子 → 请求 Future（读到该句时若仍在途就等它，不重复请求）。
  final Map<String, Future<void>> _mimoPrefetching = <String, Future<void>>{};

  // ---- 播报内部状态 ----

  /// 代次令牌：stop/pause 递增，丢弃过期播报回调。
  int _epoch = 0;

  /// 启动窗口期（preparing）收到的暂停请求：开读即停，不丢用户的点击。
  bool _pauseRequested = false;

  /// 单句播报完成信号（系统 TTS）。
  Completer<bool>? _utterance;

  /// 当前朗读设置：**实时读设置 provider**（冷启动异步恢复完成后即为
  /// 用户上次保存的值；字段式缓存会在恢复完成后变陈旧）。
  TtsSettings get _settings => ref.read(ttsSettingsControllerProvider);

  Timer? _timer;

  bool _initialized = false;

  /// 音频路由是否就绪（引擎/语言可用）。
  bool _engineReady = false;

  /// 当前已切换到的 Android 引擎包名（null = 系统默认）。
  String? _activeEngine;

  /// 当前引擎是否已经设过中文。
  bool _languageReady = false;

  @override
  TtsPlaybackState build() {
    // keepAlive 单例：进程内一直活着；应用退出由系统回收
    ref.onDispose(_disposePlayers);
    return const TtsPlaybackState();
  }

  /// 阅读页挂载时绑定跳转执行器与全书读完提示（可重复绑定，后者生效）。
  void bindReader({
    required void Function(int chapterIdx, int offset) onJump,
    required void Function() onFinishedAll,
  }) {
    _jumpExecutor = onJump;
    _onFinishedAll = onFinishedAll;
  }

  /// 阅读页退出时解绑（朗读照常继续）。
  void unbindReader() {
    _jumpExecutor = null;
    _onFinishedAll = null;
  }

  /// 供测试/调试：直接改写内部句表（正常流程由 [start] 建立）。
  @visibleForTesting
  void debugSetSession({
    required List<NativeChapter> chapters,
    required int chapterIdx,
  }) {
    _chapters = chapters;
    _chapterIdx = chapterIdx;
    _segments = _segmentsFor(chapterIdx, 0);
    state = state.copyWith(
      index: 0,
      total: _segments.length,
      currentText: _segments.isEmpty ? '' : _segments.first.text,
    );
  }

  /// 初始化引擎（首次朗读前调用；语言/音色/语速随设置生效）。
  Future<bool> _ensureEngine(TtsSettings settings) async {
    // MiMo 云端引擎：不走系统 TTS，只校验 API Key（真正合成在 _speakMimo）
    if (isMimoEngine(settings.engine)) {
      final apiKey =
          await (_mimoApiKeyLoader?.call() ?? MimoTtsCredentials().read());
      if (apiKey == null || apiKey.isEmpty) {
        _mimoClient = null;
        _fail('小米 MiMo：请先在听书页配置 API Key');
        return false;
      }
      if (_injectedMimoClient != null) {
        _mimoClient = _injectedMimoClient;
      } else if (_mimoClient == null || _mimoClientKey != apiKey) {
        _mimoClient = MimoTtsClient(apiKey: apiKey);
        _mimoClientKey = apiKey;
      }
      _mimoPlayer ??= _injectedMimoPlayer ?? MimoVoicePlayer();
      _engineReady = true;
      return true;
    }
    if (!_initialized) {
      _initialized = true;
      _tts.setCompletionHandler(_completeUtterance);
      _tts.setCancelHandler(_cancelUtterance);
      _tts.setErrorHandler((message) {
        _fail('朗读引擎错误：$message');
        _cancelUtterance();
      });
    }

    // 切换 Android 朗读引擎（小米 MiMo / 系统语音等）。setEngine 会重建
    // TextToSpeech，语言必须重新设置；默认引擎也显式设一次，用户从
    // MiMo 切回「系统默认」时才真的切回去。
    final target = settings.engine ?? await _defaultEngine();
    if (target != _activeEngine || !_languageReady) {
      if (target != null) {
        try {
          await _tts.setEngine(target);
        } catch (e) {
          debugPrint('tts: setEngine($target) failed $e');
        }
      }
      _activeEngine = target;
      _languageReady = await _selectChinese();
    }
    _engineReady = _languageReady;

    await _applyVoice(settings);
    // flutter_tts Android 侧把倍速 ×2 传给系统（0.5 = 正常语速）
    await _tts.setSpeechRate((settings.rate * 0.5).clamp(0.1, 1.0));
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    return _engineReady;
  }

  Future<String?> _defaultEngine() async {
    try {
      final raw = await _tts.getDefaultEngine;
      return raw is String && raw.isNotEmpty ? raw : null;
    } catch (e) {
      debugPrint('tts: getDefaultEngine failed $e');
      return null;
    }
  }

  Future<bool> _selectChinese() async {
    try {
      final ok = await _tts.setLanguage('zh-CN');
      if (ok != null && ok != 0) return true;
      return (await _tts.isLanguageAvailable('zh-CN')) == true;
    } catch (e) {
      debugPrint('tts: setLanguage failed $e');
      return false;
    }
  }

  Future<void> _applyVoice(TtsSettings settings) async {
    final name = settings.voiceName;
    final locale = settings.voiceLocale;
    if (name == null || locale == null) return;
    try {
      await _tts.setVoice(<String, String>{'name': name, 'locale': locale});
    } catch (e) {
      debugPrint('tts: setVoice failed $e');
    }
  }

  /// 已安装的 Android 朗读引擎（Windows / iOS 返回空）+ MiMo 云端入口。
  Future<List<TtsEngine>> availableEngines() async {
    final mimo = TtsEngine(name: kMimoTtsEngine, label: '小米 MiMo · 云端');
    try {
      final raw = await _tts.getEngines;
      if (raw is! List) return [mimo];
      final names = raw.whereType<String>().where((e) => e.isNotEmpty).toSet()
        ..remove('');
      final sorted = names.toList()..sort();
      return [
        mimo,
        for (final name in sorted)
          TtsEngine(name: name, label: ttsEngineLabel(name)),
      ];
    } catch (e) {
      debugPrint('tts: getEngines failed $e');
      return [mimo];
    }
  }

  /// 查询指定引擎的可用音色（中文优先；无中文返回全部）。
  ///
  /// [engine] 为 null 时切回系统默认引擎；切换后重新设中文，避免 MiMo
  /// 与系统引擎的语言状态串台。MiMo 云端引擎返回预置音色表，不碰系统 TTS。
  Future<List<TtsVoice>> availableVoices({String? engine}) async {
    if (engine == kMimoTtsEngine) return kMimoVoices;
    try {
      final target = engine ?? await _defaultEngine();
      if (target != null && target != _activeEngine) {
        await _tts.setEngine(target);
        _activeEngine = target;
        _languageReady = await _selectChinese();
      }
      final raw = await _tts.getVoices;
      if (raw is! List) return const [];
      final voices = <TtsVoice>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final name = item['name'] as String?;
        final locale = item['locale'] as String?;
        if (name == null || locale == null) continue;
        voices.add(
          TtsVoice(name: name, locale: locale, tags: <String>[locale]),
        );
      }
      final zh = voices.where((v) => v.locale.toLowerCase().startsWith('zh'));
      return zh.isEmpty ? voices : zh.toList();
    } catch (e) {
      debugPrint('tts: getVoices failed $e');
      return const [];
    }
  }

  /// 开始朗读：从 [chapterIdx] 章（或选区/页首所在的句子）开始。
  ///
  /// [startOffset] 是章内字符偏移：从包含该偏移的句子开始（「从此听」传
  /// 选区起点，普通开始传当前页首）；章节表由调用方（阅读页）传入。
  Future<void> start({
    required TtsSettings settings,
    required String bookId,
    required String bookTitle,
    required List<NativeChapter> chapters,
    required int chapterIdx,
    int? startOffset,
  }) async {
    debugPrint(
      'tts-diag: start book=$bookId chapter=$chapterIdx '
      'offset=$startOffset engine=${settings.engine} voice=${settings.voiceName}',
    );
    // 收编调用方传入的设置（= 设置 provider 的当前值；测试可注入）
    await _updateSettings(settings);
    _epoch++;
    final epoch = _epoch;
    _lastBookId = bookId;
    _lastBookTitle = bookTitle;
    _chapters = chapters;
    _chapterIdx = chapterIdx.clamp(
      0,
      chapters.isEmpty ? 0 : chapters.length - 1,
    );
    state = TtsPlaybackState(
      status: TtsPlaybackStatus.preparing,
      bookId: bookId,
      bookTitle: bookTitle,
    );
    _syncBgm();

    final ready = await _ensureEngine(settings);
    if (epoch != _epoch) return;
    if (!ready) {
      // 云端引擎缺 Key 等情况已经 _fail 过（带具体原因），这里只兜底系统路径
      if (state.error == null) {
        _fail('未找到中文系统语音，请在系统设置中安装 TTS 语音包');
      }
      return;
    }

    _segments = _segmentsFor(_chapterIdx, startOffset);
    if (state.status != TtsPlaybackStatus.preparing) return;
    if (_segments.isEmpty) {
      _fail('本章没有可朗读的文本');
      return;
    }
    if (_pauseRequested) {
      _pauseRequested = false;
      await stop();
      return;
    }
    _updateState(
      state.copyWith(
        status: TtsPlaybackStatus.playing,
        index: 0,
        total: _segments.length,
        currentText: _segments.first.text,
        error: null,
        sentences: _segments.map((s) => s.text).toList(),
      ),
    );
    _armTimer(settings.timerMinutes);
    unawaited(_runLoop(epoch));
  }

  /// 章内句子表：从包含 [startOffset] 的句子开始（[startOffset] 为 null
  /// 时从章首）。
  List<({int start, int end, String text})> _segmentsFor(
    int chapterIdx,
    int? startOffset,
  ) {
    if (chapterIdx < 0 || chapterIdx >= _chapters.length) return const [];
    final text = _chapters[chapterIdx].text;
    final from = (startOffset ?? 0).clamp(0, text.length);
    return splitSentences(text)
        .where((s) => s.end > from)
        .map((s) => (start: s.start, end: s.end, text: s.text))
        .toList();
  }

  /// 暂停（停掉当前播报，保留句序）。
  Future<void> pause() async {
    if (state.status == TtsPlaybackStatus.preparing) {
      // 启动窗口期（取句/合成首句）：记下请求，开读即停
      _pauseRequested = true;
      debugPrint('tts-diag: pause requested (preparing)');
      return;
    }
    if (state.status != TtsPlaybackStatus.playing) return;
    debugPrint('tts-diag: pause index=${state.index}');
    _epoch++;
    _timer?.cancel();
    await _stopSpeech();
    _updateState(
      state.copyWith(
        status: TtsPlaybackStatus.paused,
        remaining: state.remaining,
      ),
    );
  }

  /// 继续朗读。
  Future<void> resume() async {
    if (state.status != TtsPlaybackStatus.paused) return;
    _pauseRequested = false;
    _epoch++;
    final epoch = _epoch;
    _updateState(state.copyWith(status: TtsPlaybackStatus.playing));
    _armTimer(_settings.timerMinutes);
    unawaited(_runLoop(epoch));
  }

  /// 停止并清除高亮（章节表与会话记忆保留，供 [restart] 从原句继续）。
  Future<void> stop() async {
    debugPrint('tts-diag: stop index=${state.index}/${_segments.length}');
    _epoch++;
    _pauseRequested = false;
    _timer?.cancel();
    if (_segments.isNotEmpty) {
      _lastChapterIdx = _chapterIdx;
      _lastResumeOffset =
          _segments[state.index.clamp(0, _segments.length - 1)].start;
    }
    _segments = const [];
    await _stopSpeech();
    state = const TtsPlaybackState();
    _syncBgm();
  }

  /// 从上次停下的句子重新开始（听书页在 idle 状态点「开始朗读」）。
  Future<void> restart() async {
    if (!canRestart) {
      _fail('请先在书籍里开始朗读');
      return;
    }
    await start(
      settings: ref.read(ttsSettingsControllerProvider),
      bookId: _lastBookId!,
      bookTitle: _lastBookTitle ?? '',
      chapters: _chapters,
      chapterIdx: _lastChapterIdx,
      startOffset: _lastResumeOffset,
    );
  }

  /// 跳到指定句并从那里继续朗读（暂停态调用等同从该句继续播）。
  Future<void> goToSentence(int index) async {
    if (_segments.isEmpty || !state.active) return;
    final i = index.clamp(0, _segments.length - 1);
    _epoch++;
    _timer?.cancel();
    await _stopSpeech();
    final epoch = _epoch;
    _updateState(
      state.copyWith(
        status: TtsPlaybackStatus.playing,
        index: i,
        currentText: _segments[i].text,
        error: null,
      ),
    );
    _armTimer(_settings.timerMinutes);
    unawaited(_runLoop(epoch));
  }

  /// 上一句（第一句时不动）。
  Future<void> previousSentence() => goToSentence(state.index - 1);

  /// 下一句（本章最后一句时翻下一章）。
  Future<void> nextSentence() => goToSentence(state.index + 1);

  /// 切换音色：写设置；朗读中**从当前句用新音色重新读**
  /// （MiMo 按音色合成/缓存，新音色自然重新合成；系统音色重设 voice）。
  Future<void> changeVoice({
    required String? name,
    required String? locale,
  }) async {
    await _updateSettings(
      _settings.copyWith(voiceName: name, voiceLocale: locale),
    );
    if (!state.active) return;
    if (isMimoEngine(_settings.engine)) {
      // 新音色的句子缓存不存在，goToSentence 会按需重新合成
      await goToSentence(state.index);
      return;
    }
    await _applyVoice(_settings);
    await goToSentence(state.index);
  }

  /// 切换引擎：写设置；朗读中重新初始化引擎并**从当前句重读**。
  Future<void> changeEngine(String? enginePackage) async {
    await _updateSettings(_settings.copyWith(engine: enginePackage));
    if (!state.active) return;
    final ready = await _ensureEngine(_settings);
    if (!ready || state.status != TtsPlaybackStatus.playing) return;
    await goToSentence(state.index);
  }

  /// 写设置（控制器内的唯一写入口，持久化到 prefs）。
  Future<void> _updateSettings(TtsSettings next) async {
    await ref.read(ttsSettingsControllerProvider.notifier).update(next);
  }

  /// 播放中改变语速（立即生效）。
  ///
  /// 系统 TTS 由 setSpeechRate 在下一句生效；MiMo 云端由播放器变速，
  /// 当前句就变（合成结果与倍速无关）。
  Future<void> updateRate(double multiplier) async {
    await _updateSettings(_settings.copyWith(rate: multiplier));
    if (isMimoEngine(_settings.engine)) {
      await _mimoPlayer?.setRate(multiplier);
      return;
    }
    await _tts.setSpeechRate((multiplier * 0.5).clamp(0.1, 1.0));
  }

  // ---- 内部 ----

  /// 统一的状态写入：status 变化时顺带协调背景音乐。
  void _updateState(TtsPlaybackState next) {
    final statusChanged = next.status != state.status;
    state = next;
    if (statusChanged) _syncBgm();
  }

  /// 背景音乐跟随朗读起停（playing → 起，paused → 暂停，idle → 停）。
  void _syncBgm() {
    final bgm = ref.read(bgmPlayerProvider);
    switch (state.status) {
      case TtsPlaybackStatus.playing:
        final id = ref.read(ttsSettingsControllerProvider).bgmId;
        final track = id == null || id.isEmpty
            ? null
            : findAudioTrack(
                // 内置 + 导入都要查（只查导入会把内置曲目查成 null 而静音）
                allAudioTracks(ref.read(audioLibraryControllerProvider)),
                id,
              );
        if (track == null) {
          unawaited(bgm.stop());
        } else {
          unawaited(
            bgm.play(
              track,
              volume: ref.read(ttsSettingsControllerProvider).bgmVolume,
            ),
          );
        }
      case TtsPlaybackStatus.paused:
        unawaited(bgm.pause());
      case TtsPlaybackStatus.preparing:
        break; // 等真正开始播再起音乐
      case TtsPlaybackStatus.idle:
        unawaited(bgm.stop());
    }
  }

  void _armTimer(int minutes) {
    _timer?.cancel();
    if (minutes <= 0) {
      _updateState(state.copyWith(remaining: null));
      return;
    }
    var left = Duration(minutes: minutes);
    _updateState(state.copyWith(remaining: left));
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      left -= const Duration(seconds: 1);
      if (left <= Duration.zero) {
        t.cancel();
        await stop();
        return;
      }
      _updateState(state.copyWith(remaining: left));
    });
  }

  /// 主循环：逐句高亮 → 朗读 → 到期推进；章末自动续章。
  Future<void> _runLoop(int epoch) async {
    while (epoch == _epoch && state.status == TtsPlaybackStatus.playing) {
      if (state.index >= _segments.length) {
        final advanced = await _advanceChapter(epoch);
        if (!advanced) {
          if (epoch == _epoch) {
            await stop();
            _onFinishedAll?.call();
          }
          return;
        }
        continue;
      }
      final segment = _segments[state.index];
      // 高亮并确保可见（阅读页绑定时会翻到该句所在页）
      _jumpExecutor?.call(_chapterIdx, segment.start);
      if (epoch != _epoch) return;
      _updateState(
        state.copyWith(
          highlight: TtsHighlight(
            chapterIndex: _chapterIdx,
            start: segment.start,
            end: segment.end,
          ),
          currentText: segment.text,
          total: _segments.length,
        ),
      );
      debugPrint(
        'tts-diag: speak i=${state.index} ch=$_chapterIdx "${segment.text}"',
      );
      final ok = await _speak(segment.text, epoch);
      if (epoch != _epoch) return;
      if (!ok) {
        // 播报失败（引擎中断/错误）：停止并暴露错误
        if (state.error == null) {
          _fail('朗读中断，请重试');
        }
        return;
      }
      _updateState(state.copyWith(index: state.index + 1));
    }
  }

  /// 章末切到下一章；返回是否成功取到新句。
  Future<bool> _advanceChapter(int epoch) async {
    if (_chapterIdx + 1 >= _chapters.length) return false;
    _chapterIdx++;
    _segments = _segmentsFor(_chapterIdx, null);
    if (epoch != _epoch) return false;
    if (_segments.isEmpty) return false;
    // 阅读页在场就翻过去（不在场只影响高亮/翻页，朗读继续）
    _jumpExecutor?.call(_chapterIdx, 0);
    _updateState(
      state.copyWith(
        index: 0,
        total: _segments.length,
        sentences: _segments.map((s) => s.text).toList(),
      ),
    );
    return true;
  }

  /// 停掉当前播报（按引擎分流：系统 TTS / MiMo 音频播放器）。
  Future<void> _stopSpeech() async {
    if (isMimoEngine(_settings.engine)) {
      await _mimoPlayer?.stop();
      return;
    }
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<bool> _speak(String text, int epoch) async {
    if (isMimoEngine(_settings.engine)) return _speakMimo(text, epoch);
    final done = Completer<bool>();
    _utterance = done;
    try {
      await _tts.speak(text);
    } catch (e) {
      if (identical(_utterance, done)) _utterance = null;
      if (!done.isCompleted) done.complete(false);
      return false;
    }
    final ok = await done.future;
    return ok;
  }

  /// MiMo 云端合成并播放一句话；false = 失败（错误已通过 [_fail] 暴露）。
  Future<bool> _speakMimo(String text, int epoch) async {
    final client = _mimoClient;
    final player = _mimoPlayer;
    if (client == null || player == null) {
      _fail('小米 MiMo 未就绪：请先在听书页配置 API Key');
      return false;
    }
    final voice = _settings.voiceName ?? 'mimo_default';
    final cacheKey = '$voice:$text';
    var wav = _mimoCache[cacheKey];
    if (wav == null) {
      // 预取还在途中：等它落缓存，别再发一次重复请求
      final inflight = _mimoPrefetching[cacheKey];
      if (inflight != null) {
        await inflight;
        if (epoch != _epoch) return false;
        wav = _mimoCache[cacheKey];
      }
    }
    if (wav == null) {
      try {
        wav = await client.synthesize(text, voice: voice);
      } on MimoTtsException catch (e) {
        if (epoch == _epoch) _fail('小米 MiMo：$e');
        return false;
      } catch (e) {
        if (epoch == _epoch) _fail('小米 MiMo：$e');
        return false;
      }
      if (epoch != _epoch) return false;
      // 小缓存：暂停续播 / 回听上一句不再发请求；超了按 FIFO 淘汰
      if (_mimoCache.length >= 32) {
        _mimoCache.remove(_mimoCache.keys.first);
      }
      _mimoCache[cacheKey] = wav;
    }
    try {
      // 倍速由播放器变速实现（合成结果与倍速无关，缓存才得以共用）
      final playing = player.play(wav, rate: _settings.rate);
      // 当前句起播的同时预取后面两句：把合成延迟藏进上一句的播放时间里，
      // 否则每句都要现场等一次 HTTP 往返（句间明显卡顿）
      _prefetchAhead(epoch, state.index + 1);
      return await playing;
    } catch (e) {
      if (epoch == _epoch) _fail('播放合成音频失败：$e');
      return false;
    }
  }

  /// 预取 [fromIndex] 起的最多两句（同一句去重；失败静默——真正读到时会
  /// 按需重试并正常暴露错误，预取不打断当前朗读）。
  void _prefetchAhead(int epoch, int fromIndex) {
    final client = _mimoClient;
    if (client == null) return;
    final voice = _settings.voiceName ?? 'mimo_default';
    final until = (fromIndex + 2).clamp(0, _segments.length);
    for (var i = fromIndex.clamp(0, _segments.length); i < until; i++) {
      final text = _segments[i].text;
      final key = '$voice:$text';
      if (_mimoCache.containsKey(key) || _mimoPrefetching.containsKey(key)) {
        continue;
      }
      final future = _prefetchOne(key, text, voice);
      _mimoPrefetching[key] = future;
      unawaited(future);
    }
  }

  Future<void> _prefetchOne(String key, String text, String voice) async {
    try {
      final client = _mimoClient;
      if (client == null) return;
      final wav = await client.synthesize(text, voice: voice);
      // 小缓存：暂停续播 / 回听上一句不再发请求；超了按 FIFO 淘汰
      if (_mimoCache.length >= 32) {
        _mimoCache.remove(_mimoCache.keys.first);
      }
      _mimoCache[key] = wav;
    } catch (_) {
      // 预取失败不打断朗读：读到该句时按需重试
    } finally {
      // remove 返回 Future<void>?（值类型是 Future），不要真的去等它
      unawaited(_mimoPrefetching.remove(key));
    }
  }

  void _completeUtterance() {
    final done = _utterance;
    _utterance = null;
    if (done != null && !done.isCompleted) done.complete(true);
  }

  void _cancelUtterance() {
    final done = _utterance;
    _utterance = null;
    if (done != null && !done.isCompleted) done.complete(false);
  }

  void _fail(String message) {
    debugPrint('tts-diag: fail: $message');
    _epoch++;
    _pauseRequested = false;
    _timer?.cancel();
    _updateState(
      state.copyWith(status: TtsPlaybackStatus.idle, error: message),
    );
  }

  Future<void> _disposePlayers() async {
    _timer?.cancel();
    _epoch++;
    await _mimoPlayer?.dispose();
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

/// 把 Android 引擎包名转成用户看得懂的名字。
///
/// 小米设备上的 MiMo 引擎通常以 `...mimo...` 出现在包名里；没有命中时
/// 退回包名末段，保证任何已装引擎都能选。
String ttsEngineLabel(String package) {
  final p = package.toLowerCase();
  if (p.contains('mimo')) return '小米 MiMo';
  if (p.contains('xiaomi') || p.contains('miui')) return '小米语音引擎';
  if (p.contains('huawei')) return '华为语音引擎';
  if (p.contains('samsung')) return '三星语音引擎';
  if (p.contains('iflytek')) return '讯飞语音';
  if (p.contains('google')) return 'Google 语音服务';
  if (p.contains('microsoft')) return '微软语音';
  final parts = package.split('.').where((s) => s.isNotEmpty).toList();
  return parts.length > 1 ? parts[parts.length - 1] : package;
}

/// 已安装的朗读引擎。
class TtsEngine {
  const TtsEngine({required this.name, required this.label});

  /// Android 包名（setEngine 用）。
  final String name;

  /// 展示名。
  final String label;

  @override
  bool operator ==(Object other) => other is TtsEngine && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// 可用音色。
class TtsVoice {
  const TtsVoice({
    required this.name,
    required this.locale,
    this.tags = const <String>[],
  });

  /// 引擎内音色名。
  final String name;

  /// BCP-47 语言（系统音色）/ 展示用分组（MiMo 预置音色）。
  final String locale;

  /// 标签（选音色界面的小胶囊：女声 / 中文 / 默认…）。
  final List<String> tags;

  /// 展示名（去掉引擎前缀，保留语言）。
  String get label {
    final short = name.contains('-') ? name.split('-').last : name;
    return '$short · $locale';
  }

  @override
  bool operator ==(Object other) =>
      other is TtsVoice && other.name == name && other.locale == locale;

  @override
  int get hashCode => Object.hash(name, locale);
}
