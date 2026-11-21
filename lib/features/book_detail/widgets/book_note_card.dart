/// 书籍信息「笔记」页签里的单条划线 / 高亮 / 笔记卡片。
library;

import 'package:flutter/material.dart';

import '../../../domain/entities/annotation.dart';

/// 笔记卡片：整卡可点跳转，右上角单独分享。
class BookNoteCard extends StatelessWidget {
  /// 构造。
  const BookNoteCard({
    super.key,
    required this.item,
    required this.foreground,
    required this.muted,
    required this.onTap,
    required this.onShare,
  });

  /// 标注数据。
  final Annotation item;

  /// 正文前景色。
  final Color foreground;

  /// 次要文字颜色。
  final Color muted;

  /// 点卡片：跳到阅读器里的标注位置。
  final VoidCallback onTap;

  /// 点分享：打开卡片式分享面板。
  final VoidCallback onShare;

  static String typeLabel(AnnotationType type) => switch (type) {
    AnnotationType.highlight => '划线',
    AnnotationType.underline => '下划线',
    AnnotationType.note => '笔记',
  };

  static Color colorOf(AnnotationColor color) => switch (color) {
    AnnotationColor.yellow => const Color(0xFFE0A030),
    AnnotationColor.green => const Color(0xFF4CAF7D),
    AnnotationColor.blue => const Color(0xFF5B9BD5),
    AnnotationColor.rose => const Color(0xFFE57399),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quote = item.quotedText?.trim() ?? '';
    final note = item.note?.trim() ?? '';
    final date = DateTime.fromMillisecondsSinceEpoch(item.createdAt);
    final dateText =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return Material(
      key: ValueKey('book-note-${item.id}'),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorOf(item.color),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    typeLabel(item.type),
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                  const Spacer(),
                  IconButton(
                    key: ValueKey('book-note-share-${item.id}'),
                    tooltip: '分享卡片',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.ios_share, size: 17, color: muted),
                    onPressed: onShare,
                  ),
                  const SizedBox(width: 4),
                  Text(dateText, style: TextStyle(color: muted, fontSize: 11)),
                ],
              ),
              if (quote.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  quote,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.85),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
              if (note.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  note,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
