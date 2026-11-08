/// TTS 播放控制器：句级朗读 → 高亮 → 自动翻页/续章 → 定时停止。
///
/// flutter_tts 的完成/取消回调是全局的（无 utterance id），用「代次」
/// 令牌丢弃过期回调：每次 stop/pause 递增代次，旧播报的迟到回调不再
/// 推进队列。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../reader_bridge.dart';
import 'tts_settings.dart';

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
  }) =>
      TtsPlaybackState(
        status: status ?? this.status,
        index: index ?? this.index,
        total: total ?? this.total,
        currentText: currentText ?? this.currentText,
        remaining: remaining == _sentinel
            ? this.remaining
            : remaining as Duration?,
        error: error == _sentinel ? this.error : error as String?,
      );

  static const Object _sentinel = Object();
}

/// TTS 播放控制器（阅读器页面持有；不注册为 Riverpod provider，
/// 因为需要按槽位访问 WebView 桥）。
class TtsPlaybackController extends ValueNotifier<TtsPlaybackState> {
  /// 构造：注入桥访问器（返回当前可视层桥，可能为 null）。
  TtsPlaybackController({
    required ReaderBridge? Function() bridge,
    required this.onFinishedChapter,
  })  : _bridge = bridge,
        super(const TtsPlaybackState());

  final ReaderBridge? Function() _bridge;

  /// 章末无下一章时的回调（页面可提示「全书读完」）。
  final void Function() onFinishedChapter;

  final FlutterTts _tts = FlutterTts();

  /// 当前章节句子。
  List<TtsSegment> _segments = const [];

  /// 代次令牌：stop/pause 递增，丢弃过期播报回调。
  int _epoch = 0;

  /// 单句播报完成信号。
  Completer<bool>? _utterance;

  TtsSettings _settings = const TtsSettings();

  Timer? _timer;

  bool _initialized = false;

