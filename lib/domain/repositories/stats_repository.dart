/// 阅读统计仓储接口（领域层）。
library;

import '../entities/reading_stats.dart';

/// 统计仓储。
abstract interface class StatsRepository {
  /// 记录一次阅读会话（写 sessions + 按日聚合 daily_stats）。
  ///
  /// [countedDurationMs]：计入统计的时长（单页封顶后的合计）；
  /// 不传 = 按 endedAt - startedAt 全额计入。
  Future<void> recordSession({
    required String bookId,
    required int startedAt,
    required int endedAt,
    required int charsRead,
    int? countedDurationMs,
  });

  /// 统计总览（[recentDayCount] 天趋势 + 目标）。
  Future<ReadingStats> overview({int recentDayCount});

  /// 某个周期的统计（日/周/月/年；[anchor] 决定所在周期）。
  Future<PeriodReadingStats> periodStats(StatsPeriod period, DateTime anchor);

  /// 读取每日目标（分钟）。
  Future<int> dailyGoalMinutes();

  /// 写入每日目标（分钟；0 = 不设目标）。
  Future<void> setDailyGoalMinutes(int minutes);

  /// 某本书累计阅读时长（ms；来自 daily_stats 单书聚合）。
  Future<int> bookTotalDurationMs(String bookId);

  /// 所有书的累计阅读数据（「我的阅读」按书汇总一次查完）。
  Future<List<BookReadingTotal>> bookTotals();

  /// 某本书最近 [days] 天的每日阅读时长。
  ///
  /// key = 本地日期 yyyy-MM-dd（无阅读的天不在结果里），value = 时长 ms。
  Future<Map<String, int>> bookDailyDurations(String bookId, {int days});
}
