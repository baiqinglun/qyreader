/// 折页翻页几何：折线位置、纸背矩形、镜像矩阵必须自洽。
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/reader/native/curl_geometry.dart';
import 'package:qy_reader/features/reader/native/curl_painter.dart';

Offset _apply(Float64List m, Offset p) => Offset(
      m[0] * p.dx + m[4] * p.dy + m[12],
      m[1] * p.dx + m[5] * p.dy + m[13],
    );

Matcher _closeToOffset(Offset expected) => predicate<Offset>(
      (actual) => (actual - expected).distance < 0.01,
      '≈ $expected',
    );

void main() {
  group('右缘掀起（从右往左翻）', () {
    const page = Size(400, 800);

    test('折线随进度左移，纸背是折线左边的整条竖页', () {
      final g = CurlGeometry(page: page, progress: 0.4);
      expect(g.fold, closeTo(160, 0.001));
      expect(g.foldX, closeTo(240, 0.001));
      expect(g.flapRect, const Rect.fromLTRB(80, 0, 240, 800));
      expect(g.flapEdgeX, closeTo(80, 0.001));
      expect(g.isActive, isTrue);
    });

    test('镜像矩阵把原右缘折到外缘，折线上的点保持不动', () {
      final g = CurlGeometry(page: page, progress: 0.4);
      expect(
        _apply(g.reflection, const Offset(400, 0)),
        _closeToOffset(const Offset(80, 0)),
      );
      expect(
        _apply(g.reflection, Offset(g.foldX, 123)),
        _closeToOffset(Offset(g.foldX, 123)),
      );
      expect(_apply(g.reflection, const Offset(400, 800)),
          _closeToOffset(const Offset(80, 800)));
    });

    test('镜像不改变距离（等距变换），且是翻面（行列式为负）', () {
      final g = CurlGeometry(page: page, progress: 0.55);
      final m = g.reflection;
      final det = m[0] * m[5] - m[1] * m[4];
      expect(det, closeTo(-1, 1e-9));
      final a = const Offset(10, 20);
      final b = const Offset(300, 700);
      expect(
        (_apply(m, a) - _apply(m, b)).distance,
        closeTo((a - b).distance, 1e-6),
      );
    });

    test('纸背矩形面积 = 页高 × 折页宽度；新页从折线起露出', () {
      final g = CurlGeometry(page: page, progress: 0.3);
      expect(g.flapRect.width, closeTo(120, 0.001));
      expect(g.flapRect.height, closeTo(800, 0.001));
      expect(g.revealedRect.left, closeTo(280, 0.001));
      expect(g.flapPath.contains(const Offset(200, 400)), isTrue);
      expect(g.flapPath.contains(const Offset(300, 400)), isFalse);
    });
  });

  group('左缘掀起（回翻对称位，暂未启用）', () {
    const page = Size(400, 800);

    test('折线与纸背是右侧的镜像', () {
      final g = CurlGeometry(page: page, progress: 0.4, fromLeft: true);
      expect(g.foldX, closeTo(160, 0.001));
      expect(g.flapRect, const Rect.fromLTRB(160, 0, 320, 800));
      expect(g.flapEdgeX, closeTo(320, 0.001));
      expect(
        _apply(g.reflection, const Offset(0, 0)),
        _closeToOffset(const Offset(320, 0)),
      );
    });
  });

  group('边界', () {
    const page = Size(400, 800);

    test('进度 0 不画；进度 1 已翻完不画', () {
      expect(CurlGeometry(page: page, progress: 0).isActive, isFalse);
      final full = CurlGeometry(page: page, progress: 1);
      expect(full.fold, closeTo(400, 0.001));
      expect(full.foldX, closeTo(0, 0.001));
      expect(full.isActive, isFalse);
      expect(CurlGeometry(page: page, progress: 2).progress, 1);
      expect(CurlGeometry(page: page, progress: -1).progress, 0);
    });

    test('折页宽度随进度线性增长', () {
      final widths = [0.1, 0.3, 0.5, 0.8]
          .map((p) => CurlGeometry(page: page, progress: p).fold)
          .toList();
      expect(widths[0], closeTo(40, 0.001));
      expect(widths[1], closeTo(120, 0.001));
      expect(widths[2], closeTo(200, 0.001));
      expect(widths[3], closeTo(320, 0.001));
    });

    test('极小的页面不产生 NaN / 无穷', () {
      final g = CurlGeometry(page: const Size(1, 1), progress: 0.9);
      for (final p in [g.foldMid, g.shadowTo]) {
        expect(p.dx.isFinite, isTrue);
        expect(p.dy.isFinite, isTrue);
      }
      for (var i = 0; i < 16; i++) {
        expect(g.reflection[i].isFinite, isTrue);
      }
    });

    test('宽页（横屏 / 双页）折页不超出页宽', () {
      final g = CurlGeometry(page: const Size(1200, 700), progress: 1);
      expect(g.fold, closeTo(1200, 0.001));
      expect(g.foldX, closeTo(0, 0.001));
    });
  });

  group('绘制', () {
    test('纸背铺色压暗、新页折线附近有阴影、远端保持原样', () async {
      const size = Size(200, 400);
      final g = CurlGeometry(page: size, progress: 0.6);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
          Offset.zero & size, Paint()..color = const Color(0xFF808080));
      CurlTurnPainter(CurlRenderState(
        geometry: g,
        background: const Color(0xFF808080),
      )).paint(canvas, size);
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(200, 400);
      addTearDown(rendered.dispose);
      final bytes = await rendered.toByteData(format: ImageByteFormat.rawRgba);
      expect(bytes, isNotNull);

      int gray(double x, double y) {
        final i = (y.toInt() * 200 + x.toInt()) * 4;
        return bytes!.getUint8(i);
      }

      // 卷边区域（x=60：p=0.6 时卷边覆盖 [34,80]）被纸色提亮。
      expect(gray(60, 200), greaterThan(128));
      // 新页远端（x=190）只有页底色，不受影响。
      expect(gray(190, 200), 128);
      // 折线附近的新页被压暗。
      expect(gray(84, 200), lessThan(128));
    });
  });
}
