/// 阅读主题：纸 / 纯白 / 羊皮 / 夜间 / 纯黑。
///
/// 颜色不落库，数据库只存语义 token；正文主题色经 WebView 桥注入。
library;

import 'package:flutter/material.dart';

/// 阅读主题 token。
enum ReadingTheme {
  /// 纸白。
  paper('纸', Color(0xFFF7F3EB), Color(0xFF2B2B2B), Color(0xFF2E7D6B)),

  /// 纯白（干净的白底黑字）。
  white('纯白', Color(0xFFFFFFFF), Color(0xFF1F1F1F), Color(0xFF2E7D6B)),

  /// 羊皮。
  sepia('羊皮', Color(0xFFF1E4CB), Color(0xFF5B4636), Color(0xFF8A6A3B)),

  /// 夜间（深灰，比纯黑柔）。
  night('夜间', Color(0xFF1F1F22), Color(0xFFC9C9CC), Color(0xFF7FA99B)),

  /// 纯黑（OLED 省电）。
  black('纯黑', Color(0xFF000000), Color(0xFF9E9EA3), Color(0xFF5F8D80));

  const ReadingTheme(this.label, this.background, this.foreground, this.accent);

  /// 展示名。
  final String label;

  /// 正文背景色。
  final Color background;

  /// 正文前景色。
  final Color foreground;

  /// 链接/强调色。
  final Color accent;

  /// chrome（顶栏/底栏/抽屉）底色：亮主题用背景色，暗主题略提亮一档。
  Color get chromeSurface => switch (this) {
        paper || white || sepia => background,
        night => const Color(0xFF29292D),
        black => const Color(0xFF101012),
      };

  /// chrome 前景色。
  Color get chromeForeground => switch (this) {
        paper || white || sepia => const Color(0xFF2B2B2B),
        night || black => const Color(0xFFC9C9CC),
      };
}
