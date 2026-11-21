/// 层级分类的纯数据模型与操作（分类管理页用）。
///
/// 分类的层级用「/」表达：书的 `category` 字段可以是 `小说`，也可以是
/// `小说/科幻`——管理页把它解析成树：`科幻` 是 `小说` 的子分类，计数
/// 含所有后代。空分类（0 本书）由调用方持久化（prefs 的
/// `categories.extra`），与书的分类合并后一起建树。
///
/// 所有函数都是纯函数，便于单测。
library;

import '../../domain/entities/book.dart' show ShelfItem;

/// 空分类（0 本书）的 prefs key。
const String kExtraCategoriesKey = 'categories.extra';

/// 一个分类节点。
class CategoryNode {
  const CategoryNode({
    required this.path,
    required this.name,
    required this.depth,
    required this.directCount,
    required this.totalCount,
    required this.children,
  });

  /// 全路径（如 `小说/科幻`）。
  final String path;

  /// 末段名（如 `科幻`）。
  final String name;

  /// 层级深度（顶层 0）。
  final int depth;

  /// 直接挂在该分类下的书数（不含子分类）。
  final int directCount;

  /// 直接 + 所有后代的书数。
  final int totalCount;

  /// 子分类（按名称排序）。
  final List<CategoryNode> children;

  /// 是否有子分类。
  bool get hasChildren => children.isNotEmpty;
}

/// 收集所有分类路径（书的 + 额外空分类），去重。
List<String> collectCategoryPaths({
  required Iterable<ShelfItem> items,
  Iterable<String> extraPaths = const <String>[],
}) {
  final out = <String>{};
  for (final item in items) {
    final c = item.book.category?.trim() ?? '';
    if (c.isNotEmpty) out.add(c);
  }
  for (final e in extraPaths) {
    final c = e.trim();
    if (c.isNotEmpty) out.add(c);
  }
  return out.toList();
}

/// 分类是否位于某路径的子树内（含自身）。
bool categoryUnderPath(String category, String path) =>
    category == path || category.startsWith('$path/');

/// 子树整体改名：把 [category] 里的 [from] 前缀换成 [to]；不在子树内原样返回。
String renameCategoryPath(String category, String from, String to) {
  if (!categoryUnderPath(category, from)) return category;
  return '$to${category.substring(from.length)}';
}

/// 分类路径的父级（`小说/科幻` → `小说`；顶层返回空串）。
String parentCategoryOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}

/// 只改末段名、保留父级的完整新路径（`小说/科幻` 改名 `奇幻` → `小说/奇幻`）。
String renameCategorySegment(String path, String newName) {
  final parent = parentCategoryOf(path);
  return parent.isEmpty ? newName : '$parent/$newName';
}

/// 把整个子树挪到 [newParent] 下；[newParent] 空 = 移到顶层。
String moveCategoryUnder(String path, String newParent) => newParent.isEmpty
    ? path.split('/').last
    : '$newParent/${path.split('/').last}';

/// 目标路径是否与现有分类撞名（[from] 子树内的不算，它们会跟着迁移）；
/// 返回撞名的现有路径，没有冲突返回 null。
String? categoryPathConflict(
  Iterable<String> paths,
  String from,
  String newPath,
) {
  for (final p in paths) {
    if (categoryUnderPath(p, from)) continue;
    if (p == newPath) return p;
  }
  return null;
}

/// 建树（子分类按名称排序）。
List<CategoryNode> buildCategoryTree({
  required Iterable<ShelfItem> items,
  Iterable<String> extraPaths = const <String>[],
}) {
  final paths = collectCategoryPaths(items: items, extraPaths: extraPaths);

  // 直接挂书数（按完整路径）
  final direct = <String, int>{};
  for (final item in items) {
    final c = item.book.category?.trim() ?? '';
    if (c.isEmpty) continue;
    direct[c] = (direct[c] ?? 0) + 1;
  }

  // 节点字典（中间路径也建节点）
  final names = <String, String>{};
  final depths = <String, int>{};
  final counts = <String, int>{};
  for (final path in paths) {
    final segments = path.split('/');
    var prefix = '';
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i].trim();
      if (seg.isEmpty) continue;
      prefix = prefix.isEmpty ? seg : '$prefix/$seg';
      names.putIfAbsent(prefix, () => seg);
      depths.putIfAbsent(prefix, () => i);
      if (i == segments.length - 1) {
        counts[prefix] = (counts[prefix] ?? 0) + (direct[path] ?? 0);
      }
    }
  }

  CategoryNode? build(String prefix, int depth) {
    final childNames = <String>[];
    for (final path in names.keys) {
      if (depths[path] == depth && parentCategoryOf(path) == prefix) {
        childNames.add(path);
      }
    }
    childNames.sort((a, b) => names[a]!.compareTo(names[b]!));
    if (childNames.isEmpty) return null;
    final children = <CategoryNode>[];
    var total = 0;
    for (final path in childNames) {
      final child = build(path, depth + 1);
      final own = counts[path] ?? 0;
      final nodeTotal = own + (child?.totalCount ?? 0);
      total += nodeTotal;
      children.add(
        CategoryNode(
          path: path,
          name: names[path]!,
          depth: depth,
          directCount: own,
          totalCount: nodeTotal,
          children: child?.children ?? const <CategoryNode>[],
        ),
      );
    }
    // 仅用于递归返回；根级调用方取 children
    return CategoryNode(
      path: prefix,
      name: names[prefix] ?? prefix,
      depth: depth,
      directCount: counts[prefix] ?? 0,
      totalCount: total,
      children: children,
    );
  }

  final root = build('', 0);
  return root?.children ?? const <CategoryNode>[];
}

/// 把树展平成可见行（折叠集 + 搜索词；搜索时全部展开并只留匹配节点）。
List<CategoryNode> flattenCategoryTree(
  List<CategoryNode> roots,
  Set<String> collapsed,
  String? query,
) {
  final out = <CategoryNode>[];
  final searching = query != null && query.isNotEmpty;
  void walk(List<CategoryNode> nodes) {
    for (final n in nodes) {
      final matches =
          !searching || n.path.toLowerCase().contains(query.toLowerCase());
      if (matches) out.add(n);
      // 搜索时全部展开；平时按折叠集
      if (n.hasChildren && (searching || !collapsed.contains(n.path))) {
        walk(n.children);
      }
    }
  }

  walk(roots);
  return out;
}
