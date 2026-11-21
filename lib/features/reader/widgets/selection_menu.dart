/// 选区标注菜单：复制 / 划线 / 高亮 / 笔记 /（定位未定位笔记）/ 从此听 / 跨页。
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
    required this.onCopy,
    required this.onUnderline,
    required this.onHighlight,
    required this.onNote,
    required this.onListen,
    this.onLocateNote,
    super.key,
  });

  /// 选区视口矩形。
  final SelectionRect rect;

  /// 阅读主题（面板跟随纸面配色）。
  final ReadingTheme theme;

  /// 复制选区。
  final VoidCallback onCopy;

  /// 划线（下划线）。
  final VoidCallback onUnderline;

  /// 高亮。
  final VoidCallback onHighlight;

  /// 写笔记。
  final VoidCallback onNote;

  /// 从此处开始朗读。
  final VoidCallback onListen;

  /// 把当前选区设成某条未定位笔记的位置（有未定位笔记时才显示）。
  final VoidCallback? onLocateNote;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    const menuHeight = 78.0;
    const margin = 10.0;
    // 有「定位」时多一格，整体略加宽；窄屏夹到左右各留 10。
    final menuWidth = (onLocateNote == null ? 270.0 : 310.0)
        .clamp(0.0, size.width - margin * 2)
        .toDouble();
    // 优先放选区上方，放不下放下方；水平方向钳制在屏内。
    final placeAbove = rect.top > menuHeight + margin + 8;
    final top = placeAbove
        ? (rect.top - menuHeight - 10).clamp(0.0, size.height - menuHeight)
        : (rect.top + rect.height + 10).clamp(0.0, size.height - menuHeight);
    final left = rect.left.clamp(
      margin,
      (size.width - margin - menuWidth).clamp(margin, double.infinity),
    );

    final fg = theme.chromeForeground;
    return Positioned(
      left: left,
      top: top,
      child: Material(
        key: const ValueKey('selection-menu'),
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        color: theme.chromeSurface,
        child: Container(
          width: menuWidth,
          height: menuHeight,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: fg.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              _MenuAction(
                icon: Icons.copy_rounded,
                label: '复制',
                color: fg,
                onTap: onCopy,
              ),
              _MenuAction(
                icon: Icons.format_underlined,
                label: '划线',
                color: fg,
                onTap: onUnderline,
              ),
              _MenuAction(
                icon: Icons.border_color_outlined,
                label: '高亮',
                color: fg,
                onTap: onHighlight,
              ),
              _MenuAction(
                icon: Icons.edit_note_rounded,
                label: '笔记',
                color: fg,
                onTap: onNote,
              ),
              if (onLocateNote != null)
                _MenuAction(
                  icon: Icons.bookmark_added_outlined,
                  label: '定位',
                  color: fg,
                  onTap: onLocateNote!,
                ),
              _MenuAction(
                icon: Icons.headphones_rounded,
                label: '从此听',
                color: fg,
                onTap: onListen,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuAction extends StatelessWidget {
  const _MenuAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 11, height: 1.1),
            ),
          ],
        ),
      ),
    );
  }
}
