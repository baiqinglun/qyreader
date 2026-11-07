/// 书架卡片：封面 + 标题 + 作者 + 进度。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/widgets/pressable_scale.dart';
import '../../../../domain/entities/book.dart';

/// 书籍卡片。
class BookCard extends StatelessWidget {
  const BookCard({required this.item, required this.onOpen, super.key});

  /// 展示数据。
  final ShelfItem item;

  /// 打开书籍回调。
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = item.book;
    final hasProgress = item.percent > 0;

    return PressableScale(
      onTap: onOpen,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _Cover(path: book.coverPath)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (book.author != null && book.author!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      book.author!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: hasProgress ? item.percent.clamp(0, 1) : null,
                          minHeight: 3,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        hasProgress ? '${(item.percent * 100).round()}%' : '未读',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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

class _Cover extends StatelessWidget {
  const _Cover({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (path == null) {
      return _placeholder(theme);
    }
    return Image.file(
      File(path!),
      fit: BoxFit.cover,
      // 内存红线：解码到卡片所需尺寸即可，不按原图分辨率解码。
      cacheWidth: 360,
      errorBuilder: (_, __, ___) => _placeholder(theme),
    );
  }

  Widget _placeholder(ThemeData theme) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.menu_book_outlined,
          size: 40,
          color: theme.colorScheme.outline,
        ),
      );
}
