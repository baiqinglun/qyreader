/// 桌面组件的 Flutter → 原生通道。
///
/// 只有 Android 有桌面组件；其它平台（Windows / 测试环境）直接跳过，
/// 任何通道异常都静默——组件是增强功能，不能影响主流程。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'home_widget_data.dart';

/// 桌面组件通道。
class HomeWidgetService {
  HomeWidgetService._();

  static const MethodChannel _channel = MethodChannel('qyreader/home_widgets');

  /// 当前平台是否支持桌面组件。
  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// 把最新的数据快照推给原生侧并刷新所有组件。
  static Future<void> update(HomeWidgetData data) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('update', homeWidgetJson(data));
    } on MissingPluginException {
      // 桌面 / 测试环境没有实现
    } catch (_) {
      // 组件刷新失败不影响 App
    }
  }
}
