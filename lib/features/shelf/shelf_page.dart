/// 书架页：网格布局 + 空态 + 导入入口。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/transitions/book_open_transition.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/skeleton.dart';
import '../../domain/entities/book.dart';
import '../../features/reader/fonts/reader_fonts.dart';
import '../../features/settings/appearance_provider.dart';
import '../tags/tag_library.dart';
import 'shelf_controller.dart';
import 'shelf_filter.dart';
import 'shelf_prefs.dart';
import 'widgets/book_actions_sheet.dart';
import 'widgets/batch_actions.dart';
import 'widgets/recent_shelf.dart';
import 'widgets/shelf_filter_sheet.dart';
import 'widgets/shelf_flow.dart';
import 'widgets/shelf_settings_sheet.dart';
import 'widgets/sync_sheet.dart';

/// 首页：书架。
class ShelfPage extends ConsumerStatefulWidget {
  const ShelfPage({super.key});

  @override
  ConsumerState<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends ConsumerState<ShelfPage> {
  /// 书名搜索词（空 = 不搜索）。
  String _query = '';

  /// 星级 / 标签筛选（与搜索叠加）。
  ShelfFilter _filter = const ShelfFilter();

  /// 多选模式与已选书籍 id。
  bool _selectionMode = false;
  final Set<String> _selectedBookIds = {};
  bool _batchBusy = false;

  /// 右上角快捷同步进行中（按钮显示小菊花，防重复点击）。
  bool _syncing = false;

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 右上角「同步」按钮：不打开面板，直接同步一次并给出结果提示。
  Future<void> _quickSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(syncRepositoryProvider.future);
      final result = await repo.syncNow();
      // 字体也参与同步：拉回来的字体立刻出现在字体列表里（不用重启）
      unawaited(ref.read(readerFontsControllerProvider.notifier).reload());
      messenger.showSnackBar(
        SnackBar(content: Text(syncResultSummary(result))),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('同步失败：$e')));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(shelfItemsProvider);
    final importing = ref.watch(importControllerProvider) is ImportLoading;
    final rawFilter = ref.watch(shelfCategoryFilterProvider);
    final categories = items.valueOrNull == null
        ? const <String>[]
        : shelfCategories(items.valueOrNull!);
    final filter = _effectiveCategory(rawFilter, categories);
    final scheme = Theme.of(context).colorScheme;

