/// 设置 → 重复书籍整理。
///
/// 按书名（强匹配 / 疑似匹配）或文件内容查找重复书籍；支持忽略分组、
/// 按阅读状态 / 分类筛选、勾选后批量删除，单组至少保留一本。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../app/router.dart' show bookDetailPath;
import '../../domain/entities/book.dart';
import '../home/widgets/cover_thumb.dart';
import 'duplicate_books.dart';

/// 重复书籍整理页。
class DuplicateBooksPage extends ConsumerStatefulWidget {
  /// 构造。
  const DuplicateBooksPage({super.key});

  @override
  ConsumerState<DuplicateBooksPage> createState() => _DuplicateBooksPageState();
}

class _DuplicateBooksPageState extends ConsumerState<DuplicateBooksPage> {
  List<Book> _books = const [];
  Map<String, double> _percents = const {};
  bool _loading = true;
  bool _deleting = false;
  String? _error;

  DuplicateDetectType _detect = DuplicateDetectType.title;
  DuplicateMatchScope _scope = DuplicateMatchScope.all;
  bool _matchAuthor = false;
  Set<BookReadStatus> _statuses = const {};
  String? _category;

  final Set<String> _selected = <String>{};
  final Set<String> _ignored = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final repo = await ref.read(bookRepositoryProvider.future);
      final items = await repo.watchShelf().first;
      if (!mounted) return;
      setState(() {
        _books = [for (final item in items) item.book];
        _percents = {for (final item in items) item.book.id: item.percent};
        _loading = false;
        _selected.removeWhere((id) => !_books.any((book) => book.id == id));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  List<Book> get _filteredBooks {
    return [
      for (final book in _books)
        if (_statuses.isEmpty || _statuses.contains(book.readStatus))
          if (_category == null || (book.category ?? '').trim() == _category)
            book,
    ];
  }

  List<DuplicateGroup> get _allGroups {
    final filtered = _filteredBooks;
    return _detect == DuplicateDetectType.title
        ? findDuplicateBookGroups(filtered, matchAuthor: _matchAuthor)
        : findDuplicateFileGroups(filtered);
  }

  List<DuplicateGroup> get _visibleGroups {
    final byScope = filterDuplicateGroups(_allGroups, _scope);
    return [
      for (final group in byScope)
        if (!_ignored.contains(group.key)) group,
    ];
  }

  List<DuplicateGroup> get _strongGroups => [
    for (final group in _visibleGroups)
      if (group.strong) group,
  ];

  List<DuplicateGroup> get _suspectedGroups => [
    for (final group in _visibleGroups)
      if (!group.strong) group,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final groups = _visibleGroups;
    final strong = _strongGroups;
    final suspected = _suspectedGroups;

    return Scaffold(
      appBar: AppBar(
        title: const Text('书籍重名整理'),
        actions: [
          IconButton(
            key: const ValueKey('duplicate-refresh'),
            tooltip: '重新检测',
            onPressed: _loading || _deleting ? null : () => unawaited(_load()),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            key: const ValueKey('duplicate-delete-selected'),
            tooltip: '删除选中',
            onPressed: _selected.isEmpty || _deleting
                ? null
                : () => unawaited(_deleteSelected()),
            icon: const Icon(Icons.delete_outline),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('duplicate-more'),
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz),
            onSelected: _onMore,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'select-all',
                enabled: groups.isNotEmpty && !_deleting,
                child: const Text('全选每组保留一本'),
              ),
              PopupMenuItem(
                value: 'clear',
                enabled: _selected.isNotEmpty,
                child: const Text('清除选择'),
              ),
              if (_ignored.isNotEmpty)
                PopupMenuItem(
                  value: 'restore',
                  child: Text('恢复已忽略（${_ignored.length}）'),
                ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorBody(error: _error!, onRetry: () => unawaited(_load()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  _ConfigCard(
                    detect: _detect,
                    scope: _scope,
                    matchAuthor: _matchAuthor,
                    total: _books.length,
                    filtered: _filteredBooks.length,
                    hasStatusFilter: _statuses.isNotEmpty,
                    category: _category,
                    onDetect: () => unawaited(_pickDetect()),
                    onScope: () => unawaited(_pickScope()),
                    onMatchAuthor: (value) => setState(() {
                      _matchAuthor = value;
                      _selected.clear();
                    }),
                    onFilter: () => unawaited(_pickFilter()),
                  ),
                  if (groups.isEmpty)
                    _EmptyBody(
                      theme: theme,
                      ignored: _ignored.length,
                      hasBooks: _books.isNotEmpty,
                      hasFilter: _statuses.isNotEmpty || _category != null,
                      onRestore: _ignored.isEmpty
                          ? null
                          : () => setState(_ignored.clear),
                    )
                  else ...[
                    if (strong.isNotEmpty) ...[
                      _SectionLabel(text: '强匹配', color: scheme.outline),
                      for (final group in strong)
                        _GroupCard(
                          group: group,
                          selected: _selected,
                          percents: _percents,
                          onToggle: _toggle,
                          onIgnore: () => _ignore(group),
                          onDelete: (book) => unawaited(_deleteOne(book)),
                          onEdit: (book) => unawaited(_edit(book)),
                        ),
                    ],
                    if (suspected.isNotEmpty) ...[
                      _SectionLabel(text: '疑似匹配', color: scheme.outline),
                      for (final group in suspected)
                        _GroupCard(
                          group: group,
                          selected: _selected,
                          percents: _percents,
                          onToggle: _toggle,
                          onIgnore: () => _ignore(group),
                          onDelete: (book) => unawaited(_deleteOne(book)),
                          onEdit: (book) => unawaited(_edit(book)),
                        ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  void _toggle(Book book) {
    setState(() {
      if (!_selected.add(book.id)) _selected.remove(book.id);
    });
  }

  void _ignore(DuplicateGroup group) {
    setState(() {
      _ignored.add(group.key);
      for (final book in group.books) {
        _selected.remove(book.id);
      }
    });
    _snack('已忽略《${group.displayTitle}》');
  }

  void _onMore(String value) {
    switch (value) {
      case 'select-all':
        setState(() {
          for (final group in _visibleGroups) {
            final keep = group.keepCandidate;
            for (final book in group.books) {
              if (book.id != keep.id) _selected.add(book.id);
            }
          }
        });
      case 'clear':
        setState(_selected.clear);
      case 'restore':
        setState(_ignored.clear);
    }
  }

  Future<void> _edit(Book book) async {
    await context.push(bookDetailPath(book.id));
    if (!mounted) return;
    await _load();
  }

  Future<void> _deleteOne(Book book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这本书？'),
        content: Text('《${book.title}》的笔记和书签会一起删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _deleteIds({book.id}, success: '已删除《${book.title}》');
  }

  Future<void> _deleteSelected() async {
    // 每组至少保留一本，避免把某一组全部删光。
    for (final group in _visibleGroups) {
      final ids = [for (final book in group.books) book.id];
      if (ids.isNotEmpty && ids.every(_selected.contains)) {
        _snack('每组至少保留一本：《${group.displayTitle}》');
        return;
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除选中的重复书籍？'),
        content: Text('将删除 ${_selected.length} 本书，笔记和书签会一起删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _deleteIds({..._selected}, success: '已删除 ${_selected.length} 本重复书籍');
  }

  Future<void> _deleteIds(Set<String> ids, {required String success}) async {
    if (ids.isEmpty || _deleting) return;
    setState(() => _deleting = true);
    final repo = await ref.read(bookRepositoryProvider.future);
    try {
      for (final id in ids) {
        await repo.deleteBook(id, deleteAnnotations: true);
      }
      if (!mounted) return;
      setState(() {
        _books = [
          for (final book in _books)
            if (!ids.contains(book.id)) book,
        ];
        _selected.removeAll(ids);
        _deleting = false;
      });
      _snack(success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      _snack('删除失败：$e');
    }
  }

  Future<void> _pickDetect() async {
    final value = await showModalBottomSheet<DuplicateDetectType>(
      context: context,
      showDragHandle: true,
      builder: (context) => _OptionSheet<DuplicateDetectType>(
        title: '检测类型',
        options: [
          for (final type in DuplicateDetectType.values)
            _SheetOption(
              value: type,
              title: type.label,
              subtitle: type == DuplicateDetectType.title
                  ? '按书名强匹配和疑似匹配查找重复书籍'
                  : '按文件内容（SHA-256）查找完全相同的副本',
              selected: type == _detect,
            ),
        ],
      ),
    );
    if (value != null && mounted) {
      setState(() {
        _detect = value;
        _selected.clear();
      });
    }
  }

  Future<void> _pickScope() async {
    final value = await showModalBottomSheet<DuplicateMatchScope>(
      context: context,
      showDragHandle: true,
      builder: (context) => _OptionSheet<DuplicateMatchScope>(
        title: '匹配范围',
        options: [
          for (final scope in DuplicateMatchScope.values)
            _SheetOption(
              value: scope,
              title: scope.label,
              subtitle: scope.detail,
              selected: scope == _scope,
            ),
        ],
      ),
    );
    if (value != null && mounted) {
      setState(() {
        _scope = value;
        _selected.clear();
      });
    }
  }

  Future<void> _pickFilter() async {
    final categories = <String>{
      for (final book in _books)
        if ((book.category ?? '').trim().isNotEmpty) book.category!.trim(),
    }.toList()..sort();
    final result = await showModalBottomSheet<_FilterSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _FilterSheet(
        categories: categories,
        statuses: _statuses,
        category: _category,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _statuses = result.statuses;
      _category = result.category;
      _selected.clear();
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ConfigCard extends StatelessWidget {
  const _ConfigCard({
    required this.detect,
    required this.scope,
    required this.matchAuthor,
    required this.total,
    required this.filtered,
    required this.hasStatusFilter,
    required this.category,
    required this.onDetect,
    required this.onScope,
    required this.onMatchAuthor,
    required this.onFilter,
  });

  final DuplicateDetectType detect;
  final DuplicateMatchScope scope;
  final bool matchAuthor;
  final int total;
  final int filtered;
  final bool hasStatusFilter;
  final String? category;
  final VoidCallback onDetect;
  final VoidCallback onScope;
  final ValueChanged<bool> onMatchAuthor;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final filteredText = hasStatusFilter || category != null
        ? '筛选后 $filtered / $total 本'
        : '全部 $total 本书';
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          _ConfigTile(
            title: '检测类型',
            subtitle: detect == DuplicateDetectType.title
                ? '按书名强匹配和疑似匹配查找重复书籍'
                : '按文件内容（SHA-256）查找完全相同的副本',
            value: detect.label,
            onTap: onDetect,
          ),
          _divider(scheme),
          _ConfigTile(
            title: '匹配范围',
            subtitle: scope.detail,
            value: scope.label,
            onTap: onScope,
          ),
          if (detect == DuplicateDetectType.title) ...[
            _divider(scheme),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('匹配作者', style: TextStyle(fontSize: 15)),
                        SizedBox(height: 4),
                        Text(
                          '开启后只把作者也相同的书归为重名',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    key: const ValueKey('duplicate-match-author'),
                    value: matchAuthor,
                    onChanged: onMatchAuthor,
                  ),
                ],
              ),
            ),
          ],
          _divider(scheme),
          _ConfigTile(
            title: '书籍筛选',
            subtitle: filteredText,
            value: '',
            onTap: onFilter,
            showValue: false,
          ),
        ],
      ),
    );
  }

  Widget _divider(ColorScheme scheme) => Divider(
    height: 1,
    indent: 20,
    endIndent: 20,
    color: scheme.outlineVariant.withValues(alpha: 0.35),
  );
}

class _ConfigTile extends StatelessWidget {
  const _ConfigTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onTap,
    this.showValue = true,
  });

  final String title;
  final String subtitle;
  final String value;
  final VoidCallback onTap;
  final bool showValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 15, 16, 15),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (showValue) ...[
              const SizedBox(width: 12),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 22, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.selected,
    required this.percents,
    required this.onToggle,
    required this.onIgnore,
    required this.onDelete,
    required this.onEdit,
  });

  final DuplicateGroup group;
  final Set<String> selected;
  final Map<String, double> percents;
  final ValueChanged<Book> onToggle;
  final VoidCallback onIgnore;
  final ValueChanged<Book> onDelete;
  final ValueChanged<Book> onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitle = switch (group.type) {
      DuplicateDetectType.file =>
        '文件内容相同（SHA-256 前 8 位）共有 ${group.books.length} 本',
      DuplicateDetectType.title =>
        group.strong
            ? '忽略大小写、空白和格式后缀后共有 ${group.books.length} 本'
            : '忽略版本、括号和卷号等常见噪声后共有 ${group.books.length} 本',
    };
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      group.displayTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  key: ValueKey('duplicate-ignore-${group.key}'),
                  onPressed: onIgnore,
                  child: const Text('忽略'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
            for (var i = 0; i < group.books.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 30,
                  color: scheme.outlineVariant.withValues(alpha: 0.3),
                ),
              _BookRow(
                book: group.books[i],
                checked: selected.contains(group.books[i].id),
                largest: group.books[i].id == group.largestFileId,
                mostWords: group.books[i].id == group.mostWordsId,
                percent: percents[group.books[i].id] ?? 0,
                onToggle: () => onToggle(group.books[i]),
                onEdit: () => onEdit(group.books[i]),
                onDelete: () => onDelete(group.books[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({
    required this.book,
    required this.checked,
    required this.largest,
    required this.mostWords,
    required this.percent,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final Book book;
  final bool checked;
  final bool largest;
  final bool mostWords;
  final double percent;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = DateFormat(
      'yyyy-MM-dd HH:mm',
    ).format(DateTime.fromMillisecondsSinceEpoch(book.addedAt));
    final fileName = p.basename(book.filePath);
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              key: ValueKey('duplicate-check-${book.id}'),
              value: checked,
              onChanged: (_) => onToggle(),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),
            CoverThumb(path: book.coverPath, width: 46, height: 62, radius: 6),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          book.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            height: 1.35,
                          ),
                        ),
                      ),
                      _SmallIconButton(
                        key: ValueKey('duplicate-edit-${book.id}'),
                        icon: Icons.edit_outlined,
                        tooltip: '编辑信息',
                        onPressed: onEdit,
                      ),
                      _SmallIconButton(
                        key: ValueKey('duplicate-delete-${book.id}'),
                        icon: Icons.delete_outline,
                        tooltip: '删除',
                        onPressed: onDelete,
                      ),
                    ],
                  ),
                  if ((book.author ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        book.author!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Badge(
                        text:
                            '${_fileSize(book.fileSize)}${largest ? ' · 最大' : ''}',
                        emphasized: largest,
                      ),
                      _Badge(
                        text: '${book.wordCount} 字${mostWords ? ' · 最多' : ''}',
                        emphasized: mostWords,
                      ),
                      _Badge(text: book.readStatus.label),
                      if (percent > 0)
                        _Badge(text: '读至 ${(percent * 100).round()}%'),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '加入书架 $date',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _MetaChip(
                        icon: Icons.folder_outlined,
                        text: (book.category ?? '').trim().isEmpty
                            ? '未分类'
                            : book.category!.trim(),
                      ),
                      _MetaChip(
                        icon: Icons.insert_drive_file_outlined,
                        text: fileName,
                      ),
                    ],
                  ),
                  if ((book.description ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      book.description!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fileSize(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
    }
    return '${math.max(0.01, bytes / 1024).toStringAsFixed(2)} KB';
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.emphasized = false});

  final String text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: emphasized
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: emphasized
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
          fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      iconSize: 19,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({
    required this.theme,
    required this.ignored,
    required this.hasBooks,
    required this.hasFilter,
    required this.onRestore,
  });

  final ThemeData theme;
  final int ignored;
  final bool hasBooks;
  final bool hasFilter;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final title = !hasBooks
        ? '书架还是空的'
        : ignored > 0
        ? '已忽略 $ignored 组重复书籍'
        : hasFilter
        ? '当前筛选范围没有重复书籍'
        : '没有发现重复书籍';
    final detail = !hasBooks
        ? '导入书籍后再来整理重复项'
        : ignored > 0
        ? '恢复后可继续整理'
        : hasFilter
        ? '试试放宽筛选条件'
        : '当前检测类型和匹配范围下没有重复项';
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 44,
            color: scheme.primary.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (onRestore != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onRestore, child: const Text('恢复已忽略')),
          ],
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text('读取书架失败：$error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _SheetOption<T> {
  const _SheetOption({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.selected,
  });

  final T value;
  final String title;
  final String subtitle;
  final bool selected;
}

class _OptionSheet<T> extends StatelessWidget {
  const _OptionSheet({required this.title, required this.options});

  final String title;
  final List<_SheetOption<T>> options;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Card(
              elevation: 0,
              child: Column(
                children: [
                  for (var i = 0; i < options.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      key: ValueKey('duplicate-option-${options[i].title}'),
                      title: Text(options[i].title),
                      subtitle: Text(options[i].subtitle),
                      trailing: options[i].selected
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.of(context).pop(options[i].value),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSelection {
  const _FilterSelection({required this.statuses, required this.category});

  final Set<BookReadStatus> statuses;
  final String? category;
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.categories,
    required this.statuses,
    required this.category,
  });

  final List<String> categories;
  final Set<BookReadStatus> statuses;
  final String? category;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<BookReadStatus> _statuses = {...widget.statuses};
  late String? _category = widget.category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '书籍筛选',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Text('阅读状态', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final status in BookReadStatus.values)
                    FilterChip(
                      label: Text(status.label),
                      selected: _statuses.contains(status),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _statuses.add(status);
                        } else {
                          _statuses.remove(status);
                        }
                      }),
                    ),
                ],
              ),
              if (widget.categories.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('分类', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('全部分类'),
                      selected: _category == null,
                      onSelected: (_) => setState(() => _category = null),
                    ),
                    for (final category in widget.categories)
                      ChoiceChip(
                        label: Text(category),
                        selected: _category == category,
                        onSelected: (_) => setState(() => _category = category),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton(
                    key: const ValueKey('duplicate-filter-clear'),
                    onPressed: () => setState(() {
                      _statuses = {};
                      _category = null;
                    }),
                    child: const Text('清除筛选'),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const ValueKey('duplicate-filter-apply'),
                    onPressed: () => Navigator.of(context).pop(
                      _FilterSelection(
                        statuses: _statuses,
                        category: _category,
                      ),
                    ),
                    child: const Text('应用'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '筛选只影响本次整理的候选书籍，不会修改书架。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
