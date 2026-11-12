/// 标签管理页：搜索 / 新增 / 重命名 / 删除跨书标签。
///
/// 标签本体存在每本书的 `books.tags` 里（会同步）；本页的重命名/删除会
/// 批量更新所有相关书籍，新增则先落本机标签库（`tags.library`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/motion.dart';
import '../shelf/widgets/tag_capsule.dart';
import 'tag_library.dart';

/// 标签管理页。
class TagManagerPage extends ConsumerStatefulWidget {
  const TagManagerPage({super.key});

  @override
  ConsumerState<TagManagerPage> createState() => _TagManagerPageState();
}

class _TagManagerPageState extends ConsumerState<TagManagerPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  bool _busy = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addTag() async {
    final name = await _promptName(title: '新建标签');
    if (name == null || !mounted) return;
    if (ref.read(tagSummariesProvider).any((tag) => tag.name == name)) {
      _toast('标签「$name」已存在');
      return;
    }
    await ref.read(tagLibraryControllerProvider.notifier).add(name);
    if (!mounted) return;
    _toast('已添加标签「$name」');
  }

  Future<void> _editTag(TagSummary summary) async {
    final result = await _showEditDialog(summary);
    if (result == null || !mounted) return;
    if (result.delete) {
      await _deleteTag(summary);
      return;
    }
    final target = normalizeTagName(result.name);
    if (target == null) {
      _toast('标签名不能为空');
      return;
    }
    if (target == summary.name) return;
    await _run(() async {
      final repo = await ref.read(bookRepositoryProvider.future);
      final count = await repo.renameTag(summary.name, target);
      await ref
          .read(tagLibraryControllerProvider.notifier)
          .rename(summary.name, target);
      if (!mounted) return;
      _toast(
        count > 0 ? '已改名为「$target」，更新 $count 本书' : '已改名为「$target」',
      );
    });
  }

  Future<void> _deleteTag(TagSummary summary) async {
    final ok = await showDialog<bool>(
      context: context,
      animationStyle: kSmoothSheetAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('删除标签'),
        content: Text(
          '删除标签「${summary.name}」？\n'
          '会从 ${summary.count} 本书上移除，不会删除书籍。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      final repo = await ref.read(bookRepositoryProvider.future);
      final count = await repo.deleteTag(summary.name);
      await ref.read(tagLibraryControllerProvider.notifier).remove(summary.name);
      if (!mounted) return;
      _toast(
        count > 0
            ? '已删除标签「${summary.name}」，更新 $count 本书'
            : '已删除标签「${summary.name}」',
      );
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _toast('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _promptName({required String title}) async {
    var value = '';
    final raw = await showDialog<String>(
      context: context,
      animationStyle: kSmoothSheetAnimation,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          autofocus: true,
          maxLength: 20,
          textInputAction: TextInputAction.done,
          onChanged: (text) => value = text,
          onFieldSubmitted: (text) => Navigator.of(ctx).pop(text),
          decoration: const InputDecoration(
            labelText: '标签名',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(value),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return normalizeTagName(raw ?? '');
  }

  Future<_TagEditResult?> _showEditDialog(TagSummary summary) async {
    var value = summary.name;
    return showDialog<_TagEditResult>(
      context: context,
      animationStyle: kSmoothSheetAnimation,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('编辑标签'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                initialValue: summary.name,
                autofocus: true,
                maxLength: 20,
                onChanged: (text) => value = text,
                decoration: const InputDecoration(
                  labelText: '标签名',
                  border: OutlineInputBorder(),
                ),
              ),
              Text(
                '已用于 ${summary.count} 本书',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              onPressed: () =>
                  Navigator.of(ctx).pop(const _TagEditResult.delete()),
              child: const Text('删除'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_TagEditResult.save(value)),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final all = ref.watch(tagSummariesProvider);
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? all
        : [
            for (final tag in all)
              if (tag.name.toLowerCase().contains(q)) tag,
          ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('标签'),
        actions: [
          IconButton(
            tooltip: '新建标签',
            onPressed: _busy ? null : _addTag,
            icon: const Icon(Icons.add),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (value) => setState(() => _query = value.trim()),
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: all.isEmpty ? '搜索标签' : '从 ${all.length} 个标签中搜索',
                  hintStyle: TextStyle(fontSize: 14, color: muted),
                  isDense: true,
                  filled: true,
                  fillColor:
                      scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 40),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空搜索',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? _emptyState(all.isEmpty, q)
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in filtered)
                              TagCapsule(
                                tag: tag.name,
                                count: tag.count,
                                large: true,
                                onTap: () => _editTag(tag),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '点击标签可重命名或删除',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(bool noTags, String query) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              noTags ? Icons.sell_outlined : Icons.search_off,
              size: 40,
              color: muted.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              noTags ? '还没有标签' : '没有找到「$query」',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
            if (noTags) ...[
              const SizedBox(height: 6),
              Text(
                '点右上角 + 新建，或在书籍信息里给书加标签',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: muted.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 编辑标签对话框的结果：保存（带新名字）或删除。
class _TagEditResult {
  const _TagEditResult.save(this.name) : delete = false;

  const _TagEditResult.delete()
      : name = '',
        delete = true;

  final String name;
  final bool delete;
}
