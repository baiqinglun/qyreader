/// 翻页音效播放器：低延迟、可被打断，失败静默（不干扰阅读）。
///
/// 低延迟关键点：
/// - 音源只在**预载时** `setSource` 一次（Android SoundPool 由此完成解码），
///   翻页时只走 `stop` + `resume` 两个通道调用，不再每次重新装载/等待
///   prepared 事件（audioplayers 文档明确建议 preload + resume 降低延迟）。
/// - Android SoundPool 的 `resume` 只会续播当前流；`stop` 会清掉流 id，
///   下一次 `resume` 才是重新起播。所以连续翻页必须先 `stop` 再 `resume`。
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'reader_settings.dart';

/// 翻页音效播放入口（单例）。
class PageTurnSoundPlayer {
  PageTurnSoundPlayer._();

  /// 全局单例。
  static final PageTurnSoundPlayer instance = PageTurnSoundPlayer._();

  /// 测试用：替换真正的播放动作，避免碰插件通道。
  @visibleForTesting
  static Future<void> Function(String asset)? debugPlayOverride;

  final Map<PageTurnSound, AudioPlayer> _players = {};
  final Set<PageTurnSound> _prepared = {};

  /// 预载 [sound]（建 player + 装载解码音源），不发声。
  ///
  /// 在阅读页打开时调用，让第一次翻页就没有加载延迟；重复调用是幂等的。
  Future<void> preload(PageTurnSound sound) async {
    final asset = sound.asset;
    if (asset.isEmpty || debugPlayOverride != null) return;
    if (_prepared.contains(sound)) return;
    try {
      final player = _players[sound] ?? await _create(sound);
      await player.setSource(AssetSource(_assetKey(asset)));
      _prepared.add(sound);
    } catch (_) {
      // 没有音频后端 / 资源缺失：静默降级，翻页照常。
    }
  }

  /// 播放 [sound]；「无」或空资源直接返回。
  Future<void> play(PageTurnSound sound) async {
    final asset = sound.asset;
    if (asset.isEmpty) return;
    final override = debugPlayOverride;
    if (override != null) {
      await override(asset);
      return;
    }
    try {
      final player = _players[sound] ?? await _create(sound);
      if (_prepared.contains(sound)) {
        // 预载过：stop 清掉 SoundPool 的流 id，下一次 resume 才是重新起播。
        await player.stop();
        await player.resume();
      } else {
        // 没预载过（设置后立刻翻页）：走完整 play，顺带完成装载。
        await player.play(AssetSource(_assetKey(asset)));
        _prepared.add(sound);
      }
    } catch (_) {
      // 没有音频后端 / 资源缺失：静默降级，翻页照常。
    }
  }

  Future<AudioPlayer> _create(PageTurnSound sound) async {
    final player = AudioPlayer(playerId: 'qy-page-turn-${sound.name}');
    await player.setPlayerMode(PlayerMode.lowLatency);
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setVolume(0.9);
    // 只混音、不抢音频焦点：翻页声不该把用户正在听的书/音乐按停。
    await player.setAudioContext(
      AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
    );
    _players[sound] = player;
    return player;
  }

  /// `assets/sounds/x.wav` → `sounds/x.wav`（AssetSource 自带 `assets/` 前缀）。
  static String _assetKey(String asset) =>
      asset.startsWith('assets/') ? asset.substring(7) : asset;
}
