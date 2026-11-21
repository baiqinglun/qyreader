/// 标注编辑弹窗：改颜色、复制、擦除、添加笔记。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.copy = false,
  });

  /// 保存后的颜色。
  final AnnotationColor color;

  /// 保存后的想法（空串表示清空）。
  final String note;

  /// true = 删除这条标注。
  final bool delete;

  /// true = 点击了复制（原文已写入剪贴板，无需再落库）。
  final bool copy;
}

/// 打开标注编辑弹窗；取消返回 null。
Future<AnnotationEditResult?> showAnnotationEditDialog(
  BuildContext context, {
  required Annotation annotation,
  required ReadingTheme theme,
  bool focusNote = false,
}) {
  return showDialog<AnnotationEditResult>(
    context: context,
    animationStyle: kSmoothSheetAnimation,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    // 不要在外层再叠 AnimatedPadding(viewInsets)：Dialog 自己会把
    // MediaQuery.viewInsets 加进 insetPadding，外层再叠一次会让可用高度
    // 被键盘扣两遍，键盘升起后弹窗只剩标题+原文一条缝。
    builder: (dialogContext) => AnnotationEditDialog(
      annotation: annotation,
      theme: theme,
      focusNote: focusNote,
    ),
  );
}

/// 标注编辑弹窗内容。
class AnnotationEditDialog extends StatefulWidget {
  const AnnotationEditDialog({
    required this.annotation,
    required this.theme,
    this.focusNote = false,
    super.key,
  });

  /// 正在编辑的标注。
  final Annotation annotation;

  /// 阅读纸面主题（弹窗跟随阅读页配色）。
  final ReadingTheme theme;

  /// 打开后直接聚焦笔记输入框（「笔记」入口用）。
  final bool focusNote;

  @override
  State<AnnotationEditDialog> createState() => _AnnotationEditDialogState();
}

class _AnnotationEditDialogState extends State<AnnotationEditDialog> {
  late final TextEditingController _note;
  final FocusNode _noteFocus = FocusNode();
  late AnnotationColor _color;

  @override
  void initState() {
    super.initState();
    _color = widget.annotation.color;
    _note = TextEditingController(text: widget.annotation.note ?? '');
    if (widget.focusNote) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _noteFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _note.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(
      context,
    ).pop(AnnotationEditResult(color: _color, note: _note.text.trim()));
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

  void _copy() {
    final quote = widget.annotation.quotedText ?? '';
    if (quote.isEmpty) return;
    // 先关闭弹窗再写剪贴板：平台通道在部分测试/桌面环境可能较慢，
    // 不应让用户等它返回才看到面板收起。
    Navigator.of(context).pop(
      AnnotationEditResult(color: _color, note: _note.text.trim(), copy: true),
    );
    unawaited(Clipboard.setData(ClipboardData(text: quote)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final fg = theme.chromeForeground;
    final quote = widget.annotation.quotedText ?? '';
    final hint = fg.withValues(alpha: 0.45);

    return Dialog(
      backgroundColor: theme.chromeSurface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
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
                    color:
                        (kAnnotationColors[_color] ?? const Color(0xFFF7D774))
                            .withValues(alpha: 0.22),
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
                            width: 34,
                            height: 34,
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
                                    size: 17,
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
              Row(
                children: [
                  _EditAction(
                    key: const ValueKey('annotation-copy'),
                    icon: Icons.copy_rounded,
                    label: '复制',
                    color: fg,
                    onTap: _copy,
                  ),
                  const SizedBox(width: 8),
                  _EditAction(
                    key: const ValueKey('annotation-delete'),
                    icon: Icons.auto_fix_normal,
                    label: '擦除',
                    color: const Color(0xFFD05A4E),
                    onTap: _delete,
                  ),
                  const SizedBox(width: 8),
                  _EditAction(
                    key: const ValueKey('annotation-add-note'),
                    icon: Icons.edit_note_rounded,
                    label: '添加笔记',
                    color: fg,
                    onTap: () => _noteFocus.requestFocus(),
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
                focusNode: _noteFocus,
                minLines: 4,
                maxLines: 8,
                autofocus: widget.focusNote,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: TextStyle(color: fg, height: 1.45),
                decoration: InputDecoration(
                  hintText: '写点笔记吧~',
                  hintStyle: TextStyle(color: hint),
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
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
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

class _EditAction extends StatelessWidget {
  const _EditAction({
    super.key,
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
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(color: color, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
