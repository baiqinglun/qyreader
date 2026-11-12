/// 「随手仿真」折页的视觉层：下面的下一页、被掀开的当前页、翻过去的纸背，
/// 以及折线阴影/折痕。
///
/// 全部用真实页面 widget 现场裁剪/镜像，不截整页图：纸背上的字天然是
/// 镜像的（与参考稿一致），也省掉拖动开始时的 `toImage` 卡顿。
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'free_curl_geometry.dart';

/// 随手仿真覆盖层（纯视觉，不接手势）。
class FreeCurlOverlay extends StatelessWidget {
  const FreeCurlOverlay({
    required this.oldPage,
    required this.newPage,
    required this.frame,
    required this.background,
    super.key,
  });

  /// 当前页（被掀起的那一页）。
  final Widget oldPage;

  /// 下一页（从掀开的洞里露出来）。
  final Widget newPage;

  /// 当前折页几何（手指移动时更新）。
  final ValueListenable<FreeCurlGeometry?> frame;

  /// 纸张底色（折线阴影用）。
  final Color background;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FreeCurlGeometry?>(
      valueListenable: frame,
      builder: (context, geo, _) {
        if (geo == null || !geo.isActive) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          child: ExcludeSemantics(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. 下一页铺在底下，只有被掀开的洞里才看得到。
                Positioned.fill(child: newPage),
                // 2. 当前页挖掉纸角，露出下面的新页。
                Positioned.fill(
                  child: ClipPath(
                    clipper: _OldPageClipper(geo),
                    child: oldPage,
                  ),
                ),
                // 3. 翻过去的纸背：当前页关于折线镜像，裁到折页区域。
                Positioned.fill(
                  child: ClipPath(
                    clipper: _FlapClipper(geo),
                    child: Transform(
                      transform: Matrix4.fromFloat64List(geo.reflection),
                      alignment: Alignment.topLeft,
                      transformHitTests: false,
                      child: oldPage,
                    ),
                  ),
                ),
                // 4. 折线投影 + 折痕。
                Positioned.fill(
                  child: CustomPaint(
                    painter: _FreeCurlShadowPainter(geo, background),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 当前页：整页减去被掀开的纸角。
class _OldPageClipper extends CustomClipper<Path> {
  const _OldPageClipper(this.geo);

  final FreeCurlGeometry geo;

  @override
  Path getClip(Size size) {
    final all = Path()..addRect(Offset.zero & size);
    return Path.combine(PathOperation.difference, all, geo.holePath);
  }

  @override
  bool shouldReclip(_OldPageClipper old) => old.geo != geo;
}

/// 纸背：只保留翻过去的那一块。
class _FlapClipper extends CustomClipper<Path> {
  const _FlapClipper(this.geo);

  final FreeCurlGeometry geo;

  @override
  Path getClip(Size size) => geo.flapPath;

  @override
  bool shouldReclip(_FlapClipper old) => old.geo != geo;
}

/// 折线投影与折痕。
class _FreeCurlShadowPainter extends CustomPainter {
  const _FreeCurlShadowPainter(this.geo, this.background);

  final FreeCurlGeometry geo;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final toCorner = geo.corner - geo.foldMid;
    final len = toCorner.distance;
    if (len < 1e-3) return;

    // 折线投在被掀开区域里的阴影：越靠近纸角越深。
    final shadowEnd = geo.foldMid + toCorner / len * math.min(len, 80);
    canvas.save();
    canvas.clipPath(geo.holePath);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          geo.foldMid,
          shadowEnd,
          [
            const Color(0x33000000),
            const Color(0x00000000),
          ],
        ),
    );
    canvas.restore();

    // 纸背靠折线一侧再压一点光，纸页才不像一张贴纸。
    canvas.save();
    canvas.clipPath(geo.flapPath);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          geo.foldMid,
          geo.foldMid - toCorner / len * 36,
          [
            const Color(0x14000000),
            const Color(0x00000000),
          ],
        ),
    );
    canvas.restore();

    // 折痕：一条暗线 + 一条亮线。
    final crease = Paint()
      ..strokeWidth = 1
      ..isAntiAlias = true;
    canvas.drawLine(
      geo.foldA,
      geo.foldB,
      crease..color = const Color(0x1F000000),
    );
    canvas.drawLine(
      geo.foldA + const Offset(1, 0),
      geo.foldB + const Offset(1, 0),
      crease..color = const Color(0x26FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_FreeCurlShadowPainter old) =>
      old.geo != geo || old.background != background;
}
