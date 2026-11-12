/// 章节分块（标题识别）与原生排版分页的单测。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/data/parsers/epub/epub_parser.dart';
import 'package:qy_reader/features/reader/native/native_chapter_source.dart';
import 'package:qy_reader/features/reader/native/native_paginator.dart';
import 'package:qy_reader/features/reader/reader_settings.dart';

const _xhtml = '''
<html><head><style>.x{}</style></head><body>
  <h1 class="chapter-title">第一章 开端</h1>
  <div class="wrap">
    <p>第一段正文。这里有足够多的字，用来测试段落识别与分页。</p>
    <p style="text-align: center">居中段落</p>
    <div><p>嵌套段落一。</p><p>嵌套段落二。</p></div>
    <h2>第一节</h2>
    <p>结尾段落。</p>
  </div>
</body></html>
''';

NativeChapter _chapter() => NativeChapter.fromBlocks(
      idx: 0,
      title: '第一章 开端',
      href: 'c1.xhtml',
      blocks: extractChapterBlocks(_xhtml),
      fallbackText: '',
    );

ReaderTypeSpec _spec({
  int indent = 2,
  double fontSize = 16,
  double lineHeight = 1.6,
}) =>
    ReaderTypeSpec.fromSettings(
      ReadingSettings(
        fontSize: fontSize,
        lineHeight: lineHeight,
        bodyIndent: ParagraphIndent.values.firstWhere((i) => i.chars == indent),
      ),
      ReadingTheme.paper,
    );

