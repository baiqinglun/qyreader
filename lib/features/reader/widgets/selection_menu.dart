/// 选区标注菜单：锚定选区矩形，4 色 + 笔记 + 复制。
library;

import 'package:flutter/material.dart';

import '../../../domain/entities/annotation.dart';
import '../../../app/theme/reading_theme.dart';
import '../reader_bridge_events.dart' show SelectionRect;

/// 划线语义色的 UI 色值。
const Map<AnnotationColor, Color> kAnnotationColors = {
  AnnotationColor.yellow: Color(0xFFF7D774),
  AnnotationColor.green: Color(0xFFA9D98B),
  AnnotationColor.blue: Color(0xFF9CC3F5),
  AnnotationColor.rose: Color(0xFFF2A9B8),
};

/// 选区标注菜单。
class SelectionMenu extends StatelessWidget {
  const SelectionMenu({
    required this.rect,
    required this.theme,
    required this.onColor,
    required this.onNote,
    required this.onCopy,
    super.key,
  });

  /// 选区视口矩形。
  final SelectionRect rect;

  final ReadingTheme theme;
  final void Function(AnnotationColor color) onColor;
  final VoidCallback onNote;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    const menuHeight = 52.0;
    const margin = 12.0;
    // 优先放选区上方，放不下放下方；水平方向钳制在屏内
    final placeAbove = rect.top > menuHeight + margin + 8;
    final top = placeAbove
        ? (rect.top - menuHeight - 8).clamp(0.0, size.height - menuHeight)
        : (rect.top + rect.height + 8).clamp(0.0, size.height - menuHeight);
    final left = rect.left.clamp(margin, size.width - margin - 280);

    return Positioned(
      left: left,
      top: top,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        color: theme.chromeSurface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final color in AnnotationColor.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => onColor(color),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: kAnnotationColors[color],
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              _MenuButton(theme: theme, label: '笔记', onTap: onNote),
              _MenuButton(theme: theme, label: '复制', onTap: onCopy),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.theme,
    required this.label,
    required this.onTap,
  });

  final ReadingTheme theme;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: Size.zero,
      ),
      onPressed: onTap,
      child: Text(label, style: TextStyle(color: theme.chromeForeground)),
    );
  }
}
