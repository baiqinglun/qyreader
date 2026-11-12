/// 文件管理器「用其他应用打开」的接入口。
///
/// 原生侧把 content:// 复制到应用缓存，通过 `qyreader/open` 通道送进来；
/// 这里把「启动时带进来的文件」和「运行中新打开的文件」统一成一条流。
library;

import 'dart:async';

import 'package:flutter/services.dart';

/// 打开文件的服务（应用级单例）。
class OpenWithService {
  OpenWithService._();

  static const MethodChannel _channel = MethodChannel('qyreader/open');
  static final StreamController<String> _out =
      StreamController<String>.broadcast();

  /// 还没有监听者时先排队（冷启动拿到的文件不能丢）。
  static final List<String> _queue = <String>[];

  static bool _started = false;

  /// 外部打开的文件路径流。
  static Stream<String> get files => _out.stream;

  /// 开始监听原生事件并取一次「启动文件」（幂等，可重复调用）。
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openFile' && call.arguments is String) {
        _deliver(call.arguments as String);
      }
      return null;
    });
    try {
      final initial = await _channel.invokeMethod<String>('getInitialFile');
      if (initial != null && initial.isNotEmpty) _deliver(initial);
    } on MissingPluginException {
      // 桌面/测试环境没有实现
    } catch (_) {
      // 取启动文件失败不影响应用启动
    }
  }

  /// 取走排队中的文件（监听建立后调用）。
  static List<String> drainQueue() {
    final queued = List<String>.from(_queue);
    _queue.clear();
    return queued;
  }

  static void _deliver(String path) {
    if (_out.hasListener) {
      _out.add(path);
    } else {
      _queue.add(path);
    }
  }
}
