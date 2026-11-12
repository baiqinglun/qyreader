/// 书架筛选弹层：最低星级 + 标签 + 阅读状态，点「应用」返回筛选条件。
library;

import 'package:flutter/material.dart';

import '../../../app/theme/motion.dart';
import '../../../domain/entities/book.dart';
import '../shelf_filter.dart';

/// 打开筛选弹层；取消返回 null。
Future<ShelfFilter?> showShelfFilterSheet(
  BuildContext context, {
  required ShelfFilter initial,
  required List<String> tags,
}) {
  return showModalBottomSheet<ShelfFilter>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: kSmoothSheetAnimation,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _ShelfFilterSheet(initial: initial, tags: tags),
  );
}

class _ShelfFilterSheet extends StatefulWidget {
  const _ShelfFilterSheet({required this.initial, required this.tags});

  final ShelfFilter initial;
  final List<String> tags;

  @override
  State<_ShelfFilterSheet> createState() => _ShelfFilterSheetState();
}

class _ShelfFilterSheetState extends State<_ShelfFilterSheet> {
  late int _minRating;
  late Set<String> _tags;
  late Set<BookReadStatus> _statuses;

  @override
  void initState() {
    super.initState();
    _minRating = widget.initial.minRating;
    _tags = {...widget.initial.tags};
    _statuses = {...widget.initial.statuses};
  }

  void _reset() {
    setState(() {
      _minRating = 0;
      _tags = {};
      _statuses = {};
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tags = [...widget.tags]..sort();
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
              child: Row(
                children: [
                  Text(
                    '筛选',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    key: const ValueKey('shelf-filter-reset'),
                    onPressed: _reset,
                    child: const Text('重置'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('最低星级', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (var rating = 0; rating <= 5; rating++)
                          ChoiceChip(
                            key: ValueKey('shelf-filter-rating-$rating'),
                            label: Text(rating == 0 ? '不限' : '$rating 星+'),
                            selected: _minRating == rating,
                            onSelected: (_) =>
                                setState(() => _minRating = rating),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('阅读状态（任一）', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final status in BookReadStatus.values)
                          FilterChip(
                            key: ValueKey('shelf-filter-status-${status.name}'),
                            label: Text(status.label),
                            selected: _statuses.contains(status),
                            onSelected: (selected) => setState(() {
                              if (selected) {
                                _statuses.add(status);
                              } else {
                                _statuses.remove(status);
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('标签（任一）', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    if (tags.isEmpty)
                      Text(
                        '还没有标签，可以在编辑书籍时添加',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final tag in tags)
                            FilterChip(
                              key: ValueKey('shelf-filter-tag-$tag'),
                              label: Text(tag),
                              selected: _tags.contains(tag),
                              onSelected: (selected) => setState(() {
                                if (selected) {
                                  _tags.add(tag);
                                } else {
                                  _tags.remove(tag);
                                }
                              }),
                            ),
                        ],
                      ),
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
                    key: const ValueKey('shelf-filter-apply'),
                    onPressed: () => Navigator.of(context).pop(
                      ShelfFilter(
                        minRating: _minRating,
                        tags: _tags,
                        statuses: _statuses,
                      ),
                    ),
                    child: const Text('应用'),
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
