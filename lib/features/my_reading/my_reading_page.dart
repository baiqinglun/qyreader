/// 「我的阅读」：按年 / 月时间线回顾阅读记录，可生成分享海报。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../domain/entities/book.dart';
import '../../domain/entities/reading_stats.dart';
import '../../domain/repositories/stats_repository.dart';
import '../../features/shelf/shelf_controller.dart';
import 'my_reading_data.dart';
import 'reading_share_sheet.dart';

part 'my_reading_page.g.dart';

/// 所有书的累计阅读数据（时长 / 字数）。
@riverpod
Future<Map<String, BookReadingTotal>> myReadingTotals(Ref ref) async {
  final StatsRepository repo = await ref.watch(statsRepositoryProvider.future);
  final totals = await repo.bookTotals();
  return {for (final total in totals) total.bookId: total};
}

/// 我的阅读页。
class MyReadingPage extends ConsumerStatefulWidget {
  const MyReadingPage({super.key});

  @override
  ConsumerState<MyReadingPage> createState() => _MyReadingPageState();
}

class _MyReadingPageState extends ConsumerState<MyReadingPage> {
  MyReadingFilter _filter = MyReadingFilter.all;
  final TextEditingController _search = TextEditingController();
  final Set<int> _collapsedYears = <int>{};
  final Set<String> _collapsedMonths = <String>{};

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
    final totalsAsync = ref.watch(myReadingTotalsProvider);
    final totals =
        totalsAsync.valueOrNull ?? const <String, BookReadingTotal>{};
    final query = _search.text;

