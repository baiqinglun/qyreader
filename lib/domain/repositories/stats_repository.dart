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

  /// 某个周期的统计（日/周/月/年；[anchor] 决定所在周期）。
  Future<PeriodReadingStats> periodStats(
    StatsPeriod period,
    DateTime anchor,
  );

  /// 读取每日目标（分钟）。
  Future<int> dailyGoalMinutes();

  /// 写入每日目标（分钟；0 = 不设目标）。
  Future<void> setDailyGoalMinutes(int minutes);

  /// 某本书累计阅读时长（ms；来自 daily_stats 单书聚合）。
  Future<int> bookTotalDurationMs(String bookId);

  /// 某本书最近 [days] 天的每日阅读时长。
  ///
  /// key = 本地日期 yyyy-MM-dd（无阅读的天不在结果里），value = 时长 ms。
  Future<Map<String, int>> bookDailyDurations(String bookId, {int days});
}
