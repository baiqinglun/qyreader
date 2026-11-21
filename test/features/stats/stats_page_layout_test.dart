/// 统计页宽屏布局：内容限宽、汇总卡自动分列。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/providers.dart';
import 'package:qy_reader/core/stats_revision.dart';
import 'package:qy_reader/domain/entities/reading_stats.dart';
import 'package:qy_reader/domain/repositories/stats_repository.dart';
import 'package:qy_reader/features/stats/stats_page.dart';

class _FakeStatsRepository implements StatsRepository {
  _FakeStatsRepository(this.overviewResult);

  ReadingStats overviewResult;

  @override
  Future<ReadingStats> overview({int recentDayCount = 14}) async =>
      overviewResult;

  @override
  Future<PeriodReadingStats> periodStats(
    StatsPeriod period,
    DateTime anchor,
  ) async => PeriodReadingStats(
    period: period,
    start: DateTime(2026, 11, 12),
    end: DateTime(2026, 11, 13),
    durationMs: 0,
    charsRead: 0,
    sessions: 0,
    buckets: const [],
    books: const [],
  );

  @override
  Future<int> dailyGoalMinutes() async => 30;

  @override
  Future<int> bookTotalDurationMs(String bookId) async => 0;

  @override
  Future<List<BookReadingTotal>> bookTotals() async => const [];

  @override
  Future<Map<String, int>> bookDailyDurations(
    String bookId, {
    int days = 14,
  }) async => const {};

  @override
  Future<void> recordSession({
    required String bookId,
    required int startedAt,
    required int endedAt,
    required int charsRead,
    int? countedDurationMs,
  }) async {}

  @override
  Future<void> setDailyGoalMinutes(int minutes) async {}
}

Future<void> _pumpStats(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        statsRepositoryProvider.overrideWith(
          (ref) async => _FakeStatsRepository(_zeroStats),
        ),
      ],
      child: MaterialApp(home: const StatsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

const ReadingStats _zeroStats = ReadingStats(
  todayDurationMs: 0,
  todayChars: 0,
  totalDurationMs: 0,
  totalChars: 0,
  totalDays: 0,
  streakDays: 0,
  recentDays: [],
  dailyGoalMinutes: 30,
);

int _summaryColumns(WidgetTester tester) {
  final grid = tester.widget<GridView>(
    find.byKey(const ValueKey('stats-summary-grid')),
  );
  final delegate =
      grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
  return delegate.crossAxisCount;
}

void main() {
  testWidgets('切回统计 Tab（active false→true）重新拉一次统计', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = _FakeStatsRepository(
      const ReadingStats(
        todayDurationMs: 0,
        todayChars: 0,
        totalDurationMs: 90 * 60000,
        totalChars: 0,
        totalDays: 1,
        streakDays: 1,
        recentDays: [],
        dailyGoalMinutes: 30,
      ),
    );
    Widget host(bool active) => ProviderScope(
      overrides: [statsRepositoryProvider.overrideWith((ref) async => fake)],
      child: MaterialApp(home: StatsPage(active: active)),
    );
    await tester.pumpWidget(host(false));
    await tester.pumpAndSettle();
    // 累计卡在页面下方（ListView 懒加载），先滚到它
    await tester.scrollUntilVisible(
      find.text('累计时长'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('1 小时 30 分'), findsOneWidget);

    // 阅读数据变了；切回统计 Tab（active false→true）触发重拉
    fake.overviewResult = const ReadingStats(
      todayDurationMs: 0,
      todayChars: 0,
      totalDurationMs: 120 * 60000,
      totalChars: 0,
      totalDays: 2,
      streakDays: 2,
      recentDays: [],
      dailyGoalMinutes: 30,
    );
    await tester.pumpWidget(host(true));
    await tester.pumpAndSettle();
    expect(find.text('2 小时 0 分'), findsOneWidget);

    // 页面可见时统计有写入（修订号 bump）：不切 Tab 也要即时重拉
    fake.overviewResult = const ReadingStats(
      todayDurationMs: 0,
      todayChars: 0,
      totalDurationMs: 150 * 60000,
      totalChars: 0,
      totalDays: 3,
      streakDays: 3,
      recentDays: [],
      dailyGoalMinutes: 30,
    );
    bumpStatsRevision();
    await tester.pumpAndSettle();
    expect(find.text('2 小时 30 分'), findsOneWidget);
  });

  testWidgets('宽屏：内容限宽 900，汇总卡自动分 4 列', (tester) async {
    await _pumpStats(tester, const Size(1400, 900));

    final scroll = tester.getSize(
      find.byKey(const PageStorageKey('stats-scroll')),
    );
    expect(scroll.width, closeTo(900, 0.5), reason: '内容列不应被拉满宽屏');
    expect(_summaryColumns(tester), 4);
  });

  testWidgets('手机：内容占满宽度，汇总卡两列', (tester) async {
    await _pumpStats(tester, const Size(390, 844));

    final scroll = tester.getSize(
      find.byKey(const PageStorageKey('stats-scroll')),
    );
    expect(scroll.width, closeTo(390, 0.5));
    expect(_summaryColumns(tester), 2);
  });
}
