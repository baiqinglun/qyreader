/// 骨架屏基础组件：内容加载中的占位微光块。
///
/// 规范要求「不要居中转圈，用同尺寸骨架 + 内容淡入」。
library;

import 'package:flutter/material.dart';

/// 单个骨架块（矩形，圆角可选）。
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    required this.width,
    required this.height,
    this.borderRadius = 8,
    super.key,
  });

  /// 骨架宽度。
  final double width;

  /// 骨架高度。
  final double height;

  /// 圆角半径。
  final double borderRadius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      ),
    );
  }
}
