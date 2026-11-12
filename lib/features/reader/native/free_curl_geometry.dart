/// 「随手仿真」折页几何：纸角从手指落点开始折起，折线是「原纸角 → 手指」
/// 连线的垂直平分线，纸角正好落在手指上。
///
/// 坐标系：原点在本页左上角，单位逻辑像素。折线把页面分成两块：
/// - 纸角一侧（含原角 C）被掀起，露出下面的下一页（[holePath]）；
/// - 掀起的那块翻到手指一侧（[flapPath]），背面是镜像后的正文。
///
/// 与竖直折页（[CurlGeometry]）不同，这里折线是斜的、位置由手指决定，
/// 拖动多少就折多少；手指在哪，纸角就跟到哪。
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// 一次随手折页的几何快照。
class FreeCurlGeometry {
  const FreeCurlGeometry._({
    required this.pageSize,
    required this.corner,
    required this.finger,
    required this.forward,
    required this.foldA,
    required this.foldB,
    required this.holePath,
    required this.flapPath,
    required this.reflection,
    required this.progress,
  });

  /// 按页尺寸、纸角与手指位置构造；手指太靠近纸角时视为未折起。
  factory FreeCurlGeometry({
    required Size page,
    required Offset corner,
    required Offset finger,
    bool forward = true,
    bool clampFinger = true,
  }) {
    final w = math.max(page.width, 1.0);
    final h = math.max(page.height, 1.0);
    final rect = Offset.zero & Size(w, h);
    final c = Offset(
      corner.dx.clamp(0.0, w),
      corner.dy.clamp(0.0, h),
    );
    final f = clampFinger
        ? Offset(
            finger.dx.clamp(0.0, w),
            finger.dy.clamp(0.0, h),
          )
        : finger;
    final toFinger = f - c;
    final distance = toFinger.distance;
    if (distance < 8) {
      return FreeCurlGeometry._(
        pageSize: Size(w, h),
        corner: c,
        finger: f,
        forward: forward,
        foldA: c,
        foldB: c,
        holePath: Path(),
        flapPath: Path(),
        reflection: _identity(),
        progress: 0,
      );
    }

    final mid = (c + f) / 2;
    // 垂直平分线方向（与 C→F 垂直）。
    final dir = Offset(-toFinger.dy, toFinger.dx) / distance;
    final hits = _lineRectHits(rect, mid, dir);
    if (hits.length < 2) {
      return _inactive(w, h, c, f, forward);
    }

    // 取最远的两点（折线与页框最多两个交点；穿过角点时会有重复）。
    var a = hits[0];
    var b = hits[1];
    var best = (a - b).distance;
    for (var i = 0; i < hits.length; i++) {
      for (var j = i + 1; j < hits.length; j++) {
        final d = (hits[i] - hits[j]).distance;
        if (d > best) {
          best = d;
          a = hits[i];
          b = hits[j];
        }
      }
    }

    // 纸角一侧（含 C）的多边形：法向从 F 指向 C（C 在正侧）。
    final holePts = _clipHalfPlane(rect, mid, c - f);
    if (holePts.length < 3 || best < 2) {
      return _inactive(w, h, c, f, forward);
    }

    final reflection = _reflection(mid, dir);
    final flapPts = holePts.map((p) => _apply(reflection, p)).toList();
    final hole = Path()..addPolygon(holePts, true);
    final flap = Path()..addPolygon(flapPts, true);
    final pagePath = Path()..addRect(rect);

    return FreeCurlGeometry._(
      pageSize: Size(w, h),
      corner: c,
      finger: f,
      forward: forward,
      foldA: a,
      foldB: b,
      holePath: Path.combine(PathOperation.intersect, hole, pagePath),
      flapPath: Path.combine(PathOperation.intersect, flap, pagePath),
      reflection: reflection,
      progress: (distance / (w + h)).clamp(0.0, 1.0),
    );
  }

  static FreeCurlGeometry _inactive(
    double w,
    double h,
    Offset c,
    Offset f,
    bool forward,
  ) =>
      FreeCurlGeometry._(
        pageSize: Size(w, h),
        corner: c,
        finger: f,
        forward: forward,
        foldA: c,
        foldB: c,
        holePath: Path(),
        flapPath: Path(),
        reflection: _identity(),
        progress: 0,
      );

