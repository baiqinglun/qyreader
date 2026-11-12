/// App 主题色（主色）偏好：只落 shared_preferences，不参与同步。
///
/// 主色用于按钮、选中态、开关、统计图表；阅读页的纸面配色是另一套
/// （`ReadingTheme`），不受这里影响。
library;

import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'appearance_provider.g.dart';

/// 可选主题色。
enum AppAccent {
  /// 亮蓝（默认，参考稿）。
  blue('蓝', Color(0xFF1E7BFF)),

  /// 青。
  teal('青', Color(0xFF2E8B7A)),

  /// 紫。
  purple('紫', Color(0xFF7C5CFF)),

  /// 橙。
  orange('橙', Color(0xFFF08A24)),

  /// 粉。
  pink('粉', Color(0xFFE0588A)),

  /// 绿。
  green('绿', Color(0xFF2FA36B));

  const AppAccent(this.label, this.color);

  /// 展示名。
  final String label;

  /// 主色。
  final Color color;
}

/// 当前主题色（默认亮蓝）。
@Riverpod(keepAlive: true)
class AppAccentController extends _$AppAccentController {
  static const String _kKey = 'app.accent';

  /// 用户是否已手动切换（prefs 恢复晚到时不能覆盖用户刚做的选择）。
  bool _userChanged = false;

  @override
  AppAccent build() {
    _restore();
    return AppAccent.blue;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw == null || _userChanged) return;
      for (final accent in AppAccent.values) {
        if (accent.name == raw) {
          state = accent;
          return;
        }
      }
    } catch (_) {
      // 读取失败按默认（蓝）处理
    }
  }

  /// 切换主题色并落盘。
  Future<void> set(AppAccent accent) async {
    _userChanged = true;
    if (state != accent) state = accent;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, accent.name);
    } catch (_) {
      // 落盘失败：本次仍然生效
    }
  }
}

/// 亮 / 暗 / 跟随系统。
enum AppThemeMode {
  /// 跟随系统（默认）。
  system('跟随系统'),

  /// 亮色。
  light('亮色'),

  /// 暗色。
  dark('暗色');

  const AppThemeMode(this.label);

  /// 展示名。
  final String label;

  /// 对应的 Flutter 主题模式。
  ThemeMode get themeMode => switch (this) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };
}

/// 当前亮暗模式（书架右上角按钮 / 设置页共用，默认跟随系统）。
@Riverpod(keepAlive: true)
class AppThemeModeController extends _$AppThemeModeController {
  static const String _kKey = 'app.themeMode';

  /// 用户是否已手动切换（prefs 恢复晚到时不能覆盖用户刚做的选择）。
  bool _userChanged = false;

  @override
  AppThemeMode build() {
    _restore();
    return AppThemeMode.system;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw == null || _userChanged) return;
      for (final mode in AppThemeMode.values) {
        if (mode.name == raw) {
          state = mode;
          return;
        }
      }
    } catch (_) {
      // 读取失败按跟随系统处理
    }
  }

  /// 切换模式并落盘。
  Future<void> set(AppThemeMode mode) async {
    _userChanged = true;
    if (state != mode) state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, mode.name);
    } catch (_) {
      // 落盘失败：本次仍然生效
    }
  }

  /// 当前实际显示的是暗色时切到亮色，否则切到暗色（书架右上角按钮用）。
  Future<void> toggle(Brightness current) {
    return set(
      current == Brightness.dark ? AppThemeMode.light : AppThemeMode.dark,
    );
  }
}
