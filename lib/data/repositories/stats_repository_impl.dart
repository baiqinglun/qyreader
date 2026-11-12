/// 阅读统计仓储实现：reading_sessions 明细 + daily_stats 物化聚合（可重算）。
library;

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../domain/entities/reading_stats.dart';
import '../../domain/repositories/stats_repository.dart';

/// 生产实现。
class StatsRepositoryImpl implements StatsRepository {
  /// 构造。
  StatsRepositoryImpl({
    required AppDatabase db,
    required this.deviceId,
  }) : _db = db;

  final AppDatabase _db;

  /// 本机设备 id（会话明细带写入设备，便于统计多设备合并后的总量）。
  final String deviceId;

  static const String _kGoalKey = 'stats.dailyGoalMinutes';
  static const Uuid _uuid = Uuid();

  @override
  Future<void> recordSession({
    required String bookId,
    required int startedAt,
    required int endedAt,
    required int charsRead,
  }) async {
    if (endedAt <= startedAt) return;
    final durationMs = endedAt - startedAt;
    // 极短会话（<10s）视为误触，不记录
    if (durationMs < 10000) return;
    final day = _dayOf(DateTime.fromMillisecondsSinceEpoch(startedAt));
    await _db.transaction(() async {
      await _db.into(_db.readingSessions).insert(
            ReadingSessionsCompanion.insert(
              id: _uuid.v4(),
              bookId: bookId,
              startedAt: startedAt,
              endedAt: endedAt,
              durationMs: durationMs,
              charsRead: Value(charsRead < 0 ? 0 : charsRead),
              deviceId: deviceId,
            ),
          );
      // 按日聚合两份：单书 + 全书合计（bookId=''）
      await _bumpDaily(day, bookId, durationMs, charsRead);
      await _bumpDaily(day, '', durationMs, charsRead);
    });
  }

