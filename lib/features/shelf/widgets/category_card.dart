/// 分类卡片：2×2 四个书位，有书就摆前 4 本的封面，没书就摆空白书。
///
/// 「空白书」是刻意留白的书脊剪影：分类里一本都没有时，卡片仍然读得出
/// 是个「装书的格子」，而不是一格坏掉的白块。
///
/// 卡面不写分类名和本数（用户要求书架干净）：名称只作读屏标签，
/// 点进分类后由 AppBar 标题交代。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/widgets/pressable_scale.dart';
import '../../../../domain/entities/book.dart';

/// 书位数量（固定 2×2）。
const int kCategorySlots = 4;

/// 分类卡片：和书卡一样占一格，格子里 2×2 摆前 4 本封面。
class CategoryCard extends StatelessWidget {
  const CategoryCard({
    required this.title,
    required this.items,
    required this.onOpen,
    this.coverRadius = 20,
    super.key,
  });

  /// 分类名。
  final String title;

  /// 该分类下的全部书（卡片只取前 [kCategorySlots] 本做预览）。
  final List<ShelfItem> items;

  /// 点开分类。
  final VoidCallback onOpen;

  /// 卡片圆角（书架设置，0..24）。
  final double coverRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      // 卡面没有文字，名称留给读屏；本数也不显示。
      label: title,
      button: true,
      child: PressableScale(
        onTap: onOpen,
        child: Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(coverRadius),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: _Quad(
              books: _preview(items),
              slotRadius: coverRadius > 8 ? 8.0 : coverRadius,
            ),
          ),
        ),
      ),
    );
  }
}

/// 列表模式下的分类行：2×2 缩略图 + 分类名 + 本数 + 箭头。
class CategoryListTile extends StatelessWidget {
  const CategoryListTile({
    required this.title,
    required this.items,
    required this.onOpen,
    this.coverRadius = 20,
    super.key,
  });

  /// 分类名。
  final String title;

  /// 该分类下的全部书。
  final List<ShelfItem> items;

  /// 点开分类。
  final VoidCallback onOpen;

  /// 缩略图圆角（书架设置，最大用到 8，避免小图变成圆形）。
  final double coverRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressableScale(
      onTap: onOpen,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 78,
                child: _Quad(
                  books: _preview(items),
                  slotRadius: coverRadius > 8 ? 8.0 : coverRadius,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${items.length} 本',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 预览用前 4 本。
List<ShelfItem> _preview(List<ShelfItem> items) =>
    items.take(kCategorySlots).toList(growable: false);

/// 2×2 书位：每格按书的比例（宽:高 ≈ 0.72）摆，卡片拉高拉矮都不变形。
class _Quad extends StatelessWidget {
  const _Quad({required this.books, this.slotRadius = 5});

  final List<ShelfItem> books;

  /// 单个书位的圆角（跟书架设置的封面圆角联动，最多用到 8）。
  final double slotRadius;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 6.0;
        final slotW = ((c.maxWidth - gap) / 2).clamp(1.0, 1e6);
        // 和普通书卡同尺寸：网格格子给多高就铺满，不再按书的比例收窄。
        final slotH = ((c.maxHeight - gap) / 2).clamp(1.0, 1e6);
        Widget slot(int index) => index < books.length
            ? _SlotCover(
                key: ValueKey('category-slot-$index-filled'),
                path: books[index].book.coverPath,
                radius: slotRadius,
              )
            : _BlankBook(
                key: ValueKey('category-slot-$index-empty'),
                radius: slotRadius,
              );

        Widget row(int a, int b) => SizedBox(
              height: slotH,
              child: Row(
                children: [
                  SizedBox(width: slotW, child: slot(a)),
                  const SizedBox(width: gap),
                  SizedBox(width: slotW, child: slot(b)),
                ],
              ),
            );

        return Center(
          child: SizedBox(
            width: slotW * 2 + gap,
            height: slotH * 2 + gap,
            child: Column(
              children: [
                row(0, 1),
                const SizedBox(height: gap),
                row(2, 3),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 有封面的一格。
class _SlotCover extends StatelessWidget {
  const _SlotCover({required this.path, required this.radius, super.key});

  final String? path;

  /// 书位圆角。
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = path;
    final borderRadius = BorderRadius.circular(radius);
    if (p == null || p.isEmpty) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: _BlankBook(radius: radius),
      );
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.file(
        File(p),
        fit: BoxFit.cover,
        // 小格子按小尺寸解码，别为一张缩略图吃满原图内存。
        cacheWidth: 160,
        errorBuilder: (_, __, ___) => _BlankBook(radius: radius),
      ),
    );
  }
}

/// 空白书：留白的书脊剪影（一条窄脊 + 浅底）。
class _BlankBook extends StatelessWidget {
  const _BlankBook({this.radius = 5, super.key});

  /// 书位圆角。
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.9)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 3,
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
          decoration: BoxDecoration(
            color: scheme.outline.withValues(alpha: 0.55),
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}