    ref.listen<ImportState>(importControllerProvider, (prev, next) {
      final messenger = ScaffoldMessenger.of(context);
      if (next case ImportDone(:final books, :final failures)) {
        final base = books.length == 1
            ? '已导入《${books.first.title}》'
            : '已导入 ${books.length} 本书';
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              failures.isEmpty ? base : '$base，${failures.length} 本失败',
            ),
          ),
        );
        ref.read(importControllerProvider.notifier).consume();
      } else if (next case ImportError(:final message)) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
        ref.read(importControllerProvider.notifier).consume();
      }
    });

    return Scaffold(
      appBar: AppBar(
        // 多选：左上角关闭；分类：标题换成分类名，左上角返回书架首屏。
        leading: _selectionMode
            ? IconButton(
                tooltip: '退出多选',
                onPressed: _exitSelection,
                icon: const Icon(Icons.close),
              )
            : filter.isEmpty
            ? null
            : IconButton(
                tooltip: '返回书架',
                onPressed: () =>
                    ref.read(shelfCategoryFilterProvider.notifier).set(''),
                icon: const Icon(Icons.arrow_back),
              ),
        title: Text(
          _selectionMode
              ? '已选择 ${_selectedBookIds.length} 本'
              : (filter.isEmpty ? '书架' : filter),
        ),
        // 右上角：直接同步 / 亮暗切换 / 「⋯」菜单（书架设置 + 导入）。
        actions: _selectionMode
            ? const [SizedBox(width: 8)]
            : [
                IconButton(
                  key: const ValueKey('shelf-sync-button'),
                  tooltip: _syncing ? '正在同步' : '同步',
                  onPressed: _syncing ? null : _quickSync,
                  icon: _syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync_outlined),
                ),
                IconButton(
                  key: const ValueKey('shelf-theme-mode-button'),
                  tooltip: Theme.of(context).brightness == Brightness.dark
                      ? '切换为亮色'
                      : '切换为暗色',
                  onPressed: () => ref
                      .read(appThemeModeControllerProvider.notifier)
                      .toggle(Theme.of(context).brightness),
                  icon: Icon(
                    Theme.of(context).brightness == Brightness.dark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '更多',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'import') {
                      ref
                          .read(importControllerProvider.notifier)
                          .importFromPicker();
                    } else if (value == 'shelfSettings') {
                      unawaited(showShelfSettingsSheet(context));
                    } else if (value == 'select') {
                      _enterSelection();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'select',
                      child: Row(
                        children: [
                          const Icon(Icons.checklist, size: 18),
                          const SizedBox(width: 10),
                          const Text('多选'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'shelfSettings',
                      child: Row(
                        children: [
                          const Icon(Icons.tune, size: 18),
                          const SizedBox(width: 10),
                          const Text('书架设置'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'import',
                      enabled: !importing,
                      child: Row(
                        children: [
                          const Icon(Icons.file_upload_outlined, size: 18),
                          const SizedBox(width: 10),
                          const Text('导入书籍'),
                          const Spacer(),
                          if (importing)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
              ],
        bottom: _selectionMode
            ? null
            : PreferredSize(
                preferredSize: Size.fromHeight(importing ? 57 : 54),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (importing) const LinearProgressIndicator(minHeight: 3),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: TextField(
                                controller: _searchController,
                                onChanged: (value) =>
                                    setState(() => _query = value.trim()),
                                textInputAction: TextInputAction.search,
                                style: const TextStyle(fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: '搜索书名',
                                  hintStyle: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                  ),
                                  isDense: true,
                                  filled: true,
                                  fillColor: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.55),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    size: 20,
                                  ),
                                  prefixIconConstraints: const BoxConstraints(
                                    minWidth: 40,
                                  ),
                                  suffixIcon: _query.isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: '清空搜索',
                                          icon: const Icon(
                                            Icons.close,
                                            size: 18,
                                          ),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _query = '');
                                          },
                                        ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: Badge(
                              isLabelVisible: _filter.active,
                              smallSize: 8,
                              child: IconButton(
                                key: const ValueKey('shelf-filter-button'),
                                tooltip: '筛选',
                                onPressed: _openShelfFilter,
                                style: IconButton.styleFrom(
                                  backgroundColor: _filter.active
                                      ? scheme.primaryContainer
                                      : scheme.surfaceContainerHighest
                                            .withValues(alpha: 0.55),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: Icon(
                                  Icons.filter_list,
                                  size: 20,
                                  color: _filter.active
                                      ? scheme.onPrimaryContainer
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
      body: items.when(
        loading: () => const _SkeletonGrid(),
        error: (error, stack) => EmptyState(
          icon: Icons.error_outline,
          title: '书架加载失败',
          message: '$error',
        ),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: Icons.auto_stories_outlined,
                title: '书架空空如也',
                message: '导入 EPUB / TXT / Markdown，开始阅读之旅',
                actionLabel: '选择文件（可多选）',
                onAction: importing
                    ? null
                    : () => ref
                          .read(importControllerProvider.notifier)
                          .importFromPicker(),
              )
            : _BookShelf(
                items: list,
                filter: filter,
                query: _query,
                shelfFilter: _filter,
                onClearFilter: () =>
                    setState(() => _filter = const ShelfFilter()),
                selectionMode: _selectionMode,
                selectedBookIds: _selectedBookIds,
                onToggleSelect: _toggleSelect,
                onExitSelection: _exitSelection,
              ),
      ),
      bottomNavigationBar: _selectionMode
          ? _SelectionBar(
              count: _selectedBookIds.length,
              busy: _batchBusy,
              onDelete: _deleteSelected,
              onAddTags: _addTagsSelected,
              onMoveToShelf: _moveSelectedToShelf,
            )
          : null,
    );
  }

  /// 打开筛选弹层；返回 null 表示取消。
  Future<void> _openShelfFilter() async {
    final tags = ref
        .read(tagSummariesProvider)
        .map((t) => t.name)
        .toList(growable: false);
    final result = await showShelfFilterSheet(
      context,
      initial: _filter,
      tags: tags,
    );
    if (result == null || !mounted) return;
    setState(() => _filter = result);
  }

  void _enterSelection() {
    setState(() {
      _selectionMode = true;
      _selectedBookIds.clear();
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedBookIds.clear();
      _batchBusy = false;
    });
  }

  void _toggleSelect(ShelfItem item) {
    setState(() {
      if (!_selectedBookIds.add(item.book.id)) {
        _selectedBookIds.remove(item.book.id);
      }
    });
  }

  List<ShelfItem> _selectedItems() {
    final all = ref.read(shelfItemsProvider).valueOrNull ?? const <ShelfItem>[];
    return [
      for (final item in all)
        if (_selectedBookIds.contains(item.book.id)) item,
    ];
  }

  Future<void> _deleteSelected() async {
    final selected = _selectedItems();
    if (selected.isEmpty || _batchBusy) return;
    final choice = await showBatchDeleteDialog(context, count: selected.length);
    if (choice == null || !mounted) return;
    setState(() => _batchBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    var deleted = 0;
    var failed = 0;
    try {
      final repo = await ref.read(bookRepositoryProvider.future);
      for (final item in selected) {
        try {
          await repo.deleteBook(
            item.book.id,
            deleteAnnotations: choice == BatchDeleteMode.all,
          );
          deleted++;
        } catch (_) {
          failed++;
        }
        try {
          final sync = await ref.read(syncRepositoryProvider.future);
          await sync.deleteCloudBook(
            item.book.id,
            fileSha256: item.book.fileSha256,
          );
        } catch (_) {
          // 云端清理失败不影响本地删除，下次同步墓碑会再试。
        }
      }
      if (!mounted) return;
      _exitSelection();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failed == 0 ? '已删除 $deleted 本书' : '已删除 $deleted 本，$failed 本失败',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  Future<void> _addTagsSelected() async {
    final selected = _selectedItems();
    if (selected.isEmpty || _batchBusy) return;
    final knownTags = ref
        .read(tagSummariesProvider)
        .map((t) => t.name)
        .toList(growable: false);
    final tags = await showBatchTagSheet(
      context,
      count: selected.length,
      knownTags: knownTags,
    );
    if (tags == null || tags.isEmpty || !mounted) return;
    setState(() => _batchBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    var updated = 0;
    var failed = 0;
    try {
      final repo = await ref.read(bookRepositoryProvider.future);
      for (final item in selected) {
        final merged = [...item.book.tags];
        for (final tag in tags) {
          if (!merged.contains(tag)) merged.add(tag);
        }
        try {
          await repo.setPersonalization(item.book.id, tags: merged);
          updated++;
        } catch (_) {
          failed++;
        }
      }
      for (final tag in tags) {
        await ref.read(tagLibraryControllerProvider.notifier).add(tag);
      }
      if (!mounted) return;
      _exitSelection();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? '已为 $updated 本书添加标签：${tags.join('、')}'
                : '已更新 $updated 本，$failed 本失败',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  Future<void> _moveSelectedToShelf() async {
    final selected = _selectedItems();
    if (selected.isEmpty || _batchBusy) return;
    final all = ref.read(shelfItemsProvider).valueOrNull ?? const <ShelfItem>[];
    final target = await showBatchShelfSheet(
      context,
      count: selected.length,
      shelves: shelfCategories(all),
    );
    if (target == null || !mounted) return;
    setState(() => _batchBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    var updated = 0;
    var failed = 0;
    try {
      final repo = await ref.read(bookRepositoryProvider.future);
      for (final item in selected) {
        try {
          await repo.setPersonalization(item.book.id, category: target);
          updated++;
        } catch (_) {
          failed++;
        }
      }
      if (!mounted) return;
      _exitSelection();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? (target.isEmpty
                      ? '已把 $updated 本书移出分组'
                      : '已把 $updated 本书添加到「$target」')
                : '已更新 $updated 本，$failed 本失败',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }
}

/// 书架内容：顶部「最近在读」竖排架 + 分类和书混排的一屏。
///
/// 竖排架可以收起（默认显示，偏好落 prefs）；收起后留一行小入口，
/// 避免用户收起后找不到恢复的地方。竖排架只显示打开过的书，
/// 一本都没读过时整段不出现。
class _BookShelf extends ConsumerWidget {
  const _BookShelf({
    required this.items,
    required this.filter,
    required this.query,
    required this.shelfFilter,
    required this.onClearFilter,
    required this.selectionMode,
    required this.selectedBookIds,
    required this.onToggleSelect,
    required this.onExitSelection,
  });

  final List<ShelfItem> items;

  /// 正在看的分类（'' = 书架首屏：分类格 + 没有分类的书）。
  final String filter;

  /// 书名搜索词（空 = 不搜索；搜索时只摆命中的书，不摆分类）。
  final String query;

  /// 星级 / 标签筛选（与搜索叠加）。
  final ShelfFilter shelfFilter;

  /// 清除筛选条件。
  final VoidCallback onClearFilter;

  /// 多选模式。
  final bool selectionMode;

  /// 已选中的书籍 id。
  final Set<String> selectedBookIds;

  /// 切换一本书的选中状态。
  final ValueChanged<ShelfItem> onToggleSelect;

  /// 退出多选。
  final VoidCallback onExitSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(shelfViewModeControllerProvider);
    final prefs = ref.watch(shelfPrefsControllerProvider);
    final sorted = sortShelfItems(
      items,
      field: prefs.sortField,
      ascending: prefs.sortAscending,
    );
    // 多选只在「当前目录」里选：根目录 = 没有分类的书；分类里 = 该分类的书。
    final selectionScoped = filter.isEmpty
        ? rootShelfItems(sorted)
        : filterShelfByCategory(sorted, filter);
    final scoped = selectionMode
        ? selectionScoped
        : (filter.isEmpty ? sorted : filterShelfByCategory(sorted, filter));
    final searching = query.isNotEmpty;
    final filtering = shelfFilter.active;
    // 筛选、搜索或多选时压平成书格：分类卡不参与筛选结果，多选时
    // 也直接铺开所有书（分类里的书也能一起选）。
    final flatMode = searching || filtering || selectionMode;
    final lowerQuery = query.toLowerCase();
    final matches = <ShelfItem>[
      for (final item in scoped)
        if ((!searching ||
                item.book.title.toLowerCase().contains(lowerQuery)) &&
            shelfFilter.matches(item.book))
          item,
    ];
    // 首屏是「分类格 + 没有分类的书」混排；点进分类后只摆这个分类的书。
    final cells = flatMode
        ? <ShelfCell>[for (final book in matches) ShelfBookCell(book)]
        : filter.isEmpty
        ? shelfCells(sorted)
        : <ShelfCell>[for (final book in scoped) ShelfBookCell(book)];
    // 「最近在读」只在书架首屏、且没在搜索 / 筛选时出现。
    final recent = !flatMode && filter.isEmpty
        ? recentlyReadItems(items)
        : const <ShelfItem>[];
    final recentVisible = ref.watch(recentShelfVisibleProvider);
    final hasRecent = recent.isNotEmpty;
    // 一格多宽按屏宽算：默认手机上 3 个一行、平板自动加列；书架设置里
    // 也可以固定成 3/4/5 格。
    final columns = shelfColumns(
      MediaQuery.sizeOf(context).width - 32,
      columns: prefs.columns,
    );

    return PopScope(
      // 多选时系统返回键先退出多选；分类里再退回首屏。
      canPop: !selectionMode && filter.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (selectionMode) {
          onExitSelection();
        } else {
          ref.read(shelfCategoryFilterProvider.notifier).set('');
        }
      },
      child: CustomScrollView(
        slivers: [
          if (hasRecent)
            SliverToBoxAdapter(
              child: recentVisible
                  ? RecentShelf(
                      items: recent,
                      onOpen: (book) => _openBook(
                        context,
                        ref,
                        book.id,
                        kind: BookLaunchKind.spine,
                      ),
                      onManage: (book) => _manageBook(context, ref, book),
                      onHide: () => ref
                          .read(recentShelfVisibleProvider.notifier)
                          .set(false),
                    )
                  : CollapsedRecentShelf(
                      count: recent.length,
                      onShow: () => ref
                          .read(recentShelfVisibleProvider.notifier)
                          .set(true),
                    ),
            ),
          if (flatMode && matches.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 40, 32, 96),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        filtering ? Icons.filter_alt_off : Icons.search_off,
                        size: 40,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        searching && filtering
                            ? '没有找到同时符合搜索与筛选的书'
                            : searching
                            ? '没有找到「$query」'
                            : '没有符合筛选条件的书',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (filtering) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          key: const ValueKey('shelf-filter-clear'),
                          onPressed: onClearFilter,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('清除筛选'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, hasRecent ? 8 : 16, 16, 96),
              sliver: ShelfFlow(
                cells: cells,
                mode: viewMode,
                columns: columns,
                coverRadius: prefs.coverRadius.toDouble(),
                plankStyle: prefs.plankStyle,
                showProgress: prefs.showGridProgress,
                showRating: prefs.showRating,
                showTags: prefs.showTags,
                showDescription: prefs.showDescription,
                descriptionLines: prefs.descriptionLines,
                showReview: prefs.showReview,
                reviewLines: prefs.reviewLines,
                selectionMode: selectionMode,
                selectedBookIds: selectedBookIds,
                onToggleSelect: onToggleSelect,
                onOpenBook: (item) => _openBook(
                  context,
                  ref,
                  item.book.id,
                  coverPath: item.book.coverPath,
                ),
                onManageBook: (item) => _manageBook(context, ref, item.book),
                onOpenCategory: (category) => ref
                    .read(shelfCategoryFilterProvider.notifier)
                    .set(category),
              ),
            ),
        ],
      ),
    );
  }

  /// 长按书籍：先弹操作菜单（继续阅读 / 编辑信息 / 置顶 / 删除），
  /// 编辑进书籍详情页，删除走「笔记处置」确认。
  Future<void> _manageBook(
    BuildContext context,
    WidgetRef ref,
    Book book,
  ) async {
    final action = await showBookActionsSheet(context, book: book);
    if (action == null || !context.mounted) return;
    switch (action) {
      case BookShelfAction.continueReading:
        if (context.mounted) _openBook(context, ref, book.id);
      case BookShelfAction.edit:
        if (context.mounted) {
          unawaited(context.push(bookDetailPath(book.id)));
        }
      case BookShelfAction.moveToShelf:
        final repo = await ref.read(bookRepositoryProvider.future);
        final shelf = await repo.watchShelf().first;
        if (!context.mounted) return;
        final target = await showMoveToShelfSheet(
          context,
          book: book,
          shelves: shelfCategories(shelf),
        );
        if (target == null || !context.mounted) return;
        await repo.setPersonalization(
          book.id,
          // 空串 = 清除分类；null 现在表示「不改」，不能用来移出书架。
          category: target.isEmpty ? '' : target,
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(target.isEmpty ? '已移出书架' : '已移动到「$target」')),
        );
      case BookShelfAction.pin:
        final repo = await ref.read(bookRepositoryProvider.future);
        await repo.setPinned(book.id, book.pinnedAt == null);
      case BookShelfAction.clearCache:
        // 清缓存 = 先确保书源文件在同步库（没备份就立即上传），再删本地。
        // 正文/进度/标注都在数据库里，阅读不受影响；下次打开自动拉回文件。
        // 封面保留（清缓存不动封面，删除书时才删封面）。
        final sync = await ref.read(syncRepositoryProvider.future);
        final f = File(book.filePath);
        final hadLocal = await f.exists();
        final cleared = await sync.clearLocalBookCache(book.id);
        if (!context.mounted) return;
        if (!cleared) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('同步库中没有这本书的备份，清除失败')));
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(hadLocal ? '已清除本地缓存，阅读时会自动从同步库拉回' : '本地缓存已是清除状态'),
          ),
        );
      case BookShelfAction.delete:
        await confirmDeleteBook(context, ref, book: book);
    }
  }

  void _openBook(
    BuildContext context,
    WidgetRef ref,
    String bookId, {
    BookLaunchKind kind = BookLaunchKind.card,
    String? coverPath,
  }) {
    // 打开书：更新 last_opened_at（异步落库），并进入阅读器占位页。
    unawaited(
      ref
          .read(bookRepositoryProvider.future)
          .then((r) => r.touchOpened(bookId)),
    );
    // 从分类里打开书：阅读器退出后保留当前分类筛选，回到该分类页。
    // extra 带上来源：阅读路由据此播放「书封从书架升起」的转场。
    unawaited(
      context.push(
        readerPath(bookId),
        extra: BookLaunch(
          bookId: bookId,
          kind: kind,
          // 点击瞬间的位置兜底（正常退出时用书架的实时位置）
          rect: BookCoverRegistry.spotOf(kind, bookId)?.rect,
          coverPath: coverPath,
          radius: kind == BookLaunchKind.spine ? 2.5 : 12,
        ),
      ),
    );
  }
}

/// 多选底部操作条：删除 / 加标签 / 移动到分组。
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.busy,
    required this.onDelete,
    required this.onAddTags,
    required this.onMoveToShelf,
  });

  final int count;
  final bool busy;
  final VoidCallback onDelete;
  final VoidCallback onAddTags;
  final VoidCallback onMoveToShelf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = count > 0 && !busy;
    Widget action({
      required Key key,
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
      Color? color,
    }) {
      return Expanded(
        child: TextButton(
          key: key,
          onPressed: enabled ? onPressed : null,
          style: TextButton.styleFrom(
            foregroundColor: color,
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 3),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return Material(
      color: scheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: busy
              ? const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              : Row(
                  children: [
                    action(
                      key: const ValueKey('batch-delete-button'),
                      icon: Icons.delete_outline,
                      label: '删除',
                      color: scheme.error,
                      onPressed: onDelete,
                    ),
                    action(
                      key: const ValueKey('batch-tag-button'),
                      icon: Icons.sell_outlined,
                      label: '加标签',
                      onPressed: onAddTags,
                    ),
                    action(
                      key: const ValueKey('batch-shelf-button'),
                      icon: Icons.folder_outlined,
                      label: '分组',
                      onPressed: onMoveToShelf,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.72,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: 9,
      itemBuilder: (context, index) => const SkeletonBox(
        width: double.infinity,
        height: double.infinity,
        borderRadius: 12,
      ),
    );
  }
}

/// 当前生效的筛选分类：选中项已不存在（被改名/删光）时回退到首屏。
String _effectiveCategory(String raw, List<String> categories) {
  if (raw.isEmpty) return '';
  return categories.contains(raw) ? raw : '';
}
