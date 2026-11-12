/// 折页翻页的几何：右缘被掀起，沿一条竖直折线向左折过去。
///
/// 坐标系：原点在本页左上角，单位逻辑像素。只有纯数据 + 一条折页路径，
/// 阴影/纸背由 [CurlTurnPainter] 画，单测直接对几何断言。
///
/// 折法（以从右往左翻、`fromLeft = false` 为例）：
/// - 折线在 `x = W - d`，`d = progress * W`；
/// - 折页 = 原页右侧 `[W-d, W]` 关于折线镜像，落在 `[W-2d, W-d]`；
/// - 未折到的部分（`x < W-d`）仍是旧页；新页从 `x = W-d` 起盖上来。
/// - 翻满时 `d = W`，折线贴到左边，折页移出屏幕，整页换成新页。
///
/// 为什么不做「右下角三角折」：三角折只掀开一个角，拖动大半屏时
/// 页面仍整块不动，靠松手硬切到下一页，观感像卡住。竖直折页会让
/// 折线随手指一路扫过整页，拖动进度和翻页面积一一对应。
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// 一次折页翻页的几何快照。
class CurlGeometry {
  const CurlGeometry._({
    required this.pageSize,
    required this.progress,
    required this.fromLeft,
    required this.fold,
    required this.foldX,
    required this.flapRect,
    required this.reflection,
    required this.flapOpacity,
  });

  /// 按页尺寸与进度构造。`progress` 0 = 没折，1 = 折满一页。
  factory CurlGeometry({
    required Size page,
    required double progress,
    bool fromLeft = false,
  }) {
    final w = math.max(page.width, 1.0);
    final h = math.max(page.height, 1.0);
    final p = progress.clamp(0.0, 1.0);
    final d = p * w;
    final foldX = fromLeft ? d : w - d;
    final flapRect = fromLeft
        ? Rect.fromLTRB(foldX, 0, foldX + d, h)
        : Rect.fromLTRB(foldX - d, 0, foldX, h);
    final reflection = _verticalReflection(foldX);

    return CurlGeometry._(
      pageSize: Size(w, h),
      progress: p,
      fromLeft: fromLeft,
      fold: d,
      foldX: foldX,
      flapRect: flapRect,
      reflection: reflection,
      // 折页一路扫出屏幕，不需要淡出；字段保留给绘制层统一处理。
      flapOpacity: 1,
    );
  }

  /// 页尺寸（逻辑像素）。
  final Size pageSize;

  /// 折叠进度 0..1。
  final double progress;

  /// 从左侧折起（true）还是右侧折起（false）。
  final bool fromLeft;

  /// 折线离页边的距离（也就是被掀起的那段宽度）。
  final double fold;

  /// 折线的 x 坐标。
  final double foldX;

  /// 折页（纸背）矩形；进度过半后会有一部分在屏幕外。
  final Rect flapRect;

  /// 关于折线（竖直）的 2D 镜像矩阵（列主序 4x4）。
  final Float64List reflection;

  /// 折页的整体透明度（目前恒为 1，保留给绘制层）。
  final double flapOpacity;

  /// 折页是否值得画（太小 / 已翻满都跳过）。
  bool get isActive => fold > 0.75 && fold < pageSize.width - 0.5;

  /// 整页矩形。
  Rect get pageRect => Offset.zero & pageSize;

  /// 折页路径（绘制用；整条折过去后的纸背矩形）。
  Path get flapPath => Path()..addRect(flapRect);

  /// 视觉上卷起来的纸边宽度：只画折线附近这一条，不把整块纸背铺满。
  ///
  /// 把整段 [flapRect] 都铺成纸背会把旧页遮掉 2×折线宽度，拖到一半
  /// 旧页就没了，手感忽快忽慢；纸边只保留窄窄一条，旧页随折线线性
  /// 减少，新页随折线线性增加，拖动距离和翻页面积一一对应。
  double get curlWidth => math.min(46.0, fold);

  /// 卷边矩形（折线附近那条纸背）。
  Rect get curlRect => fromLeft
      ? Rect.fromLTRB(foldX, 0, foldX + curlWidth, pageSize.height)
      : Rect.fromLTRB(foldX - curlWidth, 0, foldX, pageSize.height);

  /// 新页露出的区域：折线靠页边的那一侧。
  Rect get revealedRect => fromLeft
      ? Rect.fromLTRB(0, 0, foldX, pageSize.height)
      : Rect.fromLTRB(foldX, 0, pageSize.width, pageSize.height);

  /// 折线与页边的中点（阴影/高光的起点）。
  Offset get foldMid => Offset(foldX, pageSize.height / 2);

  /// 折线内侧（新页一侧）阴影的终点。
  Offset get shadowTo => Offset(
        foldX + (fromLeft ? -24 : 24),
        pageSize.height / 2,
      );

  /// 折页外缘（原页边折过去后的位置）。
  double get flapEdgeX => fromLeft ? flapRect.right : flapRect.left;
}

/// 关于竖直直线 `x = x0` 的镜像矩阵（Canvas.transform 用，列主序）：
/// x' = -x + 2*x0，y' = y。
Float64List _verticalReflection(double x0) {
  final out = Float64List(16);
  out[0] = -1;
  out[5] = 1;
  out[10] = 1;
  out[12] = 2 * x0;
  out[15] = 1;
  return out;
}
