/// 统计页周期标题：日期居中，点击可跳日期。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/reading_stats.dart';
import 'package:qy_reader/features/stats/widgets/stats_period_header.dart';

PeriodReadingStats _period({
  StatsPeriod granularity = StatsPeriod.day,
  DateTime? start,
}) {
  final s = start ?? DateTime(2026, 11, 12);
  final end = switch (granularity) {
    StatsPeriod.day => s.add(const Duration(days: 1)),
    StatsPeriod.week => s.add(const Duration(days: 7)),
    StatsPeriod.month => DateTime(s.year, s.month + 1),
    StatsPeriod.year => DateTime(s.year + 1),
  };
  return PeriodReadingStats(
    period: granularity,
    start: s,
    end: end,
    durationMs: 0,
    charsRead: 0,
    sessions: 0,
    buckets: const [],
    books: const [],
  );
}

void main() {
  testWidgets('日期标题在整行正中，点击触发选日期', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var picked = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatsPeriodHeader(
          period: _period(),
          foreground: Colors.white,
          accent: Colors.lightBlue,
          onPrev: () {},
          onNext: null,
          onToday: null,
          onPickDate: () => picked = true,
        ),
      ),
    ));

    final label = find.text('2026-11-12 周四');
    expect(label, findsOneWidget);
    expect(tester.getCenter(label).dx, closeTo(195, 1));

    await tester.tap(find.byKey(const ValueKey('stats-period-label')));
    expect(picked, isTrue);
  });

  testWidgets('右侧有「今天」时仍然居中', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatsPeriodHeader(
          period: _period(start: DateTime(2026, 11, 11)),
          foreground: Colors.white,
          accent: Colors.lightBlue,
          onPrev: () {},
          onNext: () {},
          onToday: () {},
          onPickDate: () {},
        ),
      ),
    ));

    final label = find.text('2026-11-11 周三');
    expect(tester.getCenter(label).dx, closeTo(195, 1));
    expect(find.text('今天'), findsOneWidget);
  });

  testWidgets('周/月/年标题也能点击选日期', (tester) async {
    for (final (granularity, text) in [
      (StatsPeriod.week, '11/12 ~ 11/18'),
      (StatsPeriod.month, '2026 年 11 月'),
      (StatsPeriod.year, '2026 年'),
    ]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatsPeriodHeader(
            period: _period(granularity: granularity),
            foreground: Colors.white,
            accent: Colors.lightBlue,
            onPrev: () {},
            onNext: () {},
            onToday: () {},
            onPickDate: () {},
          ),
        ),
      ));
      expect(find.text(text), findsOneWidget);
    }
  });
}