  final Size pageSize;

  /// 被掀起的纸角（右下角 / 左下角）。
  final Offset corner;

  /// 手指当前位置（纸角折过去后的落点）。
  final Offset finger;

  /// 从右往左翻（下一页）还是从左往右翻（上一页）。
  final bool forward;

  /// 折线与页框的两个交点。
  final Offset foldA;
  final Offset foldB;

  /// 被掀起、露出下一页的区域。
  final Path holePath;

  /// 翻过去的纸背区域（镜像后的纸角）。
  final Path flapPath;

  /// 关于折线的镜像矩阵（列主序 4x4）。
  final Float64List reflection;

  /// 折起程度 0..1（只用于诊断/淡出，不参与定位）。
  final double progress;

  /// 折线中点。
  Offset get foldMid => (foldA + foldB) / 2;

  /// 是否值得绘制。
  bool get isActive => progress > 0.008 && !holePath.getBounds().isEmpty;
}

/// 直线与页框的交点（去重）。
List<Offset> _lineRectHits(Rect rect, Offset p, Offset dir) {
  final out = <Offset>[];
  void add(double t) {
    final q = p + dir * t;
    if (q.dx < -0.01 ||
        q.dx > rect.width + 0.01 ||
        q.dy < -0.01 ||
        q.dy > rect.height + 0.01) {
      return;
    }
    for (final e in out) {
      if ((e - q).distance < 0.5) return;
    }
    out.add(q);
  }

  if (dir.dx.abs() > 1e-9) {
    add((0 - p.dx) / dir.dx);
    add((rect.width - p.dx) / dir.dx);
  }
  if (dir.dy.abs() > 1e-9) {
    add((0 - p.dy) / dir.dy);
    add((rect.height - p.dy) / dir.dy);
  }
  return out;
}

/// 把矩形裁到半平面 `dot(q - mid, normal) >= 0`（Sutherland–Hodgman）。
List<Offset> _clipHalfPlane(Rect rect, Offset mid, Offset normal) {
  final input = <Offset>[
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ];
  final out = <Offset>[];
  double side(Offset p) =>
      (p.dx - mid.dx) * normal.dx + (p.dy - mid.dy) * normal.dy;

  for (var i = 0; i < input.length; i++) {
    final cur = input[i];
    final prev = input[(i - 1 + input.length) % input.length];
    final curIn = side(cur) >= 0;
    final prevIn = side(prev) >= 0;
    if (curIn != prevIn) {
      final sPrev = side(prev);
      final sCur = side(cur);
      final t = sPrev / (sPrev - sCur);
      out.add(Offset(
        prev.dx + (cur.dx - prev.dx) * t,
        prev.dy + (cur.dy - prev.dy) * t,
      ));
    }
    if (curIn) out.add(cur);
  }
  return out;
}

/// 关于过 [p]、方向 [dir] 的直线的镜像矩阵（列主序）。
Float64List _reflection(Offset p, Offset dir) {
  final len = dir.distance;
  final out = Float64List(16);
  if (len < 1e-9) {
    out[0] = 1;
    out[5] = 1;
    out[10] = 1;
    out[15] = 1;
    return out;
  }
  final ux = dir.dx / len;
  final uy = dir.dy / len;
  final m00 = 2 * ux * ux - 1;
  final m01 = 2 * ux * uy;
  final m11 = 2 * uy * uy - 1;
  out[0] = m00;
  out[1] = m01;
  out[4] = m01;
  out[5] = m11;
  out[10] = 1;
  out[12] = p.dx - (m00 * p.dx + m01 * p.dy);
  out[13] = p.dy - (m01 * p.dx + m11 * p.dy);
  out[15] = 1;
  return out;
}

Offset _apply(Float64List m, Offset p) => Offset(
      m[0] * p.dx + m[4] * p.dy + m[12],
      m[1] * p.dx + m[5] * p.dy + m[13],
    );

Float64List _identity() {
  final out = Float64List(16);
  out[0] = 1;
  out[5] = 1;
  out[10] = 1;
  out[15] = 1;
  return out;
}
