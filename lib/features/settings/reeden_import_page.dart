/// Reeden 数据导入对比页：选完 JSON 后进来，逐本看哪些信息需要更新，
/// 勾选后一次导入。笔记位置用原文全文搜索定位（复用微信读书定位函数）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../domain/entities/book.dart';
import '../../features/reader/native/native_chapter_source.dart';
import '../../features/shelf/shelf_controller.dart';
import 'reeden_import.dart';
import 'reeden_import_service.dart';

/// Reeden 数据导入对比页。
class ReedenImportPage extends ConsumerStatefulWidget {
  const ReedenImportPage({required this.books, super.key});

  /// 从 JSON 解析出的书籍数据（go_router extra 传入）。
  final List<ReedenBookData> books;

  @override
  ConsumerState<ReedenImportPage> createState() => _ReedenImportPageState();
}

class _ReedenImportPageState extends ConsumerState<ReedenImportPage> {
  List<ReedenBookDiff>? _diffs;
  final Set<int> _selected = {};
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _compare();
  }

  Future<void> _compare() async {
    final diffs = await compareReedenBooks(
      widget.books,
      bookRepo: await ref.read(bookRepositoryProvider.future),
      annotationRepo: await ref.read(annotationRepositoryProvider.future),
      statsRepo: await ref.read(statsRepositoryProvider.future),
    );
    if (!mounted) return;
    setState(() {
      _diffs = diffs;
      _selected.clear();
      for (var i = 0; i < diffs.length; i++) {
        if (diffs[i].state != ReedenDiffState.same) _selected.add(i);
      }
    });
  }

  Future<List<NativeChapter>> _loadChapters(Book book) async {
    final provider = nativeChaptersProvider(NativeChaptersKey.of(book));
    // listenManual 才能在 build 之外挂保活监听；读完立刻关掉。
    final subscription = ref.listenManual(provider, (_, __) {});
    try {
      return await ref.read(provider.future);
    } finally {
      subscription.close();
    }
  }

  Future<void> _apply() async {
    final diffs = _diffs;
    if (diffs == null || _importing) return;
    final selected = [
      for (var i = 0; i < diffs.length; i++)
        if (_selected.contains(i) && diffs[i].state != ReedenDiffState.same)
          diffs[i].data,
    ];
    if (selected.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有勾选要导入的书')));
      return;
    }
    setState(() => _importing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final summary = await importReedenData(
        selected,
        bookRepo: await ref.read(bookRepositoryProvider.future),
        annotationRepo: await ref.read(annotationRepositoryProvider.future),
        statsRepo: await ref.read(statsRepositoryProvider.future),
        progressRepo: await ref.read(progressRepositoryProvider.future),
        tempDir: (await getTemporaryDirectory()).path,
        loadChapters: _loadChapters,
      );
      messenger.showSnackBar(SnackBar(content: Text('导入完成：$summary')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
    if (mounted) {
      setState(() => _importing = false);
      // 书架 / 汇总数据刚变化：刷新书架流并重新对比（导入过的变「一致」）。
      ref.invalidate(shelfItemsProvider);
      await _compare();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diffs = _diffs;
    final selectedCount = diffs == null
        ? 0
        : [
            for (var i = 0; i < diffs.length; i++)
              if (_selected.contains(i) && diffs[i].state != ReedenDiffState.same)
                i,
          ].length;

    return Scaffold(
      appBar: AppBar(title: const Text('导入 Reeden 数据')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            key: const ValueKey('reeden-import-apply'),
            onPressed: diffs == null || _importing || selectedCount == 0
                ? null
                : _apply,
            child: Text(
              _importing ? '正在导入…' : '导入选中的书（$selectedCount）',
            ),
          ),
        ),
      ),
      body: diffs == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Text(
                        '共 ${diffs.length} 本 · '
                        '新增 ${diffs.where((d) => d.state == ReedenDiffState.create).length} · '
                        '更新 ${diffs.where((d) => d.state == ReedenDiffState.update).length} · '
                        '一致 ${diffs.where((d) => d.state == ReedenDiffState.same).length}',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: diffs.isEmpty
                      ? Center(
                          child: Text(
                            '文件里没有可导入的书籍',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          itemCount: diffs.length,
                          itemBuilder: (context, index) =>
                              _DiffCard(
                                diff: diffs[index],
                                selected: _selected.contains(index),
                                onChanged: (value) => setState(() {
                                  value == true
                                      ? _selected.add(index)
                                      : _selected.remove(index);
                                }),
                              ),
                        ),
                ),
              ],
            ),
    );
  }
}

/// 一本书的对比卡片。
class _DiffCard extends StatelessWidget {
  const _DiffCard({
    required this.diff,
    required this.selected,
    required this.onChanged,
  });

  final ReedenBookDiff diff;
  final bool selected;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = diff.state;
    final (badgeColor, badgeText) = switch (state) {
      ReedenDiffState.create => (scheme.primary, '新增'),
      ReedenDiffState.update => (Colors.orange.shade700, '更新'),
      ReedenDiffState.same => (
        scheme.onSurfaceVariant.withValues(alpha: 0.6),
        '一致',
      ),
    };
    final lines = diff.updateLines;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            color: badgeColor,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          diff.data.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (diff.data.author.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        diff.data.author,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  if (lines.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '将更新：${lines.join(' · ')}',
                        style: TextStyle(fontSize: 12.5, color: scheme.primary),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '本地已是最新的',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (state != ReedenDiffState.same)
              Checkbox(value: selected, onChanged: onChanged)
            else
              const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}
