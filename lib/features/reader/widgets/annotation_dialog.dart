/// 标注编辑弹窗（屏幕中间）：改颜色、写想法、删除。
library;

import 'package:flutter/material.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/reading_theme.dart';
import '../../../domain/entities/annotation.dart';
import 'selection_menu.dart';

/// 弹窗返回值：颜色 / 想法（可空串）/ 是否删除。
class AnnotationEditResult {
  const AnnotationEditResult({
    required this.color,
    required this.note,
    this.delete = false,
  });

  /// 保存后的颜色。
  final AnnotationColor color;

  /// 保存后的想法（空串表示清空）。
  final String note;

  /// true = 删除这条标注。
  final bool delete;
}

/// 打开居中的标注编辑弹窗；取消返回 null。
Future<AnnotationEditResult?> showAnnotationEditDialog(
  BuildContext context, {
  required Annotation annotation,
  required ReadingTheme theme,
}) {
  return showDialog<AnnotationEditResult>(
    context: context,
    animationStyle: kSmoothSheetAnimation,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (dialogContext) => AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: kSmoothCurve,
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(dialogContext).bottom,
      ),
      child: AnnotationEditDialog(annotation: annotation, theme: theme),
    ),
  );
}

/// 标注编辑弹窗内容。
class AnnotationEditDialog extends StatefulWidget {
  const AnnotationEditDialog({
    required this.annotation,
    required this.theme,
    super.key,
  });

  /// 正在编辑的标注。
  final Annotation annotation;

  /// 阅读纸面主题（弹窗跟随阅读页配色）。
  final ReadingTheme theme;

  @override
  State<AnnotationEditDialog> createState() => _AnnotationEditDialogState();
}

class _AnnotationEditDialogState extends State<AnnotationEditDialog> {
  late final TextEditingController _note;
  late AnnotationColor _color;

  @override
  void initState() {
    super.initState();
    _color = widget.annotation.color;
    _note = TextEditingController(text: widget.annotation.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      AnnotationEditResult(color: _color, note: _note.text.trim()),
    );
  }

  void _delete() {
    Navigator.of(context).pop(
      AnnotationEditResult(
        color: _color,
        note: _note.text.trim(),
        delete: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final fg = theme.chromeForeground;
    final quote = widget.annotation.quotedText ?? '';

    return Dialog(
      backgroundColor: theme.chromeSurface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '编辑标注',
                    style: TextStyle(
                      color: fg,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 20, color: fg),
                  ),
                ],
              ),
              if (quote.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (kAnnotationColors[_color] ??
                            const Color(0xFFF7D774))
                        .withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    quote,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, height: 1.5),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Text(
                '颜色',
                style: TextStyle(
                  color: fg.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final color in AnnotationColor.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Semantics(
                        selected: _color == color,
                        button: true,
                        label: '标注颜色 ${color.name}',
                        child: InkWell(
                          key: ValueKey('annotation-color-${color.name}'),
                          customBorder: const CircleBorder(),
                          onTap: () => setState(() => _color = color),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: kAnnotationColors[color],
                              shape: BoxShape.circle,
                              border: _color == color
                                  ? Border.all(color: theme.accent, width: 2.5)
                                  : null,
                            ),
                            child: _color == color
                                ? Icon(
                                    Icons.check,
                                    size: 16,
                                    color: fg.withValues(alpha: 0.7),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '想法',
                style: TextStyle(
                  color: fg.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('annotation-note-field'),
                controller: _note,
                minLines: 4,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: TextStyle(color: fg, height: 1.45),
                decoration: InputDecoration(
                  hintText: '写下你的想法…',
                  hintStyle: TextStyle(color: fg.withValues(alpha: 0.4)),
                  filled: true,
                  fillColor: fg.withValues(alpha: 0.04),
                  contentPadding: const EdgeInsets.all(12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: fg.withValues(alpha: 0.18)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.accent, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton.icon(
                    key: const ValueKey('annotation-delete'),
                    onPressed: _delete,
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 19,
                      color: Color(0xFFD05A4E),
                    ),
                    label: const Text(
                      '删除标注',
                      style: TextStyle(color: Color(0xFFD05A4E)),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      '取消',
                      style: TextStyle(color: fg.withValues(alpha: 0.65)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    key: const ValueKey('annotation-save'),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.accent,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _save,
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
