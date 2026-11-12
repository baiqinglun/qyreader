/// 首行缩进的单测：页首段落不丢缩进、缩进步进补宽到一个汉字。
///
/// 背景：断页点若落在段落「缩进之后」，页首 run 就带不上缩进字符
/// （页首段落全部顶格）；缩进字符（NBSP）的实际宽度又由字体字形决定，
/// 不少（导入的）字体把它做窄——缩进看起来只有半个字。两个问题一起
/// 在这里回归。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/data/parsers/epub/epub_parser.dart';
import 'package:qy_reader/features/reader/native/native_chapter_source.dart';
import 'package:qy_reader/features/reader/native/native_paginator.dart';
import 'package:qy_reader/features/reader/reader_settings.dart';

NativeChapter _chapter() => NativeChapter.fromBlocks(
      idx: 0,
      title: '第一章',
      href: 'c1.xhtml',
      blocks: [
        for (var i = 0; i < 10; i++)
          ParsedBlock(
            text: '第$i段。在秋日午后的光线里，我数着归途上的每一片叶子，'
                '它们从枝头落下，像一封封没有寄出的信，落在无人经过的小径上。',
          ),
      ],
      fallbackText: '',
    );

ReaderTypeSpec _spec() => ReaderTypeSpec.fromSettings(
      const ReadingSettings(fontSize: 22, lineHeight: 1.7),
      ReadingTheme.paper,
    );

Pagination _paginate(ChapterLayout layout, ReaderTypeSpec spec) =>
    _paginateWith(layout, spec, width: 360, height: 500);

Pagination _paginateWith(
  ChapterLayout layout,
  ReaderTypeSpec spec, {
  required double width,
  required double height,
}) =>
    NativePaginator().paginate(
      key: PaginationKey(
        chapterIdx: 0,
        width: width,
        height: height,
        textScale: 1,
        signature: spec.metricsSignature,
      ),
      layout: layout,
    );

