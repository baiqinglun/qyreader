/// 统计页周期标题：左右翻期 + 居中的日期（点击选择日期）。
library;

import 'package:flutter/material.dart';

import '../../../domain/entities/reading_stats.dart';

/// 周期标题行。
///
/// 左侧和右侧预留同样宽度，标题始终在整行正中；点击标题回调 [onPickDate]。
class StatsPeriodHeader extends StatelessWidget {
  const StatsPeriodHeader({
    required this.period,
    required this.foreground,
    required this.accent,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onPickDate,
    super.key,
  });

  /// 当前周期。
  final PeriodReadingStats period;

  /// 文字颜色。
  final Color foreground;

  /// 强调色（「今天」按钮）。
  final Color accent;

  /// 上一周期。
  final VoidCallback onPrev;

  /// 下一周期（不能往后时为 null）。
  final VoidCallback? onNext;

  /// 回到今天（已经是今天时为 null）。
  final VoidCallback? onToday;

  /// 点击日期，打开日期选择。
  final VoidCallback onPickDate;

  static const List<String> _weekdays = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  String get _label {
    final s = period.start;
    String two(int v) => v.toString().padLeft(2, '0');
    switch (period.period) {
      case StatsPeriod.day:
        return '${s.year}-${two(s.month)}-${two(s.day)} '
            '${_weekdays[s.weekday - 1]}';
      case StatsPeriod.week:
        final end = period.end.subtract(const Duration(days: 1));
        return '${two(s.month)}/${two(s.day)} ~ ${two(end.month)}/${two(end.day)}';
      case StatsPeriod.month:
        return '${s.year} 年 ${s.month} 月';
      case StatsPeriod.year:
        return '${s.year} 年';
    }
  }

  @override
  Widget build(BuildContext context) {
    // 左右各留出与右侧控件等宽的空间，标题才是真正的居中。
    final side = onToday == null ? 48.0 : 96.0;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(
            width: side,
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: '上一周期',
                onPressed: onPrev,
                icon: Icon(Icons.chevron_left, color: foreground),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              key: const ValueKey('stats-period-label'),
              borderRadius: BorderRadius.circular(8),
              onTap: onPickDate,
              child: Tooltip(
                message: '选择日期',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _label,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: side,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: '下一周期',
                  onPressed: onNext,
                  icon: Icon(
                    Icons.chevron_right,
                    color: onNext == null
                        ? foreground.withValues(alpha: 0.25)
                        : foreground,
                  ),
                ),
                if (onToday != null)
                  SizedBox(
                    width: 48,
                    child: TextButton(
                      onPressed: onToday,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(48, 36),
                      ),
                      child: Text(
                        '今天',
                        style: TextStyle(color: accent, fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
