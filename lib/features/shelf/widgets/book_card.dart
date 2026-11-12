/// 书架卡片：网格/封面模式只显示封面 + 右上角进度；列表行保留完整信息。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../app/transitions/book_open_transition.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../domain/entities/book.dart';
import '../../../../domain/services/book_reviews.dart';
import 'tag_capsule.dart';

/// 书籍卡片：网格模式只显示封面 + 右上角进度（名称等信息不出现在网格里）。
class BookCard extends StatelessWidget {
  const BookCard({
    required this.item,
    required this.onOpen,
    required this.onManage,
    this.coverRadius = 20,
    this.showProgress = true,
    this.selectionMode = false,
    this.selected = false,
    this.onSelect,
    super.key,
  });

  /// 展示数据。
  final ShelfItem item;

  /// 打开书籍回调。
  final VoidCallback onOpen;

  /// 编辑标签/书评/评分/置顶回调（长按）。
  final VoidCallback onManage;

  /// 封面/卡片圆角（书架设置，0..24）。
  final double coverRadius;

  /// 封面右上角是否显示圆形阅读进度。
  final bool showProgress;

  /// 多选模式：点击/长按切换选中，而不是打开或管理。
  final bool selectionMode;

  /// 当前是否被选中。
  final bool selected;

  /// 切换选中状态。
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) => BookCoverTile(
        item: item,
        onOpen: onOpen,
        onManage: onManage,
        coverRadius: coverRadius,
        showProgress: showProgress,
        selectionMode: selectionMode,
        selected: selected,
        onSelect: onSelect,
      );
}
/// 评分星条（1..5）。
class _RatingStars extends StatelessWidget {
  const _RatingStars({required this.rating});

  final int rating;

  static const Color _gold = Color(0xFFE0A030);

  @override
  Widget build(BuildContext context) {
    final stars = rating.clamp(1, 5);
    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 12,
            color: i <= stars ? _gold : Colors.grey.withValues(alpha: 0.5),
          ),
      ],
    );
  }
}

/// 标签行（最多展示 2 个彩色胶囊）。
class _TagLine extends StatelessWidget {
  const _TagLine({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 3,
      children: [
        for (final tag in tags.take(2)) TagCapsule(tag: tag, compact: true),
      ],
    );
  }
}

/// 封面右上角的圆形阅读进度：外圈弧 + 中间百分比。
class BookProgressBadge extends StatelessWidget {
  const BookProgressBadge({
    required this.percent,
    this.compact = false,
    super.key,
  });

  /// 0..1。
  final double percent;

