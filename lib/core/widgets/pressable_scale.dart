/// 通用按压反馈：scale 0.97（instant 90ms），不做触感/声音反馈。
///
/// 替代裸 InkWell 的规范组件，动效 token 从 [Motion] 取。
library;

import 'package:flutter/material.dart';

import '../../app/theme/motion.dart';

/// 按压缩放包装器。
class PressableScale extends StatefulWidget {
  const PressableScale({
    required this.child,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  /// 子组件。
  final Widget child;

  /// 单击回调；为 null 时禁用按压效果。
  final VoidCallback? onTap;

  /// 长按回调。
  final VoidCallback? onLongPress;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? 0.97 : 1.0;
    // 只做缩放反馈：点按/长按都不触发 HapticFeedback（用户要求去掉震动）。
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: scale),
        duration: context.motion.instant,
        curve: Curves.easeOutCubic,
        builder: (context, value, child) =>
            Transform.scale(scale: value, child: child),
        child: widget.child,
      ),
    );
  }
}
