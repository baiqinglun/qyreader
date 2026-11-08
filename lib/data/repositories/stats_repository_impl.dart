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
  Future<int> dailyGoalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kGoalKey) ?? 30;
  }

  @override
  Future<void> setDailyGoalMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kGoalKey, minutes.clamp(0, 600));
  }

  /// 本地日期 yyyy-MM-dd（按本地时区，与 daily_stats 语义一致）。
  static String _dayOf(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
}
