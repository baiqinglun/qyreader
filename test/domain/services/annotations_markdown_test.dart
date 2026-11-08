/// 标注导出 Markdown 单测。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:qy_reader/domain/entities/annotation.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/domain/services/annotations_markdown.dart';

void main() {
  test('空标注输出书名头与计数零', () {
    final book = _book();
    final md = annotationsToMarkdown(book, const []);
    expect(md, startsWith('# 测试之书 标注'));
    expect(md, contains('共 0 条标注'));
  });

  test('划线 + 笔记逐条渲染：引用块、色标、日期、笔记', () {
    final book = _book();
    final md = annotationsToMarkdown(book, [
      Annotation(
        id: 'a1',
        bookId: 'b1',
        type: AnnotationType.note,
        color: AnnotationColor.yellow,
        locatorStart: '{"v":1,"cfi":"epubcfi(/6/4)"}',
        locatorEnd: '{"v":1,"cfi":"epubcfi(/6/4)"}',
        quotedText: '山川湖海，日月星辰。',
        note: '开篇很有画面感',
        createdAt: DateTime(2026, 11, 8).millisecondsSinceEpoch,
        updatedAt: DateTime(2026, 11, 8).millisecondsSinceEpoch,
      ),
    ]);

    expect(md, contains('> 山川湖海，日月星辰。'));
    expect(md, contains('【黄色划线 · 笔记】2026-11-08'));
    expect(md, contains('笔记：开篇很有画面感'));
    expect(md, contains('作者：张三'));
  });
}

Book _book() => Book(
      id: 'b1',
      title: '测试之书',
      author: '张三',
      format: BookFormat.epub,
      filePath: '/tmp/x.epub',
      fileSha256: 'abc',
      fileSize: 1,
      addedAt: 0,
      updatedAt: 0,
      hlc: '0000000000000-00000-aaaaaaaa',
      deviceId: 'aaaaaaaa',
    );
