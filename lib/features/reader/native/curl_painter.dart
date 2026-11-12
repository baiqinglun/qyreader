/// 折页翻页的绘制层：一条纸背 + 折线两侧的投影 + 折痕高光。
///
/// 只画「纸背」不画正文镜像：纸背本来就不该透出正面的字，镜像正文在
/// 大折页上会变成满屏重影；纸背用阅读底色提亮一档 + 折线渐变，观感
/// 更像一张被翻起来的纸，也不会因为截图失败退回奇怪的效果。
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'curl_geometry.dart';

/// 一帧折页翻页的绘制数据。
class CurlRenderState {
  const CurlRenderState({
    required this.geometry,
    required this.background,
  });

  final CurlGeometry geometry;

  /// 纸张底色（纸背提亮/压暗按它调，深色主题下不会糊成黑块）。
  final Color background;
}

/// 折页翻页绘制器。
class CurlTurnPainter extends CustomPainter {
  const CurlTurnPainter(this.state);

  final CurlRenderState state;

  @override
  void paint(Canvas canvas, Size size) {
    final g = state.geometry;
    if (!g.isActive) return;

    _paintFoldShadow(canvas, g);
    _paintBack(canvas, g);
    _paintOuterShadow(canvas, g);
    _paintCrease(canvas, g);
  }

  /// 折线投在新页上的阴影：折页抬起来，靠折线一侧的下一页最暗。
  void _paintFoldShadow(Canvas canvas, CurlGeometry g) {
    final dir = g.fromLeft ? -1.0 : 1.0;
    final side = g.fromLeft
        ? Rect.fromLTRB(0, 0, g.foldX, g.pageSize.height)
        : Rect.fromLTRB(
            g.foldX, 0, g.pageSize.width, g.pageSize.height);
    canvas.save();
    canvas.clipRect(side);
    canvas.drawRect(
      side,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(g.foldX, 0),
          Offset(g.foldX + 26 * dir, 0),
          [
            const Color(0x33000000),
            const Color(0x00000000),
          ],
        ),
    );
    canvas.restore();
  }

  /// 纸背卷边：折线旁一条窄纸边，外缘微弯，像纸页卷起来的侧边。
  void _paintBack(Canvas canvas, CurlGeometry g) {
    final rect = g.curlRect.intersect(g.pageRect);
    if (rect.isEmpty) return;
    final base = ui.Color.lerp(
      state.background,
      const Color(0xFFFFFFFF),
      0.12,
    )!.withValues(alpha: 0.97);
    final near = ui.Color.lerp(
      state.background,
      const Color(0xFFFFFFFF),
      0.24,
    )!.withValues(alpha: 0.98);
    final from = Offset(
      g.fromLeft ? g.curlRect.right : g.curlRect.left,
      0,
    );
    final to = Offset(g.foldX, 0);
    // 外缘做一点弯曲，避免看起来像一条白色的直条。
    final outer = from.dx;
    final amp = math.min(4.0, g.curlWidth * 0.18);
    final path = Path()
      ..moveTo(g.foldX, 0)
      ..lineTo(g.foldX, g.pageSize.height)
      ..lineTo(outer + amp, g.pageSize.height)
      ..quadraticBezierTo(
        outer - amp,
        g.pageSize.height / 2,
        outer + amp,
        0,
      )
      ..close();

    canvas.save();
    // 外缘要弯出 rect 几个像素，裁剪框跟着放宽，否则弯曲会被切平。
    canvas.clipRect(rect.inflate(amp + 2).intersect(g.pageRect));
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          from,
          to,
          [base, near],
        ),
    );
    canvas.restore();
  }

  /// 卷边外缘投在旧页上的浅影，纸边才像离开纸面。
  void _paintOuterShadow(Canvas canvas, CurlGeometry g) {
    final outer = g.fromLeft ? g.curlRect.right : g.curlRect.left;
    final dir = g.fromLeft ? 1.0 : -1.0;
    final side = g.fromLeft
        ? Rect.fromLTRB(outer, 0, g.pageSize.width, g.pageSize.height)
        : Rect.fromLTRB(0, 0, outer, g.pageSize.height);
    if (side.isEmpty) return;
    canvas.save();
    canvas.clipRect(side);
    canvas.drawRect(
      side,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(outer + 16 * dir, 0),
          Offset(outer, 0),
          [
            const Color(0x00000000),
            const Color(0x1A000000),
          ],
        ),
    );
    canvas.restore();
  }

  /// 折痕：折线上一条 1px 亮线 + 一条暗线，压住卷边与新页的接缝。
  void _paintCrease(Canvas canvas, CurlGeometry g) {
    canvas.drawLine(
      Offset(g.foldX - 1, 0),
      Offset(g.foldX - 1, g.pageSize.height),
      Paint()
        ..color = const Color(0x1A000000)
        ..strokeWidth = 1
        ..isAntiAlias = true,
    );
    canvas.drawLine(
      Offset(g.foldX, 0),
      Offset(g.foldX, g.pageSize.height),
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.18)
        ..strokeWidth = 1
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant CurlTurnPainter oldDelegate) =>
      oldDelegate.state != state;
}
