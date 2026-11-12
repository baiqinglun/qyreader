/// 字体缓存视图：列出本机已下载的自定义字体文件，可逐本或一键清除。
///
/// 只删本地字体文件与本机 manifest 条目；云端字体清单还在，下次同步会把
/// 它们重新下载回来（语义与书籍缓存一致）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../reader/fonts/reader_fonts.dart';

/// 一个本机字体文件。
class _FontFile {
  const _FontFile(this.font, this.bytes);

  final ReaderFont font;
  final int bytes;
}

/// 字体缓存视图。
class FontCacheView extends ConsumerStatefulWidget {
  /// 构造。
  const FontCacheView({super.key});

  @override
  ConsumerState<FontCacheView> createState() => _FontCacheViewState();
}

class _FontCacheViewState extends ConsumerState<FontCacheView> {
  bool _loading = true;
  bool _clearingAll = false;
  List<_FontFile> _fonts = const [];
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    var list = <_FontFile>[];
    try {
      final dir = await getApplicationSupportDirectory();
      final fonts = ref.read(readerFontsControllerProvider);
      for (final font in fonts) {
        final file = File(p.join(dir.path, 'fonts', font.fileName));
        if (!file.existsSync()) continue;
        var size = 0;
        try {
          size = file.lengthSync();
        } catch (_) {
          // 读不到大小不影响列表
        }
        list.add(_FontFile(font, size));
      }
      list.sort((a, b) => a.font.name.compareTo(b.font.name));
    } catch (_) {
      list = <_FontFile>[];
    }
    if (!mounted) return;
    setState(() {
      _fonts = list;
      _loading = false;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clearOne(_FontFile entry) async {
    if (_busy.contains(entry.font.id) || _clearingAll) return;
    setState(() => _busy.add(entry.font.id));
    try {
      await ref
          .read(readerFontsControllerProvider.notifier)
          .deleteFont(entry.font.id);
      if (!mounted) return;
      _toast('已清除《${entry.font.name}》的本地字体文件，下次同步会重新下载');
      await _load();
    } catch (_) {
      if (mounted) _toast('清除失败');
    } finally {
      if (mounted) setState(() => _busy.remove(entry.font.id));
    }
  }

  Future<void> _clearAll() async {
    if (_fonts.isEmpty || _clearingAll) return;
    final count = _fonts.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除全部本地字体'),
        content: Text(
          '将删除 $count 个本地字体文件。\n'
          '云端字体清单与文件都保留，下次同步会重新下载。',
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
    final controller = ref.read(readerFontsControllerProvider.notifier);
    var cleared = 0;
    for (final entry in [..._fonts]) {
      try {
        await controller.deleteFont(entry.font.id);
        cleared++;
      } catch (_) {
        // 单个失败不影响其余
      }
    }
    if (!mounted) return;
    setState(() => _clearingAll = false);
    _toast('已清除 $cleared 个本地字体，下次同步会重新下载');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final totalBytes = _fonts.fold(0, (sum, e) => sum + e.bytes);

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
                      Icon(Icons.font_download_outlined, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '本地字体缓存',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${_fonts.length} 个 · ${formatBytes(totalBytes)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '只删本地字体文件；云端字体清单与文件保留，'
                    '下次同步会自动重新下载。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.5,
                    ),
                  ),
                  if (_fonts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        key: const ValueKey('font-clear-all'),
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
                        label: Text(_clearingAll ? '正在清除…' : '清除全部字体'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_fonts.isEmpty)
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
                    '没有本地字体文件',
                    style: TextStyle(color: muted, fontSize: 14),
                  ),
                ],
              ),
            )
          else
            for (final entry in _fonts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    leading: Icon(Icons.text_fields, color: scheme.primary),
                    title: Text(entry.font.name),
                    subtitle: Text(
                      formatBytes(entry.bytes),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    trailing: _busy.contains(entry.font.id)
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            tooltip: '清除这个字体',
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

/// 字节数转可读文本（缓存页共用）。
String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}
