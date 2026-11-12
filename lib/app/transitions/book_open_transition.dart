/// 打开 / 关闭书籍的转场动画：书封从书架上的位置展开成整屏，退出时收回原位。
///
/// 挂在阅读器路由上（见 `app/router.dart` 的 `CustomTransitionPage`）：
/// - 进入：书封（封面图 / 书脊色块）从书架上那本书的位置放大到全屏，随后
///   溶解，正文显形——视觉上是「把书从书架上抽出来翻开」。
/// - 退出：完全反向——书封重新盖上来，阅读页缩回书架上的原位。
///
/// 实现要点：
/// - 阅读页裁在「书封矩形」里（[ClipRect]），矩形随动画长大/缩回；裁剪区
///   外露出下面的书架，所以书封升起时书架始终在背景里。为此阅读路由必须
///   `opaque: false`，否则下层书架在阅读页盖住后就不再绘制。
/// - 起始帧的书封与书架上那一本像素一致（同一张封面图 / 同一渐变），
///   所以「抽出来」的第一帧没有跳变。
/// - 收回位置不能记点击瞬间的坐标：打开一本书会更新最近打开时间、书架
///   随之重排，位置会变。改为通过 [BookCoverRegistry] 实时查询。
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// 书籍在书架上的呈现形态。
enum BookLaunchKind {
  /// 网格里的封面卡片。
  card,

  /// 顶部「最近在读」的书脊。
  spine,
}

/// 打开一本书时携带的信息（随路由 extra 传入）。
class BookLaunch {
  const BookLaunch({
    required this.bookId,
    required this.kind,
    this.rect,
    this.coverPath,
    this.radius = 12,
  });

  /// 书籍 id（用来在书架上找回这本书的位置）。
  final String bookId;

  /// 来源形态。
  final BookLaunchKind kind;

  /// 点击瞬间的位置（兜底：退出时该书已滚出屏幕 / 卡片被回收）。
  final Rect? rect;

  /// 封面图片路径（null = 用书架上登记的色块/渐变）。
  final String? coverPath;

  /// 起始圆角（卡片 12 / 书脊 2.5）。
  final double radius;
}

/// 书架上某个书籍元素的当前位置与外观。
class BookCoverSpot {
  const BookCoverSpot({required this.rect, this.gradient, this.solid});

  /// 该元素在屏幕上的矩形（全局坐标）。
  final Rect rect;

  /// 书脊的横向渐变（卡片为 null）。
  final Gradient? gradient;

  /// 无封面时的纯色（书脊为 null）。
  final Color? solid;
}

/// 书架书籍元素的位置登记处。
///
/// 书架上的每张卡片 / 每根书脊都挂了 [BookCoverRectProbe]，布局完成后把
/// 自己的屏幕矩形登记进来。转场动画据此找回「这本书现在在哪」。
class BookCoverRegistry {
  BookCoverRegistry._();

  static final Map<String, BookCoverSpot> _spots = <String, BookCoverSpot>{};

  static String _key(BookLaunchKind kind, String bookId) =>
      '${kind.name}:$bookId';

  /// 登记位置。
  static void report(
    BookLaunchKind kind,
    String bookId,
    Rect rect, {
    Gradient? gradient,
    Color? solid,
  }) {
    _spots[_key(kind, bookId)] =
        BookCoverSpot(rect: rect, gradient: gradient, solid: solid);
  }

  /// 查某本书的位置；没有登记（未进屏 / 已销毁）→ null。
  static BookCoverSpot? spotOf(BookLaunchKind kind, String bookId) =>
      _spots[_key(kind, bookId)];

  /// 注销（元素销毁时调用；下次进屏会重新登记）。
  static void remove(BookLaunchKind kind, String bookId) {
    _spots.remove(_key(kind, bookId));
  }
}

/// 书架元素的定位探针：布局完成后把自己在屏幕上的矩形登记进注册表。
class BookCoverRectProbe extends StatefulWidget {
  const BookCoverRectProbe({
    required this.kind,
    required this.bookId,
    required this.child,
    this.gradient,
    this.solid,
    super.key,
  });

  /// 元素形态。
  final BookLaunchKind kind;

  /// 书籍 id。
  final String bookId;

  /// 被测量的子组件（封面图 / 书脊）。
  final Widget child;

  /// 书脊的横向渐变（卡片为 null）。
  final Gradient? gradient;

  /// 无封面时的纯色。
  final Color? solid;

