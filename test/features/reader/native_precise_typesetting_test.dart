/// 精排：开启后段落采用原书字号 / 行高 / 对齐 / 缩进 / 段距。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/data/parsers/epub/epub_block_style.dart';
import 'package:qy_reader/data/parsers/epub/epub_parser.dart';
import 'package:qy_reader/features/reader/native/native_chapter_source.dart';
import 'package:qy_reader/features/reader/native/native_paginator.dart';
import 'package:qy_reader/features/reader/reader_settings.dart';

NativeChapter _chapter() => NativeChapter.fromBlocks(
  idx: 0,
  title: '第一章',
  href: 'c1.xhtml',
  blocks: <ParsedBlock>[
    const ParsedBlock(
      text: '原书大字段落。',
      style: EpubBlockStyle(
        fontSize: 22,
        lineHeight: 1.9,
        textAlign: EpubTextAlign.center,
        indentPx: 44,
        marginBottom: 12,
        bold: true,
      ),
    ),
    const ParsedBlock(
      text: '第二段无缩进。',
      style: EpubBlockStyle(
        fontSize: 14,
        textAlign: EpubTextAlign.left,
        indentPx: 0,
        marginTop: 6,
      ),
    ),
  ],
  fallbackText: '',
);

ReaderTypeSpec _spec({required bool precise}) => ReaderTypeSpec.fromSettings(
  ReadingSettings(
    fontSize: 18,
    lineHeight: 1.5,
    bodyIndent: ParagraphIndent.two,
    paragraphSpacing: 0.5,
    preciseTypesetting: precise,
  ),
  ReadingTheme.paper,
);

void main() {
  test('精排关闭：使用阅读设置的字号 / 对齐 / 缩进 / 段距', () {
    final layout = ChapterLayout.build(chapter: _chapter(), spec: _spec(precise: false));

    final first = layout.paragraphs.first;
    expect(first.style.fontSize, 18);
    expect(first.style.height, 1.5);
    expect(first.align, TextAlign.justify);
    expect(layout.displayText.startsWith('\uFEFF\u00A0\u00A0'), isTrue);
    expect(layout.paragraphGapBetween(layout.paragraphs[0], layout.paragraphs[1]),
        greaterThan(8));
  });

  test('精排开启：字号 / 行高 / 粗细 / 对齐 / 缩进 / 段距取原书', () {
    final layout = ChapterLayout.build(chapter: _chapter(), spec: _spec(precise: true));

    final first = layout.paragraphs[0];
    expect(first.style.fontSize, 22);
    expect(first.style.height, 1.9);
    expect(first.style.fontWeight, FontWeight.w700);
    expect(first.align, TextAlign.center);
    // 44px / 22px = 2 字缩进。
    expect(layout.displayText.startsWith('\uFEFF\u00A0\u00A0'), isTrue);

    final second = layout.paragraphs[1];
    expect(second.style.fontSize, 14);
    expect(second.align, TextAlign.left);
    // 第二段 indent: 0 → 无缩进字符。
    expect(
      layout.displayText.substring(
        second.indentStart,
        second.displayStart,
      ),
      isEmpty,
    );
    // 段距 = max(第二段 marginTop 6, 第一段 marginBottom 12)。
    expect(
      layout.paragraphGapBetween(first, second),
      closeTo(12, 0.8),
    );
  });

  test('渲染片段带上原书字号与粗细', () {
    final layout = ChapterLayout.build(
      chapter: _chapter(),
      spec: _spec(precise: true),
    );
    final fragment = buildPageFragment(
      layout,
      0,
      layout.displayText.length,
    );
    final spans = fragment.span.children!.whereType<TextSpan>();
    expect(
      spans.any(
        (s) => s.style?.fontSize == 22 && s.style?.fontWeight == FontWeight.w700,
      ),
      isTrue,
    );
    expect(spans.any((s) => s.text == '原书大字段落。'), isTrue);
  });

  test('精排签名与关闭时不同，切换会重新排版', () {
    expect(_spec(precise: true).metricsSignature,
        isNot(_spec(precise: false).metricsSignature));
  });
}
