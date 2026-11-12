/// 阅读器视图层几何不变量的单测。
///
/// 重点守住「隐藏层整层在屏幕右边界之外」这条：Android WebView 走虚拟显示
/// （纹理）合成，不受 Flutter Stack 裁剪，隐藏层一旦停在内容区右侧，
/// 它的左侧就会压在右边距上——用户看到右侧露出下一页的内容。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/reader/reader_page.dart';

void main() {
  group('隐藏层静止位移', () {
    test('左边缘必须落在屏幕右边界之外', () {
      // 典型手机：屏宽 359dp，左边距 16、右边距 20。
      const screenWidth = 359.0;
      const marginLeft = 16.0;
      const marginRight = 20.0;
      final contentWidth = screenWidth - marginLeft - marginRight;

      final restDx = hiddenLayerRestDx(contentWidth, marginRight);

      // 隐藏层左边缘（屏幕坐标）>= 屏幕宽 → 整层在屏外。
      expect(marginLeft + restDx, greaterThanOrEqualTo(screenWidth));
    });

    test('右边距为 0 时同样整层在屏外', () {
      const screenWidth = 360.0;
      const marginLeft = 0.0;
      const marginRight = 0.0;
      final contentWidth = screenWidth - marginLeft - marginRight;

      final restDx = hiddenLayerRestDx(contentWidth, marginRight);

      expect(marginLeft + restDx, greaterThanOrEqualTo(screenWidth));
    });

    test('静止位随右边距增大而右移（不会压回正文区）', () {
      const contentWidth = 320.0;
      final narrow = hiddenLayerRestDx(contentWidth, 8);
      final wide = hiddenLayerRestDx(contentWidth, 40);
      expect(wide, greaterThan(narrow));
      expect(narrow, greaterThan(contentWidth));
    });
  });
}