  @override
  State<BookCoverRectProbe> createState() => _BookCoverRectProbeState();
}

class _BookCoverRectProbeState extends State<BookCoverRectProbe> {
  @override
  Widget build(BuildContext context) {
    // 位置只有布局完才知道；每次布局后登记一次（书架元素数量有限）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    return widget.child;
  }

  void _report() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    BookCoverRegistry.report(
      widget.kind,
      widget.bookId,
      box.localToGlobal(Offset.zero) & box.size,
      gradient: widget.gradient,
      solid: widget.solid,
    );
  }

  @override
  void dispose() {
    BookCoverRegistry.remove(widget.kind, widget.bookId);
    super.dispose();
  }
}

/// 阅读器路由的转场：书封展开 / 合上。
class BookOpenTransition extends StatelessWidget {
  const BookOpenTransition({
    required this.animation,
    required this.child,
    this.launch,
    super.key,
  });

  /// 路由动画：进入时 0→1，退出时 1→0（同一套公式自然反向）。
  final Animation<double> animation;

  /// 阅读器页面。
  final Widget child;

  /// 来源信息；null = 无来源（深链 / 统计页进入），走朴素淡入淡出。
  final BookLaunch? launch;

  @override
  Widget build(BuildContext context) {
    final l = launch;
    if (l == null) {
      return FadeTransition(opacity: animation, child: child);
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final v = animation.value.clamp(0.0, 1.0);
        // 退出（反向动画）走另一套节奏：阅读页全程缓慢收缩、书封从透明
        // 慢慢浮现，最后严丝合缝落回书架那本书的位置（用户要求「缓慢退出、
        // 封面慢慢回来」）。打开仍是「前半程撑满、后半程溶解」。
        final closing = animation.status == AnimationStatus.reverse;
        final full = Offset.zero & MediaQuery.sizeOf(context);
        final spot = BookCoverRegistry.spotOf(l.kind, l.bookId);
        // 优先用书架上的实时位置（打开书会重排最近在读）；都拿不到
        // （深链进入 / 书已删除）才退回点击瞬间的位置，最后退回整屏。
        final origin = _clampToScreen(spot?.rect ?? l.rect ?? full, full);
        // 展开：前半程把书封撑满，后半程溶解出正文。
        final expand = closing
            ? Curves.easeInOutCubic.transform(v)
            : Curves.easeInOutCubic.transform((v / 0.5).clamp(0.0, 1.0));
        final rect = Rect.lerp(origin, full, expand)!;
        final radius = lerpDouble(l.radius, 0, expand)!;
        // 打开：书封撑满后一小段时间溶解掉（窗口太长会糊在正文上）。
        // 关闭：书封从第一帧起就按进度线性浮现，整段退出都看得见它在「回来」。
        final coverAlpha = closing
            ? (1 - v).clamp(0.0, 1.0)
            : 1 - _smooth(v, 0.50, 0.74);
        // 退出时书封先朝观众「抬」一下（放大 7% + 一层浮起来的投影），
        // 再缩回书架——不然只看到纸页往后缩，像书被塞回架子（用户要求
        // 「书籍要往前移」）。打开不动它。
        final liftBump = closing
            ? math.sin(
                math.pi * ((1 - v) * 1.6).clamp(0.0, 1.0),
              )
            : 0.0;
        final coverScale = 1 + 0.07 * liftBump;

        return Stack(
          fit: StackFit.expand,
          children: [
            // 阅读页裁在「书封矩形」里：矩形长大 = 页面从书架上打开；
            // 矩形外露出下面的书架。正文始终保持不透明——交叉淡入如果
            // 让正文也半透明，底层书架会透上来把文字洗成灰蒙蒙一片。
            ClipRect(clipper: _RectClipper(rect), child: child),
            if (coverAlpha > 0.01)
              Positioned.fromRect(
                rect: rect,
                child: IgnorePointer(
                  key: const ValueKey('book-open-cover'),
                  child: Opacity(
                    opacity: coverAlpha,
                    child: Transform.scale(
                      key: const ValueKey('book-open-cover-lift'),
                      scale: coverScale,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(radius)),
                          boxShadow: [
                            if (liftBump > 0.01)
                              BoxShadow(
                                color: Colors.black
                                    .withValues(alpha: 0.18 * liftBump),
                                blurRadius: 30 * liftBump,
                                offset: const Offset(0, 12),
                              ),
                          ],
                        ),
                        child: _BookCover(
                          launch: l,
                          spot: spot,
                          radius: radius,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// 位置兜底：书被滚出可视区时收回到屏幕外会很怪，夹回屏幕内。
  static Rect _clampToScreen(Rect rect, Rect screen) {
    final w = rect.width.clamp(24.0, screen.width);
    final h = rect.height.clamp(24.0, screen.height);
    final left = rect.left.clamp(screen.left, screen.right - w);
    final top = rect.top.clamp(screen.top, screen.bottom - h);
    return Rect.fromLTWH(left, top, w, h);
  }

  /// 归一化区间上的平滑插值（0..1）。
  static double _smooth(double p, double from, double to) {
    if (p <= from) return 0;
    if (p >= to) return 1;
    final x = (p - from) / (to - from);
    return x * x * (3 - 2 * x);
  }
}

/// 按矩形裁剪（转场专用）。
class _RectClipper extends CustomClipper<Rect> {
  const _RectClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(_RectClipper oldClipper) => oldClipper.rect != rect;
}

/// 书封本体：封面图或书脊色块。
class _BookCover extends StatelessWidget {
  const _BookCover({
    required this.launch,
    required this.spot,
    required this.radius,
  });

  final BookLaunch launch;

  /// 书架上登记的外观（可能为 null）。
  final BookCoverSpot? spot;

  /// 当前圆角。
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = launch.coverPath;
    if (path != null && path.isNotEmpty) {
      return ClipRRect(
        // 卡片封面只有上沿是圆角，下沿与卡片内的文字区相接
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          // 与书架卡片同一解码尺寸：起始帧与卡片像素一致，展开无缝
          cacheWidth: 360,
          errorBuilder: (context, error, stack) => _block(context),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      child: _block(context),
    );
  }

  Widget _block(BuildContext context) {
    final gradient = spot?.gradient;
    if (gradient != null) {
      return DecoratedBox(decoration: BoxDecoration(gradient: gradient));
    }
    return ColoredBox(
      color: spot?.solid ??
          Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}

/// 阅读器路由页：自定义转场 + 转场期间非 opaque。
///
/// 转场期间必须 `opaque: false`，下层的书架才会继续绘制，书封矩形之外
/// 才能透出书架；转场结束后必须回到 `opaque: true`，否则阅读时书架一直在
/// 底下重绘，翻页帧时间会白白变差。路由的 opaque 由 [BookOpenRoute.opaque]
/// 按动画状态动态给出（框架在动画状态变化时会同步 overlay entry）。
class BookOpenPage<T> extends Page<T> {
  const BookOpenPage({
    required this.child,
    this.launch,
    super.key,
    super.name,
    super.arguments,
  });

  /// 阅读器页面。
  final Widget child;

  /// 打开来源（书封展开 / 收回用）。
  final BookLaunch? launch;

  @override
  Route<T> createRoute(BuildContext context) => BookOpenRoute<T>(
        settings: this,
        child: child,
        launch: launch,
      );
}

/// [BookOpenPage] 对应的路由。
class BookOpenRoute<T> extends PageRoute<T> {
  BookOpenRoute({
    required this.child,
    required this.launch,
    required super.settings,
  });

  /// 阅读器页面。
  final Widget child;

  /// 打开来源。
  final BookLaunch? launch;

  /// 放慢节奏：420 → 660 之后用户仍反馈「太快」，这版放到 1.0s / 0.85s。
  /// 再长就会挡住阅读（点开一本书要等一秒以上就看得出拖沓），到这儿为止。
  static const Duration openDuration = Duration(milliseconds: 1000);

  /// 合上略快于打开：读者主动退出时更想快点回到书架。
  /// v2.14.3：用户要求「缓慢退出」，850ms → 1100ms；
  /// v2.14.5：又反馈「太慢，稍微快一点」，收到 900ms。
  /// 书封在整段退出里慢慢浮现并缩回书架原位（见 [BookOpenTransition]）。
  static const Duration closeDuration = Duration(milliseconds: 900);

  @override
  Duration get transitionDuration => openDuration;

  @override
  Duration get reverseTransitionDuration => closeDuration;

  /// 转场中透明（露出书架），完成后不透明（阅读时不再绘制下层）。
  @override
  bool get opaque => animation?.status == AnimationStatus.completed;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: child,
      );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      BookOpenTransition(
        animation: animation,
        launch: launch,
        child: child,
      );
}
