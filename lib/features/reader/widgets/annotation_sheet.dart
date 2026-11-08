/// 划线操作面板：查看原文/笔记、换 4 色、编辑笔记、删除。
library;

import 'package:flutter/material.dart';

import '../../../app/theme/reading_theme.dart';
import '../../../domain/entities/annotation.dart';
import 'selection_menu.dart';

/// 划线操作面板（模态底部弹层）。
class AnnotationSheet extends StatelessWidget {
  const AnnotationSheet({
    required this.annotation,
    required this.theme,
    required this.onColor,
    required this.onDelete,
    required this.onEditNote,
    super.key,
  });

  final Annotation annotation;
  final ReadingTheme theme;
  final void Function(AnnotationColor color) onColor;
  final VoidCallback onDelete;
  final VoidCallback onEditNote;

  @override
  Widget build(BuildContext context) {
    final quote = annotation.quotedText ?? '';
    final note = annotation.note;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (quote.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (kAnnotationColors[annotation.color] ??
                          const Color(0xFFF7D774))
                      .withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  quote,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.chromeForeground, height: 1.5),
                ),
              ),
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '笔记：$note',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.chromeForeground.withValues(alpha: 0.8),
                ),
              ),
            ],
            const SizedBox(height: 14),
            // 换色
            Row(
              children: [
                Text('颜色', style: TextStyle(color: theme.chromeForeground)),
                const SizedBox(width: 12),
                for (final color in AnnotationColor.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        Navigator.of(context).pop();
                        onColor(color);
                      },
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: kAnnotationColors[color],
                          shape: BoxShape.circle,
                          border: annotation.color == color
                              ? Border.all(
                                  color: theme.accent,
                                  width: 2.5,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onEditNote();
                  },
                  icon: Icon(
                    Icons.edit_outlined,
                    color: theme.chromeForeground,
                    size: 20,
                  ),
                  label: Text(
                    annotation.note == null || annotation.note!.isEmpty
                        ? '添加笔记'
                        : '编辑笔记',
                    style: TextStyle(color: theme.chromeForeground),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onDelete();
                  },
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.chromeForeground.withValues(alpha: 0.8),
                    size: 20,
                  ),
                  label: Text(
                    '删除',
                    style: TextStyle(
                      color: theme.chromeForeground.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
