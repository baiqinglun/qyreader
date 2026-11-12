/// 阅读统计仓储单测：会话落库、日聚合、连续天数、目标。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qy_reader/core/db/app_database.dart';
import 'package:qy_reader/data/repositories/stats_repository_impl.dart';
import 'package:qy_reader/domain/entities/reading_stats.dart';
import 'package:qy_reader/domain/repositories/stats_repository.dart';

/// 今天正午：统计测试按「今天/昨天」断言，用固定时刻避免午夜前后跑时
/// 会话起点落到昨天（真实时间 00:05 时会误判）。
DateTime _todayNoon() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, 12);
}
void main() {
  late AppDatabase db;
  late StatsRepository repo;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    repo = StatsRepositoryImpl(db: db, deviceId: 'testdev1');
  });

  tearDown(() async => db.close());

  test('记录会话：写明细 + 当日单书/合计两份聚合', () async {
    final now = _todayNoon().millisecondsSinceEpoch;
    await repo.recordSession(
      bookId: 'b1',
      startedAt: now - 15 * 60 * 1000,
      endedAt: now,
      charsRead: 1200,
    );

    final sessions = await db.select(db.readingSessions).get();
    expect(sessions, hasLength(1));
    expect(sessions.single.durationMs, 15 * 60 * 1000);
    expect(sessions.single.charsRead, 1200);

    final daily = await db.select(db.dailyStats).get();
    expect(daily, hasLength(2));
    final total = daily.firstWhere((r) => r.bookId == '');
    expect(total.durationMs, 15 * 60 * 1000);
    expect(total.charsRead, 1200);
    expect(total.sessions, 1);
    expect(total.day, startsWith(DateTime.now().year.toString()));
  });

  test('多次会话累加到同一日聚合', () async {
    final now = _todayNoon().millisecondsSinceEpoch;
    await repo.recordSession(
      bookId: 'b1',
      startedAt: now - 20 * 60 * 1000,
      endedAt: now - 10 * 60 * 1000,
      charsRead: 800,
    );
    await repo.recordSession(
      bookId: 'b1',
      startedAt: now - 8 * 60 * 1000,
      endedAt: now,
      charsRead: 500,
    );
    final daily = await db.select(db.dailyStats).get();
    final total = daily.where((r) => r.bookId == '').single;
    expect(total.durationMs, 18 * 60 * 1000);
    expect(total.charsRead, 1300);
    expect(total.sessions, 2);
  });

  test('10 秒以内会话丢弃（误触）', () async {
    final now = _todayNoon().millisecondsSinceEpoch;
    await repo.recordSession(
      bookId: 'b1',
      startedAt: now - 3000,
      endedAt: now,
      charsRead: 10,
    );
    expect(await db.select(db.readingSessions).get(), isEmpty);
    expect(await db.select(db.dailyStats).get(), isEmpty);
  });

  test('overview：今日/累计/天数/趋势补齐', () async {
    final now = _todayNoon();
    // 今天 12 分钟 + 昨天 30 分钟
    await repo.recordSession(
      bookId: 'b1',
      startedAt: now.millisecondsSinceEpoch - 12 * 60 * 1000,
      endedAt: now.millisecondsSinceEpoch,
      charsRead: 900,
    );
    final yesterday = now.subtract(const Duration(days: 1));
    await repo.recordSession(
      bookId: 'b1',
      startedAt: yesterday.millisecondsSinceEpoch,
      endedAt: yesterday.millisecondsSinceEpoch + 30 * 60 * 1000,
      charsRead: 2400,
    );

    final stats = await repo.overview(recentDayCount: 7);
    expect(stats.todayDurationMs, 12 * 60 * 1000);
    expect(stats.todayChars, 900);
    expect(stats.totalDurationMs, 42 * 60 * 1000);
    expect(stats.totalChars, 3300);
    expect(stats.totalDays, 2);
    expect(stats.streakDays, 2); // 今天+昨天连续
    expect(stats.recentDays, hasLength(7));
    expect(stats.recentDays.last.day,
        stats.recentDays.last.day); // 最后一天是今天
    expect(stats.recentDays.last.durationMs, 12 * 60 * 1000);
    expect(stats.recentDays[5].durationMs, 30 * 60 * 1000); // 昨天
    expect(stats.charsPerMinute, closeTo(3300 / 42, 0.5));
  });

  test('连续天数：今天未读时从昨天算；空库为 0', () async {
    expect((await repo.overview()).streakDays, 0);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await repo.recordSession(
      bookId: 'b1',
      startedAt: yesterday.millisecondsSinceEpoch,
      endedAt: yesterday.millisecondsSinceEpoch + 5 * 60 * 1000,
      charsRead: 100,
    );
    final stats = await repo.overview();
    expect(stats.streakDays, 1);
  });

  test('每日目标读写与进度', () async {
    expect(await repo.dailyGoalMinutes(), 30);
    await repo.setDailyGoalMinutes(60);
    expect(await repo.dailyGoalMinutes(), 60);

    final now = _todayNoon().millisecondsSinceEpoch;
    await repo.recordSession(
      bookId: 'b1',
      startedAt: now - 30 * 60 * 1000,
      endedAt: now,
      charsRead: 500,
    );
    final stats = await repo.overview();
    expect(stats.todayGoalProgress, closeTo(0.5, 0.01));

    await repo.setDailyGoalMinutes(0);
    expect((await repo.overview()).todayGoalProgress, 0);
  });

  group('periodStats 日/周/月/年', () {
    Future<void> addSession(
      String bookId,
      DateTime start,
      int minutes,
      int chars,
    ) =>
        repo.recordSession(
          bookId: bookId,
          startedAt: start.millisecondsSinceEpoch,
          endedAt: start.add(Duration(minutes: minutes)).millisecondsSinceEpoch,
          charsRead: chars,
        );

    test('周：7 天桶 + 按书聚合（时长降序）', () async {
      final monday = DateTime(2026, 1, 5); // 周一
      await addSession('b1', monday.add(const Duration(hours: 9)), 30, 300);
      await addSession(
        'b2',
        monday.add(const Duration(days: 2, hours: 14)),
        15,
        150,
      );

      final stats = await repo.periodStats(
        StatsPeriod.week,
        DateTime(2026, 1, 7, 12),
      );
      expect(stats.start, monday);
      expect(stats.end, monday.add(const Duration(days: 7)));
      expect(stats.durationMs, 45 * 60 * 1000);
      expect(stats.charsRead, 450);
      expect(stats.sessions, 2);
      expect(stats.buckets, hasLength(7));
      expect(stats.buckets[0].minutes, 30);
      expect(stats.buckets[2].minutes, 15);
      expect(stats.books, hasLength(2));
      expect(stats.books.first.bookId, 'b1');
      expect(stats.books.first.durationMs, 30 * 60 * 1000);
      expect(stats.books.first.exists, isFalse);
    });

    test('日：24 小时桶，跨午夜按重叠裁切', () async {
      final start = DateTime(2026, 1, 7, 23, 30);
      await addSession('b1', start, 60, 600);

      final day1 = await repo.periodStats(
        StatsPeriod.day,
        DateTime(2026, 1, 7, 12),
      );
      expect(day1.buckets, hasLength(24));
      expect(day1.buckets[23].minutes, 30);
      expect(day1.durationMs, 30 * 60 * 1000);

      final day2 = await repo.periodStats(
        StatsPeriod.day,
        DateTime(2026, 1, 8, 12),
      );
      expect(day2.buckets[0].minutes, 30);
      expect(day2.durationMs, 30 * 60 * 1000);
    });

    test('月：按天分桶；年：按月分桶', () async {
      await addSession('b1', DateTime(2026, 1, 15, 10), 20, 200);
      await addSession('b2', DateTime(2026, 1, 20, 10), 10, 100);
      await addSession('b1', DateTime(2026, 3, 2, 10), 5, 50);

      final jan = await repo.periodStats(
        StatsPeriod.month,
        DateTime(2026, 1, 10),
      );
      expect(jan.buckets, hasLength(31));
      expect(jan.buckets[14].minutes, 20);
      expect(jan.buckets[19].minutes, 10);
      expect(jan.durationMs, 30 * 60 * 1000);
      expect(jan.books, hasLength(2));

      final year = await repo.periodStats(
        StatsPeriod.year,
        DateTime(2026, 6, 1),
      );
      expect(year.buckets, hasLength(12));
      expect(year.buckets[0].minutes, 30);
      expect(year.buckets[2].minutes, 5);
      expect(year.durationMs, 35 * 60 * 1000);
    });
  });

  group('单书时长查询（书籍详情页用）', () {
    test('累计时长只统计本书的聚合', () async {
      final now = _todayNoon().millisecondsSinceEpoch;
      await repo.recordSession(
        bookId: 'b1',
        startedAt: now - 15 * 60 * 1000,
        endedAt: now,
        charsRead: 1200,
      );
      await repo.recordSession(
        bookId: 'b2',
        startedAt: now - 10 * 60 * 1000,
        endedAt: now,
        charsRead: 600,
      );

      expect(await repo.bookTotalDurationMs('b1'), 15 * 60 * 1000);
      expect(await repo.bookTotalDurationMs('b2'), 10 * 60 * 1000);
      expect(await repo.bookTotalDurationMs('b3'), 0);
    });

    test('按日时长：近 N 天窗口，缺日不在结果里', () async {
      // 昨天 + 前天各读一段（今天固定正午，不受午夜跨日影响）
      final base = _todayNoon();
      await repo.recordSession(
        bookId: 'b1',
        startedAt: base.subtract(const Duration(days: 1, minutes: 20)).millisecondsSinceEpoch,
        endedAt: base.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        charsRead: 800,
      );
      await repo.recordSession(
        bookId: 'b1',
        startedAt: base.subtract(const Duration(days: 2, minutes: 30)).millisecondsSinceEpoch,
        endedAt: base.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        charsRead: 900,
      );

      final daily = await repo.bookDailyDurations('b1', days: 14);
      expect(daily, hasLength(2));
      // 昨天读 20 分钟、前天读 30 分钟（时长各归各日）
      expect(daily.values.toSet(), {
        20 * 60 * 1000,
        30 * 60 * 1000,
      });

      // 窗口收窄到 2 天（含今天）：只剩昨天这一条
      final yesterdayOnly = await repo.bookDailyDurations('b1', days: 2);
      expect(yesterdayOnly, hasLength(1));
    });
  });
}
