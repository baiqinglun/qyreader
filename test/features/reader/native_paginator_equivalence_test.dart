/// 原生分页快路径与旧实现（逐段整页测量）的逐页等价性。
///
/// 分页改成「逐段测高累加 + 每页整页复核」后，长章节改字号/行距不再
/// O(段数²) 卡住 UI；这里用旧算法当参考，确保页边界一个字符都不差。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/data/parsers/epub/epub_parser.dart';
import 'package:qy_reader/features/reader/native/native_chapter_source.dart';
import 'package:qy_reader/features/reader/native/native_paginator.dart';
import 'package:qy_reader/features/reader/reader_settings.dart';

NativeChapter _longChapter({int paragraphs = 150, int chars = 120}) =>
    NativeChapter.fromBlocks(
      idx: 0,
      title: '第一章 长章节',
      href: 'c1.xhtml',
      blocks: [
        const ParsedBlock(text: '第一章 长章节', level: 1),
        for (var i = 0; i < paragraphs; i++)
          ParsedBlock(
            text: '这是第 $i 段测试文本。'
                '${'春风又绿江南岸明月何时照我还。' * (chars ~/ 15)}',
          ),
      ],
      fallbackText: '',
    );

/// 诗集式章节：大量短段 + 小标题（用户实际遇到的排版形态）。
NativeChapter _poetryChapter() {
  final blocks = <ParsedBlock>[const ParsedBlock(text: '诗选', level: 1)];
  for (var i = 0; i < 160; i++) {
    blocks.add(ParsedBlock(text: i % 7 == 0 ? '我高兴我不相信天堂' : '短句 $i。'));
    if (i % 40 == 39) {
      blocks.add(ParsedBlock(text: '第 ${i ~/ 40 + 2} 辑', level: 2));
    }
  }
  return NativeChapter.fromBlocks(
    idx: 0,
    title: '诗选',
    href: 'c1.xhtml',
    blocks: blocks,
    fallbackText: '',
  );
}

