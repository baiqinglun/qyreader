/// 单页最长计时回归：一页停留超过上限的部分不计入统计。
///
/// 用注入时钟模拟真实停留，捕获 recordSession 的计入时长断言。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/repositories/stats_repository.dart';
import 'package:qy_reader/features/reader/reading_session_tracker.dart';

class _CapturedCall {
  int startedAt = 0;
  int endedAt = 0;
  int charsRead = 0;
  int? countedDurationMs;
}

class _CapturingRepo implements StatsRepository {
  final calls = <_CapturedCall>[];

  @override
  Future<void> recordSession({
    required String bookId,
    required int startedAt,
    required int endedAt,
    required int charsRead,
    int? countedDurationMs,
  }) async {
    calls.add(
      _CapturedCall()
        ..startedAt = startedAt
        ..endedAt = endedAt
        ..charsRead = charsRead
        ..countedDurationMs = countedDurationMs,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  // tracker.start() 会注册 WidgetsBindingObserver，需要绑定先就绪
  TestWidgetsFlutterBinding.ensureInitialized();

  test('不封顶（cap=0）：整段时长全额计入', () async {
    var t = DateTime(2026, 11, 14, 12);
    DateTime clock() => t;
    final repo = _CapturingRepo();
    final tracker = ReadingSessionTracker(
      repository: repo,
      bookId: 'b1',
      wordCount: 1000,
      pageCapMinutes: 0,
      now: clock,
    )..start();
    t = t.add(const Duration(minutes: 30));
    tracker.onPercent(0.1);
    t = t.add(const Duration(minutes: 5));
    await tracker.flush();
    expect(repo.calls.single.countedDurationMs, 35 * 60000);
  });

  test('单页停留 30 分钟、上限 10 分钟：该页只计 10 分钟', () async {
    var t = DateTime(2026, 11, 14, 12);
    DateTime clock() => t;
    final repo = _CapturingRepo();
    final tracker = ReadingSessionTracker(
      repository: repo,
      bookId: 'b1',
      wordCount: 1000,
      pageCapMinutes: 10,
      now: clock,
    )..start();
    t = t.add(const Duration(minutes: 30)); // 第一页停 30 分钟
    tracker.onPercent(0.1);
    t = t.add(const Duration(minutes: 2)); // 第二页 2 分钟（< 上限）
    await tracker.flush();
    final c = repo.calls.single;
    expect(c.countedDurationMs, 12 * 60000);
    // startedAt/endedAt 仍是真实墙钟（计入时长单独承载）
    expect(c.endedAt - c.startedAt, 32 * 60000);
  });

  test('每页都超上限：4 页各 20 分钟、上限 10 分钟 → 合计 40 分钟', () async {
    var t = DateTime(2026, 11, 14, 12);
    DateTime clock() => t;
    final repo = _CapturingRepo();
    final tracker = ReadingSessionTracker(
      repository: repo,
      bookId: 'b1',
      wordCount: 1000,
      pageCapMinutes: 10,
      now: clock,
    )..start();
    for (var i = 1; i <= 3; i++) {
      t = t.add(const Duration(minutes: 20));
      tracker.onPercent(0.1 * i);
    }
    t = t.add(const Duration(minutes: 20)); // 第四页
    await tracker.flush();
    expect(repo.calls.single.countedDurationMs, 40 * 60000);
  });

  test('回翻（percent 负增量）也算翻页：停留重新起算并封顶', () async {
    var t = DateTime(2026, 11, 14, 12);
    DateTime clock() => t;
    final repo = _CapturingRepo();
    final tracker = ReadingSessionTracker(
      repository: repo,
      bookId: 'b1',
      wordCount: 1000,
      pageCapMinutes: 10,
      now: clock,
    )..start();
    t = t.add(const Duration(minutes: 25));
    tracker.onPercent(0.3); // 前翻
    t = t.add(const Duration(minutes: 25));
    tracker.onPercent(0.2); // 回翻 —— 也算新的一页
    t = t.add(const Duration(minutes: 1));
    await tracker.flush();
    // 25min→封 10 + 25min→封 10 + 1min = 21min
    expect(repo.calls.single.countedDurationMs, 21 * 60000);
    expect(repo.calls.single.charsRead, 0); // 负增量不计字数
  });

  test('同页重复回报不重置停留计时', () async {
    var t = DateTime(2026, 11, 14, 12);
    DateTime clock() => t;
    final repo = _CapturingRepo();
    final tracker = ReadingSessionTracker(
      repository: repo,
      bookId: 'b1',
      wordCount: 1000,
      pageCapMinutes: 10,
      now: clock,
    )..start();
    t = t.add(const Duration(minutes: 4));
    tracker.onPercent(0.1); // 首次回报：第一页 4 分钟
    t = t.add(const Duration(minutes: 1));
    tracker.onPercent(0.1); // 同页重复回报：不重算停留
    t = t.add(const Duration(minutes: 1));
    tracker.onPercent(0.2); // 翻页：第一页合计 6 分钟
    t = t.add(const Duration(minutes: 1));
    await tracker.flush(); // 第二页 1 分钟
    expect(repo.calls.single.countedDurationMs, 7 * 60000);
  });

  test('字数估算不受封顶影响（照常按正增量累计）', () async {
    var t = DateTime(2026, 11, 14, 12);
    DateTime clock() => t;
    final repo = _CapturingRepo();
    final tracker = ReadingSessionTracker(
      repository: repo,
      bookId: 'b1',
      wordCount: 10000,
      pageCapMinutes: 10,
      now: clock,
    )..start();
    t = t.add(const Duration(minutes: 30));
    tracker.onPercent(0.05); // 首次回报：无上一次位置，不计字数
    t = t.add(const Duration(minutes: 30));
    tracker.onPercent(0.10); // +5%（单次上限）→ 500 字
    await tracker.flush();
    final c = repo.calls.single;
    expect(c.charsRead, 500);
    expect(c.countedDurationMs, 20 * 60000); // 30min→10 + 30min→10
  });

  test('听书播放中：切后台不结算（后台收听也计入）', () async {
    final binding = TestWidgetsFlutterBinding.instance;
    var t = DateTime(2026, 11, 14, 12);
    DateTime clock() => t;
    final repo = _CapturingRepo();
    final tracker = ReadingSessionTracker(
      repository: repo,
      bookId: 'b1',
      wordCount: 1000,
      isListening: () => true,
      now: clock,
    )..start();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tracker.flush(); // 会话还在跑（没有被 lifecycle 结算），这里手动结算
    expect(repo.calls, hasLength(1));
    tracker.dispose();
  });

  test('被盖住且没在听书：回前台不恢复计时', () async {
    final binding = TestWidgetsFlutterBinding.instance;
    var t = DateTime(2026, 11, 14, 12);
    DateTime clock() => t;
    final repo = _CapturingRepo();
    final tracker = ReadingSessionTracker(
      repository: repo,
      bookId: 'b1',
      wordCount: 1000,
      isCovered: () => true,
      now: clock,
    )..start();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tracker.flush(); // 切后台结算：会话 1
    expect(repo.calls, hasLength(1));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tracker.flush(); // 被盖住 + 没在听书 → 没重启，无会话可结算
    expect(repo.calls, hasLength(1));
    tracker.dispose();
  });

  test('被盖住但在听书：回前台恢复计时', () async {
    final binding = TestWidgetsFlutterBinding.instance;
    var t = DateTime(2026, 11, 14, 12);
    DateTime clock() => t;
    final repo = _CapturingRepo();
    final tracker = ReadingSessionTracker(
      repository: repo,
      bookId: 'b1',
      wordCount: 1000,
      isListening: () => true,
      isCovered: () => true,
      now: clock,
    )..start();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tracker.flush(); // 听书中 → lifecycle 不结算；手动结算会话 1
    expect(repo.calls, hasLength(1));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    t = t.add(const Duration(minutes: 1));
    await tracker.flush(); // resumed 时恢复计时（covered 但在听书）→ 会话 2
    expect(repo.calls, hasLength(2));
    tracker.dispose();
  });

  test('阅读页最上层：回前台重新起算，下次结算新会话', () async {
    final binding = TestWidgetsFlutterBinding.instance;
    var t = DateTime(2026, 11, 14, 12);
    DateTime clock() => t;
    final repo = _CapturingRepo();
    final tracker = ReadingSessionTracker(
      repository: repo,
      bookId: 'b1',
      wordCount: 1000,
      now: clock,
    )..start();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tracker.flush(); // 会话 1
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); // 重启
    t = t.add(const Duration(minutes: 1));
    await tracker.flush(); // 会话 2（时长 ≥10s 才落库：1 分钟 ✓）
    expect(repo.calls, hasLength(2));
    tracker.dispose();
  });
}