void main() {
  group('章节分块', () {
    test('h1/h2 识别为标题，p/div 识别为正文段落，嵌套 div 下钻', () {
      final blocks = extractChapterBlocks(_xhtml);
      expect(blocks.map((b) => b.level), [1, 0, 0, 0, 0, 2, 0]);
      expect(blocks.first.text, '第一章 开端');
      expect(blocks[1].text, startsWith('第一段正文'));
      expect(blocks[2].centered, isTrue);
      expect(blocks[3].text, '嵌套段落一。');
      expect(blocks[4].text, '嵌套段落二。');
      expect(blocks.last.text, '结尾段落。');
    });

    test('script/style 不进正文；没有块的页面退回整页一段', () {
      final blocks = extractChapterBlocks(
        '<html><body><script>var a=1</script><p>正文</p></body></html>',
      );
      expect(blocks.map((b) => b.text), ['正文']);

      final plain = extractChapterBlocks('<html><body>只有一句话</body></html>');
      expect(plain.single.text, '只有一句话');
      expect(plain.single.level, 0);
    });

    test('class 像标题的 p 也算标题（长度受限）', () {
      final blocks = extractChapterBlocks(
        '<body><p class="chapter-title">短标题</p>'
        '<p class="chapter-title">${'很长' * 40}</p></body>',
      );
      expect(blocks.first.level, 1);
      expect(blocks.last.level, 0);
    });
  });

  group('章结构', () {
    test('段落文本、起始偏移与章正文一致', () {
      final chapter = _chapter();
      expect(chapter.paragraphs.length, 7);
      expect(chapter.paragraphs.first.level, 1);
      var cursor = 0;
      for (final p in chapter.paragraphs) {
        expect(p.start, cursor);
        expect(chapter.text.substring(p.start, p.start + p.text.length), p.text);
        cursor += p.text.length + 1; // 段间 '\n'
      }
      expect(chapter.text.length, cursor - 1);
    });
  });

  group('排版与分页', () {
    test('正文段首有缩进、标题不缩进；显示↔章内坐标可往返', () {
      final chapter = _chapter();
      final spec = _spec(indent: 2);
      final layout = ChapterLayout.build(chapter: chapter, spec: spec);

      final heading = layout.paragraphs.first;
      expect(heading.isHeading, isTrue);
      expect(layout.displayText[heading.displayStart], '第');

      final body = layout.paragraphs[1];
      expect(
        layout.displayText.substring(body.displayStart - 2, body.displayStart),
        '\u00A0\u00A0',
      );

      // 章内偏移 → 显示 → 章内，正文位置必须一致（缩进不计入章内坐标）
      final chapterOffset = body.source.start + 3;
      final display = layout.displayOfChapter(chapterOffset);
      expect(layout.chapterOfDisplay(display), chapterOffset);
    });

    test('分页按版心高度切页，页首不会落在段距占位里', () {
      final chapter = _chapter();
      final spec = _spec();
      final layout = ChapterLayout.build(chapter: chapter, spec: spec);
      final paginator = NativePaginator();
      final pag = paginator.paginate(
        key: PaginationKey(
          chapterIdx: 0,
          width: 220,
          height: 90,
          textScale: 1,
          signature: spec.signature,
        ),
        layout: layout,
      );

      expect(pag.pageCount, greaterThan(1));
      for (var i = 0; i < pag.pageCount; i++) {
        final (start, end) = pag.rangeOf(i);
        expect(end, greaterThan(start));
        expect(layout.isSeparator(start), isFalse,
            reason: '第 $i 页页首不应是段距占位');
      }
      // 页首严格递增
      for (var i = 1; i < pag.starts.length; i++) {
        expect(pag.starts[i], greaterThan(pag.starts[i - 1]));
      }
    });

    test('段距越大，同样内容页数不减少', () {
      final chapter = _chapter();
      final tight = _spec();
      final loose = ReaderTypeSpec.fromSettings(
        ReadingSettings(fontSize: 16, lineHeight: 1.6, paragraphSpacing: 1.5),
        ReadingTheme.paper,
      );
      int pagesOf(ReaderTypeSpec spec) {
        final layout = ChapterLayout.build(chapter: chapter, spec: spec);
        return NativePaginator()
            .paginate(
              key: PaginationKey(
                chapterIdx: 0,
                width: 220,
                height: 120,
                textScale: 1,
                signature: spec.signature,
              ),
              layout: layout,
            )
            .pageCount;
      }

      expect(pagesOf(loose), greaterThanOrEqualTo(pagesOf(tight)));
    });

    test('页片段只保留本页段落样式，页尾不残留空行', () {
      final chapter = _chapter();
      final spec = _spec();
      final layout = ChapterLayout.build(chapter: chapter, spec: spec);
      final (start, end) = (0, layout.paragraphs[1].displayEnd);
      final fragment = buildPageFragment(layout, start, end);
      expect(fragment.text.endsWith('\n'), isFalse);
      expect(fragment.text, contains('第一章 开端'));
      expect(fragment.rangeStart, 0);
    });
  });

  group('排版设置序列化', () {
    test('正文/标题/页眉/页脚字段往返一致', () {
      const settings = ReadingSettings(
        paragraphSpacing: 0.8,
        letterSpacing: 1.5,
        bodyBold: true,
        bodyWeight: BodyFontWeight.semiBold,
        bodyAlign: TextAlignMode.center,
        bodyJustify: false,
        bodyIndent: ParagraphIndent.four,
        headingStyle: HeadingStyle.underlineShade,
        headingFontSize: 30,
        headingBold: false,
        headingAlign: TextAlignMode.right,
        headingMarginTop: 24,
        headingMarginBottom: 6,
        doublePage: true,
        headerLeft: RunningContent.time,
        headerCenter: RunningContent.chapterName,
        headerRight: RunningContent.battery,
        headerFontSize: 12,
        headerMarginTop: 8,
        headerMarginLeft: 20,
        headerMarginRight: 10,
        footerLeft: RunningContent.chapterPages,
        footerCenter: RunningContent.bookPercent,
        footerRight: RunningContent.bookPages,
        footerMarginLeft: 12,
        footerMarginRight: 14,
        footerMarginBottom: 10,
      );
      final restored = readingSettingsFromMap(settings.toMap());
      expect(restored.paragraphSpacing, 0.8);
      expect(restored.letterSpacing, 1.5);
      expect(restored.bodyBold, isTrue);
      expect(restored.bodyWeight, BodyFontWeight.semiBold);
      expect(restored.bodyAlign, TextAlignMode.center);
      expect(restored.bodyJustify, isFalse);
      expect(restored.bodyIndent, ParagraphIndent.four);
      expect(restored.headingStyle, HeadingStyle.underlineShade);
      expect(restored.headingFontSize, 30);
      expect(restored.headingBold, isFalse);
      expect(restored.headingAlign, TextAlignMode.right);
      expect(restored.headingMarginTop, 24);
      expect(restored.headingMarginBottom, 6);
      expect(restored.doublePage, isTrue);
      expect(restored.headerLeft, RunningContent.time);
      expect(restored.headerCenter, RunningContent.chapterName);
      expect(restored.headerRight, RunningContent.battery);
      expect(restored.headerFontSize, 12);
      expect(restored.headerMarginTop, 8);
      expect(restored.headerMarginLeft, 20);
      expect(restored.headerMarginRight, 10);
      expect(restored.footerLeft, RunningContent.chapterPages);
      expect(restored.footerCenter, RunningContent.bookPercent);
      expect(restored.footerRight, RunningContent.bookPages);
      expect(restored.footerMarginLeft, 12);
      expect(restored.footerMarginRight, 14);
      expect(restored.footerMarginBottom, 10);
    });

    test('非法枚举/越界数值回退默认并夹紧', () {
      final restored = readingSettingsFromMap(<String, dynamic>{
        'bodyWeight': 'feather',
        'bodyAlign': 'diagonal',
        'bodyIndent': 'wide',
        'headingStyle': 'sparkles',
        'headerLeft': 'weather',
        'paragraphSpacing': 99,
        'letterSpacing': -99,
        'headingFontSize': 999,
        'headerFontSize': 1,
        'footerMarginBottom': -5,
      });
      expect(restored.bodyWeight, BodyFontWeight.normal);
      expect(restored.bodyAlign, TextAlignMode.auto);
      expect(restored.bodyIndent, ParagraphIndent.auto);
      expect(restored.headingStyle, HeadingStyle.plain);
      expect(restored.headerLeft, RunningContent.none);
      expect(restored.paragraphSpacing, 2);
      expect(restored.letterSpacing, -1);
      expect(restored.headingFontSize, 40);
      expect(restored.headerFontSize, 8);
      expect(restored.footerMarginBottom, 0);
    });

    test('正文对齐折算：两端对齐只在默认/左对齐时生效', () {
      TextAlign alignOf(ReadingSettings s) =>
          ReaderTypeSpec.fromSettings(s, ReadingTheme.paper).bodyAlign;

      expect(alignOf(const ReadingSettings()), TextAlign.justify);
      expect(
        alignOf(const ReadingSettings(bodyJustify: false)),
        TextAlign.left,
      );
      expect(
        alignOf(const ReadingSettings(bodyAlign: TextAlignMode.center)),
        TextAlign.center,
      );
      expect(
        alignOf(const ReadingSettings(
          bodyAlign: TextAlignMode.right,
          bodyJustify: true,
        )),
        TextAlign.right,
      );
    });
  });
}
