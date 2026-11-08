/// TTS 设置：倍速 / 音色 / 定时停止时长。
///
/// 持久化到 shared_preferences（设备本地偏好，不进 SQLite、不参与同步）。
library;

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

    /// 音色名（flutter_tts voice.name）；null = 系统默认。
    String? voiceName,

    /// 音色 locale（与 voiceName 配对，setVoice 需要）。
    String? voiceLocale,

    /// 定时停止分钟数；0 = 不定时。
    @Default(0) int timerMinutes,
  }) = _TtsSettings;
}

/// 设置序列化。
Map<String, dynamic> ttsSettingsToMap(TtsSettings s) => <String, dynamic>{
      'rate': s.rate,
      if (s.voiceName != null) 'voiceName': s.voiceName,
      if (s.voiceLocale != null) 'voiceLocale': s.voiceLocale,
      'timerMinutes': s.timerMinutes,
    };

/// 反序列化（脏值逐字段兜底）。
TtsSettings ttsSettingsFromMap(Map<String, dynamic> json) => TtsSettings(
      rate: ((json['rate'] as num?)?.toDouble() ?? 1.0).clamp(0.5, 2.0),
      voiceName: json['voiceName'] as String?,
      voiceLocale: json['voiceLocale'] as String?,
      timerMinutes: switch ((json['timerMinutes'] as num?)?.toInt() ?? 0) {
        5 || 15 || 30 || 60 => (json['timerMinutes'] as num).toInt(),
        _ => 0,
      },
    );

/// 朗读设置控制器。
@Riverpod(keepAlive: true)
class TtsSettingsController extends _$TtsSettingsController {
  static const String _kKey = 'tts.settings';

  @override
  TtsSettings build() {
    _restore();
    return const TtsSettings();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null) return;
    try {
      state = ttsSettingsFromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // 损坏的设置按默认值处理
    }
  }

  /// 保存设置。
  Future<void> update(TtsSettings next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(ttsSettingsToMap(next)));
  }
}
