/// 朗读设置面板：引擎 / 定时停止 / 背景音乐 + 音量（听书页「设置」入口）。
///
/// 从旧「控制卡」抽出：倍速有独立滑杆（底栏语速）、音色有「选择声音」
/// 面板，这里只留引擎/定时/背景音乐三组。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/reading_theme.dart';
import '../reader_settings.dart';
import 'audio_library.dart';
import 'bgm_player.dart';
import 'tts_playback.dart';
import 'tts_settings.dart';

/// 弹出朗读设置面板。
Future<void> showTtsSettingsSheet(BuildContext context, ReadingTheme theme) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: kSmoothSheetAnimation,
    backgroundColor: theme.chromeSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const TtsSettingsSheet(),
  );
}

/// 朗读设置面板。
class TtsSettingsSheet extends ConsumerStatefulWidget {
  /// 构造。
  const TtsSettingsSheet({super.key});

  @override
  ConsumerState<TtsSettingsSheet> createState() => _TtsSettingsSheetState();
}

class _TtsSettingsSheetState extends ConsumerState<TtsSettingsSheet> {
  static const String _systemEngine = '__system__';
  static const String _noBgm = '__none__';

  List<TtsEngine> _engines = const [];
  bool _loadingEngines = true;

  TtsPlayback get _tts => ref.read(ttsPlaybackProvider.notifier);

  @override
  void initState() {
    super.initState();
    _loadEngines();
  }

  Future<void> _loadEngines() async {
    await ref.read(ttsSettingsControllerProvider.notifier).waitRestored();
    List<TtsEngine> engines = const [];
    try {
      engines = await _tts.availableEngines();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _engines = engines;
      _loadingEngines = false;
    });
  }

  Future<void> _patch({
    String? engine,
    bool clearEngine = false,
    int? timerMinutes,
    String? bgmId,
    bool clearBgm = false,
    double? bgmVolume,
  }) async {
    final s = ref.read(ttsSettingsControllerProvider);
    final nextEngine = clearEngine ? null : (engine ?? s.engine);
    final nextBgm = clearBgm ? null : (bgmId ?? s.bgmId);
    final bgmChanged = nextBgm != s.bgmId;
    final nextVolume = (bgmVolume ?? s.bgmVolume).clamp(0.0, 1.0);
    final next = s.copyWith(
      engine: nextEngine,
      timerMinutes: timerMinutes ?? s.timerMinutes,
      bgmId: nextBgm,
      bgmVolume: nextVolume,
    );
    await ref.read(ttsSettingsControllerProvider.notifier).update(next);
    // 引擎切换：朗读中从当前句用新引擎重读（面板内不区分朗读与否）
    if (nextEngine != s.engine) {
      await _tts.changeEngine(nextEngine);
    }
    // 背景音乐流已存在（朗读中）就立即换曲 / 调音量
    if (bgmChanged || bgmVolume != null) {
      final bgm = ref.read(bgmPlayerProvider);
      if (bgm.isPlaying || bgm.isPaused) {
        if (nextBgm == null) {
          await bgm.stop();
        } else if (bgmChanged) {
          // 内置 + 导入都要查（只查导入会把内置曲目查成 null 而静音）
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
    final theme = ref.watch(readingSettingsControllerProvider).theme;
    final settings = ref.watch(ttsSettingsControllerProvider);
    final settingsRestored = ref
        .watch(ttsSettingsControllerProvider.notifier)
        .restored;
    final tracks = allAudioTracks(ref.watch(audioLibraryControllerProvider));
    final fg = theme.chromeForeground;
    final hasMiMo = _engines.any((e) => e.label.contains('MiMo'));
    final selectedEngineMissing =
        settings.engine != null &&
        !_engines.any((e) => e.name == settings.engine);
    final bgmValue =
        settings.bgmId != null && tracks.any((t) => t.id == settings.bgmId)
        ? settings.bgmId
        : null;

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
                  Icon(Icons.tune, color: theme.accent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '朗读设置',
                    style: TextStyle(
                      color: fg,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 引擎
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
                            style: TextStyle(color: fg.withValues(alpha: 0.5)),
                          )
                        : DropdownButton<String>(
                            key: const ValueKey('tts-settings-engine'),
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
              if (_engines.isNotEmpty && !hasMiMo) ...[
                const SizedBox(height: 8),
                Text(
                  '未检测到「小米 MiMo」。在系统设置 → 文字转语音里安装后，重新打开本面板即可选择。',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.45),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // 定时停止
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 56,
                    child: Text('定时', style: TextStyle(color: fg)),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in const [0, 5, 15, 30, 60, 90])
                          ChoiceChip(
                            key: ValueKey('tts-settings-timer-$m'),
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
              const SizedBox(height: 16),
              // 背景音乐
              Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text('音乐', style: TextStyle(color: fg)),
                  ),
                  Expanded(
                    child: DropdownButton<String>(
                      key: const ValueKey('tts-settings-bgm'),
                      isExpanded: true,
                      value:
                          bgmValue ?? (settings.bgmId == null ? _noBgm : null),
                      hint: Text(
                        '无背景音乐',
                        style: TextStyle(color: fg.withValues(alpha: 0.6)),
                      ),
                      dropdownColor: theme.chromeSurface,
                      style: TextStyle(color: fg, fontSize: 14),
                      items: [
                        const DropdownMenuItem<String>(
                          value: _noBgm,
                          child: Text('无背景音乐'),
                        ),
                        for (final t in tracks)
                          DropdownMenuItem<String>(
                            value: t.id,
                            child: Text(
                              t.isBuiltin ? '${t.name} · 内置' : t.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (settings.bgmId != null && bgmValue == null)
                          DropdownMenuItem<String>(
                            value: settings.bgmId,
                            child: Text(
                              '${settings.bgmId}（已删除）',
                              overflow: TextOverflow.ellipsis,
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text('音量', style: TextStyle(color: fg)),
                    ),
                    Expanded(
                      child: Slider(
                        key: const ValueKey('tts-settings-bgm-volume'),
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
              const SizedBox(height: 8),
              Text(
                '倍速用底栏的「语速」，音色用「音色」入口调整；切换音色/引擎会从当前句重新读。',
                style: TextStyle(
                  color: fg.withValues(alpha: 0.45),
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
