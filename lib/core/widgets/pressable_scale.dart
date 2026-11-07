/// 通用按压反馈：scale 0.97（instant 90ms）+ 可选触感。
///
/// 替代裸 InkWell 的规范组件，动效 token 从 [Motion] 取。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/motion.dart';

/// 按压缩放包装器。
class PressableScale extends StatefulWidget {
  const PressableScale({
    required this.child,
    required this.onTap,
    this.haptic = true,
    super.key,
  });

  /// 子组件。
  final Widget child;

  /// 单击回调；为 null 时禁用按压效果。
  final VoidCallback? onTap;

  /// 是否触发 lightImpact 触感（设置里的「触感反馈」总开关接入后在此读取）。
  final bool haptic;

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
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
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