  /// 窄格子用小一号，避免 5 列时角标占掉半张封面。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final value = percent.clamp(0.0, 1.0);
    final label = '${(value * 100).round()}%';
    final size = compact ? 28.0 : 34.0;
    final stroke = compact ? 2.0 : 2.5;
    return Semantics(
      label: '阅读进度 $label',
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(compact ? 3 : 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          shape: BoxShape.circle,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: stroke,
                backgroundColor: Colors.white.withValues(alpha: 0.22),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 8 : 9,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
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

/// 列表模式的一行：封面缩略图 + 标题/作者/进度，按开关追加评分/标签/简介/书评。
///
/// 四组内容默认都关（见 [ShelfPrefs]）：关掉后不再插入任何占位，
/// 行高自然收紧回「标题 + 作者 + 进度」。
class BookListTile extends StatelessWidget {
  const BookListTile({
    required this.item,
    required this.onOpen,
    required this.onManage,
    this.coverRadius = 20,
    this.showRating = false,
    this.showTags = false,
    this.showDescription = false,
    this.descriptionLines = 2,
    this.showReview = false,
    this.reviewLines = 2,
    this.selectionMode = false,
    this.selected = false,
    this.onSelect,
    super.key,
  });

  /// 展示数据。
  final ShelfItem item;

  /// 打开书籍回调。
  final VoidCallback onOpen;

  /// 编辑标签/书评/评分/置顶回调（长按或右侧按钮）。
  final VoidCallback onManage;

  /// 封面圆角（列表缩略图最大用到 12，避免小图变成圆形）。
  final double coverRadius;

  /// 是否显示星级。
  final bool showRating;

  /// 是否显示标签。
  final bool showTags;

  /// 是否显示简介。
  final bool showDescription;

  /// 简介显示行数。
  final int descriptionLines;

  /// 是否显示书评。
  final bool showReview;

  /// 书评显示行数。
  final int reviewLines;

  /// 多选模式：点击/长按切换选中，而不是打开或管理。
  final bool selectionMode;

  /// 当前是否被选中。
  final bool selected;

  /// 切换选中状态。
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = item.book;
    final hasProgress = item.percent > 0;
    final muted = theme.colorScheme.onSurfaceVariant;
    final description = book.description?.trim() ?? '';
    final reviews = decodeBookReviews(book.review);
    final review = reviews.isEmpty ? '' : reviews.first;
    final thumbRadius = coverRadius > 12 ? 12.0 : coverRadius;
    final scheme = theme.colorScheme;
    final selecting = selectionMode;
    final toggle = onSelect;

    return PressableScale(
      onTap: selecting ? (toggle ?? onOpen) : onOpen,
      onLongPress: selecting ? (toggle ?? onManage) : onManage,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: selecting && selected
            ? scheme.primaryContainer.withValues(alpha: 0.45)
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          // 行高跟随文字列（大字号/多标签时不裁字），封面固定 56×78
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (selecting) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _SelectionBadge(selected: selected),
                    ),
                  ),
                ],
                // 缩略图也挂定位探针：点它打开书时转场从缩略图展开
                Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 56,
                    height: 78,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(thumbRadius),
                      child: BookCoverRectProbe(
                        kind: BookLaunchKind.card,
                        bookId: book.id,
                        solid: theme.colorScheme.surfaceContainerHighest,
                        child: _Cover(path: book.coverPath),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          if (book.pinnedAt != null)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.push_pin, size: 13),
                            ),
                          if (!selecting)
                            IconButton(
                              tooltip: '编辑书籍信息',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 30,
                              ),
                              onPressed: onManage,
                              icon: const Icon(Icons.more_horiz, size: 18),
                            ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              book.author ?? '未知作者',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                              ),
                            ),
                          ),
                          if (showRating && (book.rating ?? 0) > 0)
                            _RatingStars(rating: book.rating!),
                        ],
                      ),
                      if (showTags && book.tags.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        _TagLine(tags: book.tags),
                      ],
                      if (showDescription && description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          maxLines: descriptionLines,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            height: 1.35,
                          ),
                        ),
                      ],
                      if (showReview && review.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _ReviewLine(text: review, maxLines: reviewLines),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              // 同网格卡片：未读时画空轨道而不是不定值动画
                              value: item.percent.clamp(0, 1),
                              minHeight: 3,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            hasProgress
                                ? '${(item.percent * 100).round()}%'
                                : '未读',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: muted,
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
        ),
      ),
    );
  }
}

/// 列表行里的书评：引号图标 + 指定行数的正文。
class _ReviewLine extends StatelessWidget {
  const _ReviewLine({required this.text, required this.maxLines});

  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.format_quote_rounded,
            size: 14,
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// 封面模式的一格：只有封面图。
class BookCoverTile extends StatelessWidget {
  const BookCoverTile({
    required this.item,
    required this.onOpen,
    required this.onManage,
    this.coverRadius = 20,
    this.showProgress = true,
    this.selectionMode = false,
    this.selected = false,
    this.onSelect,
    super.key,
  });

  /// 展示数据。
  final ShelfItem item;

  /// 打开书籍回调。
  final VoidCallback onOpen;

  /// 编辑信息回调（长按）。
  final VoidCallback onManage;

  /// 封面圆角（书架设置，0..24）。
  final double coverRadius;

  /// 封面右上角是否显示圆形阅读进度。
  final bool showProgress;

  /// 多选模式：点击/长按切换选中，而不是打开或管理。
  final bool selectionMode;

  /// 当前是否被选中。
  final bool selected;

  /// 切换选中状态。
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selecting = selectionMode;
    final toggle = onSelect;
    return PressableScale(
      onTap: selecting ? (toggle ?? onOpen) : onOpen,
      onLongPress: selecting ? (toggle ?? onManage) : onManage,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(coverRadius),
            child: BookCoverRectProbe(
              kind: BookLaunchKind.card,
              bookId: item.book.id,
              solid: theme.colorScheme.surfaceContainerHighest,
              child: _Cover(path: item.book.coverPath),
            ),
          ),
          if (!selecting && showProgress && item.percent > 0)
            Positioned(
              right: 6,
              top: 6,
              child: BookProgressBadge(
                key: ValueKey('book-progress-${item.book.id}'),
                percent: item.percent,
              ),
            ),
          if (selecting) ...[
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(coverRadius),
                    border: Border.all(
                      color: selected
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 6,
              top: 6,
              child: _SelectionBadge(selected: selected),
            ),
          ],
        ],
      ),
    );
  }
}

/// 多选角标：未选为空心圆，已选为实心对勾。
class _SelectionBadge extends StatelessWidget {
  const _SelectionBadge({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : Colors.black.withValues(alpha: 0.45),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Icon(
        selected ? Icons.check : Icons.circle_outlined,
        size: 16,
        color: selected ? scheme.onPrimary : Colors.white,
      ),
    );
  }
}
