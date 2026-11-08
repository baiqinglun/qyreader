/// 全书检索页：FTS5 命中列表，点条目跳回阅读器所在章。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/reading_theme.dart';
import '../../../domain/repositories/search_repository.dart';
import '../reader_settings.dart';

/// 全书检索页。
class BookSearchPage extends ConsumerStatefulWidget {
  const BookSearchPage({required this.bookId, super.key});

  /// 书籍 id。
  final String bookId;

  @override
  ConsumerState<BookSearchPage> createState() => _BookSearchPageState();
}

class _BookSearchPageState extends ConsumerState<BookSearchPage> {
  final _controller = TextEditingController();
  List<BookSearchHit>? _results;
  bool _searching = false;
  String _error = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _error = '';
    });
    try {
      final repo = await ref.read(searchRepositoryProvider.future);
      final hits = await repo.search(bookId: widget.bookId, query: query);
      if (!mounted) return;
      setState(() {
        _results = hits;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '检索失败：$e';
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(readingSettingsControllerProvider).theme;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.chromeSurface,
        foregroundColor: theme.chromeForeground,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _doSearch(),
          style: TextStyle(color: theme.chromeForeground),
          decoration: InputDecoration(
            hintText: '搜索本书内容…',
            hintStyle: TextStyle(
              color: theme.chromeForeground.withValues(alpha: 0.4),
            ),
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: theme.chromeForeground),
            onPressed: _doSearch,
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ReadingTheme theme) {
    if (_searching) {
      return Center(
        child: CircularProgressIndicator(color: theme.accent),
      );
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Text(_error, style: TextStyle(color: theme.chromeForeground)),
      );
    }
    final results = _results;
    if (results == null) {
      return Center(
        child: Text(
          '输入关键词检索全书',
          style: TextStyle(
            color: theme.chromeForeground.withValues(alpha: 0.5),
          ),
        ),
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Text(
          '没有找到匹配内容',
          style: TextStyle(
            color: theme.chromeForeground.withValues(alpha: 0.5),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final hit = results[index];
        return _HitTile(
          hit: hit,
          theme: theme,
          onTap: () => Navigator.of(context).pop(hit),
        );
      },
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit, required this.theme, required this.onTap});

  final BookSearchHit hit;
  final ReadingTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.chromeSurface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hit.chapterTitle.isEmpty ? '第 ${hit.chapterIdx + 1} 节' : hit.chapterTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              _SnippetText(snippet: hit.snippet, theme: theme),
            ],
          ),
        ),
      ),
    );
  }
}

/// 片段渲染：把【命中】部分高亮。
class _SnippetText extends StatelessWidget {
  const _SnippetText({required this.snippet, required this.theme});

  final String snippet;
  final ReadingTheme theme;

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    var rest = snippet;
    while (true) {
      final start = rest.indexOf('【');
      final end = rest.indexOf('】', start);
      if (start < 0 || end <= start) {
        if (rest.isNotEmpty) {
          spans.add(TextSpan(text: rest));
        }
        break;
      }
      if (start > 0) {
        spans.add(TextSpan(text: rest.substring(0, start)));
      }
      spans.add(TextSpan(
        text: rest.substring(start + 1, end),
        style: TextStyle(
          color: theme.accent,
          fontWeight: FontWeight.w700,
        ),
      ));
      rest = rest.substring(end + 1);
    }
    return Text.rich(
      TextSpan(
        style: TextStyle(
          color: theme.chromeForeground.withValues(alpha: 0.85),
          height: 1.4,
        ),
        children: spans,
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}
