/// 阅读统计仓储接口（领域层）。
library;

import '../entities/reading_stats.dart';

/// 统计仓储。
abstract interface class StatsRepository {
  /// 记录一次阅读会话（写 sessions + 按日聚合 daily_stats）。
  Future<void> recordSession({
    required String bookId,
    required int startedAt,
    required int endedAt,
    required int charsRead,
  });

  /// 统计总览（[recentDayCount] 天趋势 + 目标）。
  Future<ReadingStats> overview({int recentDayCount});

  /// 读取每日目标（分钟）。
  Future<int> dailyGoalMinutes();

  /// 写入每日目标（分钟；0 = 不设目标）。
  Future<void> setDailyGoalMinutes(int minutes);
}
