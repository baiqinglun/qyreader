/// 选择声音：音色选择界面（参照主流听书 App 的选声音面板）。
///
/// 结构：顶部「朗读引擎」卡片行（点进去在面板内切引擎）→ 按语言分组的
/// 音色列表（名称 + 标签 + 试听 + 当前选中高亮勾）。
///
/// - 音色/引擎选中即写设置；**朗读中切换会从当前句用新音色重新读**
///   （`TtsPlayback.changeVoice` / `changeEngine`）。
/// - 试听：MiMo 云端音色用 API 合成一小段示例播放（朗读中会先暂停朗读）；
///   系统引擎音色不提供试听。
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/reading_theme.dart';
import 'mimo_tts_client.dart';
import 'tts_playback.dart';
import '../reader_settings.dart';
import 'tts_settings.dart';

/// 弹出「选择声音」面板。
Future<void> showVoicePickerSheet(
  BuildContext context, {
  required ReadingTheme theme,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: kSmoothSheetAnimation,
    backgroundColor: theme.chromeSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const VoicePickerSheet(),
  );
}

/// 「选择声音」面板。
class VoicePickerSheet extends ConsumerStatefulWidget {
  /// 构造。
  const VoicePickerSheet({super.key});

  @override
  ConsumerState<VoicePickerSheet> createState() => _VoicePickerSheetState();
}

class _VoicePickerSheetState extends ConsumerState<VoicePickerSheet> {
  /// 面板内视图：音色列表 / 引擎列表。
  bool _engineMode = false;

  List<TtsEngine> _engines = const [];
  List<TtsVoice> _voices = const [];
  bool _loadingVoices = true;

  /// 试听播放（独立小播放器，不干扰朗读循环）。
  AudioPlayer? _previewPlayer;
  TtsVoice? _previewing;
  bool _previewBusy = false;

  TtsPlayback get _tts => ref.read(ttsPlaybackProvider.notifier);
  TtsSettings get _settings => ref.read(ttsSettingsControllerProvider);

  bool get _isMimo => isMimoEngine(_settings.engine);

  @override
  void initState() {
    super.initState();
    _loadEngines();
  }

  @override
  void dispose() {
    unawaited(_stopPreview());
    super.dispose();
  }

  Future<void> _loadEngines() async {
    // 冷启动后设置异步恢复：等完成再按「上次的引擎」加载音色
    await ref.read(ttsSettingsControllerProvider.notifier).waitRestored();
    try {
      final engines = await _tts.availableEngines();
      if (!mounted) return;
      setState(() => _engines = engines);
    } catch (_) {}
    await _loadVoices();
  }

