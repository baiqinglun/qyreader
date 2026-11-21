/// 音频缓存视图：列出本机导入的背景音乐音频文件，可逐条或一键清除。
///
/// 只删本地音频文件与本机 manifest 条目；云端音频清单还在，下次同步会把
/// 它们重新下载回来（语义与字体缓存一致）。内置曲目打包在 APK 里，
/// 不占本地缓存、不显示。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../reader/tts/audio_library.dart';
import 'font_cache_view.dart' show formatBytes;

/// 一条本机音频文件。
class _AudioFile {
  const _AudioFile(this.track, this.bytes);

  final AudioTrack track;
  final int bytes;
}

/// 音频缓存视图。
class AudioCacheView extends ConsumerStatefulWidget {
  /// 构造。
  const AudioCacheView({super.key});

  @override
  ConsumerState<AudioCacheView> createState() => _AudioCacheViewState();
}

class _AudioCacheViewState extends ConsumerState<AudioCacheView> {
  bool _loading = true;
  bool _clearingAll = false;
  List<_AudioFile> _files = const [];
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    var list = <_AudioFile>[];
    try {
      final dir = await getApplicationSupportDirectory();
      for (final track in ref.read(audioLibraryControllerProvider)) {
        final file = File(p.join(dir.path, 'music', track.fileName!));
        if (!file.existsSync()) continue;
        var size = 0;
        try {
          size = file.lengthSync();
        } catch (_) {
          // 读不到大小不影响列表
        }
        list.add(_AudioFile(track, size));
      }
      list.sort((a, b) => a.track.name.compareTo(b.track.name));
    } catch (_) {
      list = <_AudioFile>[];
    }
    if (!mounted) return;
    setState(() {
      _files = list;
      _loading = false;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clearOne(_AudioFile entry) async {
    if (_busy.contains(entry.track.id) || _clearingAll) return;
    setState(() => _busy.add(entry.track.id));
    try {
      await _deleteTrack(entry.track.id);
      if (!mounted) return;
      _toast('已清除《${entry.track.name}》的本地音频，下次同步会重新下载');
      await _load();
    } catch (_) {
      if (mounted) _toast('清除失败');
    } finally {
      if (mounted) setState(() => _busy.remove(entry.track.id));
    }
  }

  /// 删除一条导入音频（顺带清掉指向它的背景音乐设置）。
  Future<void> _deleteTrack(String id) async {
    await ref.read(audioLibraryControllerProvider.notifier).deleteTrack(id);
  }

  Future<void> _clearAll() async {
    if (_files.isEmpty || _clearingAll) return;
    final count = _files.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除全部本地音频'),
        content: Text(
          '将删除 $count 个本地音频文件。\n'
          '云端音频清单与文件都保留，下次同步会重新下载。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('全部清除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _clearingAll = true);
    final controller = ref.read(audioLibraryControllerProvider.notifier);
    var cleared = 0;
    for (final entry in [..._files]) {
      try {
        await controller.deleteTrack(entry.track.id);
        cleared++;
      } catch (_) {
        // 单个失败不影响其余
      }
    }
    if (!mounted) return;
    setState(() => _clearingAll = false);
    _toast('已清除 $cleared 个本地音频，下次同步会重新下载');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final totalBytes = _files.fold(0, (sum, e) => sum + e.bytes);

    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                      Icon(Icons.music_note_outlined, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '本地音频缓存',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${_files.length} 个 · ${formatBytes(totalBytes)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '只删本地音频文件；云端音频清单与文件保留，'
                    '下次同步会自动重新下载。内置曲目在安装包里，不占本地缓存。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.5,
                    ),
                  ),
                  if (_files.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        key: const ValueKey('audio-clear-all'),
                        onPressed: _clearingAll ? null : _clearAll,
                        icon: _clearingAll
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.delete_sweep_outlined),
                        label: Text(_clearingAll ? '正在清除…' : '清除全部音频'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_files.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 48),
              child: Column(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 42,
                    color: muted.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '没有本地音频文件',
                    style: TextStyle(color: muted, fontSize: 14),
                  ),
                ],
              ),
            )
          else
            for (final entry in _files)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    leading: Icon(
                      Icons.music_note,
                      color: scheme.primary,
                    ),
                    title: Text(entry.track.name),
                    subtitle: Text(
                      formatBytes(entry.bytes),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    trailing: _busy.contains(entry.track.id)
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            tooltip: '清除这个音频',
                            onPressed: () => _clearOne(entry),
                            icon: const Icon(Icons.delete_outline),
                          ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
