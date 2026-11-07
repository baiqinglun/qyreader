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
}
