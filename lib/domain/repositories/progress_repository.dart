/// 阅读进度仓储接口（领域层）。
library;

import '../entities/reading_progress.dart';

/// 进度仓储。
abstract interface class ProgressRepository {
  /// 查询某本书的进度；从未读过返回 null。
  Future<ReadingProgressSnapshot?> getProgress(String bookId);

  /// 保存进度。
  ///
  /// 合并规则（见架构文档 6.3）：当前进度按 LWW；最远进度取
  /// max(percent) 永不回退；同事务追加 sync_ops。
  Future<void> saveProgress({
    required String bookId,
    required String locator,
    required double percent,
  });

  /// 用外部阅读器（微信读书）的百分比写进度。
  ///
  /// 外部只有百分比，没有本机 CFI/字符坐标；这里按章节字数把百分比换算成
  /// 「章索引 + 章内字符偏移」再走 [saveProgress]，这样重新打开书能落到
  /// 大致正确的位置，而不是回到第一页。
  Future<void> saveExternalProgress({
    required String bookId,
    required double percent,
  });
}
