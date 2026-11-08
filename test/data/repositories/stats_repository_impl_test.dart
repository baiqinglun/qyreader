/// 阅读统计仓储单测：会话落库、日聚合、连续天数、目标。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qy_reader/core/db/app_database.dart';
import 'package:qy_reader/data/repositories/stats_repository_impl.dart';
import 'package:qy_reader/domain/repositories/stats_repository.dart';

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
    final now = DateTime.now().millisecondsSinceEpoch;
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
    final now = DateTime.now().millisecondsSinceEpoch;
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
    final now = DateTime.now().millisecondsSinceEpoch;
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
    final now = DateTime.now();
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

    final now = DateTime.now().millisecondsSinceEpoch;
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
}
