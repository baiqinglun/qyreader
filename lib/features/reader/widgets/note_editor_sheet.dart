/// 笔记编辑模态：返回输入文本；取消返回 null。
library;

import 'package:flutter/material.dart';

import '../../../app/theme/reading_theme.dart';

/// 弹出笔记编辑；[initial] 为既有内容（编辑态），返回 null 表示取消。
Future<String?> showNoteEditorSheet(
  BuildContext context, {
  required ReadingTheme theme,
  String? initial,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.chromeSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => _NoteEditor(theme: theme, initial: initial),
  );
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({required this.theme, this.initial});

  final ReadingTheme theme;
  final String? initial;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '笔记',
            style: TextStyle(
              color: theme.chromeForeground,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 5,
            minLines: 2,
            style: TextStyle(color: theme.chromeForeground),
            decoration: InputDecoration(
              hintText: '写下你的想法…',
              hintStyle: TextStyle(
                color: theme.chromeForeground.withValues(alpha: 0.4),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: theme.chromeForeground.withValues(alpha: 0.2),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: theme.accent),
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
                  style: TextStyle(
                    color: theme.chromeForeground.withValues(alpha: 0.7),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.accent),
                onPressed: () => Navigator.of(context).pop(_controller.text),
                child: const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
