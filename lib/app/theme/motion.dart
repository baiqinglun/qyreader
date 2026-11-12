/// 全 App 唯一的动效 Token 定义与访问入口。
///
/// 规范：页面里禁止写裸 `Duration(milliseconds: 250)`，
/// 一律从 `context.motion.xxx` 取；系统开启「减弱动态效果」时
/// 自动降级为 90ms。
library;

import 'package:flutter/material.dart';

/// 慢—快—慢的贝塞尔曲线：`cubic-bezier(0.65, 0, 0.35, 1)`。
///
/// 弹窗和页面转场统一用它（用户口径「慢快慢」）：起手慢、中段快、落定慢。
/// 和 Material 默认的 easeOut（快起慢收）不同，别换回 `Curves.easeOutCubic`。
const Curve kSmoothCurve = Cubic(0.65, 0, 0.35, 1);

/// 弹窗（底部面板 / 对话框）统一动效：只改曲线，时长沿用 Material 默认。
const AnimationStyle kSmoothSheetAnimation = AnimationStyle(
  curve: kSmoothCurve,
);

/// 动效 token 集。
///
/// | Token      | 时长   | 用途                     |
/// |------------|--------|--------------------------|
/// | instant    | 90ms   | 按压反馈、状态切换        |
/// | quick      | 160ms  | 图标、chip、tooltip      |
/// | standard   | 240ms  | 面板、抽屉、页面元素      |
/// | emphasized | 360ms  | 页面转场、封面飞行        |
/// | slow       | 520ms  | 统计图表生长、翻书        |
class MotionTokens {
  const MotionTokens._(
    this.instant,
    this.quick,
    this.standard,
    this.emphasized,
    this.slow,
    this.enter,
    this.exit,
    this.overshoot,
  );

  /// 标准档位。
  static const MotionTokens normal = MotionTokens._(
    Duration(milliseconds: 90),
    Duration(milliseconds: 160),
    Duration(milliseconds: 240),
    Duration(milliseconds: 360),
    Duration(milliseconds: 520),
    Curves.easeOutCubic,
    Curves.easeInCubic,
    Cubic(0.34, 1.56, 0.64, 1), // easeOutBack，overshoot ≈ 1.06
  );

  /// 「减弱动态效果」档位：全部 90ms 淡入。
  static const MotionTokens reduced = MotionTokens._(
    Duration(milliseconds: 90),
    Duration(milliseconds: 90),
    Duration(milliseconds: 90),
    Duration(milliseconds: 90),
    Duration(milliseconds: 90),
    Curves.easeOut,
    Curves.easeOut,
    Curves.easeOut,
  );

  /// 按压反馈、状态切换。
  final Duration instant;

  /// 图标、chip、tooltip。
  final Duration quick;

  /// 面板、抽屉、页面元素。
  final Duration standard;

  /// 页面转场、封面飞行。
  final Duration emphasized;

  /// 统计图表生长、翻书。
  final Duration slow;

  /// 进场曲线。
  final Curve enter;

  /// 退场曲线。
  final Curve exit;

  /// 弹入曲线（easeOutBack，overshoot 1.06）。
  final Curve overshoot;
}

/// 动效访问扩展。
extension MotionX on BuildContext {
  /// 全局动效 token。
  ///
  /// 已按 `MediaQuery.disableAnimations` 折算：开启「减弱动态效果」
  /// 时返回 [MotionTokens.reduced]。
  MotionTokens get motion =>
      MediaQuery.disableAnimationsOf(this)
          ? MotionTokens.reduced
          : MotionTokens.normal;
}
