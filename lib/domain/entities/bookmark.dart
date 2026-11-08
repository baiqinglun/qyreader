/// 书签实体。
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'bookmark.freezed.dart';

/// 一条书签。位置信息全在 [locator]（Locator JSON，含 cfi/href/chapterIndex），
/// 不设冗余列——单一数据源。
@freezed
abstract class Bookmark with _$Bookmark {
  const factory Bookmark({
    /// uuid v4。
    required String id,

    /// 所属书籍。
    required String bookId,

    /// 位置 Locator JSON。
    required String locator,

    /// 用户标签。
    String? label,

    /// 创建时间（epoch ms）。
    required int createdAt,
  }) = _Bookmark;
}
