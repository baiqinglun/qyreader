/// 阅读页「页面布局」：九宫格点击区域 + 页眉/页脚左右区域。
///
/// 只影响点击，不影响滑动翻页——任何翻页模式下横向滑动都可以翻页，
/// 这里配置的是「点哪里做什么」。
library;

import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 点击区域的动作。
enum TapZoneAction {
  /// 上一页。
  previousPage('上一页'),

  /// 下一页。
  nextPage('下一页'),

  /// 打开/关闭阅读菜单。
  menu('菜单');

  const TapZoneAction(this.label);

  /// 展示名。
  final String label;
}

/// 页眉/页脚左右区域的覆盖动作；[followGrid] = 按九宫格该列的动作。
enum EdgeZoneAction {
  /// 跟随九宫格。
  followGrid('跟随九宫格'),

  /// 上一页。
  previousPage('上一页'),

  /// 下一页。
  nextPage('下一页'),

  /// 菜单。
  menu('菜单');

  const EdgeZoneAction(this.label);

  /// 展示名。
  final String label;

  /// 转成九宫格动作；[followGrid] 返回 null。
  TapZoneAction? get action => switch (this) {
        EdgeZoneAction.followGrid => null,
        EdgeZoneAction.previousPage => TapZoneAction.previousPage,
        EdgeZoneAction.nextPage => TapZoneAction.nextPage,
        EdgeZoneAction.menu => TapZoneAction.menu,
      };
}

/// 页面布局配置。
@immutable
class PageLayoutSettings {
  /// 创建配置；[zones] 固定 9 个（行优先），页眉/页脚默认跟随九宫格。
  const PageLayoutSettings({
    this.zones = const [
      TapZoneAction.previousPage,
      TapZoneAction.menu,
      TapZoneAction.nextPage,
      TapZoneAction.previousPage,
      TapZoneAction.menu,
      TapZoneAction.nextPage,
      TapZoneAction.previousPage,
      TapZoneAction.menu,
      TapZoneAction.nextPage,
    ],
    this.headerLeft = EdgeZoneAction.followGrid,
    this.headerRight = EdgeZoneAction.followGrid,
    this.footerLeft = EdgeZoneAction.followGrid,
    this.footerRight = EdgeZoneAction.followGrid,
  });

  /// 默认布局：左列上一页、中列菜单、右列下一页。
  static const PageLayoutSettings defaults = PageLayoutSettings();

  /// 九宫格动作（下标 0..8，行优先）。
  final List<TapZoneAction> zones;

  /// 页眉左侧动作。
  final EdgeZoneAction headerLeft;

  /// 页眉右侧动作。
  final EdgeZoneAction headerRight;

  /// 页脚左侧动作。
  final EdgeZoneAction footerLeft;

  /// 页脚右侧动作。
  final EdgeZoneAction footerRight;

  /// 复制并覆盖。
  PageLayoutSettings copyWith({
    List<TapZoneAction>? zones,
    EdgeZoneAction? headerLeft,
    EdgeZoneAction? headerRight,
    EdgeZoneAction? footerLeft,
    EdgeZoneAction? footerRight,
  }) {
    return PageLayoutSettings(
      zones: zones ?? this.zones,
      headerLeft: headerLeft ?? this.headerLeft,
      headerRight: headerRight ?? this.headerRight,
      footerLeft: footerLeft ?? this.footerLeft,
      footerRight: footerRight ?? this.footerRight,
    );
  }

  /// 修改某个九宫格动作。
  PageLayoutSettings withZone(int index, TapZoneAction action) {
    if (index < 0 || index >= 9) return this;
    final next = [...zones];
    next[index] = action;
    return copyWith(zones: next);
  }

  /// 按页码列解析页眉/页脚「跟随九宫格」。
  TapZoneAction _edgeAction(
    EdgeZoneAction edge,
    int row,
    double x,
    Size size,
  ) {
    final fixed = edge.action;
    if (fixed != null) return fixed;
    final col = _column(x, size.width);
    return zones[row * 3 + col];
  }

