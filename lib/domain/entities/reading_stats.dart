/// 阅读统计实体（纯数据，页面/图表用）。
library;

/// 统计周期粒度。
enum StatsPeriod {
  /// 日：按小时分桶。
  day('日'),

  /// 周：按天分桶（周一为一周起点）。
  week('周'),

  /// 月：按天分桶。
  month('月'),

  /// 年：按月分桶。
  year('年');

  const StatsPeriod(this.label);

  /// 展示名。
  final String label;
}

/// 周期内的一个时间桶（小时/天/月）。
class StatsBucket {
  const StatsBucket({
    required this.label,
    required this.durationMs,
    required this.charsRead,
  });

  /// 桶标签（如 09、11/02、3月）。
  final String label;

  /// 桶内阅读时长（ms）。
  final int durationMs;

  /// 桶内读过的字符数。
  final int charsRead;

  /// 分钟数（图表展示用）。
  int get minutes => durationMs ~/ 60000;
}

/// 周期内单本书的阅读明细（阅读内容）。
class BookReadingStat {
  const BookReadingStat({
    required this.bookId,
    required this.title,
    required this.durationMs,
    required this.charsRead,
    required this.sessions,
    this.exists = true,
  });

  /// 书籍 id。
  final String bookId;

  /// 书名（书已删除时给占位标题）。
  final String title;

  /// 时长（ms）。
  final int durationMs;

  /// 字符数。
  final int charsRead;

  /// 会话数。
  final int sessions;

  /// 书籍是否仍在书架（已删除的书不提供跳转）。
  final bool exists;
}

/// 某个周期的统计结果。
class PeriodReadingStats {
  const PeriodReadingStats({
    required this.period,
    required this.start,
    required this.end,
    required this.durationMs,
    required this.charsRead,
    required this.sessions,
    required this.buckets,
    required this.books,
  });

  /// 周期粒度。
  final StatsPeriod period;

  /// 周期开始（含）。
  final DateTime start;

  /// 周期结束（不含）。
  final DateTime end;

  /// 总时长（ms）。
  final int durationMs;

  /// 总字符数。
  final int charsRead;

  /// 会话数。
  final int sessions;

  /// 时间桶（日=24 小时，周=7 天，月=当月天数，年=12 月）。
  final List<StatsBucket> buckets;

  /// 按书籍聚合的内容明细（时长降序）。
  final List<BookReadingStat> books;

  /// 是否有数据。
  bool get hasData => durationMs > 0 || sessions > 0;

  /// 平均阅读速度（字/分）。
  double get charsPerMinute =>
      durationMs <= 0 ? 0 : charsRead / (durationMs / 60000);

  /// 是否可进入下一周期（当前周期/未来周期不可）。
  bool get canGoNext => end.isBefore(DateTime.now());
}

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
