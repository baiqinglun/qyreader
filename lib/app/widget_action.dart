/// 桌面组件的点击动作：把组件里点的位置送到 go_router。
///
/// 原生侧不用 `reader://` 深链，而是给 MainActivity 带
/// `EXTRA_WIDGET_ACTION`（`book:<id>` / `stats` / `shelf`），再经
/// `qyreader/widget_action` 通道送进来——冷启动与进程还在时走同一条路。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';

/// 组件点击路由。
class WidgetActionRouter {
  WidgetActionRouter._();

  static const MethodChannel _channel = MethodChannel('qyreader/widget_action');

  static bool _bound = false;
  static GoRouter? _router;

  /// 绑定路由并取一次「冷启动时带进来的组件动作」（幂等）。
  static void bind(GoRouter router) {
    _router = router;
    if (_bound) return;
    if (kIsWeb || !Platform.isAndroid) return;
    _bound = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') {
        _open(call.arguments is String ? call.arguments as String : null);
      }
      return null;
    });
    unawaited(_loadInitial());
  }

  static Future<void> _loadInitial() async {
    try {
      final action = await _channel.invokeMethod<String>('getInitialAction');
      _open(action);
    } on MissingPluginException {
      // 桌面 / 测试环境没有实现
    } catch (_) {
      // 取初始动作失败不影响启动
    }
  }

  static void _open(String? action) {
    final router = _router;
    if (action == null || action.isEmpty || router == null) return;
    if (action.startsWith('book:')) {
      final bookId = action.substring('book:'.length);
      if (bookId.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (router.routerDelegate.currentConfiguration.uri.path ==
            readerPath(bookId)) {
          return;
        }
        router.push(readerPath(bookId));
      });
      return;
    }
    final target = switch (action) {
      'stats' => kStatsPath,
      'shelf' => kShelfTabPath,
      _ => null,
    };
    if (target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (router.routerDelegate.currentConfiguration.uri.path == target) return;
      router.go(target);
    });
  }
}