  Future<void> _bumpDaily(
    String day,
    String bookId,
    int durationMs,
    int charsRead,
  ) async {
    final existing = await (_db.select(_db.dailyStats)
          ..where((r) => r.day.equals(day))
          ..where((r) => r.bookId.equals(bookId)))
        .getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.dailyStats).insert(
            DailyStatsCompanion.insert(
              day: day,
              bookId: Value(bookId),
              durationMs: Value(durationMs),
              charsRead: Value(charsRead < 0 ? 0 : charsRead),
              sessions: const Value(1),
            ),
          );
      return;
    }
    await (_db.update(_db.dailyStats)
          ..where((r) => r.day.equals(day))
          ..where((r) => r.bookId.equals(bookId)))
        .write(DailyStatsCompanion(
      durationMs: Value(existing.durationMs + durationMs),
      charsRead:
          Value(existing.charsRead + (charsRead < 0 ? 0 : charsRead)),
      sessions: Value(existing.sessions + 1),
    ));
  }

  @override
  Future<ReadingStats> overview({int recentDayCount = 14}) async {
    final now = DateTime.now();
    final today = _dayOf(now);

    final totalsRows = await (_db.select(_db.dailyStats)
          ..where((r) => r.bookId.equals('')))
        .get();
    var totalMs = 0;
    var totalChars = 0;
    var todayMs = 0;
    var todayChars = 0;
    final activeDays = <String>{};
    for (final r in totalsRows) {
      totalMs += r.durationMs;
      totalChars += r.charsRead;
      if (r.durationMs > 0) activeDays.add(r.day);
      if (r.day == today) {
        todayMs = r.durationMs;
        todayChars = r.charsRead;
      }
    }

    // 最近 N 天（旧→新，缺失补 0）
    final byDay = {for (final r in totalsRows) r.day: r};
    final recent = <DailyReadingStat>[];
    for (var i = recentDayCount - 1; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = _dayOf(d);
      final row = byDay[key];
      recent.add(DailyReadingStat(
        day: key,
        durationMs: row?.durationMs ?? 0,
        charsRead: row?.charsRead ?? 0,
        sessions: row?.sessions ?? 0,
      ));
    }

    final goal = await dailyGoalMinutes();
    return ReadingStats(
      todayDurationMs: todayMs,
      todayChars: todayChars,
      totalDurationMs: totalMs,
      totalChars: totalChars,
      totalDays: activeDays.length,
      streakDays: _streak(activeDays, now),
      recentDays: recent,
      dailyGoalMinutes: goal,
    );
  }

  /// 连续天数：从今天（或昨天，今天未读时）向前数连续有记录的日期。
  int _streak(Set<String> days, DateTime now) {
    if (days.isEmpty) return 0;
    var cursor = DateTime(now.year, now.month, now.day);
    if (!days.contains(_dayOf(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!days.contains(_dayOf(cursor))) return 0;
    }
    var streak = 0;
    while (days.contains(_dayOf(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  @override
  Future<PeriodReadingStats> periodStats(
    StatsPeriod period,
    DateTime anchor,
  ) async {
    final (start, end) = _rangeOf(period, anchor);
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;

    final rows = await (_db.select(_db.readingSessions)
          ..where((r) =>
              r.startedAt.isSmallerThanValue(endMs) &
              r.endedAt.isBiggerThanValue(startMs)))
        .get();
    final bookRows = await _db.select(_db.books).get();
    final titles = {for (final b in bookRows) b.id: b.title};

    final buckets = _newBuckets(period, start);
    final byBook = <String, _BookAcc>{};
    var totalMs = 0;
    var totalChars = 0;
    var totalSessions = 0;

    for (final s in rows) {
      final a = s.startedAt < startMs ? startMs : s.startedAt;
      final b = s.endedAt > endMs ? endMs : s.endedAt;
      if (b <= a) continue;
      final fullMs = s.endedAt - s.startedAt;
      final clippedMs = b - a;
      final chars = fullMs <= 0
          ? 0
          : (s.charsRead * clippedMs / fullMs).round();
      totalMs += clippedMs;
      totalChars += chars;
      totalSessions++;

      final acc = byBook.putIfAbsent(s.bookId, _BookAcc.new);
      acc.durationMs += clippedMs;
      acc.charsRead += chars;
      acc.sessions++;

      _distributeToBuckets(period, buckets, a, b, chars);
    }

    final books = byBook.entries
        .map((e) => BookReadingStat(
              bookId: e.key,
              title: titles[e.key] ?? '已删除书籍',
              durationMs: e.value.durationMs,
              charsRead: e.value.charsRead,
              sessions: e.value.sessions,
              exists: titles.containsKey(e.key),
            ))
        .toList()
      ..sort((a, b) => b.durationMs.compareTo(a.durationMs));

    return PeriodReadingStats(
      period: period,
      start: start,
      end: end,
      durationMs: totalMs,
      charsRead: totalChars,
      sessions: totalSessions,
      buckets: [
        for (final b in buckets)
          StatsBucket(
            label: b.label,
            durationMs: b.durationMs,
            charsRead: b.charsRead,
          ),
      ],
      books: books,
    );
  }

  /// 计算周期起止（本地时区，左闭右开）。
  (DateTime, DateTime) _rangeOf(StatsPeriod period, DateTime anchor) {
    final d = DateTime(anchor.year, anchor.month, anchor.day);
    switch (period) {
      case StatsPeriod.day:
        return (d, d.add(const Duration(days: 1)));
      case StatsPeriod.week:
        final monday = d.subtract(Duration(days: d.weekday - 1));
        return (monday, monday.add(const Duration(days: 7)));
      case StatsPeriod.month:
        return (DateTime(d.year, d.month, 1), DateTime(d.year, d.month + 1, 1));
      case StatsPeriod.year:
        return (DateTime(d.year, 1, 1), DateTime(d.year + 1, 1, 1));
    }
  }

  /// 初始化周期内的时间桶。
  List<_BucketAcc> _newBuckets(StatsPeriod period, DateTime start) {
    switch (period) {
      case StatsPeriod.day:
        return [
          for (var h = 0; h < 24; h++)
            _BucketAcc(h.toString().padLeft(2, '0')),
        ];
      case StatsPeriod.week:
        const labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
        return [for (final l in labels) _BucketAcc(l)];
      case StatsPeriod.month:
        final days = DateTime(start.year, start.month + 1, 0).day;
        return [for (var d = 1; d <= days; d++) _BucketAcc('$d')];
      case StatsPeriod.year:
        return [for (var m = 1; m <= 12; m++) _BucketAcc('$m月')];
    }
  }

  /// 把一段会话语义按时段拆进桶（跨小时/跨天/跨月都按重叠比例分）。
  void _distributeToBuckets(
    StatsPeriod period,
    List<_BucketAcc> buckets,
    int startMs,
    int endMs,
    int chars,
  ) {
    final totalMs = endMs - startMs;
    if (totalMs <= 0) return;
    var cursor = startMs;
    while (cursor < endMs) {
      final dt = DateTime.fromMillisecondsSinceEpoch(cursor);
      final boundary = _nextBoundary(period, dt).millisecondsSinceEpoch;
      final segEnd = boundary < endMs ? boundary : endMs;
      final segMs = segEnd - cursor;
      if (segMs > 0) {
        final index = _bucketIndex(period, dt);
        if (index >= 0 && index < buckets.length) {
          buckets[index].durationMs += segMs;
          buckets[index].charsRead +=
              (chars * segMs / totalMs).round();
        }
      }
      cursor = segEnd;
    }
  }

  /// 下一个桶边界（本地时间）。
  DateTime _nextBoundary(StatsPeriod period, DateTime t) {
    switch (period) {
      case StatsPeriod.day:
        return DateTime(t.year, t.month, t.day, t.hour + 1);
      case StatsPeriod.week:
      case StatsPeriod.month:
        return DateTime(t.year, t.month, t.day + 1);
      case StatsPeriod.year:
        return DateTime(t.year, t.month + 1, 1);
    }
  }

  /// 当前时刻落在哪个桶。
  int _bucketIndex(StatsPeriod period, DateTime t) {
    switch (period) {
      case StatsPeriod.day:
        return t.hour;
      case StatsPeriod.week:
        final monday = DateTime(t.year, t.month, t.day)
            .subtract(Duration(days: t.weekday - 1));
        return DateTime(t.year, t.month, t.day)
            .difference(monday)
            .inDays
            .clamp(0, 6);
      case StatsPeriod.month:
        return t.day - 1;
      case StatsPeriod.year:
        return t.month - 1;
    }
  }

  @override
  Future<int> dailyGoalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kGoalKey) ?? 30;
  }

  @override
  Future<void> setDailyGoalMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kGoalKey, minutes.clamp(0, 600));
  }

  @override
  Future<int> bookTotalDurationMs(String bookId) async {
    final rows = await (_db.select(_db.dailyStats)
          ..where((r) => r.bookId.equals(bookId)))
        .get();
    var total = 0;
    for (final r in rows) {
      total += r.durationMs;
    }
    return total;
  }

  @override
  Future<Map<String, int>> bookDailyDurations(
    String bookId, {
    int days = 14,
  }) async {
    final sinceDay =
        _dayOf(DateTime.now().subtract(Duration(days: days - 1)));
    final rows = await (_db.select(_db.dailyStats)
          ..where((r) => r.bookId.equals(bookId))
          ..where((r) => r.day.isBiggerOrEqualValue(sinceDay)))
        .get();
    return {for (final r in rows) r.day: r.durationMs};
  }

  /// 本地日期 yyyy-MM-dd（按本地时区，与 daily_stats 语义一致）。
  static String _dayOf(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
}

/// 单书累加器。
class _BookAcc {
  int durationMs = 0;
  int charsRead = 0;
  int sessions = 0;
}

/// 时间桶累加器（先累计再转不可变实体）。
class _BucketAcc {
  _BucketAcc(this.label);

  final String label;
  int durationMs = 0;
  int charsRead = 0;
}
