/// 听书音频管理页：内置曲目 + 导入音频，可试听 / 导入 / 删除。
///
/// 背景音乐是听书的伴音资源：内置曲目打包在 `assets/music/`（不可删、
/// 不同步），导入音频落在应用支持目录 `music/` 并随同步上传（AudioSync，
/// 并集语义）。删除正在被「背景音乐设置」引用的音频时会把设置一并清掉。
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../reader/tts/audio_library.dart';
import '../reader/tts/bgm_player.dart';
import '../reader/tts/tts_settings.dart';
import 'font_cache_view.dart' show formatBytes;

/// 听书音频管理页。
class AudioLibraryPage extends ConsumerStatefulWidget {
  /// 构造。
  const AudioLibraryPage({super.key});

  @override
  ConsumerState<AudioLibraryPage> createState() => _AudioLibraryPageState();
}

class _AudioLibraryPageState extends ConsumerState<AudioLibraryPage> {
  bool _importing = false;

  /// 本页正在试听的曲目（离开页面时停掉它，不动朗读里的背景音乐）。
  String? _previewTrackId;

  /// initState 里拿住的播放器引用（dispose 里不能再 ref.read）。
  late final BgmPlayer _bgm = ref.read(bgmPlayerProvider);

  @override
  void dispose() {
    // 只停本页试听起的流：朗读中正在放的背景音乐不受影响
    if (_previewTrackId != null && _bgm.currentTrackId == _previewTrackId) {
      unawaited(_bgm.stop());
    }
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 试听 / 停止（同一按钮切换）。
  Future<void> _togglePreview(AudioTrack track) async {
    if (_previewTrackId == track.id && _bgm.currentTrackId == track.id) {
      _previewTrackId = null;
      await _bgm.stop();
      if (mounted) setState(() {});
      return;
    }
    _previewTrackId = track.id;
    await _bgm.play(track, volume: 0.6);
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    if (_importing) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
      withData: false,
    );
    final source = picked?.files.single.path;
    if (source == null || source.isEmpty || !mounted) return;
    setState(() => _importing = true);
    try {
      final track = await ref
          .read(audioLibraryControllerProvider.notifier)
          .importFromFile(source);
      _toast('已导入《${track.name}》，可在听书页的「音乐」里选用');
    } on AudioImportException catch (e) {
      _toast('$e');
    } catch (e) {
      _toast('导入失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _delete(AudioTrack track) async {
    final settings = ref.read(ttsSettingsControllerProvider);
    final inUse = settings.bgmId == track.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除《${track.name}》'),
        content: Text(
          inUse
              ? '这条音频正被设为背景音乐，删除后会同时清掉该设置。\n'
                    '云端副本保留，下次同步会重新下载。'
              : '删除本地音频文件。\n云端副本保留，下次同步会重新下载。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref
          .read(audioLibraryControllerProvider.notifier)
          .deleteTrack(track.id);
      if (inUse) {
        await ref
            .read(ttsSettingsControllerProvider.notifier)
            .update(
              ref
                  .read(ttsSettingsControllerProvider)
                  .copyWith(bgmId: null),
            );
      }
      // 正在试听/当背景音乐放着的这条停掉
      if (_bgm.currentTrackId == track.id) {
        _previewTrackId = null;
        await _bgm.stop();
      }
      if (mounted) setState(() {});
      _toast('已删除《${track.name}》');
    } catch (e) {
      _toast('删除失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final imported = ref.watch(audioLibraryControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('听书音频')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.library_music_outlined, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '背景音乐',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${kBuiltinAudioTracks.length + imported.length} 条',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '听书页的「音乐」里选用。内置曲目随应用安装；导入的音频'
                    '会随同步上传到云端（并集语义，删除不传播）。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('audio-import'),
                      onPressed: _importing ? null : _import,
                      icon: _importing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_circle_outline),
                      label: Text(_importing ? '正在导入…' : '导入音频'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              '内置曲目',
              style: theme.textTheme.titleSmall?.copyWith(color: muted),
            ),
          ),
          for (final track in kBuiltinAudioTracks)
            _TrackTile(
              track: track,
              subtitle: '内置 · 随应用安装',
              playing: _isPreviewing(track),
              onPreview: () => unawaited(_togglePreview(track)),
            ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              '导入的音频',
              style: theme.textTheme.titleSmall?.copyWith(color: muted),
            ),
          ),
          if (imported.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 24),
              child: Text(
                '还没有导入音频。支持 mp3 / m4a / aac / wav / ogg / flac / opus，'
                '单个不超过 100 MB。',
                style: TextStyle(color: muted, fontSize: 13, height: 1.5),
              ),
            )
          else
            for (final track in imported)
              FutureBuilder<int>(
                future: _fileSize(track),
                initialData: 0,
                builder: (context, snap) => _TrackTile(
                  track: track,
                  subtitle: '导入 · ${formatBytes(snap.data ?? 0)}',
                  playing: _isPreviewing(track),
                  onPreview: () => unawaited(_togglePreview(track)),
                  onDelete: () => unawaited(_delete(track)),
                ),
              ),
        ],
      ),
    );
  }

  bool _isPreviewing(AudioTrack track) =>
      _previewTrackId == track.id && _bgm.currentTrackId == track.id;

  Future<int> _fileSize(AudioTrack track) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'music', track.fileName!));
      return await file.length();
    } catch (_) {
      return 0;
    }
  }
}

/// 一行曲目：名称 + 说明 + 试听 / 删除。
class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.subtitle,
    required this.playing,
    required this.onPreview,
    this.onDelete,
  });

  final AudioTrack track;
  final String subtitle;
  final bool playing;
  final VoidCallback onPreview;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ListTile(
          key: ValueKey('audio-track-${track.id}'),
          leading: Icon(
            playing ? Icons.graphic_eq : Icons.music_note,
            color: scheme.primary,
          ),
          title: Text(track.name),
          subtitle: Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: playing ? '停止试听' : '试听',
                onPressed: onPreview,
                icon: Icon(
                  playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  color: scheme.primary,
                ),
              ),
              if (onDelete != null)
                IconButton(
                  tooltip: '删除',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