    final base = myReadingBooks(items: items, totals: totals, filter: _filter);
    final entries = myReadingBooks(
      items: items,
      totals: totals,
      filter: _filter,
      query: query,
    );
    final groups = groupMyReading(entries);
    final counts = {
      for (final filter in MyReadingFilter.values)
        filter: myReadingBooks(
          items: items,
          totals: totals,
          filter: filter,
        ).length,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的阅读'),
        actions: [
          IconButton(
            tooltip: '筛选阅读状态',
            onPressed: _pickFilter,
            icon: const Icon(Icons.filter_list),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'share') {
                if (entries.isNotEmpty) _share(entries);
              } else if (value == 'refresh') {
                ref.invalidate(myReadingTotalsProvider);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'share',
                enabled: entries.isNotEmpty,
                child: const Text('分享当前列表'),
              ),
              const PopupMenuItem(value: 'refresh', child: Text('刷新阅读数据')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterTabs(
            selected: _filter,
            counts: counts,
            onSelect: (filter) => setState(() => _filter = filter),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const ValueKey('my-reading-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '搜索 ${base.length} 本书',
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
            child: totalsAsync.isLoading && totals.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : groups.isEmpty
                ? _EmptyState(query: query)
                : ListView.builder(
                    key: const ValueKey('my-reading-list'),
                    padding: const EdgeInsets.fromLTRB(12, 4, 16, 32),
                    itemCount: _nodeCount(groups),
                    itemBuilder: (context, index) =>
                        _buildNode(context, groups, index),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFilter() async {
    final picked = await showModalBottomSheet<MyReadingFilter>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '阅读状态',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            for (final filter in MyReadingFilter.values)
              ListTile(
                leading: Icon(
                  filter == _filter
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(filter.label),
                onTap: () => Navigator.of(context).pop(filter),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _filter = picked);
  }

  int _nodeCount(List<MyReadingYear> groups) {
    var count = 0;
    for (final year in groups) {
      count++; // 年标题
      if (_collapsedYears.contains(year.year)) continue;
      for (final month in year.months) {
        count++; // 月标题
        if (_collapsedMonths.contains('${year.year}-${month.month}')) continue;
        count += month.books.length;
      }
    }
    return count;
  }

  Widget _buildNode(
    BuildContext context,
    List<MyReadingYear> groups,
    int index,
  ) {
    var cursor = 0;
    for (final year in groups) {
      if (index == cursor) {
        return _YearHeader(
          year: year,
          collapsed: _collapsedYears.contains(year.year),
          onToggle: () => setState(() {
            if (!_collapsedYears.remove(year.year)) {
              _collapsedYears.add(year.year);
            }
          }),
          onShare: () => _share([
            for (final month in year.months) ...month.books,
          ], title: '${year.year}年'),
        );
      }
      cursor++;
      if (_collapsedYears.contains(year.year)) continue;
      for (final month in year.months) {
        if (index == cursor) {
          final key = '${year.year}-${month.month}';
          return _MonthHeader(
            month: month,
            collapsed: _collapsedMonths.contains(key),
            onToggle: () => setState(() {
              if (!_collapsedMonths.remove(key)) _collapsedMonths.add(key);
            }),
            onShare: () => _share(month.books, title: '${month.month}月'),
          );
        }
        cursor++;
        if (_collapsedMonths.contains('${year.year}-${month.month}')) {
          continue;
        }
        for (final book in month.books) {
          if (index == cursor) {
            return _BookRow(book: book, onTap: () => _openBook(book));
          }
          cursor++;
        }
      }
    }
    return const SizedBox.shrink();
  }

  void _openBook(MyReadingBook entry) {
    unawaited(
      ref
          .read(bookRepositoryProvider.future)
          .then((repo) => repo.touchOpened(entry.book.id)),
    );
    unawaited(context.push(readerPath(entry.book.id)));
  }

  void _share(List<MyReadingBook> books, {String? title}) {
    if (books.isEmpty) return;
    unawaited(showReadingShareSheet(context, books, title: title));
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final MyReadingFilter selected;
  final Map<MyReadingFilter, int> counts;
  final ValueChanged<MyReadingFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (final filter in MyReadingFilter.values)
              InkWell(
                key: ValueKey('my-reading-filter-${filter.name}'),
                onTap: () => onSelect(filter),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            filter.label,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: filter == selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: filter == selected
                                  ? scheme.onSurface
                                  : scheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${counts[filter] ?? 0}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 3,
                        width: filter == selected ? 26 : 0,
                        decoration: BoxDecoration(
                          color: scheme.onSurface,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
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

class _YearHeader extends StatelessWidget {
  const _YearHeader({
    required this.year,
    required this.collapsed,
    required this.onToggle,
    required this.onShare,
  });

  final MyReadingYear year;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _TimelineRow(
      dotSize: 11,
      dotColor: theme.colorScheme.onSurface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 0, 4),
        child: Row(
          children: [
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Text(
                      '${year.year}年',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      collapsed
                          ? Icons.keyboard_arrow_right
                          : Icons.keyboard_arrow_down,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${year.count}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: '分享这一年',
              onPressed: onShare,
              icon: const Icon(Icons.share_outlined, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.collapsed,
    required this.onToggle,
    required this.onShare,
  });

  final MyReadingMonth month;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _TimelineRow(
      dotSize: 8,
      dotColor: theme.colorScheme.onSurface.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
        child: Row(
          children: [
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text(
                      '${month.month}月',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      collapsed
                          ? Icons.keyboard_arrow_right
                          : Icons.keyboard_arrow_down,
                      size: 18,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${month.books.length}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: '分享这个月',
              onPressed: onShare,
              icon: const Icon(Icons.share_outlined, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({required this.book, required this.onTap});

  final MyReadingBook book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _TimelineRow(
      dotSize: 6,
      dotColor: theme.brightness == Brightness.dark
          ? const Color(0xFF2A2C30)
          : Colors.white,
      dotBorder: theme.colorScheme.outlineVariant,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          myReadingHeadline(book),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          book.book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          myReadingMeta(book),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _BookCover(book: book),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.book});

  final MyReadingBook book;

  @override
  Widget build(BuildContext context) {
    final path = book.book.coverPath ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 62,
        height: 90,
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

/// 时间线一行：左侧固定宽度画竖线 + 圆点，右侧放内容。
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.child,
    required this.dotSize,
    required this.dotColor,
    this.dotBorder,
  });

  final Widget child;
  final double dotSize;
  final Color dotColor;
  final Color? dotBorder;

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.outlineVariant;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Stack(
              children: [
                Positioned(
                  left: 14,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 1,
                    color: line.withValues(alpha: 0.55),
                  ),
                ),
                Positioned(
                  left: 15 - dotSize / 2,
                  top: 18 - dotSize / 2,
                  child: Container(
                    width: dotSize,
                    height: dotSize,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: dotBorder == null
                          ? null
                          : Border.all(color: dotBorder!, width: 1.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            query.trim().isEmpty ? '还没有阅读记录' : '没有找到匹配的书',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            query.trim().isEmpty ? '打开一本书，这里就会留下时间线' : '换个书名或作者试试',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
