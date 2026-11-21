/// 分类管理页：层级分类（`父/子` 路径）+ 搜索 + 新建 + 收起/展开 +
/// 每行计数与操作菜单（重命名 / 添加子分类 / 删除）。
///
/// 分类不是独立实体：书的 `category` 字段支持 `小说/科幻` 这样的路径，
/// 管理页把它解析成树。改动逐本走 `setPersonalization`（含同步日志），
/// 与在书籍详情里手动改分类等价。空分类（0 本书）持久化在 prefs
/// `categories.extra`，与书的分类合并展示。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import '../../app/theme/motion.dart';
import '../../domain/entities/book.dart' show ShelfItem;
import '../shelf/shelf_controller.dart';
import 'category_tree.dart';

/// 分类管理页。
class CategoryManagerPage extends ConsumerStatefulWidget {
  /// 构造。
  const CategoryManagerPage({super.key});

  @override
  ConsumerState<CategoryManagerPage> createState() =>
      _CategoryManagerPageState();
}

class _CategoryManagerPageState extends ConsumerState<CategoryManagerPage> {
  List<String> _extraPaths = const <String>[];
  Set<String> _collapsed = <String>{};
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadExtra());
  }

  Future<void> _loadExtra() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _extraPaths = prefs.getStringList(kExtraCategoriesKey) ?? const [];
    });
  }

  Future<void> _saveExtra(List<String> paths) async {
    _extraPaths = paths;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(kExtraCategoriesKey, paths);
    if (mounted) setState(() {});
  }

  Future<void> _renamePath(String from, String to) async {
    final repo = await ref.read(bookRepositoryProvider.future);
    final items =
        ref.read(shelfItemsProvider).valueOrNull ?? const <ShelfItem>[];
    for (final item in items) {
      final c = item.book.category?.trim() ?? '';
      if (!categoryUnderPath(c, from)) continue;
      await repo.setPersonalization(
        item.book.id,
        category: renameCategoryPath(c, from, to),
      );
    }
    await _saveExtra([
      for (final e in _extraPaths)
        if (categoryUnderPath(e, from)) renameCategoryPath(e, from, to) else e,
    ]);
    // 折叠状态里的旧路径也一并迁移
    _collapsed = {
      for (final c in _collapsed)
        if (categoryUnderPath(c, from)) renameCategoryPath(c, from, to) else c,
    };
  }

  Future<void> _deletePath(String path) async {
    final repo = await ref.read(bookRepositoryProvider.future);
    final items =
        ref.read(shelfItemsProvider).valueOrNull ?? const <ShelfItem>[];
    for (final item in items) {
      final c = item.book.category?.trim() ?? '';
      if (!categoryUnderPath(c, path)) continue;
      await repo.setPersonalization(item.book.id, category: '');
    }
    await _saveExtra([
      for (final e in _extraPaths)
        if (!categoryUnderPath(e, path)) e,
    ]);
    _collapsed = _collapsed.where((c) => !categoryUnderPath(c, path)).toSet();
  }

  Future<void> _addCategory(String path) async {
    if (_extraPaths.contains(path)) return;
    await _saveExtra([..._extraPaths, path]);
  }

  /// 顶栏「＋」：新建顶层分类。
  Future<void> _addFromPrompt(BuildContext context) async {
    final next = await _promptName(context, title: '新建分类', label: '分类名');
    if (next == null || next.isEmpty || !context.mounted) return;
    await _addCategory(next);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已创建「$next」')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final items =
        ref.watch(shelfItemsProvider).valueOrNull ?? const <ShelfItem>[];

    final roots = buildCategoryTree(items: items, extraPaths: _extraPaths);
    final visible = flattenCategoryTree(
      roots,
      _collapsed,
      _searching ? _query : null,
    );
    final totalNodes = _countNodes(roots);
    final allExpandablePaths = _allExpandablePaths(roots);
    final allCollapsed =
        allExpandablePaths.isEmpty || allExpandablePaths.every(_collapsed.contains);

    return Scaffold(
      appBar: AppBar(
        title: const Text('分类管理'),
        actions: [
          IconButton(
            key: const ValueKey('category-search-toggle'),
            tooltip: '搜索分类',
            onPressed: () => setState(() {
              _searching = !_searching;
              _query = '';
            }),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            key: const ValueKey('category-add'),
            tooltip: '新建分类',
            onPressed: () => unawaited(_addFromPrompt(context)),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TextField(
                key: const ValueKey('category-search-field'),
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索分类名',
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
            child: Row(
              children: [
                Text(
                  '$totalNodes 个分类',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
                const Spacer(),
                if (allExpandablePaths.isNotEmpty)
                  TextButton(
                    key: const ValueKey('category-collapse-all'),
                    onPressed: () => setState(() {
                      _collapsed = allCollapsed
                          ? <String>{}
                          : {...allExpandablePaths};
                    }),
                    child: Text(allCollapsed ? '展开全部' : '收起全部'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
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
                          Text(
                            _query.isEmpty ? '还没有分类' : '没有匹配的分类',
                            style: TextStyle(color: muted, fontSize: 14),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _query.isEmpty
                                ? '右上角「＋」新建分类，可在名称里用「/」建立层级'
                                : '换个关键词试试',
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
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 32),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final node = visible[index];
                      return _CategoryRow(
                        node: node,
                        theme: theme,
                        expanded: _collapsed.contains(node.path),
                        onToggle: node.hasChildren
                            ? () => setState(() {
                                  _collapsed = _collapsed.contains(node.path)
                                      ? (_collapsed..remove(node.path))
                                      : {..._collapsed, node.path};
                                })
                            : null,
                        onMenu: () => unawaited(_showActions(context, node)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  int _countNodes(List<CategoryNode> nodes) {
    var n = 0;
    for (final node in nodes) {
      n += 1 + _countNodes(node.children);
    }
    return n;
  }

  Set<String> _allExpandablePaths(List<CategoryNode> nodes) {
    final out = <String>{};
    for (final node in nodes) {
      if (node.hasChildren) {
        out.add(node.path);
        out.addAll(_allExpandablePaths(node.children));
      }
    }
    return out;
  }

  Future<void> _showActions(BuildContext context, CategoryNode node) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名'),
              subtitle: Text(node.path),
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('添加子分类'),
              onTap: () => Navigator.of(ctx).pop('addsub'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除分类'),
              subtitle: Text(
                node.totalCount > 0
                    ? '将清空 ${node.totalCount} 本书的该分类（含子分类），书籍本身不删除'
                    : '该分类下没有书',
              ),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'rename') {
      final next = await _promptName(
        context,
        title: '重命名分类',
        label: '分类名',
        initial: node.name,
      );
      if (next == null || next.isEmpty || next == node.name) return;
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        await _renamePath(node.path, next);
        messenger.showSnackBar(SnackBar(content: Text('已重命名为「$next」')));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('重命名失败：$e')));
      }
    } else if (action == 'addsub') {
      final next = await _promptName(
        context,
        title: '添加子分类',
        label: '子分类名',
      );
      if (next == null || next.isEmpty || !context.mounted) return;
      final path = '${node.path}/$next';
      await _addCategory(path);
      if (context.mounted) {
        setState(() => _collapsed.remove(node.path));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已创建「$path」')));
      }
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        animationStyle: kSmoothSheetAnimation,
        builder: (ctx) => AlertDialog(
          title: const Text('删除分类'),
          content: Text(
            node.hasChildren
                ? '将删除「${node.path}」及其所有子分类，清空这些书的分类，书籍本身不删除。'
                : '将清空 ${node.totalCount} 本书的「${node.name}」分类，书籍本身不删除。',
          ),
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
        await _deletePath(node.path);
        messenger.showSnackBar(SnackBar(content: Text('已删除「${node.path}」')));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('删除失败：$e')));
      }
    }
  }

  Future<String?> _promptName(
    BuildContext context, {
    required String title,
    required String label,
    String? initial,
  }) {
    final controller = TextEditingController(text: initial ?? '');
    final next = showDialog<String>(
      context: context,
      animationStyle: kSmoothSheetAnimation,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: InputDecoration(
            labelText: label,
            helperText: '可用「/」建立层级，如：小说/科幻',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('category-name-confirm'),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return next;
  }
}

/// 一行分类：缩进 + 折叠箭头 + 文件夹 + 名称 + 计数 + 菜单。
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.node,
    required this.theme,
    required this.expanded,
    required this.onToggle,
    required this.onMenu,
  });

  final CategoryNode node;
  final ThemeData theme;
  final bool expanded;
  final VoidCallback? onToggle;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final fg = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    return ListTile(
      key: ValueKey('category-row-${node.path}'),
      contentPadding: EdgeInsets.only(left: 8.0 + node.depth * 28, right: 8),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (node.hasChildren)
            IconButton(
              key: ValueKey('category-toggle-${node.path}'),
              visualDensity: VisualDensity.compact,
              onPressed: onToggle,
              icon: Icon(
                expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                color: muted,
              ),
            )
          else
            const SizedBox(width: 24),
          Icon(
            node.hasChildren && !expanded
                ? Icons.folder_outlined
                : Icons.folder_open_outlined,
            color: scheme.primary,
          ),
        ],
      ),
      title: Text(
        node.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: fg,
          fontSize: 16,
          fontWeight: node.depth == 0 ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${node.totalCount}', style: TextStyle(color: muted, fontSize: 14)),
          const SizedBox(width: 4),
          IconButton(
            key: ValueKey('category-menu-${node.path}'),
            tooltip: '操作',
            onPressed: onMenu,
            icon: Icon(Icons.more_horiz, color: muted),
          ),
        ],
      ),
      onTap: onToggle ?? onMenu,
    );
  }
}
