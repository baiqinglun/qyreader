/// 阅读背景管理视图：背景库（`QYReader/backgrounds/`）的图片列表，可上传、
/// 逐张或一键清除。
///
/// 主题是主题、背景是背景：上传只会把图片放进背景库，**不会新建或修改主题**；
/// 主题在排版面板里长按「更换背景」来选用某张图，一个背景可以被多个主题共用。
/// 清除只删本地图片并把引用它的主题 `backgroundImage` 清空（变回纯色），主题名、
/// 字号、边距等排版设置都保留。背景随同步上传到云端（`BackgroundSync`），
/// 清掉后下次同步能拉回来。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/theme/motion.dart';
import '../reader/reader_themes.dart';

/// 一张本地背景图。
class _Background {
  const _Background(this.path, this.bytes, this.themes);

  final String path;
  final int bytes;

  /// 引用这张图的自定义主题 id。
  final List<String> themes;
}

/// 背景图同步支持的扩展名。
const Set<String> kBackgroundImageExtensions = {'jpg', 'jpeg', 'png', 'webp'};

String formatCacheBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

/// 读出背景目录里的图片文件（按文件名排序）。
Future<List<File>> listBackgroundFiles() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'QYReader', 'backgrounds'));
  if (!await dir.exists()) return const <File>[];
  final out = <File>[];
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    final ext = p.extension(entity.path).replaceFirst('.', '').toLowerCase();
    if (!kBackgroundImageExtensions.contains(ext)) continue;
    out.add(entity);
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

/// 背景缓存/管理视图。
class BackgroundCacheView extends ConsumerStatefulWidget {
  /// 构造。
  const BackgroundCacheView({super.key});

  @override
  ConsumerState<BackgroundCacheView> createState() =>
      _BackgroundCacheViewState();
}

class _BackgroundCacheViewState extends ConsumerState<BackgroundCacheView> {
  bool _clearingAll = false;
  bool _uploading = false;
  bool _loading = true;
  List<_Background> _entries = const [];
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    var entries = <_Background>[];
    try {
      final themes = ref.read(readerThemesControllerProvider).custom;
      final usage = <String, List<String>>{};
      for (final theme in themes) {
        final path = theme.backgroundImage;
        if (path.isEmpty) continue;
        usage.putIfAbsent(path, () => <String>[]).add(theme.id);
      }
      final files = await listBackgroundFiles();
      for (final file in files) {
        var size = 0;
        try {
          size = await file.length();
        } catch (_) {
          // 读不到大小不影响列表
        }
        entries.add(_Background(file.path, size, usage[file.path] ?? const []));
      }
    } catch (_) {
      entries = <_Background>[];
    }
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 上传一张背景：复制进 `QYReader/backgrounds/`，再以当前主题为底
  /// 新建一个挂该背景的自定义主题并立即应用。
  Future<void> _upload() async {
    if (_uploading) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    final source = picked?.files.single.path;
    if (source == null || source.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    String? dest;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'QYReader', 'backgrounds'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext = p.extension(source).isEmpty
          ? '.jpg'
          : p.extension(source).toLowerCase();
      dest = p.join(
        dir.path,
        'bg-${DateTime.now().microsecondsSinceEpoch}$ext',
      );
      await File(source).copy(dest);
      if (!mounted) return;
      // 背景只进背景库，不会自动变成主题：主题是主题，背景是背景，
      // 一个背景可以被多个主题选用（在排版面板长按主题切换）。
      _toast('已上传到背景库，可在主题里长按切换背景');
    } catch (e) {
      if (dest != null) File(dest).delete().ignore();
      if (mounted) _toast('上传失败：$e');
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
        await _load();
      }
    }
  }

  /// 删除图片，并把引用它的主题背景清空（排版设置保留）。
  Future<void> _clearBackgrounds(List<_Background> entries) async {
    final controller = ref.read(readerThemesControllerProvider.notifier);
    final themes = ref.read(readerThemesControllerProvider).custom;
    for (final entry in entries) {
      try {
        final file = File(entry.path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // 文件被占用：仍把主题里的引用清掉
      }
      for (final theme in themes) {
        if (theme.backgroundImage != entry.path) continue;
        try {
          await controller.save(
            theme.copyWith(backgroundImage: ''),
            applyNow: true,
          );
        } catch (_) {
          // 单个主题保存失败不影响其他
        }
      }
    }
  }

  Future<void> _clearOne(_Background entry) async {
    if (_busy.contains(entry.path) || _clearingAll) return;
    setState(() => _busy.add(entry.path));
    try {
      await _clearBackgrounds([entry]);
      if (mounted) _toast('已清除本地背景图，主题改回纯色背景');
      await _load();
    } finally {
      if (mounted) setState(() => _busy.remove(entry.path));
    }
  }

  Future<void> _clearAll(List<_Background> entries) async {
    if (entries.isEmpty || _clearingAll) return;
    final ok = await showDialog<bool>(
      context: context,
      animationStyle: kSmoothSheetAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('清除全部本地背景'),
        content: Text(
          '将删除 ${entries.length} 张本地背景图，'
          '用到它们的自定义主题会变回纯色背景。\n'
          '主题名、字号、行距、边距等排版设置都保留；'
          '云端背景保留，下次同步会重新下载。',
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
    try {
      await _clearBackgrounds(entries);
      if (mounted) _toast('已清除 ${entries.length} 张本地背景图');
      await _load();
    } finally {
      if (mounted) setState(() => _clearingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final entries = _entries;
    final totalBytes = entries.fold(0, (sum, e) => sum + e.bytes);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
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
                      Icon(Icons.image_outlined, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '背景库',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${entries.length} 张 · ${formatCacheBytes(totalBytes)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '「上传背景」会以当前阅读主题为底新建一个主题并立即应用；'
                    '背景随同步上传云端，清除本地后下次同步会重新下载。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          key: const ValueKey('background-upload'),
                          onPressed: _uploading ? null : _upload,
                          icon: _uploading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.upload_outlined),
                          label: Text(_uploading ? '正在上传…' : '上传背景'),
                        ),
                      ),
                      if (entries.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            key: const ValueKey('background-clear-all'),
                            onPressed: _clearingAll
                                ? null
                                : () => _clearAll(entries),
                            icon: _clearingAll
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.delete_sweep_outlined),
                            label: Text(_clearingAll ? '正在清除…' : '清除全部背景'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (entries.isEmpty)
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
                  Text('没有本地背景图', style: TextStyle(color: muted, fontSize: 14)),
                ],
              ),
            )
          else
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 44,
                        height: 58,
                        child: Image.file(
                          File(entry.path),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: Color(0xFFE0E0E0)),
                        ),
                      ),
                    ),
                    title: Text(
                      p.basename(entry.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      entry.themes.isEmpty
                          ? '${formatCacheBytes(entry.bytes)} · 未使用'
                          : '${formatCacheBytes(entry.bytes)} · '
                                '${entry.themes.length} 个主题使用',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    trailing: _busy.contains(entry.path)
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            tooltip: '清除这张背景',
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
