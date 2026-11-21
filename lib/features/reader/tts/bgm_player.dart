/// 听书背景音乐播放器：与 TTS 混音、循环播放、独立音量。
///
/// 用 audioplayers 的普通媒体模式（长音频，非 SoundPool 低延迟），音频焦点
/// 与翻页音效同策略：`mixWithOthers` 只混音、不抢焦点——背景音乐不该把
/// 用户正在听的 TTS 按停（系统 TTS 引擎自己持焦点）。
///
/// 全局单例（keepAlive provider）：阅读页驱动起停、听书页/管理页换曲与
/// 试听共用同一个实例，任何时刻只有一条背景音乐流。
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'audio_library.dart';

part 'bgm_player.g.dart';

/// 背景音乐播放器。
class BgmPlayer {
  /// 测试用：替换真正的播放动作（kind ∈ play/pause/resume/stop/volume），
  /// 避免碰插件通道；source 为曲目源（asset key 或文件路径）。
  @visibleForTesting
  static Future<void> Function(String kind, String? source)? debugPlayOverride;

  AudioPlayer? _player;

  /// 当前装载的曲目 id（null = 没装）；换曲才重装音源。
  String? _loadedTrackId;

  /// 当前装载的曲目 id（试听/状态判断用；null = 没装）。
  String? get currentTrackId => _loadedTrackId;

  bool _paused = false;

  double _volume = 0.3;

  /// 是否在播放（已装载曲目且未暂停）。
  bool get isPlaying => !_paused && _loadedTrackId != null;

  /// 当前是否处于暂停（有装载曲目）。
  bool get isPaused => _paused && _loadedTrackId != null;

  /// 播放（或切换到）[track]；同曲目重复调用只是恢复播放。
  Future<void> play(AudioTrack track, {required double volume}) async {
    _volume = volume.clamp(0.0, 1.0);
    final changed = _loadedTrackId != track.id;
    _loadedTrackId = track.id;
    _paused = false;
    final source = track.assetSourceKey();
    final override = debugPlayOverride;
    if (override != null) {
      await override('play', source);
      return;
    }
    try {
      final player = _player ??= await _create();
      if (changed) {
        await player.stop();
        if (source != null) {
          await player.setSource(AssetSource(source));
        } else if (track.fileName != null) {
          final dir = await audioLibraryDir();
          await player.setSource(
            DeviceFileSource(p.join(dir.path, track.fileName)),
          );
        }
        await player.setVolume(_volume);
        await player.resume();
      } else {
        await player.setVolume(_volume);
        await player.resume();
      }
    } catch (_) {
      // 没有音频后端 / 资源缺失：静默降级（TTS 不受影响）
    }
  }

  /// 暂停（保留装载，resume 续播）。
  Future<void> pause() async {
    if (_loadedTrackId == null || _paused) return;
    _paused = true;
    final override = debugPlayOverride;
    if (override != null) {
      await override('pause', null);
      return;
    }
    try {
      await _player?.pause();
    } catch (_) {}
  }

  /// 恢复播放。
  Future<void> resume() async {
    if (_loadedTrackId == null || !_paused) return;
    _paused = false;
    final override = debugPlayOverride;
    if (override != null) {
      await override('resume', null);
      return;
    }
    try {
      await _player?.resume();
    } catch (_) {}
  }

  /// 停止并卸载曲目。
  Future<void> stop() async {
    if (_loadedTrackId == null) return;
    _loadedTrackId = null;
    _paused = false;
    final override = debugPlayOverride;
    if (override != null) {
      await override('stop', null);
      return;
    }
    try {
      await _player?.stop();
    } catch (_) {}
  }

  /// 只调音量（不改变播放状态）。
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    final override = debugPlayOverride;
    if (override != null) {
      await override('volume', null);
      return;
    }
    try {
      await _player?.setVolume(_volume);
    } catch (_) {}
  }

  Future<AudioPlayer> _create() async {
    final player = AudioPlayer(playerId: 'qy-bgm');
    await player.setPlayerMode(PlayerMode.mediaPlayer);
    await player.setReleaseMode(ReleaseMode.loop);
    // 只混音、不抢音频焦点（同翻页音效策略）
    await player.setAudioContext(
      AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
    );
    return player;
  }
}

/// 全局背景音乐播放器（keepAlive：阅读页/听书页/管理页共用一条流）。
@Riverpod(keepAlive: true)
BgmPlayer bgmPlayer(Ref ref) => BgmPlayer();
