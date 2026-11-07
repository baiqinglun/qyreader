/// 阅读进度领域实体。
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'reading_progress.freezed.dart';

/// 进度快照（定位与合并用；Locator 为 JSON 字符串，解码交给 core/locator）。
@freezed
abstract class ReadingProgressSnapshot with _$ReadingProgressSnapshot {
  const factory ReadingProgressSnapshot({
    /// 所属书籍 id。
    required String bookId,

    /// 当前位置（Locator JSON）。
    required String locator,

    /// 当前百分比 0..1。
    required double percent,

    /// 最远位置（Locator JSON）。
    String? furthestLocator,

    /// 最远百分比，合并取 max 永不回退。
    @Default(0) double furthestPercent,

    /// 更新时间（epoch ms）。
    required int updatedAt,
  }) = _ReadingProgressSnapshot;
}
