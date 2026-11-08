/// 标注导出：Markdown 纯函数（可单测）。
library;

import '../entities/annotation.dart';
import '../entities/book.dart';

/// 颜色语义 token 的中文名。
String annotationColorLabel(AnnotationColor color) => switch (color) {
      AnnotationColor.yellow => '黄',
      AnnotationColor.green => '绿',
      AnnotationColor.blue => '蓝',
      AnnotationColor.rose => '玫红',
    };

/// 把某本书的全部标注组织为 Markdown 文本。
///
/// 结构：书名做一级标题；每条标注 = 引用块原文 + 色标 + 笔记 + 日期。
/// [annotations] 按创建时间倒序（列表页顺序）。
String annotationsToMarkdown(Book book, List<Annotation> annotations) {
  final buf = StringBuffer('# ${book.title} 标注\n');
  final author = book.author;
  if (author != null && author.isNotEmpty) {
    buf.writeln('\n作者：$author');
  }
  buf.writeln('\n共 ${annotations.length} 条标注\n');
  for (final a in annotations) {
    final date = DateTime.fromMillisecondsSinceEpoch(a.createdAt);
    final dateText =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final quote = a.quotedText ?? '';
    if (quote.isNotEmpty) {
      buf.writeln('> $quote\n');
    }
    final tags = <String>[
      '${annotationColorLabel(a.color)}色划线',
      if (a.type == AnnotationType.note) '笔记',
    ];
    buf.writeln('【${tags.join(' · ')}】$dateText');
    final note = a.note;
    if (note != null && note.isNotEmpty) {
      buf.writeln('\n笔记：$note');
    }
    buf.writeln();
  }
  return buf.toString();
}
