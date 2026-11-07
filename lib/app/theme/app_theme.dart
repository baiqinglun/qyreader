/// 应用亮/暗主题。Material 3，以「青阅」品牌青绿色为种子色。
library;

import 'package:flutter/material.dart';

/// 主题工厂。
class AppTheme {
  AppTheme._();

  /// 品牌种子色：书卷青。
  static const Color seed = Color(0xFF2E7D6B);

  /// 亮色主题。
  static ThemeData light() => _base(Brightness.light);

  /// 暗色主题。
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Android 不用 Predictive/Zoom 转场：两者动画期间用 SnapshotWidget 把整页
      // 快照成图片绘制，而平台视图（WebView）内容无法被快照捕获——快照挂起时
      // PlatformViewLayer 不进合成树，WebView 视图不创建、页面只剩背景色（实测
      // Android 17 模拟器整页空白）。FadeForwards 为 Android 15 原生风格且无快照。
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
      }),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
