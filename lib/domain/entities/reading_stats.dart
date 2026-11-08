/// 阅读统计实体（纯数据，页面/图表用）。
library;

/// 单日阅读聚合。
class DailyReadingStat {
  const DailyReadingStat({
    required this.day,
    required this.durationMs,
    required this.charsRead,
    required this.sessions,
  });

  /// 本地日期 yyyy-MM-dd。
  final String day;

  /// 当日阅读时长（ms）。
  final int durationMs;

  /// 当日读过的字符数。
  final int charsRead;

  /// 当日会话数。
  final int sessions;

  /// 当日分钟数（整数，图表展示用）。
  int get minutes => durationMs ~/ 60000;

  /// 当日小时数（一位小数）。
  double get hours => durationMs / 3600000;
}

/// 统计总览。
class ReadingStats {
  const ReadingStats({
    required this.todayDurationMs,
    required this.todayChars,
    required this.totalDurationMs,
    required this.totalChars,
    required this.totalDays,
    required this.streakDays,
    required this.recentDays,
    required this.dailyGoalMinutes,
  });

  /// 今日时长（ms）。
  final int todayDurationMs;

  /// 今日字符数。
  final int todayChars;

  /// 累计时长（ms）。
  final int totalDurationMs;

  /// 累计字符数。
  final int totalChars;

  /// 有阅读记录的总天数。
  final int totalDays;

  /// 连续阅读天数（含今天；今天未读则从昨天算）。
  final int streakDays;

  /// 最近 N 天（旧→新，缺失日补 0）。
  final List<DailyReadingStat> recentDays;

  /// 每日目标（分钟）。
  final int dailyGoalMinutes;

  /// 平均阅读速度（字/分钟）；无时长返回 0。
  double get charsPerMinute {
    if (totalDurationMs <= 0) return 0;
    return totalChars / (totalDurationMs / 60000);
  }

  /// 今日目标完成比例 0..1。
  double get todayGoalProgress {
    if (dailyGoalMinutes <= 0) return 0;
    return (todayDurationMs / 60000 / dailyGoalMinutes).clamp(0.0, 1.0);
  }
}
