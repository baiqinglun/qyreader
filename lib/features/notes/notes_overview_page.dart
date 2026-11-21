/// 「笔记」概览：按书汇总划线 / 书签，进入卡片式漫游。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../domain/entities/book.dart';
import '../../domain/entities/reading_stats.dart';
import '../my_reading/my_reading_page.dart';
import '../shelf/shelf_controller.dart';
import 'notes_data.dart';
import 'notes_providers.dart';

/// 笔记概览页。
class NotesOverviewPage extends ConsumerStatefulWidget {
  const NotesOverviewPage({super.key});

  @override
  ConsumerState<NotesOverviewPage> createState() => _NotesOverviewPageState();
}

class _NotesOverviewPageState extends ConsumerState<NotesOverviewPage> {
  final TextEditingController _search = TextEditingController();
  NotesBookSort _sort = NotesBookSort.recent;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items =
        ref.watch(shelfItemsProvider).valueOrNull ?? const <ShelfItem>[];
    final annotations =
        ref.watch(allAnnotationsProvider).valueOrNull ?? const [];
    final bookmarks = ref.watch(allBookmarksProvider).valueOrNull ?? const [];
    final totals =
        ref.watch(myReadingTotalsProvider).valueOrNull ??
        const <String, BookReadingTotal>{};
    final totalNotes = annotations.length + bookmarks.length;
    final summaries = notesBookSummaries(
      items: items,
      annotations: annotations,
      bookmarks: bookmarks,
      totals: totals,
      sort: _sort,
      query: _search.text,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('笔记'),
        actions: [
          IconButton(
            key: const ValueKey('notes-wander-button'),
            tooltip: '笔记漫游',
            onPressed: () => _openWander(),
            icon: const Icon(Icons.auto_awesome_motion_outlined),
          ),
          PopupMenuButton<NotesBookSort>(
            tooltip: '排序',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (_) => [
              for (final sort in NotesBookSort.values)
                PopupMenuItem(value: sort, child: Text(sort.label)),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'wander') {
                _openWander();
              } else if (value == 'reading') {
                unawaited(context.push(kMyReadingPath));
              } else if (value == 'refresh') {
                ref.invalidate(myReadingTotalsProvider);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'wander', child: Text('全部笔记漫游')),
              PopupMenuItem(value: 'reading', child: Text('打开我的阅读')),
              PopupMenuItem(value: 'refresh', child: Text('刷新阅读数据')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const ValueKey('notes-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '搜索 $totalNotes 条笔记',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: theme.brightness == Brightness.dark
                    ? scheme.surfaceContainerHigh
                    : const Color(0xFFE9EBF1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ),
          Expanded(
            child: summaries.isEmpty
                ? _EmptyNotes(
                    hasNotes: totalNotes > 0,
                    searching: _search.text.trim().isNotEmpty,
                  )
                : ListView.builder(
                    key: const ValueKey('notes-book-list'),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    itemCount: summaries.length,
                    itemBuilder: (context, index) {
                      final summary = summaries[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _NotesBookCard(
                          summary: summary,
                          onTap: () => _openWander(summary.book.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _openWander([String? bookId]) {
    unawaited(context.push(kNotesWanderPath, extra: bookId));
  }
}

class _NotesBookCard extends StatelessWidget {
  const _NotesBookCard({required this.summary, required this.onTap});

  final NotesBookSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: ValueKey('notes-book-${summary.book.id}'),
      color: theme.cardColor,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${summary.count} 条笔记',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      summary.book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      notesReadLabel(summary.durationMs, summary.charsRead),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (summary.highlightCount > 0 &&
                        summary.bookmarkCount > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '划线 ${summary.highlightCount} · '
                        '书签 ${summary.bookmarkCount}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _NotesCover(summary: summary),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotesCover extends StatelessWidget {
  const _NotesCover({required this.summary});

  final NotesBookSummary summary;

  @override
  Widget build(BuildContext context) {
    final path = summary.book.coverPath ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 64,
        height: 92,
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
      child: Icon(Icons.menu_book_outlined, color: Color(0xFF8A8F98), size: 22),
    ),
  );
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes({required this.hasNotes, required this.searching});

  final bool hasNotes;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.edit_note_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            !hasNotes ? '还没有笔记' : (searching ? '没有找到匹配的笔记' : '还没有笔记'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            hasNotes ? '换个书名、作者或原文片段试试' : '在阅读时长按选字，划线或添加书签',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
