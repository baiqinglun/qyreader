/// 导出阅读数据（JSON）。
///
/// 导出范围：书架上的书籍元数据 + 阅读进度 + 划线/高亮/笔记 + 书签 +
/// 每本书的累计/每日阅读时长。**不导出书源文件、封面文件、本机路径和
/// HLC/设备 id**，方便用户备份、分析或迁移。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../app/theme/motion.dart';
import '../../domain/entities/annotation.dart';
import '../../domain/entities/book.dart';
import '../../domain/entities/bookmark.dart';
import '../../domain/entities/reading_progress.dart';
import '../../domain/entities/reading_stats.dart';

/// 导出结果。
class ReadingDataExportResult {
  /// 构造。
  const ReadingDataExportResult({
    required this.file,
    required this.bookCount,
    required this.annotationCount,
    required this.bookmarkCount,
    required this.durationMs,
    required this.charsRead,
    required this.dayCount,
  });

  /// 写出的 JSON 文件。
  final File file;

  /// 书籍数。
  final int bookCount;

  /// 标注数。
  final int annotationCount;

  /// 书签数。
  final int bookmarkCount;

  /// 累计阅读时长（ms）。
  final int durationMs;

  /// 累计字符数。
  final int charsRead;

  /// 有阅读记录的天数。
  final int dayCount;
}

/// 纯函数：把已经聚合好的数据拼成导出 JSON（便于单测）。
Map<String, dynamic> buildReadingDataJson({
  required DateTime exportedAt,
  required List<Book> books,
  required Map<String, ReadingProgressSnapshot?> progress,
  required Map<String, List<Annotation>> annotations,
  required Map<String, List<Bookmark>> bookmarks,
  required Map<String, BookReadingTotal> totals,
  required Map<String, Map<String, int>> dailyDurations,
  required int dailyGoalMinutes,
}) {
  var annotationCount = 0;
  var bookmarkCount = 0;
  var durationMs = 0;
  var charsRead = 0;
  final days = <String>{};
  for (final book in books) {
    annotationCount += annotations[book.id]?.length ?? 0;
    bookmarkCount += bookmarks[book.id]?.length ?? 0;
    durationMs += totals[book.id]?.durationMs ?? 0;
    charsRead += totals[book.id]?.charsRead ?? 0;
    days.addAll(dailyDurations[book.id]?.keys ?? const <String>[]);
  }

  return <String, dynamic>{
    'format': 'qyreader-reading-data',
    'version': 1,
    'app': 'QYReader',
    'exportedAt': exportedAt.millisecondsSinceEpoch,
    'exportedAtIso': exportedAt.toUtc().toIso8601String(),
    'dailyGoalMinutes': dailyGoalMinutes,
    'summary': <String, dynamic>{
      'books': books.length,
      'annotations': annotationCount,
      'bookmarks': bookmarkCount,
      'readingDurationMs': durationMs,
      'charsRead': charsRead,
      'daysWithReading': days.length,
    },
    'books': <Map<String, dynamic>>[
      for (final book in books)
        <String, dynamic>{
          'id': book.id,
          'title': book.title,
          if (book.author != null && book.author!.isNotEmpty)
            'author': book.author,
          if (book.series != null && book.series!.isNotEmpty)
            'series': book.series,
          if (book.seriesIndex != 0) 'seriesIndex': book.seriesIndex,
          if (book.language != null && book.language!.isNotEmpty)
            'language': book.language,
          if (book.description != null && book.description!.isNotEmpty)
            'description': book.description,
          'format': book.format.name,
          'chapterCount': book.chapterCount,
          'wordCount': book.wordCount,
          'addedAt': book.addedAt,
          'updatedAt': book.updatedAt,
          if (book.lastOpenedAt != null) 'lastOpenedAt': book.lastOpenedAt,
          if (book.finishedAt != null) 'finishedAt': book.finishedAt,
          'readStatus': book.readStatus.name,
          'isFinished': book.isFinished,
          if (book.rating != null) 'rating': book.rating,
          if (book.review != null && book.review!.isNotEmpty)
            'review': book.review,
          if (book.tags.isNotEmpty) 'tags': book.tags,
          if (book.category != null && book.category!.isNotEmpty)
            'category': book.category,
          if (book.pinnedAt != null) 'pinnedAt': book.pinnedAt,
          'progress': _progressJson(progress[book.id]),
          'reading': <String, dynamic>{
            'durationMs': totals[book.id]?.durationMs ?? 0,
            'charsRead': totals[book.id]?.charsRead ?? 0,
            'dailyDurations': <Map<String, dynamic>>[
              for (final entry in _sortedDaily(dailyDurations[book.id]))
                <String, dynamic>{'day': entry.key, 'durationMs': entry.value},
            ],
          },
          'annotations': <Map<String, dynamic>>[
            for (final a in annotations[book.id] ?? const <Annotation>[])
              _annotationJson(a),
          ],
          'bookmarks': <Map<String, dynamic>>[
            for (final b in bookmarks[book.id] ?? const <Bookmark>[])
              _bookmarkJson(b),
          ],
        },
    ],
  };
}

