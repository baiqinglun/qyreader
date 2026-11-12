/// 顶部竖排书架：最近在读的书以「书脊」形式立在一块木质架板上。
///
/// 书脊是纯 Flutter 绘制（渐变 + 竖排标题），不依赖封面图：
/// - 封面尺寸/比例五花八门，直接贴上去当书脊会花；
/// - 竖排书名在任何主题下都能读，且一眼能扫到最近读的是哪几本。
///
/// 书多时横向滚动，不挤压下面的网格。
library;

import 'package:flutter/material.dart';

import '../../../app/transitions/book_open_transition.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../domain/entities/book.dart';

/// 最近在读竖排架。
class RecentShelf extends StatelessWidget {
  const RecentShelf({
    required this.items,
    required this.onOpen,
    required this.onManage,
    required this.onHide,
    super.key,
  });

  /// 最近在读（已按最近打开倒序）。
  final List<ShelfItem> items;

  /// 点书脊打开书籍。
  final void Function(Book book) onOpen;

  /// 长按书脊编辑（评分/标签/置顶）。
  final void Function(Book book) onManage;

  /// 收起竖排架。
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 6, 0),
          child: Row(
            children: [
              Icon(
                Icons.auto_stories_outlined,
                size: 15,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text('最近在读', style: theme.textTheme.titleSmall),
              const SizedBox(width: 6),
              Text(
                '${items.length} 本',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '隐藏最近在读',
                visualDensity: VisualDensity.compact,
                onPressed: onHide,
                icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 176,
          child: Stack(
            children: [
              // 木质架板：整条铺满，书脊全部立在它上沿
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ShelfBoard(),
              ),
              Positioned.fill(
                // 底部让出架板高度，书脊脚正好落在架板上沿
                bottom: 11,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 3),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Align(
                      alignment: Alignment.bottomCenter,
                      child: PressableScale(
                        onTap: () => onOpen(item.book),
                        onLongPress: () => onManage(item.book),
                        child: _BookSpine(item: item),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 收起后的入口条：一行小按钮，点一下恢复竖排架。
class CollapsedRecentShelf extends StatelessWidget {
  const CollapsedRecentShelf({
    required this.count,
    required this.onShow,
    super.key,
  });

  /// 最近在读本数。
  final int count;

  /// 展开竖排架。
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onShow,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 12.5),
          ),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          label: Text('最近在读 · $count 本'),
        ),
      ),
    );
  }
}

/// 木质架板（顶部亮线 + 木色渐变 + 底部投影）。
class _ShelfBoard extends StatelessWidget {
  const _ShelfBoard();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF6E4A2C), Color(0xFF32200F)]
              : const [Color(0xFFB98A55), Color(0xFF6F4A28)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          height: 1.2,
          color: Colors.white.withValues(alpha: 0.28),
        ),
      ),
    );
  }
}

/// 单本书的书脊。
class _BookSpine extends StatelessWidget {
  const _BookSpine({required this.item});

  final ShelfItem item;

  /// 书脊配色：深色系，明暗主题下白字都清晰。
  static const List<Color> _palette = [
    Color(0xFF8C2F39), // 酒红
    Color(0xFF2F4A6D), // 藏蓝
    Color(0xFF3F6B4E), // 墨绿
    Color(0xFF6B4A7A), // 紫
    Color(0xFF8A6A3B), // 褐金
    Color(0xFF2E7D6B), // 青
    Color(0xFFB5651D), // 赭
    Color(0xFF4A4A55), // 石墨
    Color(0xFF7A3B5E), // 绛
    Color(0xFF35617A), // 灰蓝
    Color(0xFF5C6B3C), // 橄榄
    Color(0xFF6E3B2F), // 砖
    Color(0xFF44506B), // 靛
    Color(0xFF9A5B34), // 铜
  ];

  @override
  Widget build(BuildContext context) {
    final title = item.book.title.trim().isEmpty ? '无题' : item.book.title;
    final seed = title.hashCode.abs();
    final base = _palette[seed % _palette.length];
    // 宽度/高度按书名散列做小幅变化，一排书看起来才有长短厚薄
    final width = 30.0 + (seed % 3) * 4;
    final height = 128.0 + ((seed ~/ 3) % 3) * 10;

    const fontSize = 10.5;
    const lineHeight = 1.14;
    // 竖排每字占「字号 × 行高」，按书脊高度算最多能放几个字（留出饰线与内边距）
    final maxChars = ((height - 26) / (fontSize * lineHeight)).floor();

    final Widget titleWidget = _hasCjk(title)
        ? _VerticalTitle(
            text: title,
            maxChars: maxChars,
            fontSize: fontSize,
            lineHeight: lineHeight,
          )
        : RotatedBox(
            quarterTurns: 1,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize + 0.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: Colors.white.withValues(alpha: 0.94),
              ),
            ),
          );

    final gradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Color.lerp(base, Colors.black, 0.34)!,
        base,
        Color.lerp(base, Colors.white, 0.12)!,
      ],
      stops: const [0, 0.42, 1],
    );

    // 书脊挂在定位探针里：打开书的转场要知道这根书脊在屏幕上的位置
    // （关书时按最新位置收回；打开一本书会让「最近在读」重排）。
    return BookCoverRectProbe(
      kind: BookLaunchKind.spine,
      bookId: item.book.id,
      gradient: gradient,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2.5)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2A000000),
              blurRadius: 3,
              offset: Offset(1, 0),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(3, 6, 3, 6),
          child: Column(
            children: [
              _spineRule(),
              const SizedBox(height: 5),
              Expanded(child: Center(child: titleWidget)),
              const SizedBox(height: 5),
              _spineRule(),
            ],
          ),
        ),
      ),
    );
  }

  /// 书脊上下两端的压印饰线。
  Widget _spineRule() => Container(
        height: 1,
        color: Colors.white.withValues(alpha: 0.22),
      );
}

/// 逐字竖排的书名（中文/日文/韩文）。
class _VerticalTitle extends StatelessWidget {
  const _VerticalTitle({
    required this.text,
    required this.maxChars,
    required this.fontSize,
    required this.lineHeight,
  });

  final String text;

  /// 最多放几个字（超出用省略号）。
  final int maxChars;

  final double fontSize;
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    final chars = text.characters.toList();
    final limit = maxChars.clamp(1, 40);
    final clipped = chars.length > limit
        ? <String>[...chars.take(limit - 1), '…']
        : chars;
    final style = TextStyle(
      fontSize: fontSize,
      height: lineHeight,
      fontWeight: FontWeight.w600,
      color: Colors.white.withValues(alpha: 0.94),
      shadows: const [
        Shadow(
          color: Color(0x40000000),
          blurRadius: 1,
          offset: Offset(0, 0.5),
        ),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final ch in clipped) Text(ch, style: style),
      ],
    );
  }
}

/// 标题是否含中日韩字符（决定竖排方式：逐字堆叠 vs 整行旋转）。
bool _hasCjk(String text) => _cjkPattern.hasMatch(text);

final RegExp _cjkPattern = RegExp(
  r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\u3040-\u30FF\uAC00-\uD7AF]',
);
