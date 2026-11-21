/// 云端 TTS 音频播放器：播放 MiMo 返回的 WAV 字节，完成/打断语义与
/// 系统 TTS 的「播报完成回调」对齐（play 返回 true = 自然播完）。
///
/// 与背景音乐同策略：`mixWithOthers` 只混音不抢焦点——TTS 播放不该按停
/// 用户自己的背景音乐（两者都是本应用的流）。
///
/// 倍速走 `setPlaybackRate`（Android MediaPlayer 的 playbackParams.speed，
/// 起播时应用、播放中可随时改，`WrappedPlayer.rate` 会跨换源保留）；
/// 注意 >1x 时音调会随之升高（MediaPlayer 变速不保音高），这是当前
/// audioplayers 内核的限制。
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 播放 MiMo 合成出的 WAV。
class MimoVoicePlayer {
  /// 测试用：替换真正的播放动作，返回 true 表示「自然播完」。
  @visibleForTesting
  static Future<bool> Function(Uint8List wav)? debugPlayOverride;

  AudioPlayer? _player;
  Completer<bool>? _done;
  bool _hooked = false;
  double _rate = 1.0;

  /// 播放一段 WAV（[rate] 为播放倍速），等到播完（true）或被打断（false）
  /// 才返回。
  Future<bool> play(Uint8List wav, {double rate = 1.0}) async {
    final override = debugPlayOverride;
    if (override != null) return override(wav);
    final player = _player ??= await _create();
    await player.stop(); // 换源前先停掉上一段
    await _applyRate(player, rate);
    await player.play(BytesSource(wav));
    final done = Completer<bool>();
    _done = done;
    return done.future;
  }

  /// 播放中改倍速（当前句立即生效；未在播放时只记录，下次起播应用）。
  Future<void> setRate(double rate) async {
    _rate = rate.clamp(0.5, 2.0);
    final override = debugPlayOverride;
    if (override != null) return;
    try {
      await _player?.setPlaybackRate(_rate);
    } catch (_) {
      // 未 prepare 时 setRate 会被 MediaPlayer 拒绝：rate 已在
      // WrappedPlayer 记录，下次 start()（play）时会应用
    }
  }

  Future<void> _applyRate(AudioPlayer player, double rate) async {
    final next = rate.clamp(0.5, 2.0);
    if ((next - _rate).abs() < 0.01 && _player != null) return;
    _rate = next;
    try {
      await player.setPlaybackRate(next);
    } catch (_) {}
  }

  /// 停止当前播报（pause/stop/跳句用；未在播放时是 no-op）。
  Future<void> stop() async {
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete(false);
    try {
      await _player?.stop();
    } catch (_) {}
  }

  Future<AudioPlayer> _create() async {
    final player = AudioPlayer(playerId: 'qy-mimo-tts');
    await player.setPlayerMode(PlayerMode.mediaPlayer);
    await player.setReleaseMode(ReleaseMode.stop);
    // 只混音、不抢音频焦点（同 PageTurnSoundPlayer / BgmPlayer 策略）
    await player.setAudioContext(
      AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
    );
    if (!_hooked) {
      _hooked = true;
      player.onPlayerComplete.listen((_) {
        final done = _done;
        _done = null;
        if (done != null && !done.isCompleted) done.complete(true);
      });
    }
    return player;
  }

  /// 释放底层播放器（控制器 dispose 时调用）。
  Future<void> dispose() async {
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete(false);
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}
