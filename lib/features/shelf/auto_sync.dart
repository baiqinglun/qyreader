/// 自动同步：按「同步设置」里的间隔定时跑一次 syncNow。
///
/// 间隔存 prefs `sync.autoMinutes`（0 = 关闭）。规则：
/// - 只在前台跑（后台被系统冻结时 Timer 也不会准时，回来后下一跳补上）；
/// - 同步进行中跳过（仓储侧也有防重入守卫，这里是第二道）；
/// - 后端没配好时静默跳过（syncRepositoryProvider 会抛「请先配置」）；
/// - 自动同步不弹提示：结果记进状态表，同步面板里能看到上次时间与错误。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';

part 'auto_sync.g.dart';

/// 自动同步间隔选项（分钟 → 文案；0 = 关闭）。
const Map<int, String> kAutoSyncOptions = <int, String>{
  0: '关闭',
  5: '5 分钟',
  10: '10 分钟',
  15: '15 分钟',
  30: '30 分钟',
  60: '60 分钟',
};

/// prefs key：自动同步间隔（分钟）。
const String kAutoSyncPrefsKey = 'sync.autoMinutes';

/// 自动同步控制器：持有定时器，间隔变化时重排。
class AutoSyncController {
  /// 构造。[runSync] 是一次「实际同步」的闭包（provider 里接 syncNow），
  /// 独立注入便于单测。
  AutoSyncController({required Future<void> Function() runSync})
    : _runSync = runSync;

  final Future<void> Function() _runSync;
  Timer? _timer;
  int _minutes = 0;
  bool _syncing = false;

  /// 当前间隔（分钟；0 = 关闭）。
  int get minutes => _minutes;

  /// 从 prefs 恢复上次设置的间隔（provider 构造时调用）。
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _apply(prefs.getInt(kAutoSyncPrefsKey) ?? 0);
  }

  /// 设置间隔并落盘；0 = 关闭。
  Future<void> setMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kAutoSyncPrefsKey, minutes);
    _apply(minutes);
  }

  void _apply(int minutes) {
    _timer?.cancel();
    _timer = null;
    _minutes = minutes;
    if (minutes <= 0) return;
    _timer = Timer.periodic(Duration(minutes: minutes), (_) => _tick());
  }

  /// 一次定时触发（测试可直接调）。
  Future<void> tick() => _tick();

  Future<void> _tick() async {
    if (_minutes <= 0 || _syncing) return;
    // 后台不跑：回前台后的下一次定时补上
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    _syncing = true;
    try {
      await _runSync();
    } catch (_) {
      // 没配置后端 / 网络失败：静默；同步面板里能看到上次错误
    } finally {
      _syncing = false;
    }
  }

  /// 停掉定时器（provider dispose 时）。
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// 诊断（测试用）：定时器是否在跑。
  bool get debugTimerActive => _timer?.isActive ?? false;
}

/// 自动同步控制器（应用级单例；HomeShell initState 里 read 一次启动）。
@Riverpod(keepAlive: true)
AutoSyncController autoSync(Ref ref) {
  final controller = AutoSyncController(
    runSync: () async {
      final repo = await ref.read(syncRepositoryProvider.future);
      await repo.syncNow();
    },
  );
  ref.onDispose(controller.dispose);
  controller.restore();
  return controller;
}
