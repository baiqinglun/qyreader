/// 作者分组：把书架的书按作者归组，供作者管理页展示。
///
/// 纯函数，方便单测；页面只负责展示、跳转与批量重命名。
library;

import '../../domain/entities/book.dart';

/// 未知作者的展示名。
const String kUnknownAuthorLabel = '未知作者';

/// 未知作者卡片的说明文案（点击可进入书籍列表补全作者）。
const String kUnknownAuthorHint = '这些书没有作者信息，点击查看并补全';

/// 一位作者（或未知作者）名下的全部书籍。
class AuthorGroup {
  /// 构造。
  const AuthorGroup({required this.key, required this.books});

  /// 作者名（trim 后）；空字符串 = 未知作者。
  final String key;

  /// 该作者名下的书（组内保持书架原始顺序）。
  final List<ShelfItem> books;

  /// 是否未知作者（author 为空 / 空白）。
  bool get isUnknown => key.isEmpty;

  /// 展示名：未知作者组显示「未知作者」。
  String get displayName => isUnknown ? kUnknownAuthorLabel : key;
}

/// 按作者分组：未知作者组在最前，其余按书数降序、同数按名字排。
///
/// 作者名按 trim 后精确匹配；「（美）约翰」和「约翰」算两位作者，
/// 不做括号归并（批量重命名可以手动合并，见作者管理页菜单）。
List<AuthorGroup> groupBooksByAuthor(List<ShelfItem> items) {
  final byKey = <String, List<ShelfItem>>{};
  for (final item in items) {
    byKey.putIfAbsent((item.book.author ?? '').trim(), () => []).add(item);
  }
  final groups = <AuthorGroup>[
    for (final entry in byKey.entries)
      AuthorGroup(key: entry.key, books: entry.value),
  ];
  groups.sort((a, b) {
    if (a.isUnknown != b.isUnknown) return a.isUnknown ? -1 : 1;
    if (a.books.length != b.books.length) {
      return b.books.length - a.books.length;
    }
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  });
  return groups;
}

/// 按关键字过滤分组：作者名或组内任一书名命中即保留。
List<AuthorGroup> filterAuthorGroups(List<AuthorGroup> groups, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return groups;
  return [
    for (final group in groups)
      if (group.displayName.toLowerCase().contains(q) ||
          group.books.any(
            (item) => item.book.title.toLowerCase().contains(q),
          ))
        group,
  ];
}
