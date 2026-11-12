/// 书架长按操作菜单：继续阅读 / 编辑信息 / 置顶 / 删除。
///
/// 长按先弹轻量菜单，编辑进详情页（[showBookActionsSheet] 返回动作由
/// 调用方路由）；删除流程（笔记处置三选）从旧的信息面板迁过来，菜单与
/// 详情页共用。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/motion.dart';
import '../../../domain/entities/book.dart';
import 'batch_actions.dart';

/// 长按菜单可执行的动作。
enum BookShelfAction {
  /// 继续阅读（从上次进度）。
  continueReading,

  /// 编辑信息（进书籍详情页）。
  edit,

  /// 移动到书架（选已有书架 / 新建书架）。
  moveToShelf,

  /// 清除本地缓存（书源文件已备份到同步库后删本地文件）。
  clearCache,

  /// 置顶 / 取消置顶。
  pin,

  /// 删除书籍。
  delete,
}

/// 弹出书籍长按菜单，返回用户选择的动作（点外部 = null）。
Future<BookShelfAction?> showBookActionsSheet(
  BuildContext context, {
  required Book book,
}) {
  return showModalBottomSheet<BookShelfAction>(
    context: context,
    sheetAnimationStyle: kSmoothSheetAnimation,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _BookActionsSheet(book: book),
  );
}

