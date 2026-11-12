/// 书架多选后的批量操作弹层：删除 / 加标签 / 移动到分组。
library;

import 'package:flutter/material.dart';

import '../../../app/theme/motion.dart';
import '../../tags/tag_library.dart';

/// 批量删除的两种方式。
enum BatchDeleteMode {
  /// 仅删除书籍：保留笔记/划线（不导出）。
  bookOnly('删除书籍'),

  /// 删除全部：书籍 + 笔记/划线一起删除。
  all('删除全部');

  const BatchDeleteMode(this.label);

  /// 展示名。
  final String label;
}

/// 「删除全部」的二次危险确认。
///
/// 笔记、划线、书签、阅读进度与阅读记录一旦删除不可恢复，所以单独再问一次。
Future<bool> confirmDeleteAllDanger(
  BuildContext context, {
  required String message,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    animationStyle: kSmoothSheetAnimation,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        Icons.warning_amber_rounded,
        color: scheme.error,
        size: 40,
      ),
      title: Text(
        '危险操作',
        style: TextStyle(
          color: scheme.error,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Text(
        '$message\n\n'
        '笔记、划线、书签、阅读进度和阅读记录会一起删除，且无法恢复。\n'
        '确定继续删除吗？',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('danger-delete-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('继续删除'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 批量删除确认；取消返回 null。
Future<BatchDeleteMode?> showBatchDeleteDialog(
  BuildContext context, {
  required int count,
}) async {
  final choice = await showDialog<BatchDeleteMode>(
    context: context,
    animationStyle: kSmoothSheetAnimation,
    builder: (ctx) => AlertDialog(
      title: Text('删除 $count 本书'),
      content: Text(
        '「删除书籍」会删除这 $count 本书及其阅读进度、统计数据，'
        '但保留笔记与划线；「删除全部」会连笔记、划线、书签和阅读记录一起删除。'
        '云端备份也会删除。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          key: const ValueKey('batch-delete-book-only'),
          onPressed: () => Navigator.of(ctx).pop(BatchDeleteMode.bookOnly),
          child: const Text('删除书籍'),
        ),
        TextButton(
          key: const ValueKey('batch-delete-all'),
          onPressed: () => Navigator.of(ctx).pop(BatchDeleteMode.all),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(ctx).colorScheme.error,
          ),
          child: const Text('删除全部'),
        ),
      ],
    ),
  );
  if (choice != BatchDeleteMode.all) return choice;
  if (!context.mounted) return null;
  final ok = await confirmDeleteAllDanger(
    context,
    message: '即将删除 $count 本书的全部内容。',
  );
  return ok ? BatchDeleteMode.all : null;
}

/// 批量加标签；取消返回 null。返回的是去重后的新标签列表。
Future<List<String>?> showBatchTagSheet(
  BuildContext context, {
  required int count,
  required List<String> knownTags,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: kSmoothSheetAnimation,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _BatchTagSheet(count: count, knownTags: knownTags),
  );
}

class _BatchTagSheet extends StatefulWidget {
  const _BatchTagSheet({required this.count, required this.knownTags});

  final int count;
  final List<String> knownTags;

  @override
  State<_BatchTagSheet> createState() => _BatchTagSheetState();
}

class _BatchTagSheetState extends State<_BatchTagSheet> {
  final TextEditingController _ctrl = TextEditingController();
  final Set<String> _picked = {};

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<String> _parsed() {
    final out = <String>[];
    final raw = _ctrl.text.split(RegExp(r'[,，、\s]+'));
    for (final item in [..._picked, ...raw]) {
      final name = normalizeTagName(item);
      if (name != null && !out.contains(name)) out.add(name);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tags = [...widget.knownTags]..sort();
    final parsed = _parsed();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                child: Text(
                  '给 ${widget.count} 本书加标签',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (tags.isNotEmpty) ...[
                        Text('已有标签', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final tag in tags)
                              FilterChip(
                                key: ValueKey('batch-tag-known-$tag'),
                                label: Text(tag),
                                selected: _picked.contains(tag),
                                onSelected: (selected) => setState(() {
                                  if (selected) {
                                    _picked.add(tag);
                                  } else {
                                    _picked.remove(tag);
                                  }
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextField(
                        key: const ValueKey('batch-tag-input'),
                        controller: _ctrl,
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: '新标签',
                          hintText: '多个标签用逗号分隔',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      if (parsed.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '将添加：${parsed.join('、')}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                    const Spacer(),
                    FilledButton(
                      key: const ValueKey('batch-tag-apply'),
                      onPressed: parsed.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(parsed),
                      child: const Text('添加'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 批量移动到分组；取消返回 null，空串 = 移出分组。
Future<String?> showBatchShelfSheet(
  BuildContext context, {
  required int count,
  required List<String> shelves,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: kSmoothSheetAnimation,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _BatchShelfSheet(count: count, shelves: shelves),
  );
}

class _BatchShelfSheet extends StatefulWidget {
  const _BatchShelfSheet({required this.count, required this.shelves});

  final int count;
  final List<String> shelves;

  @override
  State<_BatchShelfSheet> createState() => _BatchShelfSheetState();
}

class _BatchShelfSheetState extends State<_BatchShelfSheet> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String? _newName() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return null;
    return name.length > 20 ? name.substring(0, 20) : name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shelves = [...widget.shelves]..sort();
    final canCreate = _newName() != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                child: Text(
                  '把 ${widget.count} 本书添加到分组',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '一本书同一时间只在一个分组；选择已有分组或新建。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    ListTile(
                      key: const ValueKey('batch-shelf-none'),
                      leading: const Icon(Icons.remove_circle_outline),
                      title: const Text('移出分组（未分类）'),
                      onTap: () => Navigator.of(context).pop(''),
                    ),
                    for (final name in shelves)
                      ListTile(
                        key: ValueKey('batch-shelf-$name'),
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(name),
                        onTap: () => Navigator.of(context).pop(name),
                      ),
                    if (shelves.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                        child: Text('还没有分组，可以新建一个'),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('batch-shelf-input'),
                        controller: _ctrl,
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          final name = _newName();
                          if (name != null) Navigator.of(context).pop(name);
                        },
                        decoration: const InputDecoration(
                          hintText: '新建分组',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const ValueKey('batch-shelf-create'),
                      onPressed: canCreate
                          ? () => Navigator.of(context).pop(_newName())
                          : null,
                      child: const Text('新建'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
