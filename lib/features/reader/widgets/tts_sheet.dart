/// 朗读面板：倍速 / 音色 / 定时停止 + 开始朗读。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/reading_theme.dart';
import '../tts/tts_playback.dart';
import '../tts/tts_settings.dart';

/// 弹出朗读设置面板；返回 true 表示用户点了「开始朗读」。
Future<bool?> showTtsSheet(
  BuildContext context, {
  required ReadingTheme theme,
  required Future<List<TtsVoice>> Function() loadVoices,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: kSmoothSheetAnimation,
    backgroundColor: theme.chromeSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => TtsSheet(theme: theme, loadVoices: loadVoices),
  );
}

/// 朗读设置面板。
class TtsSheet extends ConsumerStatefulWidget {
  const TtsSheet({required this.theme, required this.loadVoices, super.key});

  /// 阅读主题。
  final ReadingTheme theme;

  /// 音色加载回调（引擎异步枚举）。
  final Future<List<TtsVoice>> Function() loadVoices;

  @override
  ConsumerState<TtsSheet> createState() => _TtsSheetState();
}

class _TtsSheetState extends ConsumerState<TtsSheet> {
  List<TtsVoice> _voices = const [];
  bool _loadingVoices = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final voices = await widget.loadVoices();
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _loadingVoices = false;
    });
  }

  TtsSettings get _settings => ref.read(ttsSettingsControllerProvider);

  Future<void> _patch({
    double? rate,
    String? voiceName,
    String? voiceLocale,
    int? timerMinutes,
    bool clearVoice = false,
  }) async {
    final s = _settings;
    await ref.read(ttsSettingsControllerProvider.notifier).update(
          TtsSettings(
            rate: rate ?? s.rate,
            voiceName: clearVoice ? null : (voiceName ?? s.voiceName),
            voiceLocale: clearVoice ? null : (voiceLocale ?? s.voiceLocale),
            timerMinutes: timerMinutes ?? s.timerMinutes,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(ttsSettingsControllerProvider);
    final theme = widget.theme;
    final fg = theme.chromeForeground;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
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
                    divisions: 6,
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
            // 音色
            Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text('音色', style: TextStyle(color: fg)),
                ),
                Expanded(
                  child: _loadingVoices
                      ? Text(
                          '读取中…',
                          style: TextStyle(
                            color: fg.withValues(alpha: 0.5),
                          ),
                        )
                      : DropdownButton<String>(
                          isExpanded: true,
                          value: settings.voiceName,
                          hint: Text(
                            '系统默认',
                            style: TextStyle(
                              color: fg.withValues(alpha: 0.6),
                            ),
                          ),
                          dropdownColor: theme.chromeSurface,
                          style: TextStyle(color: fg, fontSize: 14),
                          items: [
                            DropdownMenuItem<String>(
                              value: null,
                              child: Text(
                                '系统默认',
                                style: TextStyle(color: fg),
                              ),
                            ),
                            for (final v in _voices)
                              DropdownMenuItem<String>(
                                value: v.name,
                                child: Text(
                                  v.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: fg),
                                ),
                              ),
                          ],
                          onChanged: (name) {
                            if (name == null) {
                              _patch(clearVoice: true);
                              return;
                            }
                            final v =
                                _voices.where((x) => x.name == name).first;
                            _patch(
                              voiceName: v.name,
                              voiceLocale: v.locale,
                            );
                          },
                        ),
                ),
              ],
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
    );
  }
}