/// 旧实现（每段都从页首整页重排）原样保留，作为页边界的参考真值。
Pagination _referencePagination(ChapterLayout layout, PaginationKey key) {
  final text = layout.displayText;
  if (text.isEmpty) {
    return const Pagination(starts: [0], textLength: 0);
  }
  final paragraphs = layout.paragraphs;
  final starts = <int>[0];
  var pageStart = 0;
  var i = 0;

  double measure(int end) =>
      layout.renderedHeight(pageStart, end, key.width, key.textScale);

  void nextPage(int offset) {
    if (offset > starts.last) starts.add(offset);
    pageStart = offset;
  }

  while (i < paragraphs.length) {
    final p = paragraphs[i];
    if (measure(p.displayEnd) <= key.height + 0.01) {
      i++;
      continue;
    }
    final fragStart = math.max(p.indentStart, pageStart);
    if (fragStart >= p.displayEnd) {
      i++;
      continue;
    }
    // 与生产路径同口径：片段从缩进起点起测，缩进字符用补宽样式
    // （漏掉缩进会让首行多塞一个字，行首与渲染断行错位）。
    final bodyStart = math.max(p.displayStart, fragStart);
    final painter = TextPainter(
      text: TextSpan(
        style: p.style,
        children: [
          if (fragStart < p.displayStart)
            TextSpan(
              text: text.substring(fragStart, p.displayStart),
              style: layout.spec.indentStyleFor(key.textScale),
            ),
          TextSpan(text: text.substring(bodyStart, p.displayEnd)),
        ],
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      textScaler: TextScaler.linear(key.textScale),
    )..layout(maxWidth: key.width);
    final metrics = painter.computeLineMetrics();
    if (metrics.isEmpty) {
      painter.dispose();
      i++;
      continue;
    }
    final lineStarts = <int>[];
    for (final m in metrics) {
      final top = m.baseline - m.ascent;
      lineStarts.add(
        fragStart + painter.getPositionForOffset(Offset(0, top + 0.5)).offset,
      );
    }
    painter.dispose();

    var lo = 1;
    var hi = metrics.length;
    var best = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final end = mid == metrics.length ? p.displayEnd : lineStarts[mid];
      if (measure(end) <= key.height + 0.01) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (best == 0) {
      if (fragStart > pageStart) {
        // 断点取本段的缩进起点（而非缩进后正文起点），下一页 run 才能带
        // 上首行缩进——与 NativePaginator.computeSafe 一致。
        final indentStart = paragraphs[i].indentStart;
        if (indentStart > pageStart) {
          nextPage(indentStart);
          continue;
        }
      }
      final end = metrics.length == 1 ? p.displayEnd : lineStarts[1];
      if (end <= pageStart) {
        i++;
        continue;
      }
      nextPage(end);
      if (end >= p.displayEnd) i++;
      continue;
    }
    if (best >= metrics.length) {
      i++;
      continue;
    }
    final end = lineStarts[best];
    if (end <= pageStart) {
      i++;
      continue;
    }
    nextPage(end);
  }
  return Pagination(starts: starts, textLength: text.length);
}

void main() {
  final chapters = <String, NativeChapter>{
    '长章节': _longChapter(),
    '诗集': _poetryChapter(),
  };
  final settings = <String, ReadingSettings>{
    '默认': const ReadingSettings(fontSize: 18, lineHeight: 1.7),
    '大字号': const ReadingSettings(fontSize: 26, lineHeight: 2.2),
    '大段距': const ReadingSettings(
      fontSize: 18,
      lineHeight: 1.6,
      paragraphSpacing: 1.5,
    ),
    '无缩进居中': const ReadingSettings(
      fontSize: 20,
      lineHeight: 1.8,
      bodyIndent: ParagraphIndent.none,
      bodyAlign: TextAlignMode.center,
      bodyJustify: false,
    ),
    '标题装饰': const ReadingSettings(
      fontSize: 18,
      lineHeight: 1.7,
      headingStyle: HeadingStyle.underlineShade,
      headingFontSize: 30,
      headingMarginTop: 28,
      headingMarginBottom: 20,
    ),
  };
  const sizes = <(double, double)>[
    (360, 700),
    (240, 140),
    (700, 500),
  ];

  test('快路径与旧实现的页边界逐页一致', () {
    for (final chapterEntry in chapters.entries) {
      for (final settingEntry in settings.entries) {
        final spec = ReaderTypeSpec.fromSettings(
          settingEntry.value,
          ReadingTheme.paper,
        );
        final layout = ChapterLayout.build(
          chapter: chapterEntry.value,
          spec: spec,
        );
        for (final (width, height) in sizes) {
          final key = PaginationKey(
            chapterIdx: 0,
            width: width,
            height: height,
            textScale: 1,
            signature: spec.metricsSignature,
          );
          final expected = _referencePagination(layout, key);

          // 1) 完整测量后走「纯算术装箱」快路径
          final paginator = NativePaginator();
          final measurement = paginator.measurementFor(
            layout: layout,
            chapterIdx: key.chapterIdx,
            width: key.width,
            textScale: key.textScale,
          );
          while (!measurement.complete) {
            measurement.measureNext(layout);
          }
          final packed = measurement.packAllExact(
            layout,
            maxHeight: key.height + 0.01,
            width: key.width,
            textScale: key.textScale,
          );
          expect(
            packed.starts,
            expected.starts,
            reason: '装箱 ${chapterEntry.key}/${settingEntry.key}/'
                '${width}x$height',
          );
          expect(packed.textLength, expected.textLength);
          expect(
            PaginationValidator.validate(
              pagination: packed,
              layout: layout,
              maxHeight: key.height + 0.01,
              width: key.width,
              textScale: key.textScale,
            ),
            isTrue,
            reason: '自检 ${chapterEntry.key}/${settingEntry.key}/'
                '${width}x$height',
          );

          // 2) 缓存命中后 paginate 也走快路径
          final actual = paginator.paginate(key: key, layout: layout);
          expect(
            actual.starts,
            expected.starts,
            reason: '${chapterEntry.key}/${settingEntry.key}/'
                '${width}x$height',
          );
          expect(actual.textLength, expected.textLength);
        }
      }
    }
  });

  test('纯颜色变化不进分页签名；字号/行距/字距会', () {
    const base = ReadingSettings(fontSize: 18, lineHeight: 1.7);
    final paper = ReaderTypeSpec.fromSettings(base, ReadingTheme.paper);
    final night = ReaderTypeSpec.fromSettings(base, ReadingTheme.night);
    expect(night.metricsSignature, paper.metricsSignature);
    expect(night.signature, isNot(paper.signature));

    int metrics(ReadingSettings s) => ReaderTypeSpec.fromSettings(
          s,
          ReadingTheme.paper,
        ).metricsSignature;
    expect(metrics(base.copyWith(fontSize: 19)), isNot(paper.metricsSignature));
    expect(
      metrics(base.copyWith(lineHeight: 1.8)),
      isNot(paper.metricsSignature),
    );
    expect(
      metrics(base.copyWith(letterSpacing: 0.5)),
      isNot(paper.metricsSignature),
    );
  });
}
