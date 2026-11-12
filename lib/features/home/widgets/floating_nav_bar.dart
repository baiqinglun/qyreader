/// 悬浮胶囊底栏：白底大圆角 + 柔和投影，选中项套一个浅灰胶囊。
///
/// 参考用户给的账单类 App：底栏不贴边、不画分隔线，选中态是「胶囊套图标 +
/// 文字」，颜色跟随主题 primary。
library;

import 'package:flutter/material.dart';

import '../../../app/theme/motion.dart';

/// 底栏的三个 Tab。
const List<({IconData icon, IconData selected, String label})> kHomeTabs = [
  (icon: Icons.menu_book_outlined, selected: Icons.menu_book, label: '书架'),
  (icon: Icons.insights_outlined, selected: Icons.insights, label: '统计'),
  (icon: Icons.settings_outlined, selected: Icons.settings, label: '设置'),
];

/// 悬浮胶囊底栏。
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    required this.index,
    required this.onSelect,
    super.key,
  });

  /// 当前 Tab 下标。
  final int index;

  /// 切换 Tab。
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        key: const ValueKey('nav-bar'),
        height: 66,
        decoration: BoxDecoration(
          color: dark ? scheme.surfaceContainerHigh : Colors.white,
          borderRadius: BorderRadius.circular(33),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.30 : 0.07),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth / kHomeTabs.length;
            // 胶囊在轨道内滑动：左右各留 10px，高度 52（条高 66，上下各 7）。
            const pillInset = 10.0;
            return Stack(
              children: [
                AnimatedPositioned(
                  key: const ValueKey('nav-pill'),
                  duration: context.motion.standard,
                  curve: kSmoothCurve,
                  left: pillInset + itemWidth * index,
                  top: 7,
                  width: itemWidth - pillInset * 2,
                  height: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.75,
                      ),
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < kHomeTabs.length; i++)
                      Expanded(
                        child: _NavItem(
                          item: kHomeTabs[i],
                          selected: i == index,
                          onTap: () => onSelect(i),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 底栏单项：图标在上、文字在下；选中态由底层的滑动胶囊负责。
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ({IconData icon, IconData selected, String label}) item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? item.selected : item.icon,
                size: 22,
                color: color,
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: context.motion.quick,
                curve: kSmoothCurve,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
                child: Text(item.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
