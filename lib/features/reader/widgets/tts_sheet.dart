/// 朗读面板：倍速 / 引擎 / 音色 / 定时 / 背景音乐 + 开始朗读。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import '../../../app/theme/motion.dart';
import '../../../app/theme/reading_theme.dart';
import '../tts/audio_library.dart';
import '../tts/bgm_player.dart';
import '../tts/mimo_key_card.dart';
import '../tts/tts_playback.dart';
import '../tts/voice_picker_sheet.dart';
import '../tts/tts_settings.dart';

/// 引擎下拉里是否选中了 MiMo 云端引擎。
bool _isMimo(String? engine) => engine == kMimoTtsEngine;

/// 弹出朗读设置面板；返回 true 表示用户点了「开始朗读」。
Future<bool?> showTtsSheet(
  BuildContext context, {
  required ReadingTheme theme,
  required Future<List<TtsEngine>> Function() loadEngines,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: kSmoothSheetAnimation,
    backgroundColor: theme.chromeSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => TtsSheet(theme: theme, loadEngines: loadEngines),
  );
}

/// 朗读设置面板。
class TtsSheet extends ConsumerStatefulWidget {
  const TtsSheet({required this.theme, required this.loadEngines, super.key});

  /// 阅读主题。
  final ReadingTheme theme;

  /// 已安装引擎加载回调（Android 才有）。
  final Future<List<TtsEngine>> Function() loadEngines;

  @override
  ConsumerState<TtsSheet> createState() => _TtsSheetState();
}

class _TtsSheetState extends ConsumerState<TtsSheet> {
  static const String _systemEngine = '__system__';

  static const String _noBgm = '__none__';