  /// 点击位置对应的动作。
  ///
  /// [headerHeight] / [footerHeight] 为实际页眉/页脚带高度（0 = 没显示）。
  TapZoneAction actionAt(
    Offset local,
    Size size, {
    double headerHeight = 0,
    double footerHeight = 0,
  }) {
    if (size.width <= 0 || size.height <= 0) return TapZoneAction.menu;
    final x = local.dx.clamp(0.0, size.width);
    final y = local.dy.clamp(0.0, size.height);
    if (headerHeight > 0 && y < headerHeight) {
      final edge = x < size.width / 2 ? headerLeft : headerRight;
      return _edgeAction(edge, 0, x, size);
    }
    if (footerHeight > 0 && y > size.height - footerHeight) {
      final edge = x < size.width / 2 ? footerLeft : footerRight;
      return _edgeAction(edge, 2, x, size);
    }
    final col = _column(x, size.width);
    final row = ((y / size.height) * 3).floor().clamp(0, 2);
    return zones[row * 3 + col];
  }

  static int _column(double x, double width) =>
      ((x / width) * 3).floor().clamp(0, 2);

  /// 序列化成 prefs JSON。
  String toJson() => jsonEncode({
        'zones': [for (final z in zones) z.name],
        'headerLeft': headerLeft.name,
        'headerRight': headerRight.name,
        'footerLeft': footerLeft.name,
        'footerRight': footerRight.name,
      });

  /// 从 prefs JSON 恢复；坏数据回退默认。
  factory PageLayoutSettings.fromJson(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return defaults;
      final rawZones = map['zones'];
      final zones = <TapZoneAction>[];
      if (rawZones is List) {
        for (final name in rawZones.take(9)) {
          zones.add(_actionOf(name));
        }
      }
      while (zones.length < 9) {
        zones.add(const PageLayoutSettings().zones[zones.length]);
      }
      return PageLayoutSettings(
        zones: zones,
        headerLeft: _edgeOf(map['headerLeft']),
        headerRight: _edgeOf(map['headerRight']),
        footerLeft: _edgeOf(map['footerLeft']),
        footerRight: _edgeOf(map['footerRight']),
      );
    } catch (_) {
      return defaults;
    }
  }

  static TapZoneAction _actionOf(Object? raw) {
    for (final value in TapZoneAction.values) {
      if (value.name == raw) return value;
    }
    return TapZoneAction.menu;
  }

  static EdgeZoneAction _edgeOf(Object? raw) {
    for (final value in EdgeZoneAction.values) {
      if (value.name == raw) return value;
    }
    return EdgeZoneAction.followGrid;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PageLayoutSettings &&
        listEquals(other.zones, zones) &&
        other.headerLeft == headerLeft &&
        other.headerRight == headerRight &&
        other.footerLeft == footerLeft &&
        other.footerRight == footerRight;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(zones),
        headerLeft,
        headerRight,
        footerLeft,
        footerRight,
      );
}

/// 页面布局配置的读取 / 保存（prefs key `reader.pageLayout`）。
final pageLayoutControllerProvider =
    NotifierProvider<PageLayoutController, PageLayoutSettings>(
  PageLayoutController.new,
);

/// 页面布局配置控制器。
class PageLayoutController extends Notifier<PageLayoutSettings> {
  static const String _key = 'reader.pageLayout';

  bool _userChanged = false;

  @override
  PageLayoutSettings build() {
    _restore();
    return PageLayoutSettings.defaults;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || _userChanged) return;
      state = PageLayoutSettings.fromJson(raw);
    } catch (_) {
      // 读取失败按默认布局处理
    }
  }

  /// 保存并立即生效。
  Future<void> save(PageLayoutSettings value) async {
    _userChanged = true;
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value.toJson());
    } catch (_) {
      // 保存失败只影响下次启动，当前会话仍生效
    }
  }

  /// 恢复默认布局。
  Future<void> reset() => save(PageLayoutSettings.defaults);
}
