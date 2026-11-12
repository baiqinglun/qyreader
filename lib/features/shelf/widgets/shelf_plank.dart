/// 书架的架板：网格每行书下面一条木板（无 / 木纹 / 纯色）。
///
/// 木纹是深胡桃渐变 + 几条确定性（不随机）的横向纹理 + 板沿高光 + 板沿投影。
/// 不随机是有意的：同一条板每帧长得一样，重建时不会「抖」，组件测试也稳定。
library;

import 'package:flutter/material.dart';

import '../shelf_prefs.dart';

/// 书架一格行下面的架板。
class ShelfPlank extends StatelessWidget {
  const ShelfPlank({
    required this.style,
    this.height = 12,
    super.key,
  });

  /// 架板样式；[ShelfPlankStyle.none] 时不占空间。
  final ShelfPlankStyle style;

  /// 板厚。
  final double height;

  @override
  Widget build(BuildContext context) {
    if (style == ShelfPlankStyle.none) return const SizedBox.shrink();

    const radius = BorderRadius.vertical(
      top: Radius.circular(2),
      bottom: Radius.circular(4),
    );
    final shadow = [
      // 板沿落在纸面上的投影
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.22),
        blurRadius: 8,
        offset: const Offset(0, 4),
      ),
    ];

    if (style == ShelfPlankStyle.solid) {
      return Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: radius,
          color: const Color(0xFF5C3A25),
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.16),
            ),
          ),
          boxShadow: shadow,
        ),
      );
    }

    // 木纹：顶部亮、底部暗，像一块打光的深胡桃木板。
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF7A5036),
            Color(0xFF5A3823),
            Color(0xFF3A2215),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: shadow,
      ),
      child: CustomPaint(painter: const _WoodGrainPainter()),
    );
  }
}

/// 横向木纹：几条轻微起伏的浅色细线 + 顶部板沿高光。
class _WoodGrainPainter extends CustomPainter {
  const _WoodGrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    const lines = 6;
    for (var i = 0; i < lines; i++) {
      final y = size.height * (i + 1) / (lines + 1);
      // 隔行深浅交替，看起来像木头本身的纹理，而不是均匀的扫描线。
      paint.color = const Color(0xFFE0B184)
          .withValues(alpha: i.isEven ? 0.22 : 0.12);
      final wave = size.height * 0.05 + 0.5;
      final path = Path()
        ..moveTo(0, y)
        ..cubicTo(
          size.width * 0.3,
          y - wave,
          size.width * 0.68,
          y + wave,
          size.width,
          y,
        );
      canvas.drawPath(path, paint);
    }

    // 板沿高光：受光的上边缘。
    final edge = Paint()
      ..color = const Color(0xFFE8C095).withValues(alpha: 0.5)
      ..strokeWidth = 1.2;
    canvas.drawLine(const Offset(0, 0.8), Offset(size.width, 0.8), edge);
  }

  @override
  bool shouldRepaint(covariant _WoodGrainPainter oldDelegate) => false;
}
