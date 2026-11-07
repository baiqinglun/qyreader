/// 目录抽屉：左滑入，条目 stagger，当前章高亮。
library;

import 'package:flutter/material.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/reading_theme.dart';
import '../../../domain/entities/book.dart';

/// 目录抽屉。
class TocDrawer extends StatelessWidget {
  const TocDrawer({
    required this.open,
    required this.theme,
    required this.chapters,
    required this.currentHref,
    required this.onDismiss,
    required this.onChapter,
    super.key,
  });

  /// 是否展开。
  final bool open;

  /// 阅读主题（配色跟随）。
  final ReadingTheme theme;

  /// 章节列表。
  final List<BookChapter> chapters;

  /// 当前可视页 href（高亮当前章）。
  final String? currentHref;

  /// 点击遮罩关闭。
  final VoidCallback onDismiss;

  /// 点击章节跳转。
  final void Function(String href) onChapter;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: context.motion.standard,
      child: open
          ? Stack(
              key: const ValueKey('toc-open'),
              children: [
                // 遮罩
                Positioned.fill(
                  child: GestureDetector(
                    onTap: onDismiss,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                // 面板
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: 0,
                  width: MediaQuery.sizeOf(context).width * 0.78,
                  child: _Panel(
                    theme: theme,
                    chapters: chapters,
                    currentHref: currentHref,
                    onDismiss: onDismiss,
                    onChapter: onChapter,
                  ),
                ),
              ],
            )
          : const SizedBox.shrink(key: ValueKey('toc-closed')),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.theme,
    required this.chapters,
    required this.currentHref,
    required this.onDismiss,
    required this.onChapter,
  });

  final ReadingTheme theme;
  final List<BookChapter> chapters;
  final String? currentHref;
  final VoidCallback onDismiss;
  final void Function(String href) onChapter;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Material(
      color: theme.chromeSurface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, padding.top, 0, padding.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Text(
                    '目录',
                    style: TextStyle(
                      color: theme.chromeForeground,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onDismiss,
                    icon: Icon(Icons.close, color: theme.chromeForeground),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: chapters.isEmpty
                  ? Center(
                      child: Text(
                        '本书没有目录信息',
                        style: TextStyle(color: theme.chromeForeground),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: chapters.length,
                      itemBuilder: (context, index) {
                        final chapter = chapters[index];
                        final isCurrent = chapter.href == currentHref;
                        return _AnimatedRow(
                          index: index,
                          child: _ChapterRow(
                            chapter: chapter,
                            isCurrent: isCurrent,
                            theme: theme,
                            onTap: () => onChapter(chapter.href),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 条目 stagger 淡入（每条 +12ms，封顶 300ms）。
class _AnimatedRow extends StatelessWidget {
  const _AnimatedRow({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    final delayMs = (index * 12).clamp(0, 300);
    final total = motion.standard + Duration(milliseconds: delayMs);
    final begin = delayMs / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(begin, 1, curve: motion.enter),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(-16 * (1 - value), 0),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.chapter,
    required this.isCurrent,
    required this.theme,
    required this.onTap,
  });

  final BookChapter chapter;
  final bool isCurrent;
  final ReadingTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = theme.chromeForeground;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(
          left: 16.0 + chapter.level * 16,
          right: 16,
          top: 12,
          bottom: 12,
        ),
        child: Row(
          children: [
            // 当前章左侧竖条 0→3px
            TweenAnimationBuilder<double>(
              tween: Tween(end: isCurrent ? 3 : 0),
              duration: context.motion.quick,
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => Container(
                width: value,
                height: 16,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: theme.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Expanded(
              child: Text(
                chapter.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isCurrent ? theme.accent : fg,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
