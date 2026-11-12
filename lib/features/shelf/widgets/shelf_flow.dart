/// 书架内容流：分类格和书格铺在同一套格子里（分类始终在前）。
library;

import 'package:flutter/material.dart';

import '../../../../app/theme/motion.dart';
import '../../../../domain/entities/book.dart';
import '../shelf_controller.dart';
import '../shelf_prefs.dart';
import 'book_card.dart';
import 'category_card.dart';
import 'shelf_plank.dart';

/// 书架内容：分类卡和书卡一块排版。
///
/// 平铺 / 封面用网格，列表用竖排；网格一行 [columns] 格（手机上 3 格）。
/// [cells] 里分类格永远排在散落的书前面（由 [shelfCells] 保证）。
class ShelfFlow extends StatelessWidget {
  const ShelfFlow({
    required this.cells,
    required this.mode,
    required this.columns,
    required this.onOpenBook,
    required this.onManageBook,
    required this.onOpenCategory,
    this.selectionMode = false,
    this.selectedBookIds = const <String>{},
    this.onToggleSelect,
    this.coverRadius = 20,
    this.plankStyle = ShelfPlankStyle.wood,
    this.showProgress = true,
    this.showRating = false,
    this.showTags = false,
    this.showDescription = false,
    this.descriptionLines = 2,
    this.showReview = false,
    this.reviewLines = 2,
    super.key,
  });

  /// 书架格（分类在前，没有分类的书在后）。
  final List<ShelfCell> cells;

  /// 展示形式。
  final ShelfViewMode mode;

  /// 网格一行几格。
  final int columns;

  /// 点开一本书。
  final ValueChanged<ShelfItem> onOpenBook;

  /// 长按/编辑一本书。
  final ValueChanged<ShelfItem> onManageBook;

  /// 点开一个分类。
  final ValueChanged<String> onOpenCategory;

  /// 多选模式：书格点击变成切换选中。
  final bool selectionMode;

  /// 已选中的书籍 id。
  final Set<String> selectedBookIds;

  /// 切换一本书的选中状态。
  final ValueChanged<ShelfItem>? onToggleSelect;

  /// 封面/卡片圆角（0..24）。
  final double coverRadius;

  /// 网格架板样式。
  final ShelfPlankStyle plankStyle;

  /// 网格/封面模式是否显示封面右上角进度。
  final bool showProgress;

  /// 列表行是否显示星级。
  final bool showRating;

  /// 列表行是否显示标签。
  final bool showTags;

  /// 列表行是否显示简介。
  final bool showDescription;

  /// 简介显示行数。
  final int descriptionLines;

  /// 列表行是否显示书评。
  final bool showReview;

  /// 书评显示行数。
  final int reviewLines;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      ShelfViewMode.grid => _grid(context, coverOnly: false),
      ShelfViewMode.cover => _grid(context, coverOnly: true),
      ShelfViewMode.list => SliverList.builder(
          itemCount: cells.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AnimatedAppear(
              index: index,
              child: switch (cells[index]) {
                ShelfCategoryCell(:final title, :final books) =>
                  CategoryListTile(
                    key: ValueKey('category-$title'),
                    title: title,
                    items: books,
                    coverRadius: coverRadius,
                    onOpen: () => onOpenCategory(title),
                  ),
                ShelfBookCell(:final item) => BookListTile(
                    key: ValueKey('book-${item.book.id}'),
                    item: item,
                    coverRadius: coverRadius,
                    showRating: showRating,
                    showTags: showTags,
                    showDescription: showDescription,
                    descriptionLines: descriptionLines,
                    showReview: showReview,
                    reviewLines: reviewLines,
                    selectionMode: selectionMode,
                    selected: selectedBookIds.contains(item.book.id),
                    onSelect: onToggleSelect == null
                        ? null
                        : () => onToggleSelect!(item),
                    onOpen: () => onOpenBook(item),
                    onManage: () => onManageBook(item),
                  ),
              },
            ),
          ),
        ),
    };
  }

  /// 平铺 / 封面：同一套网格，一格一个分类卡或一本书。
  ///
  /// 按「行」铺而不是按格铺：架板是一条横贯整行的木板，格子之间的 12dp
  /// 缝隙也要接上，所以一行一个 Row，下面压一条 [ShelfPlank]。
  Widget _grid(BuildContext context, {required bool coverOnly}) {
    final rows = (cells.length + columns - 1) ~/ columns;
    return SliverList.builder(
      itemCount: rows,
      itemBuilder: (context, row) {
        final start = row * columns;
        final rowEnd = start + columns;
        final end = rowEnd < cells.length ? rowEnd : cells.length;
        return Padding(
          // 行距落在架板下面；最后一行不留空白。
          padding: EdgeInsets.only(bottom: row == rows - 1 ? 0 : 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              final cellWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              // 与原来的 childAspectRatio: 0.72 一致。
              final cellHeight = cellWidth / 0.72;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: cellHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = start; i < end; i++) ...[
                          if (i > start) const SizedBox(width: gap),
                          Expanded(
                            child: _AnimatedAppear(
                              index: i,
                              child: _gridCell(i, coverOnly: coverOnly),
                            ),
                          ),
                        ],
                        // 最后一行不满时补空位，保证每格宽度一致。
                        for (var i = end; i < start + columns; i++) ...[
                          if (i > start) const SizedBox(width: gap),
                          const Expanded(child: SizedBox.shrink()),
                        ],
                      ],
                    ),
                  ),
                  if (plankStyle != ShelfPlankStyle.none)
                    ShelfPlank(
                      key: ValueKey('shelf-plank-$row'),
                      style: plankStyle,
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _gridCell(int index, {required bool coverOnly}) {
    return switch (cells[index]) {
      ShelfCategoryCell(:final title, :final books) => CategoryCard(
          key: ValueKey('category-$title'),
          title: title,
          items: books,
          coverRadius: coverRadius,
          onOpen: () => onOpenCategory(title),
        ),
      ShelfBookCell(:final item) => coverOnly
          ? BookCoverTile(
              key: ValueKey('book-${item.book.id}'),
              item: item,
              coverRadius: coverRadius,
              // 纯封面模式只留封面，不看进度；网格模式才显示右上角进度。
              showProgress: false,
              selectionMode: selectionMode,
              selected: selectedBookIds.contains(item.book.id),
              onSelect: onToggleSelect == null
                  ? null
                  : () => onToggleSelect!(item),
              onOpen: () => onOpenBook(item),
              onManage: () => onManageBook(item),
            )
          : BookCard(
              key: ValueKey('book-${item.book.id}'),
              item: item,
              coverRadius: coverRadius,
              showProgress: showProgress,
              selectionMode: selectionMode,
              selected: selectedBookIds.contains(item.book.id),
              onSelect: onToggleSelect == null
                  ? null
                  : () => onToggleSelect!(item),
              onOpen: () => onOpenBook(item),
              onManage: () => onManageBook(item),
            ),
    };
  }
}

/// 冷启动 stagger：每格 +20ms，封顶 300ms。
class _AnimatedAppear extends StatelessWidget {
  const _AnimatedAppear({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    final delayMs = (index * 20).clamp(0, 300);
    final total = motion.emphasized + Duration(milliseconds: delayMs);
    final beginFraction = delayMs / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(beginFraction, 1, curve: motion.enter),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
