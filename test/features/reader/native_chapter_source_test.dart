/// 标注 locator → 原生章：多章共用一份 XHTML 时按章索引定位。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/locator.dart';
import 'package:qy_reader/data/parsers/epub/epub_parser.dart';
import 'package:qy_reader/features/reader/native/native_chapter_source.dart';

NativeChapter _chapter(int idx, String href) => NativeChapter.fromBlocks(
      idx: idx,
      title: '第$idx章',
      href: href,
      blocks: [ParsedBlock(text: '正文$idx')],
      fallbackText: '',
    );

void main() {
  final chapters = [
    _chapter(0, 'a.xhtml'),
    _chapter(1, 'b.xhtml'),
    _chapter(2, 'b.xhtml'),
    _chapter(3, 'c.xhtml'),
  ];

  test('同一份 XHTML 拆出的多章：按章索引定位（v2.13.2 划线不显示回归）', () {
    final loc = Locator(href: 'b.xhtml', chapterIndex: 2, offset: 1);
    expect(nativeChapterForLocator(chapters, loc)?.idx, 2);
  });

  test('旧数据：索引是重切章节前的，退回 href 的第一章', () {
    final loc = Locator(href: 'b.xhtml', chapterIndex: 9, offset: 0);
    expect(nativeChapterForLocator(chapters, loc)?.idx, 1);
  });

  test('没有 href 时按章索引', () {
    final loc = Locator(chapterIndex: 3, offset: 0);
    expect(nativeChapterForLocator(chapters, loc)?.idx, 3);
  });

  test('href 和索引都对不上返回 null', () {
    expect(
      nativeChapterForLocator(
        chapters,
        const Locator(href: 'z.xhtml', chapterIndex: 7),
      ),
      isNull,
    );
  });
}
