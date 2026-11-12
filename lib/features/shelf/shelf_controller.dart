/// 书架控制器：书籍流 + 导入状态机 + 首屏排版单元。
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/providers.dart';
import '../../domain/entities/book.dart';
import 'shelf_prefs.dart';

part 'shelf_controller.freezed.dart';
part 'shelf_controller.g.dart';

/// 导入状态。
@freezed
sealed class ImportState with _$ImportState {
  /// 空闲。
  const factory ImportState.idle() = ImportIdle;

  /// 解析/写库中。
  const factory ImportState.loading() = ImportLoading;

  /// 导入完成（可能部分失败）。
  const factory ImportState.done(
    List<Book> books, {
    @Default(<String>[]) List<String> failures,
  }) = ImportDone;

  /// 导入失败（含重复导入提示）。
  const factory ImportState.error(String message) = ImportError;
}

/// 书架书籍流（未删除、按最近打开排序）。
@riverpod
Stream<List<ShelfItem>> shelfItems(Ref ref) async* {
  final repo = await ref.watch(bookRepositoryProvider.future);
  yield* repo.watchShelf();
}

/// 书架里出现过的分类（去空、按名称排序）。
List<String> shelfCategories(List<ShelfItem> items) {
  final set = <String>{};
  for (final item in items) {
    final c = item.book.category?.trim();
    if (c != null && c.isNotEmpty) set.add(c);
  }
  return set.toList()..sort();
}

/// 按分类筛选；[filter] 空 = 全部。
///
/// 分类名按去掉首尾空格后比较：入库的分类可能带空格，而分类名本身是
/// 去空格后的值，不这样比会让那本书从书架里消失。
List<ShelfItem> filterShelfByCategory(List<ShelfItem> items, String filter) {
  if (filter.isEmpty) return items;
  return items
      .where((it) => (it.book.category?.trim() ?? '') == filter)
      .toList();
}

/// 书架「根目录」的书：没有分类的书（分类里的书不算根目录）。
List<ShelfItem> rootShelfItems(List<ShelfItem> items) => [
      for (final item in items)
        if ((item.book.category?.trim() ?? '').isEmpty) item,
    ];

/// 书架首屏的一格：分类卡，或一本没有分类的书。
sealed class ShelfCell {
  const ShelfCell();
}

/// 分类格：点开看该分类下的书。
final class ShelfCategoryCell extends ShelfCell {
  const ShelfCategoryCell({required this.title, required this.books});

  /// 分类名（同时是筛选值）。
  final String title;

  /// 该分类下的全部书（卡片只取前几本封面做预览）。
  final List<ShelfItem> books;
}

/// 散落的书格：没有分类的书各占一格。
final class ShelfBookCell extends ShelfCell {
  const ShelfBookCell(this.item);

  /// 书架条目。
  final ShelfItem item;
}

/// 书架首屏：分类在前，没有分类的书散落在后面。
///
/// 有分类的书只出现在分类格里（点开分类才看得到），不单独占格；这样
/// 分类和书是同一套格子里的内容，一行三个一路排下去。
List<ShelfCell> shelfCells(List<ShelfItem> items) {
  final cells = <ShelfCell>[
    for (final category in shelfCategories(items))
      ShelfCategoryCell(
        title: category,
        books: filterShelfByCategory(items, category),
      ),
  ];
  for (final item in items) {
    if ((item.book.category?.trim() ?? '').isEmpty) {
      cells.add(ShelfBookCell(item));
    }
  }
  return cells;
}

/// 书架一行摆几格：默认自动（手机 3 格，宽屏每格约 140dp 加列），
/// 也可以在书架设置里固定 3/4/5 格。
int shelfColumns(double width, {ShelfColumnCount columns = ShelfColumnCount.auto}) {
  return columns.resolve(width);
}

