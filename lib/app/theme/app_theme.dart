/// 应用亮/暗主题。Material 3，以「青阅」品牌青绿色为种子色。
library;

import 'package:flutter/material.dart';

import 'motion.dart';

/// 主题工厂。
class AppTheme {
  AppTheme._();

  /// 默认主色：参考稿的亮蓝。
  static const Color defaultSeed = Color(0xFF1E7BFF);

  /// 亮色页面底色：带一点紫的浅灰，白卡片浮在上面（参考稿）。
  static const Color lightBackground = Color(0xFFF3F4F9);

  /// 亮色主题。
  static ThemeData light([Color seed = defaultSeed]) =>
      _base(Brightness.light, seed);

  /// 暗色主题。
  static ThemeData dark([Color seed = defaultSeed]) =>
      _base(Brightness.dark, seed);

  static ThemeData _base(Brightness brightness, Color seed) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? scheme.surface : lightBackground,
      // 参考稿的顶栏和页面同底色、无阴影，靠留白分组。
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      // Android 不用 Predictive/Zoom 转场：两者动画期间用 SnapshotWidget 把整页
      // 快照成图片绘制，而平台视图（WebView）内容无法被快照捕获——快照挂起时
      // PlatformViewLayer 不进合成树，WebView 视图不创建、页面只剩背景色（实测
      // Android 17 模拟器整页空白）。这里用纯 Fade/Slide 转场（无快照），
      // 缓动统一走「慢快慢」贝塞尔 [kSmoothCurve]。
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: SmoothPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: SmoothPageTransitionsBuilder(),
      }),
      // 参考稿：大圆角白卡片、无描边、极轻阴影。
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? scheme.surfaceContainerLow : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}

/// 页面转场：淡入 + 2% 上移，缓动统一用「慢快慢」贝塞尔。
///
/// 不用 `SnapshotWidget` 类转场（会让平台视图整页空白，原因见上面的注释）。
class SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: kSmoothCurve,
      reverseCurve: kSmoothCurve,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
