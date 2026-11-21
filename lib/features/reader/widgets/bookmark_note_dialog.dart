/// 添加书签时填写备注（可留空）。
library;

import 'package:flutter/material.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/reading_theme.dart';

/// 打开「添加书签」弹窗。
///
/// 返回 `null` = 取消；返回空串 = 不加备注；否则返回 trim 后的备注。
Future<String?> showBookmarkNoteDialog(
  BuildContext context, {
  required ReadingTheme theme,
}) {
  return showDialog<String>(
    context: context,
    animationStyle: kSmoothSheetAnimation,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (_) => _BookmarkNoteDialog(theme: theme),
  );
}

class _BookmarkNoteDialog extends StatefulWidget {
  const _BookmarkNoteDialog({required this.theme});

  final ReadingTheme theme;

  @override
  State<_BookmarkNoteDialog> createState() => _BookmarkNoteDialogState();
}

class _BookmarkNoteDialogState extends State<_BookmarkNoteDialog> {
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final fg = theme.chromeForeground;
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
                    '添加书签',
                    style: TextStyle(
                      color: fg,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const ValueKey('bookmark-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 20, color: fg),
                    tooltip: '取消',
                  ),
                ],
              ),
              Text(
                '给这一页留条备注，也可以直接添加。',
                style: TextStyle(
                  color: fg.withValues(alpha: 0.55),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('bookmark-note-field'),
                controller: _note,
                autofocus: false,
                minLines: 2,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                style: TextStyle(color: fg, fontSize: 14),
                cursorColor: theme.accent,
                decoration: InputDecoration(
                  hintText: '备注（可选）',
                  hintStyle: TextStyle(
                    color: fg.withValues(alpha: 0.4),
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: fg.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('bookmark-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      '取消',
                      style: TextStyle(color: fg.withValues(alpha: 0.7)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    key: const ValueKey('bookmark-add'),
                    onPressed: () =>
                        Navigator.of(context).pop(_note.text.trim()),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.accent,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('添加'),
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
