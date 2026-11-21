/// 设置 → 作者管理。
///
/// 书架的书按作者归组：未知作者排最前（点开可补全作者信息），
/// 其余按书数降序；点作者卡查看名下全部书籍，菜单可批量重命名作者。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../domain/entities/book.dart';
import '../home/widgets/cover_thumb.dart';
import '../shelf/shelf_controller.dart';
import 'author_groups.dart';

/// 作者管理页。
class AuthorsPage extends ConsumerStatefulWidget {
  /// 构造。
  const AuthorsPage({super.key});

  @override
  ConsumerState<AuthorsPage> createState() => _AuthorsPageState();
}

class _AuthorsPageState extends ConsumerState<AuthorsPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = ref.watch(shelfItemsProvider).valueOrNull ??
        const <ShelfItem>[];
    final groups = filterAuthorGroups(groupBooksByAuthor(items), _query);

    return Scaffold(
      appBar: AppBar(title: const Text('作者管理')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              key: const ValueKey('authors-search'),
              decoration: InputDecoration(
                hintText:
                    groups.isEmpty ? '还没有书籍' : '搜索 ${groups.length} 位作者',
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _query = ''),
                      ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: groups.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _query.isEmpty
                            ? '书架上还没有书籍\n导入书籍后会自动按作者归组'
                            : '没有匹配的作者',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: groups.length,
                    itemBuilder: (context, index) => _AuthorCard(
                      group: groups[index],
                      onRename: () => _renameGroup(groups[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 批量重命名：把该组所有书籍的作者改成同一个名字（清空 = 未知作者）。
  Future<void> _renameGroup(AuthorGroup group) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => _AuthorRenameDialog(initial: group.key),
    );
    if (newName == null || !mounted) return;
    final repo = await ref.read(bookRepositoryProvider.future);
    for (final item in group.books) {
      await repo.updateBookMeta(item.book.id, author: newName);
    }
    if (!mounted) return;
    final count = group.books.length;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          newName.isEmpty ? '已清空 $count 本书籍的作者' : '已把 $count 本书籍的作者改为「$newName」',
        ),
      ));
  }
}

/// 一位作者的卡片：左侧 2×2 封面预览，右侧作者名 + 本数，菜单可重命名。
class _AuthorCard extends StatelessWidget {
  const _AuthorCard({required this.group, required this.onRename});

  final AuthorGroup group;

  /// 点菜单「重命名作者」时的回调。
  final Future<void> Function() onRename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(kAuthorBooksPath, extra: group.key),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _AuthorCoverGrid(books: group.books),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: _AuthorCoverGrid.height,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (group.isUnknown) ...[
                            const SizedBox(height: 4),
                            Text(
                              kUnknownAuthorHint,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '${group.books.length} 本',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!group.isUnknown)
                PopupMenuButton<String>(
                  key: ValueKey('author-menu-${group.key}'),
                  tooltip: '作者操作',
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'rename') unawaited(onRename());
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'rename',
                      child: ListTile(
                        leading: Icon(Icons.drive_file_rename_outline),
                        title: Text('重命名作者'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

}

/// 2×2 封面预览：摆该作者前 4 本书的封面，空位显示灰色占位。
class _AuthorCoverGrid extends StatelessWidget {
  const _AuthorCoverGrid({required this.books});

  /// 该作者名下的书（最多取前 4 本的封面）。
  final List<ShelfItem> books;

  /// 单个封面宽。
  static const double cellW = 42;

  /// 单个封面高。
  static const double cellH = 56;

  /// 封面间距 / 网格内边距。
  static const double gap = 3;

  /// 预览框边框宽（1px 描边，占位要算进总尺寸）。
  static const double border = 1;

  /// 整个预览网格的宽。
  static double get width => gap * 3 + cellW * 2 + border * 2;

  /// 整个预览网格的高。
  static double get height => gap * 3 + cellH * 2 + border * 2;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget slot(int index) {
      final book = index < books.length ? books[index].book : null;
      if (book == null) {
        return Container(
          width: cellW,
          height: cellH,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }
      return CoverThumb(
        path: book.coverPath,
        width: cellW,
        height: cellH,
        radius: 4,
      );
    }

    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(gap),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              slot(0),
              SizedBox(width: gap),
              slot(1),
            ],
          ),
          SizedBox(height: gap),
          Row(
            children: [
              slot(2),
              SizedBox(width: gap),
              slot(3),
            ],
          ),
        ],
      ),
    );
  }
}

/// 批量重命名作者弹窗；返回新作者名（可能为空串 = 清空），取消返回 null。
class _AuthorRenameDialog extends StatefulWidget {
  const _AuthorRenameDialog({required this.initial});

  /// 当前作者名。
  final String initial;

  @override
  State<_AuthorRenameDialog> createState() => _AuthorRenameDialogState();
}

class _AuthorRenameDialogState extends State<_AuthorRenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名作者'),
      content: TextField(
        key: const ValueKey('author-rename-field'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '作者名（清空 = 未知作者）',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('author-rename-save'),
          onPressed: () =>
              Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 某位作者名下的全部书籍。
///
/// [authorKey] 为作者名（trim 后）；空字符串 = 未知作者。
class AuthorBooksPage extends ConsumerWidget {
  /// 构造。
  const AuthorBooksPage({super.key, required this.authorKey});

  /// 作者名；空字符串表示未知作者组。
  final String authorKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = ref.watch(shelfItemsProvider).valueOrNull ??
        const <ShelfItem>[];
    final groups = groupBooksByAuthor(items);
    AuthorGroup? group;
    for (final candidate in groups) {
      if (candidate.key == authorKey) {
        group = candidate;
        break;
      }
    }
    final books = group?.books ?? const <ShelfItem>[];
    final isUnknown = authorKey.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(group?.displayName ?? kUnknownAuthorLabel),
      ),
      body: books.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  '该作者名下暂时没有书籍',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      Text(
                        '共 ${books.length} 本',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isUnknown)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Card(
                      elevation: 0,
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '这些书没有作者信息，点开书籍详情可在「编辑信息」里补全',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final item = books[index];
                      final book = item.book;
                      final percentLabel = item.percent > 0
                          ? ' · 已读 ${(item.percent * 100).toStringAsFixed(0)}%'
                          : '';
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          key: ValueKey('author-book-${book.id}'),
                          leading: CoverThumb(
                            path: book.coverPath,
                            width: 46,
                            height: 64,
                            radius: 6,
                          ),
                          title: Text(
                            book.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${book.readStatus.label}$percentLabel',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12.5,
                            ),
                          ),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: theme.iconTheme.color?.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          onTap: () => context.push(bookDetailPath(book.id)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
