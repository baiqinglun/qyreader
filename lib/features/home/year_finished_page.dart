/// 首页「今年读完的书」的完整展示页。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/layout.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../domain/entities/book.dart';
import 'widgets/cover_thumb.dart';

/// 今年读完的全部书籍：封面 + 书名 + 作者，按最近的在前。
class YearFinishedPage extends StatelessWidget {
  /// 构造。
  const YearFinishedPage({
    required this.books,
    required this.onOpen,
    super.key,
  });

  /// 今年读完的书。
  final List<ShelfItem> books;

  /// 点书回调（打开阅读器）。
  final ValueChanged<ShelfItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('year-finished-page'),
      appBar: AppBar(
        title: const Text('今年读完的书'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${books.length} 本',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
      body: books.isEmpty
          ? Center(
              child: Text(
                '今年还没有读完的书',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 12.0;
                    final available = constraints.maxWidth - 40;
                    final columns = math
                        .max(2, (available / 105).floor())
                        .clamp(2, 8)
                        .toInt();
                    final width =
                        (available - spacing * (columns - 1)) / columns;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                      // Wrap 收缩到内容宽度时 alignment.center 失效，
                      // 撑满视口宽最后一行不足整列时才居中。
                      child: SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: spacing,
                          runSpacing: 18,
                          children: <Widget>[
                            for (final item in books)
                              SizedBox(
                                width: width,
                                child: PressableScale(
                                  key: ValueKey(
                                    'year-finished-book-${item.book.id}',
                                  ),
                                  onTap: () => onOpen(item),
                                  child: _FinishedTile(
                                    item: item,
                                    width: width,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}

class _FinishedTile extends StatelessWidget {
  const _FinishedTile({required this.item, required this.width});

  final ShelfItem item;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = item.book;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CoverThumb(
          path: book.coverPath,
          width: width,
          height: width / 0.68,
          radius: 12,
          shadow: true,
        ),
        const SizedBox(height: 7),
        Text(
          book.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        if (book.author?.trim().isNotEmpty == true) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            book.author!.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ],
    );
  }
}
