/// 「笔记漫游」：全库划线 / 书签的卡片式回顾，左右滑动翻页。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../domain/entities/annotation.dart';
import '../../domain/entities/book.dart';
import '../../domain/entities/bookmark.dart';
import '../../domain/entities/reading_stats.dart';
import '../my_reading/my_reading_page.dart';
import '../shelf/shelf_controller.dart';
import 'notes_data.dart';
import 'annotation_share_sheet.dart';
import 'notes_providers.dart';

/// 笔记漫游页。
class NotesWanderPage extends ConsumerStatefulWidget {
  const NotesWanderPage({this.initialBookId, super.key});

  /// 从某本书进入时只漫游这本书；null = 全部。
  final String? initialBookId;

  @override
  ConsumerState<NotesWanderPage> createState() => _NotesWanderPageState();
}

class _NotesWanderPageState extends ConsumerState<NotesWanderPage> {
  final PageController _pageController = PageController(viewportFraction: 0.88);
  NoteKind? _kind;
  String? _bookFilter;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _bookFilter = widget.initialBookId;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 卡片式分享一条笔记 / 划线 / 书签。
  void _shareCard(NoteEntry entry, ShelfItem item) {
    final quote =
        entry.kind == NoteKind.bookmark &&
            entry.chapterIndex != null &&
            (entry.quote == null || entry.quote == '书签')
        ? '第 ${entry.chapterIndex! + 1} 章 · 书签'
        : (entry.quote ?? entry.label ?? '');
    unawaited(
      showAnnotationShareSheet(
        context,
        AnnotationCardData(
          quote: quote,
          note: entry.note,
          bookTitle: item.book.title,
          author: item.book.author,
          createdAt: entry.createdAt.millisecondsSinceEpoch,
          colorToken: entry.colorToken,
          kindLabel: entry.kind.label,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items =
        ref.watch(shelfItemsProvider).valueOrNull ?? const <ShelfItem>[];
    final annotations =
        ref.watch(allAnnotationsProvider).valueOrNull ?? const [];
    final bookmarks = ref.watch(allBookmarksProvider).valueOrNull ?? const [];
    final entries = noteEntries(
      items: items,
      annotations: annotations,
      bookmarks: bookmarks,
      kind: _kind,
      bookId: _bookFilter,
    );
    final books = {for (final item in items) item.book.id: item};
    final page = entries.isEmpty ? 0 : _page.clamp(0, entries.length - 1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记漫游'),
        actions: [
          IconButton(
            tooltip: '按书籍筛选',
            onPressed: () => _pickBook(items, annotations, bookmarks),
            icon: const Icon(Icons.filter_list),
          ),
          IconButton(
            tooltip: '返回笔记列表',
            onPressed: _backToOverview,
            icon: const Icon(Icons.grid_view_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                _KindChip(
                  key: const ValueKey('notes-kind-all'),
                  label: '全部',
                  selected: _kind == null,
                  onTap: () => _setKind(null),
                ),
                const SizedBox(width: 8),
                _KindChip(
                  key: const ValueKey('notes-kind-highlight'),
                  label: '划线',
                  selected: _kind == NoteKind.highlight,
                  onTap: () => _setKind(NoteKind.highlight),
                ),
                const SizedBox(width: 8),
                _KindChip(
                  key: const ValueKey('notes-kind-bookmark'),
                  label: '书签',
                  selected: _kind == NoteKind.bookmark,
                  onTap: () => _setKind(NoteKind.bookmark),
                ),
                const Spacer(),
                if (_bookFilter != null)
                  Flexible(
                    child: Text(
                      books[_bookFilter]?.book.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const _EmptyWander()
                : PageView.builder(
                    key: const ValueKey('notes-wander-pages'),
                    controller: _pageController,
                    itemCount: entries.length,
                    onPageChanged: (index) => setState(() => _page = index),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final item = books[entry.bookId];
                      if (item == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 12,
                        ),
                        child: _NoteCard(
                          entry: entry,
                          item: item,
                          onOpenBook: () => _openBook(entry.bookId),
                          onShare: () => _shareCard(entry, item),
                        ),
                      );
                    },
                  ),
          ),
          SizedBox(
            height: 34,
            child: Center(
              child: Text(
                entries.isEmpty ? '0 / 0' : '${page + 1} / ${entries.length}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _setKind(NoteKind? kind) {
    setState(() {
      _kind = kind;
      _page = 0;
    });
    if (_pageController.hasClients) _pageController.jumpToPage(0);
  }

  void _backToOverview() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(kNotesPath);
    }
  }

  Future<void> _pickBook(
    List<ShelfItem> items,
    List<Annotation> annotations,
    List<Bookmark> bookmarks,
  ) async {
    final totals =
        ref.read(myReadingTotalsProvider).valueOrNull ??
        const <String, BookReadingTotal>{};
    final summaries = notesBookSummaries(
      items: items,
      annotations: annotations,
      bookmarks: bookmarks,
      totals: totals,
    );
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.6,
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '按书籍筛选',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    ListTile(
                      leading: Icon(
                        _bookFilter == null
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      title: const Text('全部书籍'),
                      onTap: () => Navigator.of(context).pop(''),
                    ),
                    for (final summary in summaries)
                      ListTile(
                        leading: Icon(
                          _bookFilter == summary.book.id
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        title: Text(
                          summary.book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text('${summary.count} 条'),
                        onTap: () => Navigator.of(context).pop(summary.book.id),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _bookFilter = picked.isEmpty ? null : picked;
      _page = 0;
    });
    if (_pageController.hasClients) _pageController.jumpToPage(0);
  }

  void _openBook(String bookId) {
    unawaited(
      ref
          .read(bookRepositoryProvider.future)
          .then((repo) => repo.touchOpened(bookId)),
    );
    unawaited(context.push(readerPath(bookId)));
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? (Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : const Color(0xFF1C1C1E))
          : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? (Theme.of(context).brightness == Brightness.dark
                        ? Colors.black
                        : Colors.white)
                  : scheme.onSurface.withValues(alpha: 0.65),
              fontSize: 15,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.entry,
    required this.item,
    required this.onOpenBook,
    required this.onShare,
  });

  final NoteEntry entry;
  final ShelfItem item;
  final VoidCallback onOpenBook;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final quote =
        entry.kind == NoteKind.bookmark &&
            entry.chapterIndex != null &&
            (entry.quote == null || entry.quote == '书签')
        ? '第 ${entry.chapterIndex! + 1} 章 · 书签'
        : (entry.quote ?? entry.label ?? '');

    return Material(
      key: ValueKey('note-card-${entry.id}'),
      color: theme.cardColor,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    entry.kind.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  noteTimeLabel(entry.createdAt),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                // 紧凑分享按钮（卡片头部空间有限）
                InkResponse(
                  key: ValueKey('note-share-${entry.id}'),
                  onTap: onShare,
                  radius: 16,
                  child: Icon(
                    Icons.ios_share_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              quote,
              maxLines: 7,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 22,
                height: 1.55,
                fontWeight: FontWeight.w400,
              ),
            ),
            if (entry.note != null) ...[
              const SizedBox(height: 20),
              Text(
                '笔记',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                entry.note!,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.55,
                  color: scheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ],
            const Spacer(),
            const Divider(height: 24),
            InkWell(
              onTap: onOpenBook,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    _BookCover(item: item),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.book.author?.trim().isNotEmpty == true
                                ? item.book.author!.trim()
                                : '未知作者',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 22),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.item});

  final ShelfItem item;

  @override
  Widget build(BuildContext context) {
    final path = item.book.coverPath ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        width: 50,
        height: 72,
        child: path.isEmpty
            ? _placeholder()
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(),
              ),
      ),
    );
  }

  Widget _placeholder() => ColoredBox(
    color: const Color(0xFF8A8F98).withValues(alpha: 0.18),
    child: const Center(
      child: Icon(Icons.menu_book_outlined, color: Color(0xFF8A8F98), size: 18),
    ),
  );
}

class _EmptyWander extends StatelessWidget {
  const _EmptyWander();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.style_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('这里还没有笔记', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '阅读时划线或添加书签，就能在这里一张张回顾',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
