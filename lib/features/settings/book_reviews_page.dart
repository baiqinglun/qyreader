/// 我的书评：书评与评分汇总（书籍详情 / Reeden 导入写入 books.review）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../domain/entities/book.dart';
import '../../features/home/widgets/cover_thumb.dart';
import '../../features/shelf/shelf_controller.dart';

/// 我的书评页。
class BookReviewsPage extends ConsumerStatefulWidget {
  const BookReviewsPage({super.key});

  @override
  ConsumerState<BookReviewsPage> createState() => _BookReviewsPageState();
}

class _BookReviewsPageState extends ConsumerState<BookReviewsPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = ref.watch(shelfItemsProvider).valueOrNull ??
        const <ShelfItem>[];
    // 有书评的书（新读完的在前）。
    final reviewed = [
      for (final item in items)
        if ((item.book.review ?? '').trim().isNotEmpty) item,
    ]..sort((a, b) => _dateOf(b.book).compareTo(_dateOf(a.book)));
    final query = _query.trim().toLowerCase();
    final matched = query.isEmpty
        ? reviewed
        : [
            for (final item in reviewed)
              if (item.book.title.toLowerCase().contains(query) ||
                  (item.book.author ?? '').toLowerCase().contains(query) ||
                  (item.book.review ?? '').toLowerCase().contains(query))
                item,
          ];

    return Scaffold(
      appBar: AppBar(title: const Text('我的书评')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              key: const ValueKey('book-reviews-search'),
              decoration: InputDecoration(
                hintText:
                    reviewed.isEmpty ? '还没有书评' : '搜索 ${reviewed.length} 条书评',
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _query = ''),
                      ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: matched.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        reviewed.isEmpty
                            ? '还没有书评\n在书籍详情里写下书评，或导入 Reeden 数据'
                            : '没有匹配的书评',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: matched.length,
                    itemBuilder: (context, index) => _ReviewCard(
                      item: matched[index],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static int _dateOf(Book book) =>
      book.finishedAt ?? book.lastOpenedAt ?? book.updatedAt;
}

/// 一条书评卡片：标题 / 作者 / 星级 / 日期 / 书评全文（可展开）/ 封面。
class _ReviewCard extends StatefulWidget {
  const _ReviewCard({required this.item});

  final ShelfItem item;

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final book = widget.item.book;
    final review = (book.review ?? '').trim();
    final dateMs = book.finishedAt ?? book.lastOpenedAt ?? book.updatedAt;
    final date = DateTime.fromMillisecondsSinceEpoch(dateMs);
    final dateLabel =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(bookDetailPath(book.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            book.author ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (book.rating != null) ...[
                          const SizedBox(width: 8),
                          _Stars(rating: book.rating!),
                          const SizedBox(width: 4),
                          Text(
                            '${book.rating}',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      dateLabel,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      review,
                      maxLines: _expanded ? null : 5,
                      overflow: _expanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, height: 1.5),
                    ),
                    if (review.length > 60)
                      GestureDetector(
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _expanded ? '收起' : '展开',
                            style: TextStyle(
                              color: scheme.primary,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              CoverThumb(
                path: book.coverPath,
                width: 64,
                height: 90,
                radius: 8,
                shadow: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 五星显示（整数评分）。
class _Stars extends StatelessWidget {
  const _Stars({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 16,
            color: i <= rating
                ? Colors.amber.shade600
                : Theme.of(context).colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.45,
                  ),
          ),
      ],
    );
  }
}
