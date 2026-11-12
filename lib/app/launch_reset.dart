/// 启动归位：点桌面图标重新进入时的路由处理。
///
/// 场景：按 Home / 切后台（进程还活着），再点桌面图标。Android 侧
/// `launchMode=singleTop` 走 `onNewIntent`，原生经 `qyreader/launch` 通道
/// 通知这里。
/// - 正在阅读：**保持阅读页**（用户要求切后台回来不要合书）；
/// - 不在阅读页（书架/统计/设置）：回书架首屏。
/// 冷启动本来就从 `/` 开始；从文件管理器/深链进来的不归位。
library;

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../features/reader/reader_active_marker.dart';
import 'router.dart';

/// 「点桌面图标重新进入」的归位通道。
class LaunchReset {
  LaunchReset._();

  static const MethodChannel _channel = MethodChannel('qyreader/launch');

  static bool _bound = false;

  /// 绑定到路由（幂等；`QyReaderApp` 构建时调用）。
  static void bind(GoRouter router) {
    if (_bound) return;
    _bound = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'resetToShelf') {
        // 正在阅读时用户切后台再回来（桌标、最近任务）不要合上书：
        // 阅读页处于活动状态时忽略归位，仍然停在阅读界面。
        final active = activeReaderBookSync() ?? await activeReaderBook();
        if (active != null && active.isNotEmpty) return null;
        // 不在阅读页：沿用「点图标回书架」的旧行为。
        router.go(kShelfPath);
      }
      return null;
    });
  }
}
