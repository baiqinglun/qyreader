/// 书架分类卡长按管理：修改名称 / 移动到。
///
/// 分类不是独立实体：改动逐本走 `setPersonalization`（含同步日志），
/// 空分类（prefs `categories.extra`）同步迁移，与分类管理页同一套语义。
/// 「移动到」= 把该分类及其子分类整体挪到另一个分类下（或移到顶层）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/providers.dart';
import '../../../app/theme/motion.dart';
import '../../../domain/entities/book.dart' show ShelfItem;
import '../../settings/category_tree.dart';
import '../shelf_controller.dart';

/// 长按分类卡：弹操作菜单（修改名称 / 移动到）并执行所选动作。
Future<void> manageCategory(
  BuildContext context,
  WidgetRef ref, {
  required String category,
}) async {
  final parent = parentCategoryOf(category);
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('category-action-add-child'),
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('新建子分类'),
            onTap: () => Navigator.of(ctx).pop('add'),
          ),
          ListTile(
            key: const ValueKey('category-action-rename'),
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('修改名称'),
            subtitle: Text(category),
            onTap: () => Navigator.of(ctx).pop('rename'),
          ),
          ListTile(
            key: const ValueKey('category-action-move'),
            leading: const Icon(Icons.drive_file_move_outline),
            title: const Text('移动到'),
            subtitle: Text(parent.isEmpty ? '当前是顶层分类' : '当前在「$parent」下'),
            onTap: () => Navigator.of(ctx).pop('move'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (action == 'add') {
    final name = await _promptName(
      context,
      title: '新建子分类',
      initial: '',
      helper: '请输入分类名称',
    );
    if (name == null || name.trim().isEmpty || name.contains('/')) return;
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList(kExtraCategoriesKey) ?? <String>[];
    final path = '$category/${name.trim()}';
    if (!paths.contains(path)) {
      await prefs.setStringList(kExtraCategoriesKey, [...paths, path]);
    }
  } else if (action == 'rename') {
    await _renameFlow(context, ref, category);
  } else if (action == 'move') {
    await _moveFlow(context, ref, category);
  }
}

Future<void> _renameFlow(
  BuildContext context,
  WidgetRef ref,
  String category,
) async {
  final segments = category.split('/');
  final next = await _promptName(
    context,
    initial: segments.last,
    helper: parentCategoryOf(category).isEmpty
        ? '只能改这一级的名称'
        : '只改这一级名称，「${parentCategoryOf(category)}」保持不变',
  );
  if (next == null || next.isEmpty || !context.mounted) return;
  final target = renameCategorySegment(category, next);
  if (target == category) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final paths = await _allCategoryPaths(ref);
    final conflict = categoryPathConflict(paths, category, target);
    if (conflict != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('已有同名分类「$conflict」，换个名字试试')),
      );
      return;
    }
    final changed = await _applyCategoryPaths(ref, category, target);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          changed > 0 ? '已重命名为「$target」，更新 $changed 本书' : '已重命名为「$target」',
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('重命名失败：$e')));
  }
}

Future<void> _moveFlow(
  BuildContext context,
  WidgetRef ref,
  String category,
) async {
  final paths = await _allCategoryPaths(ref);
  // 可选目标：除自身子树外的所有分类（顶层入口单独给）。
  final candidates =
      paths.where((p) => !categoryUnderPath(p, category)).toList()..sort();
  final currentParent = parentCategoryOf(category);
  if (!context.mounted) return;
  final parent = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              '移动「${category.split('/').last}」到',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          if (currentParent.isNotEmpty)
            ListTile(
              key: const ValueKey('category-move-root'),
              leading: const Icon(Icons.reply_outlined),
              title: const Text('顶层分类'),
              subtitle: Text('移出「$currentParent」'),
              onTap: () => Navigator.of(ctx).pop(''),
            ),
          for (final p in candidates)
            ListTile(
              key: ValueKey('category-move-$p'),
              leading: const Icon(Icons.folder_outlined),
              title: Text(p),
              onTap: () => Navigator.of(ctx).pop(p),
            ),
        ],
      ),
    ),
  );
  if (parent == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (parent == currentParent) {
    messenger.showSnackBar(SnackBar(content: Text('「$category」已经在这个分类下了')));
    return;
  }
  try {
    final target = moveCategoryUnder(category, parent);
    final conflict = categoryPathConflict(paths, category, target);
    if (conflict != null) {
      messenger.showSnackBar(SnackBar(content: Text('「$conflict」已存在，无法移动过去')));
      return;
    }
    final changed = await _applyCategoryPaths(ref, category, target);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          parent.isEmpty
              ? '已把「$category」移到顶层${changed > 0 ? '，更新 $changed 本书' : ''}'
              : '已把「$category」移到「$parent」下${changed > 0 ? '，更新 $changed 本书' : ''}',
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('移动失败：$e')));
  }
}

/// 全部分类路径：书的 + prefs 里的空分类。
Future<Set<String>> _allCategoryPaths(WidgetRef ref) async {
  final items = ref.read(shelfItemsProvider).valueOrNull ?? const <ShelfItem>[];
  final prefs = await SharedPreferences.getInstance();
  final extra = prefs.getStringList(kExtraCategoriesKey) ?? const <String>[];
  return {
    for (final item in items)
      if ((item.book.category ?? '').trim().isNotEmpty)
        item.book.category!.trim(),
    ...extra,
  };
}

/// 把 [from] 子树整体改成 [to] 前缀：逐本写书籍分类 + 迁移空分类。
/// 返回更新的书籍本数。
Future<int> _applyCategoryPaths(WidgetRef ref, String from, String to) async {
  final repo = await ref.read(bookRepositoryProvider.future);
  final items = ref.read(shelfItemsProvider).valueOrNull ?? const <ShelfItem>[];
  var changed = 0;
  for (final item in items) {
    final c = item.book.category?.trim() ?? '';
    if (!categoryUnderPath(c, from)) continue;
    await repo.setPersonalization(
      item.book.id,
      category: renameCategoryPath(c, from, to),
    );
    changed++;
  }
  final prefs = await SharedPreferences.getInstance();
  final extra = prefs.getStringList(kExtraCategoriesKey) ?? const <String>[];
  if (extra.any((e) => categoryUnderPath(e, from))) {
    await prefs.setStringList(kExtraCategoriesKey, [
      for (final e in extra)
        if (categoryUnderPath(e, from)) renameCategoryPath(e, from, to) else e,
    ]);
  }
  return changed;
}

Future<String?> _promptName(
  BuildContext context, {
  required String initial,
  required String helper,
  String title = '修改分类名称',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    animationStyle: kSmoothSheetAnimation,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const ValueKey('category-rename-field'),
        controller: controller,
        autofocus: true,
        maxLength: 30,
        decoration: InputDecoration(labelText: '分类名', helperText: helper),
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
}
