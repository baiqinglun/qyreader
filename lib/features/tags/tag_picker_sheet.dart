/// 标签选择器（编辑书籍用）：从标签库里直接多选，不必手打。
///
/// 标签自带使用数，点一下切换选中；每本书最多 12 个（与仓储规范化一致）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/motion.dart';
import '../shelf/widgets/tag_capsule.dart';
import 'tag_library.dart';

/// 每本书最多可挂的标签数（与 `BookRepositoryImpl._normalizeTags` 一致）。
const int kMaxTagsPerBook = 12;

/// 弹出标签选择器。
Future<void> showTagPickerSheet(
  BuildContext context, {
  required List<TagSummary> tags,
  required Set<String> selected,
  required ValueChanged<String> onToggle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: kSmoothSheetAnimation,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => TagPickerSheet(
      tags: tags,
      selected: selected,
      onToggle: onToggle,
    ),
  );
}

/// 标签多选面板。
class TagPickerSheet extends StatefulWidget {
  const TagPickerSheet({
    required this.tags,
    required this.selected,
    required this.onToggle,
    super.key,
  });

  /// 标签库全量（含使用数）。
  final List<TagSummary> tags;

  /// 当前这本书已选的标签。
  final Set<String> selected;

  /// 点标签时回调（已选 → 取消，未选 → 添加）。
  final ValueChanged<String> onToggle;

  @override
  State<TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<TagPickerSheet> {
  late final Set<String> _selected = {...widget.selected};
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggle(String tag) {
    final isSelected = _selected.contains(tag);
    if (!isSelected && _selected.length >= kMaxTagsPerBook) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('每本书最多 $kMaxTagsPerBook 个标签')),
      );
      return;
    }
    setState(() {
      if (isSelected) {
        _selected.remove(tag);
      } else {
        _selected.add(tag);
      }
    });
    widget.onToggle(tag);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.tags
        : [
            for (final tag in widget.tags)
              if (tag.name.toLowerCase().contains(q)) tag,
          ];

    return SizedBox(
      height: 520,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Row(
                children: [
                  Icon(Icons.sell_outlined, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '选择标签',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '已选 ${_selected.length}/$kMaxTagsPerBook',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                height: 42,
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (value) => setState(() => _query = value.trim()),
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '搜索标签',
                    hintStyle: TextStyle(fontSize: 14, color: muted),
                    isDense: true,
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest
                        .withValues(alpha: 0.55),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 40),
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
                  ? Center(
                      child: Text(
                        q.isEmpty ? '标签库是空的' : '没有找到「$_query」',
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in filtered)
                            TagCapsule(
                              tag: tag.name,
                              count: tag.count,
                              selected: _selected.contains(tag.name),
                              onTap: () => _toggle(tag.name),
                            ),
                        ],
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
                onPressed: () => unawaited(Navigator.of(context).maybePop()),
                child: const Text('完成'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