  Future<void> _loadVoices() async {
    if (mounted) setState(() => _loadingVoices = true);
    List<TtsVoice> voices = const [];
    try {
      voices = await _tts.availableVoices(engine: _settings.engine);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _loadingVoices = false;
    });
  }

  // ---- 试听 ----

  Future<void> _togglePreview(TtsVoice voice) async {
    if (_previewBusy) return;
    // 已在试听同一条 → 停止
    if (_previewing == voice) {
      await _stopPreview();
      if (mounted) setState(() => _previewing = null);
      return;
    }
    if (!_isMimo) return; // 系统引擎音色不支持试听
    setState(() {
      _previewBusy = true;
      _previewing = voice;
    });
    try {
      // 朗读中先暂停，避免示例与朗读叠音
      if (ref.read(ttsPlaybackProvider).status == TtsPlaybackStatus.playing) {
        await _tts.pause();
      }
      final apiKey = await MimoTtsCredentials().read();
      if (apiKey == null || apiKey.isEmpty) {
        _toast('小米 MiMo：请先在听书页配置 API Key');
        return;
      }
      final client = MimoTtsClient(apiKey: apiKey);
      final wav = await client.synthesize('你好，这是一段试听。', voice: voice.name);
      final player = _previewPlayer ??= AudioPlayer(
        playerId: 'qy-voice-preview',
      );
      await player.setAudioContext(
        AudioContextConfig(
          focus: AudioContextConfigFocus.mixWithOthers,
        ).build(),
      );
      await player.stop();
      await player.play(BytesSource(wav));
    } on MimoTtsException catch (e) {
      _toast('试听失败：$e');
    } catch (_) {
      _toast('试听失败');
    } finally {
      if (mounted) {
        setState(() {
          _previewBusy = false;
          _previewing = null;
        });
      }
    }
  }

  Future<void> _stopPreview() async {
    try {
      await _previewPlayer?.stop();
    } catch (_) {}
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- 选择 ----

  Future<void> _selectVoice(TtsVoice voice) async {
    await _tts.changeVoice(name: voice.name, locale: voice.locale);
    if (mounted) setState(() {});
  }

  Future<void> _selectEngine(String? engine) async {
    await _tts.changeEngine(engine);
    if (mounted) {
      setState(() => _engineMode = false);
      await _loadVoices();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(readingSettingsControllerProvider).theme;
    final settings = ref.watch(ttsSettingsControllerProvider);
    final fg = theme.chromeForeground;
    final engineLabel = _engineDisplayName(settings.engine);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 头部：标题 + 返回（引擎模式时）
              Row(
                children: [
                  if (_engineMode)
                    IconButton(
                      tooltip: '返回音色列表',
                      onPressed: () => setState(() => _engineMode = false),
                      icon: Icon(Icons.arrow_back, color: fg, size: 22),
                    ),
                  Text(
                    _engineMode ? '选择引擎' : '选择声音',
                    style: TextStyle(
                      color: fg,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 引擎卡片行（音色模式下显示）
              if (!_engineMode) ...[
                _EngineCard(
                  label: engineLabel,
                  fg: fg,
                  onTap: () => setState(() => _engineMode = true),
                ),
                const SizedBox(height: 12),
              ],
              // 列表
              Expanded(
                child: _engineMode
                    ? _buildEngineList(fg)
                    : _buildVoiceList(theme, fg, settings),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _engineDisplayName(String? engine) {
    if (engine == null) return '系统默认';
    for (final e in _engines) {
      if (e.name == engine) return e.label;
    }
    return ttsEngineLabel(engine);
  }

  /// 音色列表：按语言分组。
  Widget _buildVoiceList(ReadingTheme theme, Color fg, TtsSettings settings) {
    if (_loadingVoices) {
      return Center(
        child: Text('读取中…', style: TextStyle(color: fg.withValues(alpha: 0.5))),
      );
    }
    // 分组保持出现顺序（中文组在前）
    final Map<String, List<TtsVoice>> groups = <String, List<TtsVoice>>{};
    for (final v in _voices) {
      groups.putIfAbsent(v.locale, () => <TtsVoice>[]).add(v);
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text(
              '${entry.key} · ${entry.value.length}',
              style: TextStyle(color: fg.withValues(alpha: 0.55), fontSize: 15),
            ),
          ),
          for (final voice in entry.value)
            _VoiceTile(
              voice: voice,
              theme: theme,
              fg: fg,
              selected: settings.voiceName == voice.name,
              previewing: _previewing == voice,
              previewSupported: _isMimo,
              onPreview: () => unawaited(_togglePreview(voice)),
              onSelect: () => unawaited(_selectVoice(voice)),
            ),
        ],
      ],
    );
  }

  /// 引擎列表（面板内切换视图）。
  Widget _buildEngineList(Color fg) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        _EngineTile(
          name: '系统默认',
          label: '系统默认',
          selected: _settings.engine == null,
          fg: fg,
          onSelect: () => unawaited(_selectEngine(null)),
        ),
        for (final e in _engines)
          if (e.name != kMimoTtsEngine)
            _EngineTile(
              name: e.name,
              label: e.label,
              selected: _settings.engine == e.name,
              fg: fg,
              onSelect: () => unawaited(_selectEngine(e.name)),
            ),
      ],
    );
  }
}

/// 顶部「朗读引擎」卡片行。
class _EngineCard extends StatelessWidget {
  const _EngineCard({
    required this.label,
    required this.fg,
    required this.onTap,
  });

  final String label;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: fg.withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Text('朗读引擎', style: TextStyle(color: fg, fontSize: 16)),
              const Spacer(),
              Text(
                label,
                style: TextStyle(
                  color: fg.withValues(alpha: 0.8),
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: fg.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一行音色：名称 + 标签 + 试听 + 当前选中勾与描边。
class _VoiceTile extends StatelessWidget {
  const _VoiceTile({
    required this.voice,
    required this.theme,
    required this.fg,
    required this.selected,
    required this.previewing,
    required this.previewSupported,
    required this.onPreview,
    required this.onSelect,
  });

  final TtsVoice voice;
  final ReadingTheme theme;
  final Color fg;
  final bool selected;
  final bool previewing;
  final bool previewSupported;
  final VoidCallback onPreview;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onSelect,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? theme.accent : fg.withValues(alpha: 0.15),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              voice.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: fg,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (selected) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.check_rounded,
                              color: theme.accent,
                              size: 20,
                            ),
                          ],
                        ],
                      ),
                      if (voice.tags.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: [
                            for (final tag in voice.tags)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: fg.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  tag,
                                  style: TextStyle(
                                    color: fg.withValues(alpha: 0.65),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (previewSupported)
                  IconButton(
                    tooltip: previewing ? '停止试听' : '试听',
                    onPressed: onPreview,
                    icon: previewing
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.accent,
                            ),
                          )
                        : Icon(
                            Icons.headphones_outlined,
                            color: fg.withValues(alpha: 0.8),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一行引擎（面板内切换视图用）。
class _EngineTile extends StatelessWidget {
  const _EngineTile({
    required this.name,
    required this.label,
    required this.selected,
    required this.fg,
    required this.onSelect,
  });

  final String name;
  final String label;
  final bool selected;
  final Color fg;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onSelect,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? fg : fg.withValues(alpha: 0.15),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 16,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (selected) Icon(Icons.check_rounded, color: fg, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
