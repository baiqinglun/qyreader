/// TTS 设置：倍速 / 音色 / 定时停止时长。
///
/// 持久化到 shared_preferences（设备本地偏好，不进 SQLite、不参与同步）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'tts_settings.freezed.dart';
part 'tts_settings.g.dart';

/// 朗读设置。
@freezed
abstract class TtsSettings with _$TtsSettings {
  const factory TtsSettings({
    /// 倍速 0.5..2.0（1.0 为正常语速）。
    @Default(1.0) double rate,

    /// 朗读引擎包名（Android TTS engine；null = 系统默认）。
    String? engine,

    /// 音色名（flutter_tts voice.name）；null = 系统默认。
    String? voiceName,

    /// 音色 locale（与 voiceName 配对，setVoice 需要）。
    String? voiceLocale,

    /// 定时停止分钟数；0 = 不定时。
    @Default(0) int timerMinutes,

    /// 背景音乐曲目 id（内置或导入；null = 不放背景音乐）。
    String? bgmId,

    /// 背景音乐音量 0..1（与朗读音量独立）。
    @Default(0.3) double bgmVolume,
  }) = _TtsSettings;
}

/// 设置序列化。
Map<String, dynamic> ttsSettingsToMap(TtsSettings s) => <String, dynamic>{
  'rate': s.rate,
  if (s.engine != null) 'engine': s.engine,
  if (s.voiceName != null) 'voiceName': s.voiceName,
  if (s.voiceLocale != null) 'voiceLocale': s.voiceLocale,
  'timerMinutes': s.timerMinutes,
  if (s.bgmId != null) 'bgmId': s.bgmId,
  'bgmVolume': s.bgmVolume,
};

/// 反序列化（脏值逐字段兜底）。
TtsSettings ttsSettingsFromMap(Map<String, dynamic> json) => TtsSettings(
  rate: ((json['rate'] as num?)?.toDouble() ?? 1.0).clamp(0.5, 2.0),
  engine: json['engine'] as String?,
  voiceName: json['voiceName'] as String?,
  voiceLocale: json['voiceLocale'] as String?,
  timerMinutes: switch ((json['timerMinutes'] as num?)?.toInt() ?? 0) {
    5 || 15 || 30 || 60 || 90 => (json['timerMinutes'] as num).toInt(),
    _ => 0,
  },
  bgmId: json['bgmId'] as String?,
  bgmVolume: ((json['bgmVolume'] as num?)?.toDouble() ?? 0.3).clamp(0.0, 1.0),
);

/// 朗读设置控制器。
@Riverpod(keepAlive: true)
class TtsSettingsController extends _$TtsSettingsController {
  static const String _kKey = 'tts.settings';

  /// 恢复完成信号：冷启动后第一次访问拿到的是默认值（异步恢复），
  /// 在此之前的读/写都必须等它（否则会用默认值覆盖用户上次的选择，
  /// 弹窗也会先闪一下「系统默认」）。
  final Completer<void> _restored = Completer<void>();

  @override
  TtsSettings build() {
    _restore();
    return const TtsSettings();
  }

  /// 等上次保存的设置恢复完成（读设置前调用，保证拿到的是用户的值）。
  Future<void> waitRestored() => _restored.future;

  /// 是否已恢复完成。
  bool get restored => _restored.isCompleted;

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw != null) {
        state = ttsSettingsFromMap(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // 损坏的设置按默认值处理
    } finally {
      if (!_restored.isCompleted) _restored.complete();
    }
  }

  /// 保存设置（等恢复完成再写，避免恢复把刚保存的值覆盖回旧值）。
  Future<void> update(TtsSettings next) async {
    await _restored.future;
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(ttsSettingsToMap(next)));
  }
}