void main() {
  group('页首段落缩进', () {
    test('断页点在上一段文本结束处，页首 run 带缩进字符', () {
      final spec = _spec();
      final layout = ChapterLayout.build(chapter: _chapter(), spec: spec);
      final pag = _paginate(layout, spec);

      expect(pag.pageCount, greaterThan(1));
      for (var page = 1; page < pag.pageCount; page++) {
        final start = pag.starts[page];
        // 页首不得落在某段的缩进之后、正文之前（那里开始必丢缩进）。
        for (final p in layout.paragraphs) {
          if (p.indentStart < p.displayStart) {
            expect(start, isNot(p.displayStart),
                reason: '页 $page 起点落在第${p.source.start}段的缩进之后');
          }
        }
        // 页首 run 的首个样式段应包含缩进字符（用渲染同一套 segmentsOf）。
        final segments = layout.segmentsOf(start, pag.rangeOf(page).$2);
        expect(segments, isNotEmpty);
        final firstText =
            layout.displayText.substring(segments.first.$1, segments.first.$2);
        if (firstText.startsWith('\uFEFF')) {
          // 零宽锚必须用字距 0 的锚样式（行首 span 带字距会整行右移）。
          expect(segments.first.$3, spec.indentPrefixStyle,
              reason: '页 $page 页首缩进锚必须用零字距样式');
          if (segments.length > 1) {
            final secondText = layout.displayText
                .substring(segments[1].$1, segments[1].$2);
            if (secondText.startsWith('\u00A0')) {
              expect(segments[1].$3, spec.indentStyle,
                  reason: '页 $page 页首缩进必须用补宽样式');
            }
          }
        } else if (firstText.startsWith('\u00A0\u00A0')) {
          expect(segments.first.$3, spec.indentStyle,
              reason: '页 $page 页首缩进必须用补宽样式');
        }
      }
    });

    test('自检通过：页高不溢出、页间连续', () {
      final spec = _spec();
      final layout = ChapterLayout.build(chapter: _chapter(), spec: spec);
      final pag = _paginate(layout, spec);
      expect(
        PaginationValidator.validate(
          pagination: pag,
          layout: layout,
          maxHeight: 500,
          width: 360,
          textScale: 1,
        ),
        isTrue,
      );
    });
  });

  group('缩进补宽', () {
    test('indentStyle 的步进 = 一个汉字（fontSize）', () {
      const fontSize = 22.0;
      final spec = ReaderTypeSpec.fromSettings(
        const ReadingSettings(fontSize: fontSize, lineHeight: 1.7),
        ReadingTheme.paper,
      );

      double widthOf(String text) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: spec.bodyStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final w = painter.width;
        painter.dispose();
        return w;
      }

      final advance = widthOf('\u00A0\u00A0国') - widthOf('\u00A0国');
      final letterSpacing = spec.indentStyle.letterSpacing;
      expect(letterSpacing, closeTo(fontSize - advance, 0.01));
      // 补宽后的单字符步进 = 字号（一个汉字宽），与字体字形无关。
      expect(advance + letterSpacing!, closeTo(fontSize, 0.01));
    });

    test('缩进字符在渲染分段里用 indentStyle，正文不受影响', () {
      final spec = _spec();
      final layout = ChapterLayout.build(chapter: _chapter(), spec: spec);
      final p = layout.paragraphs.firstWhere((p) => p.indentStart < p.displayStart);
      final segments = layout.segmentsOf(p.indentStart, p.displayEnd);
      // 缩进区 = 零宽锚（字距0）+ 补宽 NBSP，两段；
      expect(segments.first.$1, p.indentStart);
      expect(segments.first.$3, spec.indentPrefixStyle);
      expect(
        layout.displayText.substring(segments.first.$1, segments.first.$2),
        '\uFEFF',
      );
      expect(segments[1].$3, spec.indentStyle);
      expect(
        layout.displayText.substring(segments[1].$1, segments[1].$2),
        '\u00A0\u00A0',
      );
      // 正文段用段落自己的样式
      expect(segments.last.$3, same(p.style));
    });

    test('页首段落（run 从缩进起点开始）首段样式是 indentStyle', () {
      // 复现线上问题：cut == pos（缩进段恰好从分段开头开始）时补宽样式
      // 被漏掉，页首段落缩进只剩字体的原始 U+3000 宽度。
      final spec = _spec();
      final layout = ChapterLayout.build(chapter: _chapter(), spec: spec);
      final p = layout.paragraphs
          .firstWhere((p) => p.indentStart < p.displayStart);
      final segments = layout.segmentsOf(p.indentStart, p.displayEnd);
      expect(segments.first.$1, p.indentStart);
      expect(segments.first.$3, spec.indentPrefixStyle,
          reason: '缩进区以零宽锚开头，锚必须用零字距样式');
      expect(
        layout.displayText.substring(segments.first.$1, segments.first.$2),
        '\uFEFF',
      );
      expect(segments[1].$1, p.indentStart + 1);
      expect(segments[1].$3, spec.indentStyle,
          reason: '缩进段恰好从分段开头开始时也必须用补宽样式');
      expect(
        layout.displayText.substring(segments[1].$1, segments[1].$2),
        '\u00A0\u00A0',
      );
    });

    test('标题后的第一段（对齐变化起新 run）缩进用补宽样式', () {
      final spec = _spec();
      final blocks = <ParsedBlock>[
        const ParsedBlock(text: '推荐序', level: 1),
        ParsedBlock(text: '这是一本深入浅出的好书，' * 3),
      ];
      final chapter = NativeChapter.fromBlocks(
        idx: 0, title: '推荐序', href: 'c1.xhtml',
        blocks: blocks, fallbackText: '',
      );
      final layout = ChapterLayout.build(chapter: chapter, spec: spec);
      final body = layout.paragraphs.last;
      final segments = layout.segmentsOf(
        layout.paragraphs.first.displayEnd, body.displayEnd,
      );
      final anchorSegment = segments.firstWhere(
        (s) => s.$1 == body.indentStart,
      );
      expect(anchorSegment.$3, spec.indentPrefixStyle,
          reason: '缩进区零宽锚必须用零字距样式');
      final indentSegment = segments.firstWhere(
        (s) => s.$1 == body.indentStart + 1,
      );
      expect(indentSegment.$3, spec.indentStyle);
      expect(
        layout.displayText.substring(indentSegment.$1, indentSegment.$2),
        '\u00A0\u00A0',
      );
    });

    test('正文字距为负时缩进步进仍是一个汉字', () {
      // 旧实现把补宽量算成 fontSize −（含正文字距的步进），渲染步进
      // = fontSize − 正文字距：正文设负字距时缩进比一个字宽
      // （用户实测「设 1 字，渲染比 1 字多一点」）。
      const fontSize = 22.0;
      final spec = ReaderTypeSpec.fromSettings(
        const ReadingSettings(
          fontSize: fontSize, lineHeight: 1.7, letterSpacing: -0.5),
        ReadingTheme.paper,
      );
      double stepOf(TextStyle style) {
        final painter = TextPainter(
          text: TextSpan(text: '\u00A0\u00A0国', style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        final w2 = painter.width;
        painter.dispose();
        final painter1 = TextPainter(
          text: TextSpan(text: '\u00A0国', style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        final w1 = painter1.width;
        painter1.dispose();
        return w2 - w1;
      }

      // 不缩放口径：步进恰好一个字号（与正文字距无关）。
      expect(stepOf(spec.indentStyleFor(1)), closeTo(fontSize, 0.01));
    });

    test('系统字号缩放下缩进步进等于渲染后的字号', () {
      const fontSize = 22.0;
      const scale = 1.3;
      final spec = ReaderTypeSpec.fromSettings(
        const ReadingSettings(fontSize: fontSize, lineHeight: 1.7),
        ReadingTheme.paper,
      );
      TextPainter painterOf(String text, TextStyle style) => TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.linear(scale),
          )..layout();
      final style = spec.indentStyleFor(scale);
      final p2 = painterOf('\u00A0\u00A0国', style);
      final w2 = p2.width;
      p2.dispose();
      final p1 = painterOf('\u00A0国', style);
      final w1 = p1.width;
      p1.dispose();
      expect(w2 - w1, closeTo(fontSize * scale, 0.01));
    });
  });

  group('断页点与渲染断行一致（缩进计入测量）', () {
    // 回归：_measureParagraph 原来只量 displayStart 之后的正文（不含缩进
    // 字符），渲染端却把缩进一起排版——首行断行位置差一个字，测量以为
    // 行尾装得下的字在渲染里被挤成孤字行（页码「前」孤行、页底留白忽大
    // 忽小）。页界必须落在**渲染模型**的行首上。
    test('每个页界都是渲染行首', () {
      const fontSize = 20.0;
      const lineHeight = 1.5;
      final spec = ReaderTypeSpec.fromSettings(
        const ReadingSettings(fontSize: fontSize, lineHeight: lineHeight),
        ReadingTheme.paper,
      );
      // 版心恰好 12 个汉字宽：带 1 字缩进的首行装 11 字，不带缩进装 12 字
      // ——两种口径的断行必然错开。
      final width = fontSize * 12;
      final chapter = NativeChapter.fromBlocks(
        idx: 0,
        title: '第一章',
        href: 'c1.xhtml',
        blocks: [ParsedBlock(text: '山泉水在石缝间叮咚作响，' * 8)],
        fallbackText: '',
      );
      final layout = ChapterLayout.build(chapter: chapter, spec: spec);
      final p = layout.paragraphs.first;
      final pag = _paginateWith(layout, spec,
          width: width, height: fontSize * lineHeight * 4);

      // 渲染模型（零宽锚 + 补宽 NBSP + 正文，与渲染同一套分段）的行首集合。
      final painter = TextPainter(
        text: TextSpan(
          style: spec.bodyStyle,
          children: [
            for (final (a, b, style)
                in layout.segmentsOf(p.indentStart, p.displayEnd))
              TextSpan(
                text: layout.displayText.substring(a, b),
                style: style,
              ),
          ],
        ),
        textDirection: TextDirection.ltr,
        textAlign: p.align,
        textScaler: TextScaler.linear(1),
      )..layout(maxWidth: width);
      final renderStarts = <int>{p.indentStart};
      for (final m in painter.computeLineMetrics()) {
        final top = m.baseline - m.ascent;
        final local =
            painter.getPositionForOffset(Offset(0, top + 0.5)).offset;
        renderStarts.add(p.indentStart + local);
      }
      painter.dispose();
      expect(renderStarts.length, greaterThan(3));

      for (var page = 1; page < pag.pageCount; page++) {
        final start = pag.starts[page];
        if (start < p.displayEnd) {
          expect(renderStarts, contains(start),
              reason: '页 $page 起点 $start 不在渲染行首上'
                  '（会把行尾字挤成孤字行）');
        }
      }
    });
  });

  group('行首零宽锚（justify 出界回归）', () {
    // 回归：SkParagraph 对「行的第一个 span 带 letterSpacing L」的行会
    // 整体右移 L/2，且 justify 按未偏移宽度拉伸——首行行尾油墨出界 L/2，
    // 末字被裁（用户实测「缩进比设置大一点、第一行最后一个字显示不全」）。
    // 缩进区以零宽锚（U+FEFF，字距 0）开头，让补宽 span 退居行中。
    // 本组用显式字距模拟设备上「NBSP 被字体做窄、补宽字距较大」的条件，
    // 不依赖宿主字体：断言的是「缩进 = n×(NBSP步进+字距)，行首无偏移、
    // 行尾不出界」这条与字体无关的不变式。
    test('锚分段：缩进精确 n 个步进，justify 首行不出版心', () {
      const fontSize = 18.0;
      const maxW = 330.0;
      const body = '中国和日本元素仍让我感到亲切这就是为什么当我带的博士生杨东伟在';
      TextSpan ts(String t, double l) => TextSpan(
            text: t,
            style: TextStyle(fontSize: fontSize, letterSpacing: l),
          );

      // 宿主实际的 NBSP 步进（差值法，与 app 同口径）。
      double widthOf(String t) {
        final p = TextPainter(
          text: TextSpan(text: t, style: const TextStyle(fontSize: fontSize)),
          textDirection: TextDirection.ltr,
        )..layout();
        final w = p.width;
        p.dispose();
        return w;
      }

      final advance = widthOf('\u00A0\u00A0国') - widthOf('\u00A0国');
      const forcedL = 13.5; // 模拟设备的较大补宽字距

      for (final align in [TextAlign.left, TextAlign.justify]) {
        for (final n in [1, 2, 3]) {
          final painter = TextPainter(
            text: TextSpan(
              style: const TextStyle(fontSize: fontSize),
              children: [
                ts('\uFEFF', 0), // 锚：字距必须为 0
                ts('\u00A0' * n, forcedL),
                ts(body, 0),
              ],
            ),
            textDirection: TextDirection.ltr,
            textAlign: align,
          )..layout(maxWidth: maxW);

          final firstBody = painter.getBoxesForSelection(
            TextSelection(baseOffset: 1 + n, extentOffset: 2 + n),
          ).first;
          expect(
            firstBody.left,
            closeTo(n * (advance + forcedL), 0.02),
            reason: '$align n=$n：缩进应精确 n×(步进+字距)，无 L/2 偏移',
          );

          if (align == TextAlign.justify) {
            final line0 =
                painter.getLineBoundary(const TextPosition(offset: 0)).end;
            final last = painter.getBoxesForSelection(
              TextSelection(baseOffset: line0 - 1, extentOffset: line0),
            ).first;
            expect(
              last.right,
              lessThanOrEqualTo(maxW + 0.02),
              reason: 'justify 首行行尾不得超出版心（末字被裁）',
            );
          }
          painter.dispose();
        }
      }
    });

    test('锚样式字距为 0、锚字符零宽', () {
      final spec = _spec();
      expect(spec.indentPrefixStyle.letterSpacing, 0);
      final p1 = TextPainter(
        text: TextSpan(text: '国', style: spec.bodyStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final w1 = p1.width;
      p1.dispose();
      final p2 = TextPainter(
        text: TextSpan(
          text: '\uFEFF国',
          style: spec.bodyStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(p2.width - w1, closeTo(0, 0.01), reason: '锚字符必须零宽');
      p2.dispose();
    });
  });
}