  List<TtsEngine> _engines = const [];
  bool _loadingEngines = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final engines = await widget.loadEngines();
    if (!mounted) return;
    setState(() {
      _engines = engines;
      _loadingEngines = false;
    });
  }

  TtsSettings get _settings => ref.read(ttsSettingsControllerProvider);

  Future<void> _patch({
    double? rate,
    String? engine,
    bool clearEngine = false,
    String? voiceName,
    String? voiceLocale,
    int? timerMinutes,
    bool clearVoice = false,
    String? bgmId,
    bool clearBgm = false,
    double? bgmVolume,
  }) async {
    final s = _settings;
    final nextEngine = clearEngine ? null : (engine ?? s.engine);
    final engineChanged = nextEngine != s.engine;
    final nextBgm = clearBgm ? null : (bgmId ?? s.bgmId);
    final bgmChanged = nextBgm != s.bgmId;
    final nextVolume = (bgmVolume ?? s.bgmVolume).clamp(0.0, 1.0);
    await ref
        .read(ttsSettingsControllerProvider.notifier)
        .update(
          TtsSettings(
            rate: rate ?? s.rate,
            engine: nextEngine,
            voiceName: engineChanged || clearVoice
                ? null
                : (voiceName ?? s.voiceName),
            voiceLocale: engineChanged || clearVoice
                ? null
                : (voiceLocale ?? s.voiceLocale),
            timerMinutes: timerMinutes ?? s.timerMinutes,
            bgmId: nextBgm,
            bgmVolume: nextVolume,
          ),
        );
    // 背景音乐流已存在（朗读中）就立即换曲 / 调音量；还没开始朗读时只落
    // 设置，起停由阅读页监听 TTS 状态驱动
    if (bgmChanged || bgmVolume != null) {
      final bgm = ref.read(bgmPlayerProvider);
      if (bgm.isPlaying || bgm.isPaused) {
        if (nextBgm == null) {
          await bgm.stop();
        } else if (bgmChanged) {
          final track = findAudioTrack(
            allAudioTracks(ref.read(audioLibraryControllerProvider)),
            nextBgm,
          );
          if (track == null) {
            await bgm.stop();
          } else {
            await bgm.play(track, volume: nextVolume);
          }
        } else {
          await bgm.setVolume(nextVolume);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(ttsSettingsControllerProvider);
    // 冷启动后异步恢复需要一小会儿：恢复完成前引擎别显示成「系统默认」
    final settingsRestored = ref
        .watch(ttsSettingsControllerProvider.notifier)
        .restored;
    final tracks = allAudioTracks(ref.watch(audioLibraryControllerProvider));
    final theme = widget.theme;
    final fg = theme.chromeForeground;
    final hasMiMo = _engines.any((e) => e.label.contains('MiMo'));
    final selectedEngineMissing =
        settings.engine != null &&
        !_engines.any((e) => e.name == settings.engine);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.headphones, color: theme.accent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '朗读',
                    style: TextStyle(
                      color: fg,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 倍速
              Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text('倍速', style: TextStyle(color: fg)),
                  ),
                  Expanded(
                    child: Slider(
                      value: settings.rate,
                      min: 0.5,
                      max: 2.0,
                      divisions: 15,
                      label: '${settings.rate.toStringAsFixed(1)}×',
                      activeColor: theme.accent,
                      onChanged: (v) => _patch(rate: v),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${settings.rate.toStringAsFixed(1)}×',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: fg),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 朗读引擎（Android 系统里已安装的 TTS；小米 MiMo 装好后会出现在这里）
              if (_loadingEngines || _engines.isNotEmpty) ...[
                Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text('引擎', style: TextStyle(color: fg)),
                    ),
                    Expanded(
                      child: (_loadingEngines || !settingsRestored)
                          ? Text(
                              '读取中…',
                              style: TextStyle(
                                color: fg.withValues(alpha: 0.5),
                              ),
                            )
                          : DropdownButton<String>(
                              key: const ValueKey('tts-engine'),
                              isExpanded: true,
                              value: settings.engine ?? _systemEngine,
                              dropdownColor: theme.chromeSurface,
                              style: TextStyle(color: fg, fontSize: 14),
                              items: [
                                DropdownMenuItem<String>(
                                  value: _systemEngine,
                                  child: Text(
                                    '系统默认',
                                    style: TextStyle(color: fg),
                                  ),
                                ),
                                for (final e in _engines)
                                  DropdownMenuItem<String>(
                                    value: e.name,
                                    child: Text(
                                      e.label,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: fg),
                                    ),
                                  ),
                                if (selectedEngineMissing)
                                  DropdownMenuItem<String>(
                                    value: settings.engine,
                                    child: Text(
                                      '${settings.engine}（未安装）',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: fg),
                                    ),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                if (value == _systemEngine) {
                                  _patch(clearEngine: true);
                                } else {
                                  _patch(engine: value);
                                }
                              },
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              // 音色：点开「选择声音」面板（按语言分组 + 试听）
              InkWell(
                key: const ValueKey('tts-voice'),
                borderRadius: BorderRadius.circular(8),
                onTap: () =>
                    unawaited(showVoicePickerSheet(context, theme: theme)),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text('音色', style: TextStyle(color: fg)),
                    ),
                    Expanded(
                      child: Text(
                        settings.voiceName ?? '系统默认',
                        style: TextStyle(
                          color: settings.voiceName == null
                              ? fg.withValues(alpha: 0.6)
                              : fg,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: fg.withValues(alpha: 0.6),
                      size: 20,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // 定时停止
              Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text('定时', style: TextStyle(color: fg)),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final m in const [0, 5, 15, 30, 60])
                          ChoiceChip(
                            label: Text(m == 0 ? '关' : '$m 分'),
                            selected: settings.timerMinutes == m,
                            selectedColor: theme.accent.withValues(alpha: 0.25),
                            labelStyle: TextStyle(
                              color: settings.timerMinutes == m
                                  ? theme.accent
                                  : fg.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                            onSelected: (_) => _patch(timerMinutes: m),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 背景音乐（内置 + 导入；管理与导入入口在设置 → 资源 → 听书音频）
              Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text('音乐', style: TextStyle(color: fg)),
                  ),
                  Expanded(
                    child: DropdownButton<String>(
                      key: const ValueKey('tts-bgm'),
                      isExpanded: true,
                      value:
                          settings.bgmId != null &&
                              tracks.any((t) => t.id == settings.bgmId)
                          ? settings.bgmId
                          : (settings.bgmId == null ? _noBgm : null),
                      hint: Text(
                        '无背景音乐',
                        style: TextStyle(color: fg.withValues(alpha: 0.6)),
                      ),
                      dropdownColor: theme.chromeSurface,
                      style: TextStyle(color: fg, fontSize: 14),
                      items: [
                        DropdownMenuItem<String>(
                          value: _noBgm,
                          child: Text('无背景音乐', style: TextStyle(color: fg)),
                        ),
                        for (final t in tracks)
                          DropdownMenuItem<String>(
                            value: t.id,
                            child: Text(
                              t.isBuiltin ? '${t.name} · 内置' : t.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: fg),
                            ),
                          ),
                        if (settings.bgmId != null &&
                            !tracks.any((t) => t.id == settings.bgmId))
                          DropdownMenuItem<String>(
                            value: settings.bgmId,
                            child: Text(
                              '${settings.bgmId}（已删除）',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: fg),
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        if (value == _noBgm) {
                          _patch(clearBgm: true);
                        } else {
                          _patch(bgmId: value);
                        }
                      },
                    ),
                  ),
                ],
              ),
              if (settings.bgmId != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text('音量', style: TextStyle(color: fg)),
                    ),
                    Expanded(
                      child: Slider(
                        key: const ValueKey('tts-bgm-volume'),
                        value: settings.bgmVolume,
                        min: 0.0,
                        max: 1.0,
                        label: '${(settings.bgmVolume * 100).round()}%',
                        activeColor: theme.accent,
                        onChanged: (v) => _patch(bgmVolume: v),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${(settings.bgmVolume * 100).round()}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: fg),
                      ),
                    ),
                  ],
                ),
              ],
              if (_isMimo(settings.engine)) ...[
                const SizedBox(height: 12),
                MimoKeyCard(theme: theme),
                const SizedBox(height: 8),
                Text(
                  '云端大模型逐句合成，需联网；倍速由播放器即时变速。',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.45),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
              if (_engines.isNotEmpty && !hasMiMo) ...[
                const SizedBox(height: 8),
                Text(
                  '未检测到「小米 MiMo」。在系统设置 → 文字转语音里安装后，'
                  '重新打开本面板即可选择。',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.45),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.accent,
                  minimumSize: const Size.fromHeight(46),
                ),
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.play_arrow),
                label: const Text('开始朗读'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
