/// 自动同步控制器：间隔落盘、定时器重排、前台与防重入守卫。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qy_reader/features/shelf/auto_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    // 恢复生命周期状态，别影响其它测试
    TestWidgetsFlutterBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  test('restore：读回上次设置的间隔并启动定时器', () async {
    SharedPreferences.setMockInitialValues({kAutoSyncPrefsKey: 10});
    final c = AutoSyncController(runSync: () async {});
    await c.restore();
    expect(c.minutes, 10);
    expect(c.debugTimerActive, isTrue);
    c.dispose();
  });

  test('restore：没有设置时默认关闭（不启动定时器）', () async {
    final c = AutoSyncController(runSync: () async {});
    await c.restore();
    expect(c.minutes, 0);
    expect(c.debugTimerActive, isFalse);
    c.dispose();
  });

  test('setMinutes：落盘 + 重排定时器；0 = 关闭并停掉定时器', () async {
    final c = AutoSyncController(runSync: () async {});
    await c.restore();
    await c.setMinutes(5);
    expect(c.minutes, 5);
    expect(c.debugTimerActive, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(kAutoSyncPrefsKey), 5);
    await c.setMinutes(0);
    expect(c.minutes, 0);
    expect(c.debugTimerActive, isFalse);
    expect(prefs.getInt(kAutoSyncPrefsKey), 0);
    c.dispose();
  });

  test('tick：同步进行中再触发直接跳过（不叠加）', () async {
    var calls = 0;
    final gate = Completer<void>();
    final c = AutoSyncController(runSync: () async {
      calls++;
      await gate.future;
    });
    await c.setMinutes(5);
    final first = c.tick(); // 进入同步（挂在 gate 上）
    final second = c.tick(); // in-flight → 跳过
    gate.complete();
    await first;
    await second;
    expect(calls, 1);
    c.dispose();
  });

  test('tick：后台不跑，回前台后恢复', () async {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    var calls = 0;
    final c = AutoSyncController(runSync: () async {
      calls++;
    });
    await c.setMinutes(5);
    await c.tick();
    expect(calls, 0);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await c.tick();
    expect(calls, 1);
    c.dispose();
  });
}
