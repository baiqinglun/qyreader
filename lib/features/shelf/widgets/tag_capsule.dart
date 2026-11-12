/// 彩色胶囊标签：同一标签名在任何地方颜色一致，明暗主题各一套可读配色。
///
/// 颜色由标签名散列到色相，不落库（标签本身是用户数据，颜色只是呈现）；
/// 这样不需要维护「标签 → 颜色」的额外配置，新增标签自动有颜色。
library;

import 'package:flutter/material.dart';

/// 胶囊标签的配色。
@immutable
class TagColors {
  const TagColors({
    required this.background,
    required this.foreground,
    required this.border,
  });

  /// 底色（浅色主题是淡彩，深色主题是暗彩）。
  final Color background;

  /// 文字/图标颜色。
  final Color foreground;

  /// 描边颜色。
  final Color border;
}

/// 标签名 → 胶囊配色（同一名称恒定）。
TagColors tagColorsOf(String tag, Brightness brightness) {
  // 色相候选：红/橙/琥珀/绿/青/蓝/靛/紫/粉/棕…，避免灰调
  const hues = <double>[
    0,
    16,
    36,
    52,
    92,
    132,
    158,
    182,
    204,
    226,
    252,
    278,
    304,
    332,
  ];
  final seed = tag.hashCode.abs();
  final hue =
      (hues[seed % hues.length] + (seed ~/ hues.length % 10) * 1.5) % 360;
  if (brightness == Brightness.dark) {
    return TagColors(
      background: HSLColor.fromAHSL(1, hue, 0.34, 0.21).toColor(),
      foreground: HSLColor.fromAHSL(1, hue, 0.58, 0.80).toColor(),
      border: HSLColor.fromAHSL(0.5, hue, 0.45, 0.46).toColor(),
    );
  }
  return TagColors(
    background: HSLColor.fromAHSL(1, hue, 0.62, 0.945).toColor(),
    foreground: HSLColor.fromAHSL(1, hue, 0.56, 0.31).toColor(),
    border: HSLColor.fromAHSL(0.3, hue, 0.5, 0.55).toColor(),
  );
}

/// 胶囊标签。
class TagCapsule extends StatelessWidget {
  const TagCapsule({
    required this.tag,
    this.count,
    this.compact = false,
    this.large = false,
    this.selected = false,
    this.showAdd = false,
    this.onTap,
    this.onDeleted,
    super.key,
  });

  /// 标签名。
  final String tag;

  /// 右侧数量（标签管理/筛选用；普通展示留空）。
  final int? count;

  /// 紧凑尺寸（书架卡片/列表行用）。
  final bool compact;

  /// 大号胶囊（标签管理页用，接近参考稿的整行药丸）。
  final bool large;

  /// 选中态（编辑面板里当前选中的标签）。
  final bool selected;

  /// 前置图标用「+」（可添加的推荐标签）。
  final bool showAdd;

  /// 点击回调（null = 仅展示）。
  final VoidCallback? onTap;

  /// 删除回调（非空时右侧出现小叉）。
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final colors = tagColorsOf(tag, brightness);
    final fontSize = compact ? 9.5 : (large ? 14.0 : 12.0);
    final iconSize = compact ? 9.5 : (large ? 15.0 : 12.5);
    final background = selected
        ? colors.foreground.withValues(
            alpha: brightness == Brightness.dark ? 0.30 : 0.14,
          )
        : colors.background;

    final content = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : (large ? 14 : 10),
        vertical: compact ? 2 : (large ? 7 : 4.5),
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colors.border,
          width: selected ? 1.3 : 0.9,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            showAdd ? Icons.add : Icons.bookmark_border,
            size: iconSize,
            color: colors.foreground,
          ),
          SizedBox(width: compact ? 3 : (large ? 6 : 4)),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 96 : 220),
            child: Text(
              tag,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.foreground,
                fontSize: fontSize,
                height: 1.15,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                color: colors.foreground.withValues(alpha: 0.72),
                fontSize: fontSize - 1,
                height: 1.15,
              ),
            ),
          ],
          if (onDeleted != null) ...[
            const SizedBox(width: 3),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDeleted,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close,
                  size: iconSize + 2,
                  color: colors.foreground.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: content,
    );
  }
}
