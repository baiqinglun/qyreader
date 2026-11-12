/// 目录抽屉：目录 / 书签 / 标注三 Tab，条目 stagger，当前章高亮。
library;

import 'package:flutter/material.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/reading_theme.dart';
import '../../../core/locator.dart';
import '../../../domain/entities/annotation.dart';
import '../../../domain/entities/book.dart';
import '../../../domain/entities/bookmark.dart';
import 'annotation_tab.dart';

/// 目录抽屉。
class TocDrawer extends StatelessWidget {
  const TocDrawer({
    required this.open,
    required this.theme,
    required this.chapters,
    required this.currentHref,
    required this.bookmarks,
    required this.annotations,
    required this.onDismiss,
    required this.onChapter,
    required this.onGotoLocator,
    required this.onDeleteBookmark,
    required this.onDeleteAnnotation,
    required this.onEditNote,
    required this.onExport,
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

  /// 书签列表。
  final List<Bookmark> bookmarks;

  /// 标注列表。
  final List<Annotation> annotations;

  /// 点击遮罩关闭。
  final VoidCallback onDismiss;

  /// 点击章节跳转。
  final void Function(String href) onChapter;

  /// 跳转到 locator（书签/标注）。
  final void Function(String locatorJson) onGotoLocator;

  /// 删除书签。
  final void Function(String id) onDeleteBookmark;

  /// 删除标注。
  final void Function(String id) onDeleteAnnotation;

  /// 给标注添加/编辑想法。
  final void Function(Annotation annotation) onEditNote;

  /// 导出 Markdown。
  final VoidCallback onExport;

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
                  width: MediaQuery.sizeOf(context).width * 0.82,
                  child: _Panel(
                    theme: theme,
                    chapters: chapters,
                    currentHref: currentHref,
                    bookmarks: bookmarks,
                    annotations: annotations,
                    onDismiss: onDismiss,
                    onChapter: onChapter,
                    onGotoLocator: onGotoLocator,
                    onDeleteBookmark: onDeleteBookmark,
                    onDeleteAnnotation: onDeleteAnnotation,
                    onEditNote: onEditNote,
                    onExport: onExport,
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
    required this.bookmarks,
    required this.annotations,
    required this.onDismiss,
    required this.onChapter,
    required this.onGotoLocator,
    required this.onDeleteBookmark,
    required this.onDeleteAnnotation,
    required this.onEditNote,
    required this.onExport,
  });

  final ReadingTheme theme;
  final List<BookChapter> chapters;
  final String? currentHref;
  final List<Bookmark> bookmarks;
  final List<Annotation> annotations;
  final VoidCallback onDismiss;
  final void Function(String href) onChapter;
  final void Function(String locatorJson) onGotoLocator;
  final void Function(String id) onDeleteBookmark;
  final void Function(String id) onDeleteAnnotation;
  final void Function(Annotation annotation) onEditNote;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Material(
      color: theme.chromeSurface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, padding.top, 0, padding.bottom),
        child: DefaultTabController(
          length: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
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
              TabBar(
                labelColor: theme.accent,
                unselectedLabelColor:
                    theme.chromeForeground.withValues(alpha: 0.6),
                indicatorColor: theme.accent,
                tabs: const [
                  Tab(text: '目录'),
                  Tab(text: '书签'),
                  Tab(text: '标注'),
                ],
              ),
              Divider(height: 1, color: theme.chromeForeground.withValues(alpha: 0.1)),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildToc(),
                    _buildBookmarks(),
                    _buildAnnotations(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToc() {
    return chapters.isEmpty
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
          );
  }

  Widget _buildBookmarks() {
    if (bookmarks.isEmpty) {
      return Center(
        child: Text(
          '点底栏书签图标标记本页',
          style: TextStyle(
            color: theme.chromeForeground.withValues(alpha: 0.6),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: bookmarks.length,
      itemBuilder: (context, index) {
        final bm = bookmarks[index];
        final loc = locatorFromJson(bm.locator);
        final label = bm.label ?? '书签 ${bookmarks.length - index}';
        final subtitle = loc?.href ?? '';
        return Dismissible(
          key: ValueKey(bm.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.redAccent,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          onDismissed: (_) => onDeleteBookmark(bm.id),
          child: ListTile(
            leading: Icon(
              Icons.bookmark,
              color: theme.accent,
              size: 22,
            ),
            title: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.chromeForeground, fontSize: 14),
            ),
            subtitle: subtitle.isEmpty
                ? null
                : Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.chromeForeground.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
            onTap: () => onGotoLocator(bm.locator),
          ),
        );
      },
    );
  }

  Widget _buildAnnotations() {
    return AnnotationTab(
      theme: theme,
      chapters: chapters,
      annotations: annotations,
      onGotoLocator: onGotoLocator,
      onDelete: onDeleteAnnotation,
      onEditNote: onEditNote,
      onExport: onExport,
    );
  }

}

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
