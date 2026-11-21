/// 首页微信读书个性化推荐。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../settings/weread/weread_client.dart';
import '../settings/weread/weread_credentials.dart';

/// null 表示尚未登录。
final recommendationsProvider = FutureProvider<List<WeReadRecommendation>?>((
  ref,
) async {
  final key = await WeReadCredentials().read();
  if (key == null) return null;
  return WeReadClient(apiKey: key).fetchRecommendations();
});

class RecommendationsCard extends ConsumerWidget {
  const RecommendationsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final data = ref.watch(recommendationsProvider);
    return Container(
      key: const ValueKey('home-recommendations-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? theme.colorScheme.surfaceContainerLow
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '书籍推荐',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: '刷新推荐',
                onPressed: data.isLoading
                    ? null
                    : () => ref.invalidate(recommendationsProvider),
                icon: data.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          data.when(
            skipLoadingOnRefresh: false,
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => Row(
              children: [
                const Expanded(child: Text('推荐获取失败，请稍后重试')),
                TextButton(
                  onPressed: () => ref.invalidate(recommendationsProvider),
                  child: const Text('重试'),
                ),
              ],
            ),
            data: (books) {
              if (books == null) {
                return Row(
                  children: [
                    const Expanded(child: Text('登录微信读书后获取个性化推荐')),
                    TextButton(
                      onPressed: () async {
                        await context.push(kWeReadPath);
                        if (!context.mounted) return;
                        ref.invalidate(recommendationsProvider);
                      },
                      child: const Text('登录'),
                    ),
                  ],
                );
              }
              if (books.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('暂时没有推荐书籍，请稍后刷新'),
                );
              }
              return SizedBox(
                height: 200,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: books.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final book = books[index];
                    return SizedBox(
                      width: 96,
                      child: InkWell(
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (context) =>
                              _RecommendationDialog(book: book),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 96,
                                height: 130,
                                child: book.cover == null || book.cover!.isEmpty
                                    ? const ColoredBox(
                                        color: Colors.black12,
                                        child: Icon(Icons.menu_book),
                                      )
                                    : Image.network(
                                        book.cover!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const ColoredBox(
                                              color: Colors.black12,
                                              child: Icon(Icons.menu_book),
                                            ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              book.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                            if (book.author?.isNotEmpty == true)
                              Text(
                                book.author!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RecommendationDialog extends StatefulWidget {
  const _RecommendationDialog({required this.book});
  final WeReadRecommendation book;
  @override
  State<_RecommendationDialog> createState() => _RecommendationDialogState();
}

class _RecommendationDialogState extends State<_RecommendationDialog> {
  late final Future<WeReadClient?> _client = widget.book.bookId.isEmpty
      ? Future.value(null)
      : _getClient();
  Future<Map<String, dynamic>>? _info;
  Future<List<Map<String, dynamic>>>? _chapters;
  Future<List<String>>? _highlights;
  Future<List<String>>? _reviews;
  Future<WeReadClient?> _getClient() async {
    final key = await WeReadCredentials().read();
    return key == null ? null : WeReadClient(apiKey: key);
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DefaultTabController(
      length: 4,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SizedBox(
          width: 500,
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 66,
                        height: 90,
                        child: book.cover == null || book.cover!.isEmpty
                            ? ColoredBox(
                                color: scheme.surfaceContainerHighest,
                                child: const Icon(Icons.menu_book_outlined),
                              )
                            : Image.network(
                                book.cover!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => ColoredBox(
                                  color: scheme.surfaceContainerHighest,
                                  child: const Icon(Icons.menu_book_outlined),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            book.author?.isNotEmpty == true
                                ? book.author!
                                : '作者未知',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              TabBar(
                labelPadding: EdgeInsets.zero,
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(text: '基本信息'),
                  Tab(text: '目录'),
                  Tab(text: '热门划线'),
                  Tab(text: '热门书评'),
                ],
              ),
              Expanded(
                child: FutureBuilder<WeReadClient?>(
                  future: _client,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final client = snapshot.data;
                    if (client == null || book.bookId.isEmpty) {
                      return TabBarView(
                        children: [
                          SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: _BookSummary(book: book, details: const {}),
                          ),
                          const _ReadingText(text: '暂无目录'),
                          const _ReadingText(text: '暂无数据'),
                          const _ReadingText(text: '暂无数据'),
                        ],
                      );
                    }
                    return TabBarView(
                      children: [
                        _DetailFuture<Map<String, dynamic>>(
                          future: _info ??= client.fetchRecommendationInfo(
                            book.bookId,
                          ),
                          builder: (data) =>
                              _BookSummary(book: book, details: data),
                        ),
                        _DetailFuture<List<Map<String, dynamic>>>(
                          future: _chapters ??= client.fetchChapters(
                            book.bookId,
                          ),
                          builder: (items) => items.isEmpty
                              ? const _ReadingText(text: '暂无目录')
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final item in items)
                                      Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          (((item['level'] as num?)?.toInt() ??
                                                          1) -
                                                      1)
                                                  .clamp(0, 5) *
                                              16.0,
                                          8,
                                          0,
                                          8,
                                        ),
                                        child: Text('${item['title'] ?? ''}'),
                                      ),
                                  ],
                                ),
                        ),
                        _DetailFuture<List<String>>(
                          future: _highlights ??= client.fetchPopularHighlights(
                            book.bookId,
                          ),
                          builder: (items) => _SeparatedEntries(
                            items: items,
                            emptyText: '暂无热门划线',
                          ),
                        ),
                        _DetailFuture<List<String>>(
                          future: _reviews ??= client.fetchPopularReviews(
                            book.bookId,
                          ),
                          builder: (items) => _SeparatedEntries(
                            items: items,
                            emptyText: '暂无热门书评',
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailFuture<T> extends StatelessWidget {
  const _DetailFuture({required this.future, required this.builder});
  final Future<T> future;
  final Widget Function(T) builder;
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('加载失败，请稍后重试'));
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: builder(snapshot.data as T),
      );
    },
  );
}

/// 将接口实际提供的字段展示为书籍概览。
class _BookSummary extends StatelessWidget {
  const _BookSummary({required this.book, required this.details});
  final WeReadRecommendation book;
  final Map<String, dynamic> details;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Object? getValue(String name) => details[name] ?? book.metadata[name];
    final rawRating = getValue('newRating');
    final score = rawRating is num
        ? rawRating.toDouble()
        : double.tryParse('$rawRating');
    final ratingInfo = getValue('newRatingDetail');
    final ratingTitle = ratingInfo is Map ? ratingInfo['title'] : null;
    String? nonempty(Object? value) {
      if (value == null || '$value'.trim().isEmpty) return null;
      return '$value';
    }

    String count(Object value) {
      final n = value is num ? value : num.tryParse('$value');
      return n != null && n >= 10000
          ? '${(n / 10000).toStringAsFixed(1)}万'
          : '$value';
    }

    final entries = <(String, String)>[
      if (getValue('readingCount') case final value?)
        ('在读', '${count(value)} 人'),
      if (getValue('finishCount') case final value?)
        ('读完', '${count(value)} 人'),
      if (getValue('wordCount') case final value?) ('字数', '${count(value)} 字'),
      if (getValue('newRatingCount') case final value?)
        ('评分人数', '${count(value)} 人'),
    ];
    final category = nonempty(getValue('category'));
    final tags = getValue('tags');
    final tagNames = <String>[
      if (category != null) category,
      if (tags is List)
        for (final tag in tags)
          if (tag is String && tag.trim().isNotEmpty) tag.trim(),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: () async {
            var opened = false;
            if ((Platform.isAndroid || Platform.isIOS) &&
                book.bookId.isNotEmpty) {
              final appUri = Uri(
                scheme: 'weread',
                host: 'reading',
                queryParameters: {'bId': book.bookId},
              );
              try {
                opened = await launchUrl(
                  appUri,
                  mode: LaunchMode.externalApplication,
                );
              } catch (_) {}
            }
            final link = getValue('readerLink');
            final uri = link is String ? Uri.tryParse(link) : null;
            if (!opened &&
                uri != null &&
                (uri.scheme == 'https' || uri.scheme == 'http')) {
              try {
                opened = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
              } catch (_) {}
            }
            if (!opened && context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('无法打开微信读书，请稍后重试')));
            }
          },
          icon: const Icon(Icons.open_in_new),
          label: const Text('去阅读'),
        ),
        if (score != null && score > 0)
          Row(
            children: [
              Icon(Icons.star_rounded, color: Colors.amber.shade700, size: 25),
              const SizedBox(width: 4),
              Text(
                (score / 10).toStringAsFixed(1),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              if (nonempty(ratingTitle) case final label?)
                Text(
                  label,
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final entry in entries)
                Container(
                  width: 112,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.55,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.$2,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.$1,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        if (tagNames.isNotEmpty) ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final name in tagNames.toSet())
                Chip(label: Text(name), visualDensity: VisualDensity.compact),
            ],
          ),
        ],
        if (nonempty(getValue('publisher')) case final publisher?) ...[
          const SizedBox(height: 14),
          Text('出版社  $publisher', style: theme.textTheme.bodyMedium),
        ],
        if (nonempty(getValue('publishTime')) case final date?) ...[
          const SizedBox(height: 8),
          Text('出版日期  $date', style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 16),
        Text('简介', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(
          nonempty(getValue('intro')) ?? book.intro ?? '暂无简介',
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
        ),
        if (book.reason?.isNotEmpty == true) ...[
          const SizedBox(height: 16),
          Text('推荐理由', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            book.reason!,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ],
      ],
    );
  }
}

class _ReadingText extends StatelessWidget {
  const _ReadingText({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.7),
  );
}

/// 热门内容逐条展示，条目之间用分隔线区分。
class _SeparatedEntries extends StatelessWidget {
  const _SeparatedEntries({required this.items, required this.emptyText});
  final List<String> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return _ReadingText(text: emptyText);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(height: 24),
          _ReadingText(text: items[i]),
        ],
      ],
    );
  }
}
