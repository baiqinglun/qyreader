/// 书架筛选条件：最低星级 + 标签（任一）+ 阅读状态（任一）。
library;

import 'package:flutter/foundation.dart';

import '../../domain/entities/book.dart';

/// 书架筛选条件。
@immutable
class ShelfFilter {
  /// 创建筛选条件；[minRating] 0 = 不限星级，[tags] 为空 = 不限标签，
  /// [statuses] 为空 = 不限阅读状态。
  const ShelfFilter({
    this.minRating = 0,
    this.tags = const <String>{},
    this.statuses = const <BookReadStatus>{},
  });

  /// 最低星级（0..5）。
  final int minRating;

  /// 选中的标签；命中任意一个即可。
  final Set<String> tags;

  /// 选中的阅读状态；命中任意一个即可。
  final Set<BookReadStatus> statuses;

  /// 是否设置了有效筛选。
  bool get active => minRating > 0 || tags.isNotEmpty || statuses.isNotEmpty;

  /// 书籍是否命中筛选。
  bool matches(Book book) {
    if (minRating > 0 && (book.rating ?? 0) < minRating) return false;
    if (tags.isNotEmpty && !book.tags.any(tags.contains)) return false;
    if (statuses.isNotEmpty && !statuses.contains(book.readStatus)) {
      return false;
    }
    return true;
  }

  /// 复制并覆盖。
  ShelfFilter copyWith({
    int? minRating,
    Set<String>? tags,
    Set<BookReadStatus>? statuses,
  }) {
    return ShelfFilter(
      minRating: minRating ?? this.minRating,
      tags: tags ?? this.tags,
      statuses: statuses ?? this.statuses,
    );
  }
}
