/// 微信读书划线 / 想法查看面板。
///
/// 不依赖本机是否有这本书：只要 API 能拉到，就在面板里按章节展示原文与
/// 想法。本机有书时可再「同步」导入成标注；没有书也不影响查看。
library;

import 'package:flutter/material.dart';

import 'weread_models.dart';

/// 打开划线/想法面板。
Future<void> showWeReadNotesSheet(
  BuildContext context, {
  required String bookTitle,
  required Future<List<WeReadNote>> Function() loader,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.86,
      child: _WeReadNotesSheet(bookTitle: bookTitle, loader: loader),
    ),
  );
}

class _WeReadNotesSheet extends StatefulWidget {
  const _WeReadNotesSheet({required this.bookTitle, required this.loader});

  final String bookTitle;
  final Future<List<WeReadNote>> Function() loader;

  @override
  State<_WeReadNotesSheet> createState() => _WeReadNotesSheetState();
}

class _WeReadNotesSheetState extends State<_WeReadNotesSheet> {
  bool _loading = true;
  String? _error;
  List<WeReadNote> _notes = const <WeReadNote>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final notes = await widget.loader();
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is WeReadApiException ? error.message : '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;
    return Column(
      key: const ValueKey('weread-notes-sheet'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.bookTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _loading ? '正在读取划线 / 想法…' : '${_notes.length} 条划线 / 想法',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: color.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('weread-notes-close'),
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _body(theme)),
      ],
    );
  }

  Widget _body(ThemeData theme) {
    final color = theme.colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.error_outline, color: color.error),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const ValueKey('weread-notes-retry'),
                onPressed: _load,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_notes.isEmpty) {
      return Center(
        child: Text(
          '这本没有可导出的划线或想法',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: color.onSurface.withValues(alpha: 0.6),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      itemCount: _notes.length,
      separatorBuilder: (_, __) => const Divider(height: 24),
      itemBuilder: (context, index) {
        final note = _notes[index];
        final quote = note.quote.trim();
        final thought = note.thought.trim();
        return Column(
          key: ValueKey('weread-note-${note.id}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if ((note.chapterName ?? '').isNotEmpty)
                  Expanded(
                    child: Text(
                      note.chapterName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (note.createdAt != null)
                  Text(
                    _formatDate(note.createdAt!),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
              ],
            ),
            if (quote.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: color.primary.withValues(alpha: 0.06),
                  border: Border(
                    left: BorderSide(
                      color: color.primary.withValues(alpha: 0.55),
                      width: 3,
                    ),
                  ),
                ),
                child: Text(
                  quote,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                ),
              ),
            ],
            if (thought.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                thought,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color.onSurface.withValues(alpha: 0.8),
                  height: 1.55,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  static String _formatDate(int unixSeconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      unixSeconds * 1000,
    ).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }
}