List<MapEntry<String, int>> _sortedDaily(Map<String, int>? daily) {
  final list = (daily ?? const <String, int>{}).entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return list;
}

Map<String, dynamic>? _progressJson(ReadingProgressSnapshot? progress) {
  if (progress == null) return null;
  return <String, dynamic>{
    'percent': progress.percent,
    'locator': _locatorJson(progress.locator),
    if (progress.furthestLocator != null)
      'furthestLocator': _locatorJson(progress.furthestLocator!),
    'furthestPercent': progress.furthestPercent,
    'updatedAt': progress.updatedAt,
  };
}

Map<String, dynamic> _annotationJson(Annotation a) => <String, dynamic>{
  'id': a.id,
  'type': a.type.token,
  'color': a.color.token,
  if (a.quotedText != null) 'quote': a.quotedText,
  if (a.note != null) 'note': a.note,
  'locatorStart': _locatorJson(a.locatorStart),
  'locatorEnd': _locatorJson(a.locatorEnd),
  'createdAt': a.createdAt,
  'updatedAt': a.updatedAt,
};

Map<String, dynamic> _bookmarkJson(Bookmark b) => <String, dynamic>{
  'id': b.id,
  if (b.label != null) 'label': b.label,
  'locator': _locatorJson(b.locator),
  'createdAt': b.createdAt,
};

/// locator 字符串 → JSON 对象；损坏数据保留原字符串，不丢信息。
Object? _locatorJson(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  try {
    return jsonDecode(text);
  } catch (_) {
    return text;
  }
}

/// 弹出书籍选择（导出哪些书），然后开始导出。
///
/// 返回 null = 用户取消；空列表 = 没选任何书（不导出）。
Future<void> exportReadingDataJson(BuildContext context, WidgetRef ref) async {
  final bookRepo = await ref.read(bookRepositoryProvider.future);
  final shelf = await bookRepo.watchShelf().first;
  final books = [for (final item in shelf) item.book];
  if (!context.mounted) return;
  if (books.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('书架是空的，没有可导出的书籍')));
    return;
  }
  final selected = await showReadingDataBookPicker(context, books);
  if (selected == null || selected.isEmpty || !context.mounted) return;
  await _runExport(context, ref, selected);
}

/// 导出一本书的阅读数据（长按菜单入口，不再选择范围）。
Future<void> exportBookReadingData(
  BuildContext context,
  WidgetRef ref,
  Book book,
) async {
  await _runExport(context, ref, [book]);
}

Future<void> _runExport(
  BuildContext context,
  WidgetRef ref,
  List<Book> books,
) async {
  final future = _buildAndWrite(ref, books);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ReadingDataExportDialog(future: future),
  );
}

Future<ReadingDataExportResult> _buildAndWrite(
  WidgetRef ref,
  List<Book> books,
) async {
  final progressRepo = await ref.read(progressRepositoryProvider.future);
  final annotationRepo = await ref.read(annotationRepositoryProvider.future);
  final statsRepo = await ref.read(statsRepositoryProvider.future);

  final totals = <String, BookReadingTotal>{
    for (final t in await statsRepo.bookTotals()) t.bookId: t,
  };
  final progress = <String, ReadingProgressSnapshot?>{};
  final annotations = <String, List<Annotation>>{};
  final bookmarks = <String, List<Bookmark>>{};
  final daily = <String, Map<String, int>>{};
  for (final book in books) {
    progress[book.id] = await progressRepo.getProgress(book.id);
    annotations[book.id] = await annotationRepo.listForBook(book.id);
    bookmarks[book.id] = await annotationRepo.listBookmarks(book.id);
    daily[book.id] = await statsRepo.bookDailyDurations(book.id, days: 3660);
  }
  final goal = await statsRepo.dailyGoalMinutes();
  final exportedAt = DateTime.now();
  final json = buildReadingDataJson(
    exportedAt: exportedAt,
    books: books,
    progress: progress,
    annotations: annotations,
    bookmarks: bookmarks,
    totals: totals,
    dailyDurations: daily,
    dailyGoalMinutes: goal,
  );
  final summary = json['summary'] as Map<String, dynamic>;

  final dir = await getApplicationDocumentsDirectory();
  final exportDir = Directory(p.join(dir.path, 'exports'));
  await exportDir.create(recursive: true);
  final file = File(
    p.join(exportDir.path, 'QYReader-reading-data-${_stamp(exportedAt)}.json'),
  );
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(json),
    flush: true,
  );
  return ReadingDataExportResult(
    file: file,
    bookCount: summary['books'] as int? ?? 0,
    annotationCount: summary['annotations'] as int? ?? 0,
    bookmarkCount: summary['bookmarks'] as int? ?? 0,
    durationMs: summary['readingDurationMs'] as int? ?? 0,
    charsRead: summary['charsRead'] as int? ?? 0,
    dayCount: summary['daysWithReading'] as int? ?? 0,
  );
}

