/// 分类管理页：分类来自每本书的「分类」字段，这里可以批量改名 / 删除。
///
/// 分类不是独立实体：改名就是把同一分类下所有书改成新名字，删除就是把
/// 这些书的分类清空。所有改动逐本走 `setPersonalization`（含同步日志），
/// 与在书籍详情里手动改分类等价。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/motion.dart';
import '../../domain/entities/book.dart' show ShelfItem;
import '../shelf/shelf_controller.dart';

/// 分类管理页。
class CategoryManagerPage extends ConsumerWidget {
  /// 构造。
  const CategoryManagerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final items =
        ref.watch(shelfItemsProvider).valueOrNull ?? const <ShelfItem>[];
    final counts = <String, int>{};
    for (final item in items) {
      final category = item.book.category?.trim() ?? '';
      if (category.isEmpty) continue;
      counts[category] = (counts[category] ?? 0) + 1;
    }
    final names = counts.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('分类')),
      body: names.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 44,
                      color: muted.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 12),
                    Text('还没有分类', style: TextStyle(color: muted, fontSize: 14)),
                    const SizedBox(height: 6),
                    Text(
                      '在书籍详情里给书设置「分类」，同一分类会自动归到一起',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: muted.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: names.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final name = names[index];
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    leading: Icon(Icons.folder_outlined, color: scheme.primary),
                    title: Text(name),
                    subtitle: Text(
                      '${counts[name]} 本书',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    trailing: IconButton(
                      tooltip: '改名 / 删除',
                      icon: const Icon(Icons.more_horiz),
                      onPressed: () =>
                          _showActions(context, ref, name, counts[name] ?? 0),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    String name,
    int count,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名分类'),
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除分类'),
              subtitle: const Text('只清空书的分类，不删除书籍'),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'rename') {
      await _rename(context, ref, name, count);
    } else {
      await _delete(context, ref, name, count);
    }
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    String from,
    int count,
  ) async {
    final controller = TextEditingController(text: from);
    final next = await showDialog<String>(
      context: context,
      animationStyle: kSmoothSheetAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名分类'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(labelText: '分类名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('category-rename-confirm'),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (next == null || next.isEmpty || next == from) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(bookRepositoryProvider.future);
      final items =
          ref.read(shelfItemsProvider).valueOrNull ?? const <ShelfItem>[];
      var changed = 0;
      for (final item in items) {
        if ((item.book.category?.trim() ?? '') != from) continue;
        await repo.setPersonalization(item.book.id, category: next);
        changed++;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('已把 $changed 本书的分类改为「$next」')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('重命名失败：$e')));
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    String name,
    int count,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      animationStyle: kSmoothSheetAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('删除分类'),
        content: Text('将清空 $count 本书的「$name」分类，书籍本身不删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除分类'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(bookRepositoryProvider.future);
      final items =
          ref.read(shelfItemsProvider).valueOrNull ?? const <ShelfItem>[];
      var changed = 0;
      for (final item in items) {
        if ((item.book.category?.trim() ?? '') != name) continue;
        await repo.setPersonalization(item.book.id, category: '');
        changed++;
      }
      messenger.showSnackBar(SnackBar(content: Text('已清空 $changed 本书的分类')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }
}