class _BookActionsSheet extends ConsumerWidget {
  const _BookActionsSheet({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    final muted = fg.withValues(alpha: 0.6);
    final pinned = book.pinnedAt != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部：小封面 + 书名/作者，让人确认操作对象
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(
                children: [
                  _MiniCover(path: book.coverPath),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: fg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (book.author != null &&
                            book.author!.isNotEmpty)
                          Text(
                            book.author!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (book.lastOpenedAt != null)
              _ActionTile(
                icon: Icons.auto_stories_outlined,
                label: '继续阅读',
                fg: fg,
                onTap: () => Navigator.of(context).pop(
                  BookShelfAction.continueReading,
                ),
              ),
            _ActionTile(
              icon: Icons.edit_outlined,
              label: '编辑信息',
              fg: fg,
              onTap: () => Navigator.of(context).pop(BookShelfAction.edit),
            ),
            _ActionTile(
              icon: Icons.drive_file_move_outline,
              label: '移动到书架',
              fg: fg,
              onTap: () =>
                  Navigator.of(context).pop(BookShelfAction.moveToShelf),
            ),
            _ActionTile(
              icon: Icons.delete_sweep_outlined,
              label: '清除本地缓存',
              fg: fg,
              onTap: () => Navigator.of(context).pop(
                BookShelfAction.clearCache,
              ),
            ),
            _ActionTile(
              icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
              label: pinned ? '取消置顶' : '在书架置顶',
              fg: fg,
              onTap: () => Navigator.of(context).pop(BookShelfAction.pin),
            ),
            _ActionTile(
              icon: Icons.delete_outline,
              label: '删除这本书',
              fg: theme.colorScheme.error,
              onTap: () => Navigator.of(context).pop(BookShelfAction.delete),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「移动到书架」弹层：选已有书架 / 移出书架 / 新建书架。
///
/// 返回目标书架名；**null = 用户取消**，空串 = 移出书架（未分类），
/// 非空 = 移入该书架（含新建）。书架即书籍的单值分类（category），
/// 已带多设备同步。
Future<String?> showMoveToShelfSheet(
  BuildContext context, {
  required Book book,
  required List<String> shelves,
}) {
  return showModalBottomSheet<String>(
    context: context,
    sheetAnimationStyle: kSmoothSheetAnimation,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _MoveToShelfSheet(book: book, shelves: shelves),
  );
}

class _MoveToShelfSheet extends StatefulWidget {
  const _MoveToShelfSheet({required this.book, required this.shelves});

  final Book book;
  final List<String> shelves;

  @override
  State<_MoveToShelfSheet> createState() => _MoveToShelfSheetState();
}

class _MoveToShelfSheetState extends State<_MoveToShelfSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _pick(String? value) => Navigator.of(context).pop(value);

  void _create() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    _pick(name.length > 20 ? name.substring(0, 20) : name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    final muted = fg.withValues(alpha: 0.6);
    final current = widget.book.category;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: Text(
                '把《${widget.book.title}》移动到…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                '一本书同一时间只在一个书架；书架可在顶部筛选条切换。',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  if (current != null && current.isNotEmpty)
                    _ActionTile(
                      icon: Icons.remove_circle_outline,
                      label: '移出书架（未分类）',
                      fg: muted,
                      onTap: () => _pick(''),
                    ),
                  for (final s in widget.shelves)
                    _ActionTile(
                      icon: s == current
                          ? Icons.folder
                          : Icons.folder_outlined,
                      label: s,
                      fg: fg,
                      onTap: () => _pick(s),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _create(),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '新建书架',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _create,
                    child: const Text('新建'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.fg,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: fg, size: 22),
      title: Text(label, style: TextStyle(color: fg, fontSize: 15)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    );
  }
}

class _MiniCover extends StatelessWidget {
  const _MiniCover({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: 38,
        height: 53,
        child: path == null
            ? Container(
                color: theme.colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Icon(
                  Icons.menu_book_outlined,
                  size: 18,
                  color: theme.colorScheme.outline,
                ),
              )
            : Image.file(
                File(path!),
                fit: BoxFit.cover,
                cacheWidth: 120,
                errorBuilder: (_, __, ___) => Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
      ),
    );
  }
}

/// 删除书籍：先问「是否同时删除该书的笔记/标注」。
///
/// 三个选项：取消 / 删除书籍（保留笔记）/ 删除全部（连笔记、阅读记录）。
///
/// 「删除全部」是不可恢复的操作，选它还要再过一次危险确认。返回是否真的删除了。
Future<bool> confirmDeleteBook(
  BuildContext context,
  WidgetRef ref, {
  required Book book,
}) async {
  final repo = await ref.read(bookRepositoryProvider.future);
  final annotations =
      await ref.read(annotationRepositoryProvider.future).then(
            (r) => r.listForBook(book.id),
          );
  if (!context.mounted) return false;

  final choice = await showDialog<_DeleteChoice>(
    context: context,
    animationStyle: kSmoothSheetAnimation,
    builder: (ctx) => AlertDialog(
      title: const Text('删除书籍'),
      content: Text(
        annotations.isEmpty
            ? '将删除《${book.title}》及其阅读进度、统计数据，云端备份也会删除。'
            : '《${book.title}》有 ${annotations.length} 条笔记/划线。\n'
                '「删除书籍」保留笔记与划线；「删除全部」连笔记、划线、书签和'
                '阅读记录一起删除。云端备份也会删除。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(null),
          child: const Text('取消'),
        ),
        TextButton(
          key: const ValueKey('book-delete-book-only'),
          onPressed: () => Navigator.of(ctx).pop(_DeleteChoice.bookOnly),
          child: const Text('删除书籍'),
        ),
        TextButton(
          key: const ValueKey('book-delete-all'),
          onPressed: () => Navigator.of(ctx).pop(_DeleteChoice.deleteAll),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(ctx).colorScheme.error,
          ),
          child: const Text('删除全部'),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return false;
  if (choice == _DeleteChoice.deleteAll) {
    final ok = await confirmDeleteAllDanger(
      context,
      message: '即将删除《${book.title}》的全部内容。',
    );
    if (!ok || !context.mounted) return false;
  }

  final messenger = ScaffoldMessenger.of(context);
  try {
    await repo.deleteBook(
      book.id,
      deleteAnnotations: choice == _DeleteChoice.deleteAll,
    );
    // 删除书 = 云端书源 + 封面 + 分片一起删除；同步未配置/网络失败时
    // 静默跳过，下次同步推送墓碑时还会重试一次清理。
    try {
      final sync = await ref.read(syncRepositoryProvider.future);
      await sync.deleteCloudBook(book.id, fileSha256: book.fileSha256);
    } catch (_) {
      // 云端清理失败不影响本地删除
    }
    messenger.showSnackBar(
      SnackBar(content: Text('已删除《${book.title}》')),
    );
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('删除失败：$e')));
    return false;
  }
}

enum _DeleteChoice {
  bookOnly,
  deleteAll,
}
