/// TTS 设置序列化单测。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:qy_reader/features/reader/tts/tts_settings.dart';

void main() {
  test('toMap / fromMap 往返一致', () {
    const s = TtsSettings(
      rate: 1.5,
      engine: 'com.xiaomi.mimo.tts',
      voiceName: 'cmn-cn-x-ssa-server',
      voiceLocale: 'zh-CN',
      timerMinutes: 15,
      bgmId: 'builtin-rain',
      bgmVolume: 0.4,
    );
    final back = ttsSettingsFromMap(ttsSettingsToMap(s));
    expect(back.rate, 1.5);
    expect(back.engine, 'com.xiaomi.mimo.tts');
    expect(back.voiceName, 'cmn-cn-x-ssa-server');
    expect(back.voiceLocale, 'zh-CN');
    expect(back.timerMinutes, 15);
    expect(back.bgmId, 'builtin-rain');
    expect(back.bgmVolume, 0.4);
  });

  test('脏值兜底：倍速夹紧、非法定时归零、背景音乐音量夹紧', () {
    expect(ttsSettingsFromMap({'rate': 5.0}).rate, 2.0);
    expect(ttsSettingsFromMap({'rate': 0.1}).rate, 0.5);
    expect(ttsSettingsFromMap({'timerMinutes': 7}).timerMinutes, 0);
    expect(ttsSettingsFromMap({'timerMinutes': 30}).timerMinutes, 30);
    expect(ttsSettingsFromMap({'timerMinutes': 90}).timerMinutes, 90);
    expect(ttsSettingsFromMap({}).rate, 1.0);
    // 背景音乐：缺省 = 无音乐 + 30% 音量；脏值夹紧到 0..1
    expect(ttsSettingsFromMap({}).bgmId, isNull);
    expect(ttsSettingsFromMap({}).bgmVolume, 0.3);
    expect(ttsSettingsFromMap({'bgmVolume': 5}).bgmVolume, 1.0);
    expect(ttsSettingsFromMap({'bgmVolume': -1}).bgmVolume, 0.0);
  });
}
