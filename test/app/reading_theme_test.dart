/// 阅读主题：新增纯白背景。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';

void main() {
  test('纯白主题：白底、深色文字', () {
    expect(ReadingTheme.white.label, '纯白');
    expect(ReadingTheme.white.background, const Color(0xFFFFFFFF));
    expect(ReadingTheme.white.chromeSurface, const Color(0xFFFFFFFF));
    expect(ReadingTheme.white.chromeForeground, const Color(0xFF2B2B2B));
    expect(ReadingTheme.white.foreground, const Color(0xFF1F1F1F));
  });

  test('纯白与纸面/羊皮同属亮色 chrome', () {
    expect(ReadingTheme.white.chromeForeground, ReadingTheme.paper.chromeForeground);
    expect(ReadingTheme.white.chromeSurface, ReadingTheme.white.background);
  });
}