  /// 音频路由是否就绪（引擎/语言可用）。
  bool _engineReady = false;

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    _epoch++;
    try {
      await _tts.stop();
    } catch (_) {}
    super.dispose();
  }

  /// 初始化引擎（首次朗读前调用；语言/音色/语速随设置生效）。
  Future<bool> _ensureEngine(TtsSettings settings) async {
    _settings = settings;
    if (!_initialized) {
      _initialized = true;
      _tts.setCompletionHandler(_completeUtterance);
      _tts.setCancelHandler(_cancelUtterance);
      _tts.setErrorHandler((message) {
        _fail('朗读引擎错误：$message');
        _cancelUtterance();
      });
      try {
        // 中文优先；无中文引擎时退回系统默认语言
        final ok = await _tts.setLanguage('zh-CN');
        _engineReady = ok != 0 && ok != null;
        if (!_engineReady) {
          _engineReady = (await _tts.isLanguageAvailable('zh-CN')) == true;
        }
      } catch (e) {
        _engineReady = false;
        debugPrint('tts: setLanguage failed $e');
      }
    }
    await _applyVoice(settings);
    // flutter_tts Android 侧把倍速 ×2 传给系统（0.5 = 正常语速）
    await _tts.setSpeechRate((settings.rate * 0.5).clamp(0.1, 1.0));
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    return _engineReady;
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

  /// 查询可用音色（中文优先；无中文返回全部）。
  Future<List<TtsVoice>> availableVoices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return const [];
      final voices = <TtsVoice>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final name = item['name'] as String?;
        final locale = item['locale'] as String?;
        if (name == null || locale == null) continue;
        voices.add(TtsVoice(name: name, locale: locale));
      }
      final zh = voices.where((v) => v.locale.toLowerCase().startsWith('zh'));
      return zh.isEmpty ? voices : zh.toList();
    } catch (e) {
      debugPrint('tts: getVoices failed $e');
      return const [];
    }
  }

  /// 从当前页开始朗读。
  Future<void> start(TtsSettings settings) async {
    _settings = settings;
    _epoch++;
    final epoch = _epoch;
    value = const TtsPlaybackState(status: TtsPlaybackStatus.preparing);

    final ready = await _ensureEngine(settings);
    if (epoch != _epoch) return;
    if (!ready) {
      _fail('未找到中文系统语音，请在系统设置中安装 TTS 语音包');
      return;
    }

    final segments = await _loadSegments();
    if (epoch != _epoch) return;
    if (segments.isEmpty) {
      _fail('本章没有可朗读的文本');
      return;
    }
    _segments = segments;
    value = value.copyWith(
      status: TtsPlaybackStatus.playing,
      index: 0,
      total: segments.length,
      currentText: segments.first.text,
      error: null,
    );
    _armTimer(settings.timerMinutes);
    unawaited(_runLoop(epoch));
  }

  /// 暂停（停掉当前播报，保留句序）。
  Future<void> pause() async {
    if (value.status != TtsPlaybackStatus.playing) return;
    _epoch++;
    _timer?.cancel();
    try {
      await _tts.stop();
    } catch (_) {}
    final remaining = _remainingSnapshot();
    value = value.copyWith(
      status: TtsPlaybackStatus.paused,
      remaining: remaining,
    );
  }

  /// 继续朗读。
  Future<void> resume() async {
    if (value.status != TtsPlaybackStatus.paused) return;
    _epoch++;
    final epoch = _epoch;
    value = value.copyWith(status: TtsPlaybackStatus.playing);
    _armTimer(_settings.timerMinutes);
    unawaited(_runLoop(epoch));
  }

  /// 停止并清除高亮。
  Future<void> stop() async {
    _epoch++;
    _timer?.cancel();
    _segments = const [];
    try {
      await _tts.stop();
    } catch (_) {}
    await _bridge()?.ttsClear();
    value = const TtsPlaybackState();
  }

  /// 播放中改变语速（立即生效）。
  Future<void> updateRate(double multiplier) async {
    _settings = _settings.copyWith(rate: multiplier);
    await _tts.setSpeechRate((multiplier * 0.5).clamp(0.1, 1.0));
  }

  // ---- 内部 ----

  Duration? _remainingSnapshot() {
    // 暂停时把剩余定时时长冻结在状态里
    if (value.remaining == null) return null;
    return value.remaining;
  }

  void _armTimer(int minutes) {
    _timer?.cancel();
    if (minutes <= 0) {
      value = value.copyWith(remaining: null);
      return;
    }
    var left = Duration(minutes: minutes);
    value = value.copyWith(remaining: left);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      left -= const Duration(seconds: 1);
      if (left <= Duration.zero) {
        t.cancel();
        await stop();
        return;
      }
      value = value.copyWith(remaining: left);
    });
  }

  Future<List<TtsSegment>> _loadSegments() async {
    final b = _bridge();
    if (b == null) return const [];
    final list = await b.ttsSegments();
    return list ?? const [];
  }

  /// 主循环：逐句高亮 → 朗读 → 到期推进；章末自动续章。
  Future<void> _runLoop(int epoch) async {
    while (epoch == _epoch && value.status == TtsPlaybackStatus.playing) {
      if (value.index >= _segments.length) {
        final advanced = await _advanceChapter(epoch);
        if (!advanced) {
          if (epoch == _epoch) {
            await stop();
            onFinishedChapter();
          }
          return;
        }
        continue;
      }
      final segment = _segments[value.index];
      // 高亮并确保可见（不在当前页时 JS 会自动翻页）
      await _bridge()?.ttsShow(segment.cfi);
      if (epoch != _epoch) return;
      value = value.copyWith(
        currentText: segment.text,
        total: _segments.length,
      );
      final ok = await _speak(segment.text, epoch);
      if (epoch != _epoch) return;
      if (!ok) {
        // 播报失败（引擎中断/错误）：停止并暴露错误
        if (value.error == null) {
          _fail('朗读中断，请重试');
        }
        return;
      }
      value = value.copyWith(index: value.index + 1);
    }
  }

  /// 章末切到下一章；返回是否成功取到新句。
  Future<bool> _advanceChapter(int epoch) async {
    final b = _bridge();
    if (b == null) return false;
    final nextHref = await b.ttsNextHref();
    if (epoch != _epoch) return false;
    if (nextHref == null || nextHref.isEmpty) return false;
    await b.gotoHref(nextHref);
    // 等视图渲染出新章节（epub.js display 异步）
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (epoch != _epoch) return false;
    final segments = await _loadSegments();
    if (epoch != _epoch) return false;
    if (segments.isEmpty) return false;
    _segments = segments;
    value = value.copyWith(index: 0, total: segments.length);
    return true;
  }

  Future<bool> _speak(String text, int epoch) async {
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
    _epoch++;
    _timer?.cancel();
    value = value.copyWith(
      status: TtsPlaybackStatus.idle,
      error: message,
    );
  }
}

/// 可用音色。
class TtsVoice {
  const TtsVoice({required this.name, required this.locale});

  /// 引擎内音色名。
  final String name;

  /// BCP-47 语言。
  final String locale;

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
