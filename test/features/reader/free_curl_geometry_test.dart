/// 随手仿真几何：纸角折到手指、纸背与露出的新页互补。
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/reader/native/free_curl_geometry.dart';

Offset _apply(Float64List m, Offset p) => Offset(
      m[0] * p.dx + m[4] * p.dy + m[12],
      m[1] * p.dx + m[5] * p.dy + m[13],
    );

Matcher _closeToOffset(Offset expected) => predicate<Offset>(
      (actual) => (actual - expected).distance < 0.01,
      '≈ $expected',
    );

void main() {
  const page = Size(400, 800);

  test('纸角映射到手指，折线经过两者的垂直平分线', () {
    const corner = Offset(400, 800);
    const finger = Offset(200, 400);
    final g = FreeCurlGeometry(
      page: page,
      corner: corner,
      finger: finger,
    );

    expect(g.isActive, isTrue);
    expect(_apply(g.reflection, corner), _closeToOffset(finger));
    final mid = (corner + finger) / 2;
    final normal = finger - corner;
    for (final p in [g.foldA, g.foldB]) {
      final dot = (p.dx - mid.dx) * normal.dx + (p.dy - mid.dy) * normal.dy;
      expect(dot.abs(), lessThan(0.01), reason: '折点应落在折线上');
    }
  });

  test('被掀起的纸角在 C 一侧，纸背在手指一侧，两边不重叠', () {
    const corner = Offset(400, 800);
    const finger = Offset(200, 400);
    final g = FreeCurlGeometry(
      page: page,
      corner: corner,
      finger: finger,
    );

    final inHole = Offset.lerp(corner, g.foldMid, 0.35)!;
    final inFlap = Offset.lerp(finger, g.foldMid, 0.35)!;
    expect(g.holePath.contains(inHole), isTrue);
    expect(g.flapPath.contains(inFlap), isTrue);
    expect(g.holePath.contains(inFlap), isFalse);
    expect(g.flapPath.contains(inHole), isFalse);
  });

  test('镜像等距、翻面，行列式为 -1', () {
    final g = FreeCurlGeometry(
      page: page,
      corner: const Offset(400, 800),
      finger: const Offset(120, 300),
    );
    final m = g.reflection;
    final det = m[0] * m[5] - m[1] * m[4];
    expect(det, closeTo(-1, 1e-9));
    final a = const Offset(30, 40);
    final b = const Offset(260, 610);
    expect(
      (_apply(m, a) - _apply(m, b)).distance,
      closeTo((a - b).distance, 1e-6),
    );
  });

  test('手指贴着纸角时不折起；往反方向拉到页面外会被夹住', () {
    final still = FreeCurlGeometry(
      page: page,
      corner: const Offset(400, 800),
      finger: const Offset(398, 798),
    );
    expect(still.isActive, isFalse);

    final clamped = FreeCurlGeometry(
      page: page,
      corner: const Offset(400, 800),
      finger: const Offset(-100, -100),
    );
    expect(clamped.finger, Offset.zero);
    expect(clamped.holePath.getBounds().isEmpty, isFalse);
  });

  test('从左下角掀起（回翻）同样把角折到手指', () {
    final g = FreeCurlGeometry(
      page: page,
      corner: const Offset(0, 800),
      finger: const Offset(200, 420),
      forward: false,
    );
    expect(g.forward, isFalse);
    expect(g.isActive, isTrue);
    expect(
      _apply(g.reflection, const Offset(0, 800)),
      _closeToOffset(const Offset(200, 420)),
    );
    final inHole = Offset.lerp(g.corner, g.foldMid, 0.3)!;
    final inFlap = Offset.lerp(g.finger, g.foldMid, 0.3)!;
    expect(g.holePath.contains(inHole), isTrue);
    expect(g.flapPath.contains(inFlap), isTrue);
    expect(g.holePath.contains(inFlap), isFalse);
  });

  test('极小页面不产生 NaN', () {
    final g = FreeCurlGeometry(
      page: const Size(1, 1),
      corner: const Offset(1, 1),
      finger: const Offset(0, 0),
    );
    expect(g.progress.isFinite, isTrue);
    for (final p in [g.foldA, g.foldB]) {
      expect(p.dx.isFinite && p.dy.isFinite, isTrue);
    }
    for (var i = 0; i < 16; i++) {
      expect(g.reflection[i].isFinite, isTrue);
    }
  });
}