/// 最近在读：打开过的书，置顶优先，再按最近打开时间倒序，最多 [limit] 本。
///
/// 书架上「刚打开的」要排到最上面，但置顶书的优先级更高；从没打开过的
/// 书（lastOpenedAt 为空）不进入竖排架。
List<ShelfItem> recentlyReadItems(List<ShelfItem> items, {int limit = 20}) {
  final read = <ShelfItem>[
    for (final item in items)
      if (item.book.lastOpenedAt != null) item,
  ]..sort(
      (a, b) {
        final aPin = a.book.pinnedAt ?? 0;
        final bPin = b.book.pinnedAt ?? 0;
        if (aPin != bPin) return bPin - aPin;
        return b.book.lastOpenedAt!.compareTo(a.book.lastOpenedAt!);
      },
    );
  if (read.length <= limit) return read;
  return read.sublist(0, limit);
}

/// 按书架设置排序：置顶始终在前，其次按所选字段升/降序。
///
/// 同字段相等的书保持仓库返回的原始顺序（稳定排序），避免每次刷新跳动。
List<ShelfItem> sortShelfItems(
  List<ShelfItem> items, {
  required ShelfSortField field,
  required bool ascending,
}) {
  int primary(ShelfItem a, ShelfItem b) {
    switch (field) {
      case ShelfSortField.title:
        return a.book.title
            .trim()
            .toLowerCase()
            .compareTo(b.book.title.trim().toLowerCase());
      case ShelfSortField.added:
        return a.book.addedAt.compareTo(b.book.addedAt);
      case ShelfSortField.lastOpened:
        return (a.book.lastOpenedAt ?? 0)
            .compareTo(b.book.lastOpenedAt ?? 0);
    }
  }

  final indexed = <(int, ShelfItem)>[
    for (var i = 0; i < items.length; i++) (i, items[i]),
  ];
  indexed.sort((a, b) {
    final aPin = a.$2.book.pinnedAt ?? 0;
    final bPin = b.$2.book.pinnedAt ?? 0;
    if (aPin != bPin) return bPin - aPin;
    final byField = primary(a.$2, b.$2);
    if (byField != 0) return ascending ? byField : -byField;
    return a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

/// 导入控制器。
@riverpod
class ImportController extends _$ImportController {
  @override
  ImportState build() => const ImportState.idle();

  /// 弹出文件选择器并导入（支持多选 EPUB / TXT / Markdown）。
  Future<void> importFromPicker() async {
    if (state is ImportLoading) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub', 'txt', 'md', 'markdown'],
      allowMultiple: true,
      withData: false,
    );
    final paths = (picked?.files ?? const [])
        .map((f) => f.path)
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .toList();
    if (paths.isEmpty) return; // 用户取消选择
    await importPaths(paths);
  }

  /// 导入单个文件（文件管理器「打开方式」用）；返回导入成功（或已在
  /// 架上）的书。系统重建 Activity 会重新投递同一文件，重复时返回已有
  /// 书籍让调用方直接回到阅读页。
  Future<Book?> importFromPath(String path) async {
    if (state is ImportLoading) return null;
    state = const ImportState.loading();
    final books = <Book>[];
    final failures = <String>[];
    try {
      final repo = await ref.read(bookRepositoryProvider.future);
      final result = await repo.importFromFile(path, returnExistingOnDuplicate: true);
      result.when(
        ok: books.add,
        failure: (e) => failures.add(e.message),
      );
    } catch (e) {
      failures.add('导入失败：$e');
    }
    state = books.isEmpty
        ? ImportState.error(failures.join('\n'))
        : ImportState.done(books, failures: failures);
    return books.isEmpty ? null : books.first;
  }

  /// 逐个导入；单本失败不阻断其余文件。
  Future<List<Book>> importPaths(List<String> paths) async {
    if (paths.isEmpty || state is ImportLoading) return const <Book>[];
    state = const ImportState.loading();
    final books = <Book>[];
    final failures = <String>[];
    try {
      final repo = await ref.read(bookRepositoryProvider.future);
      for (final path in paths) {
        try {
          final result = await repo.importFromFile(path);
          result.when(
            ok: books.add,
            failure: (e) => failures.add(e.message),
          );
        } catch (e) {
          failures.add('导入失败：$e');
        }
      }
    } catch (e) {
      failures.add('导入失败：$e');
    }
    state = books.isEmpty
        ? ImportState.error(failures.join('\n'))
        : ImportState.done(books, failures: failures);
    return books;
  }

  /// UI 消费完 done/error 状态后回到 idle。
  void consume() => state = const ImportState.idle();
}
