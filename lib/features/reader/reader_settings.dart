/// 阅读排版设置：主题 / 字号 / 行距 / 边距 / flow / 翻页模式。
///
/// 持久化到 shared_preferences（JSON）；不进 SQLite、不参与同步
/// （v1 设置为设备本地偏好）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme/reading_theme.dart';

part 'reader_settings.freezed.dart';
part 'reader_settings.g.dart';

/// 排版流向。
enum ReadingFlow {
  /// 分页（左右翻页）。
  paginated('分页'),

  /// 上下滚动。
  scrolled('滚动');

  const ReadingFlow(this.label);

  /// 展示名。
  final String label;
}

/// 翻页动画模式。
enum PageTurnMode {
  /// 滑动：双页同移。
  slide('滑动'),

  /// 覆盖：新页右入，旧页左移并压暗。
  cover('覆盖'),

  /// 无动画：瞬间切换。
  none('无'),

  /// 淡入：交叉淡入 + 2px 上移。
  fade('淡入'),

  /// 仿真：当前页沿左缘 3D 折叠翻起，下一页原样露出（无 WebView 截图，
  /// 以透视折叠 + 折线阴影近似仿真翻页）。
  curl('仿真');

  const PageTurnMode(this.label);

  /// 展示名。
  final String label;
}

/// 排版设置集合。
@freezed
abstract class ReadingSettings with _$ReadingSettings {
  const factory ReadingSettings({
    /// 阅读主题。
    @Default(ReadingTheme.paper) ReadingTheme theme,

    /// 正文字号（14..28）。
    @Default(18.0) double fontSize,

    /// 行距倍数（1.2..2.4）。
    @Default(1.7) double lineHeight,

    /// 左右边距（0..48）。
    @Default(16.0) double margin,

    /// 排版流向。
    @Default(ReadingFlow.paginated) ReadingFlow flow,

    /// 翻页动画模式。
    @Default(PageTurnMode.slide) PageTurnMode pageTurnMode,
  }) = _ReadingSettings;
}

/// 手写序列化（json_serializable 与 freezed 3 在 Dart 3.8 下不兼容）。
extension ReadingSettingsJson on ReadingSettings {
  /// 序列化为 JSON Map。
  Map<String, dynamic> toMap() => <String, dynamic>{
        'theme': theme.name,
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'margin': margin,
        'flow': flow.name,
        'pageTurnMode': pageTurnMode.name,
      };
}

/// 顶层反序列化；非法值逐字段兜底默认。
ReadingSettings readingSettingsFromMap(Map<String, dynamic> json) =>
    ReadingSettings(
      theme: ReadingTheme.values.firstWhere(
        (t) => t.name == json['theme'],
        orElse: () => ReadingTheme.paper,
      ),
      fontSize: _clamp((json['fontSize'] as num?)?.toDouble(), 14, 28, 18),
      lineHeight: _clamp(
          (json['lineHeight'] as num?)?.toDouble(), 1.2, 2.4, 1.7),
      margin: _clamp((json['margin'] as num?)?.toDouble(), 0, 48, 16),
      flow: ReadingFlow.values.firstWhere(
        (f) => f.name == json['flow'],
        orElse: () => ReadingFlow.paginated,
      ),
      pageTurnMode: PageTurnMode.values.firstWhere(
        (m) => m.name == json['pageTurnMode'],
        orElse: () => PageTurnMode.slide,
      ),
    );

double _clamp(double? v, double min, double max, double fallback) {
  if (v == null) return fallback;
  return v.clamp(min, max);
}

/// 排版设置控制器：读写 shared_preferences。
@Riverpod(keepAlive: true)
class ReadingSettingsController extends _$ReadingSettingsController {
  static const String _kKey = 'reader.settings';

  @override
  ReadingSettings build() {
    _restore();
    return const ReadingSettings();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null) return;
    try {
      state = readingSettingsFromMap(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      // 损坏的设置按默认值处理
    }
  }

  Future<void> update(ReadingSettings next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(next.toMap()));
  }

  /// 仅替换部分字段（面板快捷操作用）。
  Future<void> patch({
    ReadingTheme? theme,
    double? fontSize,
    double? lineHeight,
    double? margin,
    ReadingFlow? flow,
    PageTurnMode? pageTurnMode,
  }) async {
    // freezed 3 的 copyWith 对非空字段收非空参数，这里用 ?? 合成新值
    await update(ReadingSettings(
      theme: theme ?? state.theme,
      fontSize: fontSize ?? state.fontSize,
      lineHeight: lineHeight ?? state.lineHeight,
      margin: margin ?? state.margin,
      flow: flow ?? state.flow,
      pageTurnMode: pageTurnMode ?? state.pageTurnMode,
    ));
  }
}

/// 注入 WebView 的样式载荷（JSON 字符串）。
String readerStylePayload(ReadingSettings s) => jsonEncode(<String, dynamic>{
      'theme': <String, String>{
        'background': _cssColor(s.theme.background),
        'foreground': _cssColor(s.theme.foreground),
        'accent': _cssColor(s.theme.accent),
      },
      'fontSize': s.fontSize.round(),
      'lineHeight': s.lineHeight,
      'margin': s.margin.round(),
      'flow': s.flow.name,
    });

String _cssColor(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
