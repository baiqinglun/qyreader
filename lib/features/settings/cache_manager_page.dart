/// 本地书籍缓存视图：列出本地有书源文件的书籍，可逐本或全部清除。
///
/// 只删本地书源文件：云端书籍/封面、本机封面、数据库里的进度与标注都保留；
/// 下次打开这本书会从同步库自动拉回。没有云端备份的书不允许清除（避免丢失）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/motion.dart';
import '../../domain/entities/book.dart';

/// 一本有本地缓存的书籍。
class _LocalBook {
  const _LocalBook(this.item, this.bytes);

  final ShelfItem item;
  final int bytes;
}

/// 本地书籍缓存视图（缓存中心「书籍」页签共用）。
class BookCacheView extends ConsumerStatefulWidget {
  const BookCacheView({super.key});

  @override
  ConsumerState<BookCacheView> createState() => _BookCacheViewState();
}

class _BookCacheViewState extends ConsumerState<BookCacheView> {
  List<_LocalBook> _books = const [];
  int _totalBytes = 0;
  bool _loading = true;
  bool _clearingAll = false;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    var list = <_LocalBook>[];
    try {
      final repo = await ref.read(bookRepositoryProvider.future);
      final shelf = await repo.watchShelf().first;
      for (final item in shelf) {
        // 缓存页只在本地做 stat：同步 API 足够快，也避免大量异步 IO 卡进度。
        final file = File(item.book.filePath);
        if (!file.existsSync()) continue;
        var size = 0;
        try {
          size = file.lengthSync();
        } catch (_) {
          // 单个文件读不到大小不影响列表
        }
        list.add(_LocalBook(item, size));
      }
      list.sort((a, b) => a.item.book.title.compareTo(b.item.book.title));
    } catch (_) {
      list = <_LocalBook>[];
    }
    if (!mounted) return;
    setState(() {
      _books = list;
      _totalBytes = list.fold(0, (sum, entry) => sum + entry.bytes);
      _loading = false;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clearOne(_LocalBook entry) async {
    final id = entry.item.book.id;
    if (_busy.contains(id) || _clearingAll) return;
    setState(() => _busy.add(id));
    try {
      final sync = await ref.read(syncRepositoryProvider.future);
      final cleared = await sync.clearLocalBookCache(id);
      if (!mounted) return;
      _toast(
        cleared
            ? '已清除《${entry.item.book.title}》的本地文件，封面与云端保留'
            : '同步库里没有这本书的备份，未清除',
      );
      if (cleared) await _load();
    } catch (_) {
      if (mounted) _toast('清除失败：请先在设置里配置同步存储');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _clearAll() async {
    if (_books.isEmpty || _clearingAll) return;
    final total = _books.length;
    final ok = await showDialog<bool>(
      context: context,
      animationStyle: kSmoothSheetAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('清除全部本地书籍'),
        content: Text(
          '将清除 $total 本书的本地书源文件。\n'
          '云端书籍、封面、阅读进度和笔记都会保留，下次打开时自动拉回。',
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
    var cleared = 0;
    var skipped = 0;
    try {
      final sync = await ref.read(syncRepositoryProvider.future);
      for (final entry in [..._books]) {
        try {
          if (await sync.clearLocalBookCache(entry.item.book.id)) {
            cleared++;
          } else {
            skipped++;
          }
        } catch (_) {
          // 单本失败不影响其余书
          skipped++;
        }
      }
    } catch (_) {
      skipped = total;
    }
    if (!mounted) return;
    setState(() => _clearingAll = false);
    _toast(
      skipped == 0
          ? '已清除 $cleared 本书的本地文件，封面与云端保留'
          : '已清除 $cleared 本；$skipped 本没有云端备份，未清除',
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;

    return _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _SummaryCard(
                  count: _books.length,
                  bytes: _totalBytes,
                  clearing: _clearingAll,
                  onClearAll: _books.isEmpty ? null : _clearAll,
                ),
                const SizedBox(height: 14),
                if (_books.isEmpty)
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
                          '没有本地缓存的书籍',
                          style: TextStyle(color: muted, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '书源文件都已清理，阅读时会自动从云端拉回',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: muted.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ..._books.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _BookCacheTile(
                        entry: entry,
                        busy: _busy.contains(entry.item.book.id),
                        onClear: () => _clearOne(entry),
                      ),
                    ),
                  ),
              ],
            ),
          );
  }
}

/// 顶部汇总卡：多少本 / 多大 / 全部清除。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.count,
    required this.bytes,
    required this.clearing,
    required this.onClearAll,
  });

  final int count;
  final int bytes;
  final bool clearing;
  final VoidCallback? onClearAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cleaning_services_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '本地书籍缓存',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$count 本 · ${_formatBytes(bytes)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '只删除本地书源文件；云端书籍、封面、阅读进度与笔记都保留。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '下次打开这本书会自动从云端拉回文件。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted.withValues(alpha: 0.75),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  key: const ValueKey('cache-clear-all'),
                  onPressed: clearing ? null : onClearAll,
                  icon: clearing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: Text(clearing ? '清除中…' : '全部清除'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一行：封面缩略图 + 书名 + 大小 + 清除按钮。
class _BookCacheTile extends StatelessWidget {
  const _BookCacheTile({
    required this.entry,
    required this.busy,
    required this.onClear,
  });

  final _LocalBook entry;
  final bool busy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = entry.item.book;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
        leading: _CoverThumb(path: book.coverPath),
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${_formatBytes(entry.bytes)} · 封面保留',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        trailing: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                key: ValueKey('cache-clear-${book.id}'),
                onPressed: onClear,
                child: const Text('清除'),
              ),
      ),
    );
  }
}

/// 封面缩略图（显示用；清缓存不会删封面文件）。
class _CoverThumb extends StatelessWidget {
  const _CoverThumb({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.menu_book_outlined, size: 18, color: scheme.outline),
    );
    final p = path;
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        width: 40,
        height: 56,
        child: p == null || p.isEmpty
            ? placeholder
            : Image.file(
                File(p),
                fit: BoxFit.cover,
                cacheWidth: 120,
                errorBuilder: (_, __, ___) => placeholder,
              ),
      ),
    );
  }
}

/// 字节数转人类可读。
String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
