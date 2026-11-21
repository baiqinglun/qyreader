/// 书架内容流：分类格和书格铺在同一套格子里（分类始终在前）。
library;

import 'package:flutter/material.dart';

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
    this.onManageCategory,
    this.selectionMode = false,
    this.selectedBookIds = const <String>{},
    this.onToggleSelect,
    this.coverRadius = 20,
    this.plankStyle = ShelfPlankStyle.wood,
    this.showProgress = true,
    this.showTitle = false,
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

  /// 长按一个分类（弹出管理菜单）；null = 不响应长按。
  final ValueChanged<String>? onManageCategory;

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

  /// 网格是否在封面下方显示书名（纯封面模式不显示）。
  final bool showTitle;

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
          child: switch (cells[index]) {
            ShelfCategoryCell(:final title, :final books) => CategoryListTile(
              key: ValueKey('category-$title'),
              title: title == kFavoritesShelf ? '收藏' : title.split('/').last,
              items: books,
              coverRadius: coverRadius,
              onOpen: () => onOpenCategory(title),
              onLongPress: onManageCategory == null
                  ? null
                  : () => onManageCategory!(title),
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
    };
  }

  /// 平铺 / 封面：同一套网格，一格一个分类卡或一本书。
  ///
  /// 按「行」铺而不是按格铺：架板是一条横贯整行的木板，格子之间的 12dp
  /// 缝隙也要接上，所以一行一个 Row，下面压一条 [ShelfPlank]。
  Widget _grid(BuildContext context, {required bool coverOnly}) {
    final showBookTitle = !coverOnly && showTitle;
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
              // 与原来的 childAspectRatio: 0.72 一致；显示书名时给下方
              // 文字留 28px（字号 12.5 + 间距 4）。
              final cellHeight =
                  cellWidth / 0.72 + (showBookTitle ? 48.0 : 0.0);
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
                            child: _gridCell(
                              context,
                              i,
                              coverOnly: coverOnly,
                              showTitle: showBookTitle,
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

  Widget _gridCell(
    BuildContext context,
    int index, {
    required bool coverOnly,
    required bool showTitle,
  }) {
    return switch (cells[index]) {
      ShelfCategoryCell(:final title, :final books) => _gridCategoryCell(
        context,
        title,
        books,
        showTitle: showTitle,
      ),
      ShelfBookCell(:final item) => _gridBookCell(
        context,
        item,
        coverOnly: coverOnly,
        showTitle: showTitle,
      ),
    };
  }

  Widget _gridCategoryCell(
    BuildContext context,
    String title,
    List<ShelfItem> books, {
    required bool showTitle,
  }) {
    final card = CategoryCard(
      key: ValueKey('category-$title'),
      title: title == kFavoritesShelf ? '收藏' : title,
      items: books,
      coverRadius: coverRadius,
      onOpen: () => onOpenCategory(title),
      onLongPress: onManageCategory == null || title == kFavoritesShelf
          ? null
          : () => onManageCategory!(title),
    );
    if (!showTitle) {
      if (title != kFavoritesShelf) return card;
      return Stack(
        children: [
          Positioned.fill(child: card),
          Positioned(
            left: 4,
            bottom: 4,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text('收藏', style: TextStyle(fontSize: 11)),
                ),
              ),
            ),
          ),
        ],
      );
    }
    // 书格下面显示书名，分类格也显示分类名，行高保持一致。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: card),
        const SizedBox(height: 4),
        Text(
          title == kFavoritesShelf ? '收藏' : title.split('/').last,
          key: ValueKey('category-title-$title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
          style: _gridTitleStyle(context),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                '共 ${books.length} 本',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (onManageCategory != null && title != kFavoritesShelf)
              SizedBox(
                width: 32,
                height: 24,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: '管理分类',
                  iconSize: 20,
                  onPressed: () => onManageCategory!(title),
                  icon: const Icon(Icons.more_horiz),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _gridBookCell(
    BuildContext context,
    ShelfItem item, {
    required bool coverOnly,
    required bool showTitle,
  }) {
    void open() => onOpenBook(item);
    void manage() => onManageBook(item);
    void toggle() => onToggleSelect!(item);
    if (coverOnly) {
      return BookCoverTile(
        key: ValueKey('book-${item.book.id}'),
        item: item,
        coverRadius: coverRadius,
        // 纯封面模式只留封面，不看进度；网格模式才显示右上角进度。
        showProgress: false,
        selectionMode: selectionMode,
        selected: selectedBookIds.contains(item.book.id),
        onSelect: onToggleSelect == null ? null : toggle,
        onOpen: open,
        onManage: manage,
      );
    }
    final card = BookCard(
      key: ValueKey('book-${item.book.id}'),
      item: item,
      coverRadius: coverRadius,
      showProgress: showProgress,
      selectionMode: selectionMode,
      selected: selectedBookIds.contains(item.book.id),
      onSelect: onToggleSelect == null ? null : toggle,
      onOpen: open,
      onManage: manage,
    );
    if (!showTitle) return card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: card),
        const SizedBox(height: 4),
        Text(
          item.book.title,
          key: ValueKey('book-title-${item.book.id}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
          style: _gridTitleStyle(context),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// 网格书名 / 分类名的统一样式（单行居中）。
TextStyle _gridTitleStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.bodySmall?.copyWith(
        fontSize: 12.5,
        height: 1.2,
        fontWeight: FontWeight.w500,
        color: theme.colorScheme.onSurface,
      ) ??
      const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500);
}