String _stamp(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${time.year}${two(time.month)}${two(time.day)}-'
      '${two(time.hour)}${two(time.minute)}${two(time.second)}';
}

class _ReadingDataExportDialog extends StatelessWidget {
  const _ReadingDataExportDialog({required this.future});

  final Future<ReadingDataExportResult> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ReadingDataExportResult>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return AlertDialog(
            key: const ValueKey('reading-data-export-progress'),
            content: Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                const SizedBox(width: 16),
                const Expanded(child: Text('正在汇总阅读数据…')),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return AlertDialog(
            title: const Text('导出失败'),
            content: Text('${snapshot.error}'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('知道了'),
              ),
            ],
          );
        }
        final result = snapshot.requireData;
        return AlertDialog(
          key: const ValueKey('reading-data-export-result'),
          title: const Text('导出完成'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${result.bookCount} 本书 · ${result.annotationCount} 条标注 · '
                  '${result.bookmarkCount} 个书签',
                ),
                const SizedBox(height: 4),
                Text(
                  '累计阅读 ${_durationLabel(result.durationMs)} · '
                  '${result.dayCount} 天有记录',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  result.file.path,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('reading-data-export-share'),
              onPressed: () async {
                try {
                  await SharePlus.instance.share(
                    ShareParams(
                      files: [
                        XFile(result.file.path, mimeType: 'application/json'),
                      ],
                      text: 'QYReader 阅读数据',
                    ),
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('分享失败：$e')));
                  }
                }
              },
              child: const Text('分享文件'),
            ),
            FilledButton(
              key: const ValueKey('reading-data-export-close'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('完成'),
            ),
          ],
        );
      },
    );
  }
}

String _durationLabel(int ms) {
  final totalMinutes = ms ~/ 60000;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours > 0) return '$hours 小时 $minutes 分';
  return '$minutes 分钟';
}

/// 选择要导出哪些书籍；返回选中的书（保持原顺序），null = 取消。
Future<List<Book>?> showReadingDataBookPicker(
  BuildContext context,
  List<Book> books,
) {
  return showModalBottomSheet<List<Book>>(
    context: context,
    sheetAnimationStyle: kSmoothSheetAnimation,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ReadingDataBookPickerSheet(books: books),
  );
}

class _ReadingDataBookPickerSheet extends StatefulWidget {
  const _ReadingDataBookPickerSheet({required this.books});

  final List<Book> books;

  @override
  State<_ReadingDataBookPickerSheet> createState() =>
      _ReadingDataBookPickerSheetState();
}

class _ReadingDataBookPickerSheetState
    extends State<_ReadingDataBookPickerSheet> {
  late final Set<String> _selected = {for (final book in widget.books) book.id};

  void _toggle(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '选择要导出的书籍',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('reading-data-pick-toggle-all'),
                    onPressed: () => setState(() {
                      if (_selected.length == widget.books.length) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll({for (final b in widget.books) b.id});
                      }
                    }),
                    child: Text(
                      _selected.length == widget.books.length ? '全不选' : '全选',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                '导出书籍信息、进度、笔记书签与阅读时长；'
                '已选 ${_selected.length}/${widget.books.length} 本',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.books.length,
                itemBuilder: (context, index) {
                  final book = widget.books[index];
                  final checked = _selected.contains(book.id);
                  return CheckboxListTile(
                    key: ValueKey('reading-data-pick-${book.id}'),
                    value: checked,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    title: Text(
                      book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: (book.author ?? '').isEmpty
                        ? null
                        : Text(
                            book.author!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    onChanged: (_) => _toggle(book.id),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton(
                key: const ValueKey('reading-data-pick-apply'),
                onPressed: () {
                  final picked = [
                    for (final book in widget.books)
                      if (_selected.contains(book.id)) book,
                  ];
                  Navigator.of(context).pop(picked);
                },
                child: Text('导出 ${_selected.length} 本'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
