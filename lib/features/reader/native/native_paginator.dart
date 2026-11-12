/// 原生文本排版：把「标题 + 正文段落」排成分页，并提供显示坐标 ↔ 章内
/// 字符坐标的双向映射。
///
/// 为什么整章一次性排：Flutter 的 `TextPainter` 是单段落排版，只有把整章
/// 拼成一棵带样式的 `TextSpan` 树，才能让分页结果与实际渲染逐行一致
/// （不同段落各有字号/行高/字重）。章长通常几千字，一次排版可接受。
///
/// 段间距的实现：Flutter 不能在同一个文本里给段落加任意垂直间距，这里用
/// 「一行只放一个零宽空格、其 `TextStyle` 的 (fontSize=1 × height=间距) 恰好
/// 等于间距」来撑出一条与正文无关的空白行。分页时页首会跳过这条占位行，
/// 不会在页顶留下空白。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/reading_theme.dart';
import '../reader_settings.dart';
import 'native_chapter_source.dart';

/// 版式规格：分页与渲染共用同一份，保证量出来的行和画出来的一模一样。
class ReaderTypeSpec {
  const ReaderTypeSpec({
    required this.bodyStyle,
    required this.headingStyle,
    required this.bodyAlign,
    required this.headingAlign,
    required this.indentChars,
    required this.paragraphSpacing,
    required this.headingMarginTop,
    required this.headingMarginBottom,
    required this.headingStyleKind,
  });

  /// 从阅读设置生成。
  factory ReaderTypeSpec.fromSettings(
    ReadingSettings s,
    ReadingTheme theme,
  ) {
    final family = s.fontFamily.isEmpty ? null : s.fontFamily;
    final weight =
        s.bodyBold ? math.max(700, s.bodyWeight.value) : s.bodyWeight.value;
    final body = TextStyle(
      color: theme.foreground,
      fontSize: s.fontSize,
      height: s.lineHeight,
      letterSpacing: s.letterSpacing,
      fontWeight: FontWeight.values[(weight ~/ 100) - 1],
      fontFamily: family,
    );
    final underline = s.headingStyle == HeadingStyle.underline ||
        s.headingStyle == HeadingStyle.underlineShade;
    final shade = s.headingStyle == HeadingStyle.shade ||
        s.headingStyle == HeadingStyle.underlineShade;
    final heading = TextStyle(
      color: theme.foreground,
      fontSize: s.headingFontSize,
      height: 1.35,
      letterSpacing: s.letterSpacing,
      fontWeight: s.headingBold ? FontWeight.w700 : FontWeight.w400,
      fontFamily: family,
      decoration: underline ? TextDecoration.underline : TextDecoration.none,
      decorationColor: underline ? theme.accent : null,
      decorationThickness: underline ? 1.2 : null,
      backgroundColor: shade ? theme.accent.withValues(alpha: 0.14) : null,
    );
    return ReaderTypeSpec(
      bodyStyle: body,
      headingStyle: heading,
      bodyAlign: _bodyAlign(s),
      headingAlign: _headingAlign(s),
      indentChars: s.bodyIndent.chars,
      paragraphSpacing: s.paragraphSpacing * s.fontSize,
      headingMarginTop: s.headingMarginTop,
      headingMarginBottom: s.headingMarginBottom,
      headingStyleKind: s.headingStyle,
    );
  }

  /// 正文字体样式。
  final TextStyle bodyStyle;

  /// 标题字体样式。
  final TextStyle headingStyle;

  /// 正文对齐（已把「两端对齐」折算进来）。
  final TextAlign bodyAlign;

  /// 标题对齐。
  final TextAlign headingAlign;

  /// 正文首行缩进字数（标题不缩进）。
  final int indentChars;

  /// 段间距（逻辑像素）。
  final double paragraphSpacing;

  /// 标题上边距。
  final double headingMarginTop;

  /// 标题下边距。
  final double headingMarginBottom;

  /// 标题装饰（渲染层用）。
  final HeadingStyle headingStyleKind;

  static final Map<int, double> _indentAdvanceCache = {};

  /// 缩进字符（NBSP，U+00A0）在正文样式下的单字符步进。
  ///
  /// 用「两个前导缩进字符 + 锚字」减「一个缩进字符 + 锚字」取差值：空白
  /// 只出现在行首（不会被当行尾空白裁掉），差值就是精确的单字符步进，
  /// 已含正文 letterSpacing。纯空白文本的 painter.width 会因行尾空白
  /// 被裁剪而失真，不能用。
  static double _indentCharAdvance(TextStyle style) {
    final key = Object.hash(
      style.fontSize,
      style.fontFamily,
      style.fontFamilyFallback,
      style.fontWeight,
      style.letterSpacing,
    );
    return _indentAdvanceCache.putIfAbsent(key, () {
      double widthOf(String text) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        )..layout();
        final w = painter.width;
        painter.dispose();
        return w;
      }

      const anchor = '国';
      return widthOf('\u00A0\u00A0$anchor') - widthOf('\u00A0$anchor');
    });
  }

  /// 首行缩进的专用样式：把每个缩进字符的步进精确补到一个汉字宽。
  ///
  /// 缩进字符是 NBSP，实际宽度由字体字形决定——不少（导入的）字体把
  /// 空白字符做窄，缩进看起来只有半个字。用 letterSpacing 把步进补到
  /// fontSize，落实「首行缩进 N 字」的中文惯例，与具体字体无关。
  ///
  /// 两个精度要点（2026-11-11）：
  /// - 步进必须用**剥离了正文字距**的样式去量：`_indentCharAdvance(bodyStyle)`
  ///   的差值里含正文 letterSpacing，补出来的步进 = fontSize − 正文字距——
  ///   正文设了负字距时缩进会比一个字宽（用户实测「设 1 字渲染比 1 字多」）。
  /// - 系统字号缩放 [textScale] 下字形步进随 fontSize 一起缩放，而
  ///   letterSpacing 是绝对值不缩放，所以补偿量要乘 textScale，渲染步进
  ///   才恒等于 fontSize × textScale。
  TextStyle indentStyleFor(double textScale) {
    final fontSize = bodyStyle.fontSize ?? 16;
    final bare = bodyStyle.copyWith(letterSpacing: 0);
    final advance = _indentCharAdvance(bare);
    return bodyStyle.copyWith(
      letterSpacing: (fontSize - advance) * textScale,
    );
  }

  /// 缩进锚字符（零宽 U+FEFF）的样式：letterSpacing 必须为 0。
  ///
  /// SkParagraph 有一个行为：**行的第一个 span 若带 letterSpacing L，
  /// 整行字形会整体右移 L/2**（左对齐下行 left = L/2，实测 1/2/3 个字、
  /// 汉字/NBSP 一致）。缩进补宽样式 L = fontSize − NBSP步进 是个较大的
  /// 正数，放行首后果有二：
  /// ① 缩进渲染成 n×字宽 + L/2（用户实测「设 2 比2大一点」）；
  /// ② justify 按未偏移的宽度拉伸 → 首行行尾油墨出界 L/2，末字被裁
  ///   （用户实测「第一行最后一个字显示不全」）。
  /// 在缩进区最前面放一个零宽、letterSpacing=0 的锚字符，让补宽 span
  /// 退居行中，两个症状同时消失（U+3000 不行——justify 会把行首的
  /// U+3000 折叠成 0 宽，锚就没了；U+FEFF 是格式字符，shaper 保留
  /// 零宽字形，左对齐/justify 下都稳定）。
  TextStyle get indentPrefixStyle => bodyStyle.copyWith(letterSpacing: 0);

  /// 不缩放口径的缩进样式（测试/工具用）。
  TextStyle get indentStyle => indentStyleFor(1);

  /// 版式签名（任何影响排版的字段变化都会让排版缓存失效）。
  int get signature => Object.hash(
        bodyStyle,
        headingStyle,
        bodyAlign,
        headingAlign,
        indentChars,
        paragraphSpacing,
        headingMarginTop,
        headingMarginBottom,
        headingStyleKind,
      );

  /// 只包含「影响行数/行高」的签名，用作分页缓存键。
  ///
  /// 与 [signature] 的区别：颜色、下划线、标题底色等只影响绘制、不影响
  /// 排版。换主题时 [signature] 会变（排版结果里的样式要换成新颜色），
  /// 但分页结果完全可复用——长章节不必因为换个主题再重排一遍。
  int get metricsSignature => Object.hash(
        bodyStyle.fontSize,
        bodyStyle.height,
        bodyStyle.letterSpacing,
        bodyStyle.fontWeight,
        bodyStyle.fontFamily,
        headingStyle.fontSize,
        headingStyle.height,
        headingStyle.letterSpacing,
        headingStyle.fontWeight,
        headingStyle.fontFamily,
        bodyAlign,
        headingAlign,
        indentChars,
        paragraphSpacing,
        headingMarginTop,
        headingMarginBottom,
      );

  /// 只影响「文字本身怎么断行/行多高」的签名（测量缓存键）。
  ///
  /// 段距与标题上下边距只改变段与段之间的距离，不影响每段的断行与行高；
  /// 改段距时可以复用测量结果，只重新装箱。
  int get textMetricsSignature => Object.hash(
        bodyStyle.fontSize,
        bodyStyle.height,
        bodyStyle.letterSpacing,
        bodyStyle.fontWeight,
        bodyStyle.fontFamily,
        headingStyle.fontSize,
        headingStyle.height,
        headingStyle.letterSpacing,
        headingStyle.fontWeight,
        headingStyle.fontFamily,
        bodyAlign,
        headingAlign,
        indentChars,
      );

  static TextAlign _bodyAlign(ReadingSettings s) {
    if (s.bodyAlign == TextAlignMode.center) return TextAlign.center;
    if (s.bodyAlign == TextAlignMode.right) return TextAlign.right;
    return s.bodyJustify ? TextAlign.justify : TextAlign.left;
  }

  static TextAlign _headingAlign(ReadingSettings s) => switch (s.headingAlign) {
        TextAlignMode.auto => TextAlign.center,
        TextAlignMode.left => TextAlign.left,
        TextAlignMode.center => TextAlign.center,
        TextAlignMode.right => TextAlign.right,
      };
}

/// 排版后的段落（显示坐标）。
class LayoutParagraph {
  const LayoutParagraph({
    required this.source,
    required this.indentStart,
    required this.displayStart,
    required this.displayEnd,
    required this.style,
    required this.align,
  });

  /// 原始段落。
  final NativeParagraph source;

  /// 缩进字符起点（无缩进 = [displayStart]）。
  ///
  /// 页面从这里的 run 开始渲染时才带得上首行缩进；从 [displayStart]
  /// 开始就会丢缩进。
  final int indentStart;

  /// 显示文本起点（缩进之后）。
  final int displayStart;

  /// 显示文本终点（不含）。
  final int displayEnd;

  /// 该段的字体样式。
  final TextStyle style;

  /// 该段的对齐。
  final TextAlign align;

  /// 是否标题。
  bool get isHeading => source.isHeading;
}

/// 一章的排版结果：显示文本 + 每段样式区间 + 坐标映射。
class ChapterLayout {
  ChapterLayout._({
    required this.chapter,
    required this.displayText,
    required this.paragraphs,
    required this.separators,
    required this.spec,
  });

  /// 按版式构建（缩进/段距都体现在 displayText 里）。
  factory ChapterLayout.build({
    required NativeChapter chapter,
    required ReaderTypeSpec spec,
  }) {
    final buffer = StringBuffer();
    final paragraphs = <LayoutParagraph>[];
    final separators = <({int start, int end, double gap})>[];

    void write(String text) {
      if (text.isEmpty) return;
      buffer.write(text);
    }

    for (var i = 0; i < chapter.paragraphs.length; i++) {
      final p = chapter.paragraphs[i];
      final style = p.isHeading ? spec.headingStyle : spec.bodyStyle;
      if (i > 0) {
        final prev = chapter.paragraphs[i - 1];
        final gap = _gapBetween(prev, p, spec);
        final start = buffer.length;
        write('\n');
        if (gap > 0.5) {
          // 一行只有一个零宽空格，字号 1 × height=gap = 恰好 gap 像素
          write(String.fromCharCode(0x200B));
          write('\n');
        }
        separators.add((start: start, end: buffer.length, gap: gap));
      }
      final indent = p.isHeading ? 0 : spec.indentChars;
      final indentStart = buffer.length;
      // 缩进字符用 NBSP（U+00A0）而不是全角空格 U+3000：两端对齐
      // （TextAlign.justify）会把行首的 U+3000 空白压缩成 0 宽——首行
      // 缩进整个消失、换行却仍按缩进宽度提前断行（实测）；NBSP 不被
      // justify 折叠，宽度由 indentStyle 的 letterSpacing 精确补到 1 字。
      // 缩进区最前面还有个零宽锚（U+FEFF，indentPrefixStyle，字距 0）：
      // 补宽 span 带 letterSpacing，放行首会让整行右移 L/2（见
      // [ReaderTypeSpec.indentPrefixStyle]），锚把它顶到行中。
      if (indent > 0) {
        write('\uFEFF');
        write(String.fromCharCode(0x00A0) * indent);
      }
      final start = buffer.length;
      write(p.text);
      paragraphs.add(LayoutParagraph(
        source: p,
        indentStart: indentStart,
        displayStart: start,
        displayEnd: buffer.length,
        style: style,
        align: p.isHeading ? spec.headingAlign : spec.bodyAlign,
      ));
    }

    return ChapterLayout._(
      chapter: chapter,
      displayText: buffer.toString(),
      paragraphs: paragraphs,
      separators: separators,
      spec: spec,
    );
  }

  /// 原始章节。
  final NativeChapter chapter;

  /// 带缩进与段距占位的显示文本。
  final String displayText;

  /// 段落区间（按 displayStart 升序）。
  final List<LayoutParagraph> paragraphs;

  /// 段间占位区间（换行 + 可选零宽空格行）。
  final List<({int start, int end, double gap})> separators;

  /// 版式规格。
  final ReaderTypeSpec spec;

  final Map<double, double> _spacerHeights = <double, double>{};

  /// 段距占位行的**真实**行高。
  ///
  /// 不能直接用 gap：Flutter 对「字号 1 × height=gap」的行会有取整/最小
  /// 行高，实际高度与 gap 有零点几像素的偏差；一页几十段累积起来就会让
  /// 正文超出页底（真机表现为页底裁字、测试里是 RenderFlex overflow）。
  double spacerHeight(double gap) {
    if (gap <= 0.5) return 0;
    return _spacerHeights.putIfAbsent(gap, () {
      final painter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(0x200B),
          style: TextStyle(fontSize: 1, height: gap),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final h = painter.height;
      painter.dispose();
      return h;
    });
  }

  /// 两段之间的真实间距（含标题边距，已换算成占位行高）。
  double paragraphGapBetween(LayoutParagraph prev, LayoutParagraph next) =>
      spacerHeight(_gapBetween(prev.source, next.source, spec));

  /// 第一个 `displayEnd > offset` 的段落下标（段落按显示区间升序）。
  ///
  /// 分页与渲染都会频繁按偏移找段；从 0 线性扫在长章节里会退化成 O(n²)。
  int _paragraphIndexAfter(int offset) {
    var lo = 0;
    var hi = paragraphs.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (paragraphs[mid].displayEnd > offset) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  /// 测量「一段片段」[from, to) 的高度（可选中渲染的最小单元）。
  ///
  /// 与 [renderedHeight] 中单个 run 的测量完全一致：同一套样式分段、
  /// 同对齐方式、同样的宽高约束。分页快速路径用它逐段累加。
  /// [from] 早于缩进起点（页首从缩进起排）时，缩进字符计入测量——
  /// 漏掉会让快速路径低估页高（每段首行多塞一个字）。
  double measureFragment(
    LayoutParagraph paragraph,
    int from,
    double width,
    double textScale,
  ) {
    final start =
        from < paragraph.indentStart ? paragraph.indentStart : from;
    final end = paragraph.displayEnd;
    if (end <= start) return 0;
    return _measureRun(start, end, paragraph.align, width, textScale);
  }

  /// 测量 [start, end) 区间的高度（单段内的片段，含跨段时按渲染分段）。
  double measureRange(
    int start,
    int end,
    TextAlign align,
    double width,
    double textScale,
  ) {
    if (end <= start) return 0;
    return _measureRun(start, end, align, width, textScale);
  }

  double _measureRun(
    int start,
    int end,
    TextAlign align,
    double width,
    double textScale,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        style: spec.bodyStyle,
        children: [
          for (final (a, b, style) in segmentsOf(start, end, textScale: textScale))
            TextSpan(text: displayText.substring(a, b), style: style),
        ],
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      textScaler: TextScaler.linear(textScale),
    )..layout(maxWidth: width);
    final h = painter.height;
    painter.dispose();
    return h;
  }

  /// 按**渲染模型**测量 [start, end) 这一页的实际高度。
  ///
  /// 分页必须与渲染用同一套分组/样式/间距：同对齐段落会合并成一个文本，
  /// 合并后的行数与逐段测量可能略有差异；只按行高累加会在页底裁掉一行。
  double renderedHeight(int start, int end, double width, double textScale) {
    var realEnd = math.min(end, displayText.length);
    while (realEnd > start) {
      final ch = displayText[realEnd - 1];
      if (ch == String.fromCharCode(10) ||
          ch == String.fromCharCode(0x200B) ||
          ch == String.fromCharCode(0x3000)) {
        realEnd--;
      } else {
        break;
      }
    }
    if (realEnd <= start) return 0;

    final runs = <_MeasureRun>[];
    final first = _paragraphIndexAfter(start);
    LayoutParagraph? prev = first > 0 ? paragraphs[first - 1] : null;
    for (var k = first; k < paragraphs.length; k++) {
      final p = paragraphs[k];
      if (p.displayStart >= realEnd) break;
      // 页面从缩进之前开始（断页点在上一段文本末尾）时，把缩进字符
      // 纳入测量——渲染端的 run 同样带上缩进，两边必须一致。
      final from = start <= p.indentStart
          ? p.indentStart
          : math.max(p.displayStart, start);
      final to = math.min(p.displayEnd, realEnd);
      if (to > from) {
        if (runs.isNotEmpty && prev != null && runs.last.align == p.align) {
          runs.last.end = to;
        } else {
          runs.add(_MeasureRun(
            start: from,
            end: to,
            align: p.align,
            gap: runs.isEmpty || prev == null
                ? 0
                : spacerHeight(_gapBetween(prev.source, p.source, spec)),
          ));
        }
      }
      prev = p;
    }

    var total = 0.0;
    for (final r in runs) {
      total += r.gap;
      total += _measureRun(r.start, r.end, r.align, width, textScale);
    }
    return total;
  }

  /// 第 [index] 段之前的间距（含标题上下边距；首段为 0）。
  double paragraphGapBefore(int index) {
    if (index <= 0 || index >= paragraphs.length) return 0;
    return _gapBetween(paragraphs[index - 1].source, paragraphs[index].source, spec);
  }

  /// 取 [start, end) 的样式分段（段距占位行保留自己的行高样式）。
  ///
  /// 渲染端必须用这一个方法切分：页首/页尾的占位与正文样式的差异会直接
  /// 影响行高，用错样式会让「量出来的页」和「画出来的页」对不上。
  /// [textScale] 用于缩进补宽样式的补偿量（见 [ReaderTypeSpec.indentStyleFor]）。
  List<(int, int, TextStyle)> segmentsOf(int start, int end,
      {double textScale = 1}) {
    final out = <(int, int, TextStyle)>[];
    var cursor = start;
    final first = _paragraphIndexAfter(start);
    for (var k = first; k < paragraphs.length; k++) {
      final p = paragraphs[k];
      if (p.displayStart >= end) break;
      final from = math.max(p.displayStart, start);
      if (from > end) break;
      if (cursor < from) {
        // 区间里带上了这一段的缩进字符时，用补宽样式渲染。页首 run 从
        // 缩进起点开始（cursor == indentStart），同样算「带上缩进」。
        final withIndent = from == p.displayStart &&
            p.indentStart >= cursor &&
            p.indentStart < from;
        _appendGapSegments(
          out,
          cursor,
          math.min(from, end),
          indentOf: withIndent ? p : null,
          textScale: textScale,
        );
        cursor = math.min(from, end);
      }
      final to = math.min(p.displayEnd, end);
      if (to > from) {
        out.add((from, to, p.style));
        cursor = to;
      }
    }
    if (cursor < end) _appendGapSegments(out, cursor, end, textScale: textScale);
    return out;
  }

  void _appendGapSegments(
    List<(int, int, TextStyle)> out,
    int start,
    int end, {
    LayoutParagraph? indentOf,
    double textScale = 1,
  }) {
    final zwsp = String.fromCharCode(0x200B);
    final lf = String.fromCharCode(10);
    var pos = start;
    while (pos < end) {
      if (displayText[pos] == zwsp) {
        // 零宽空格与它后面的换行都必须用占位样式：
        // 换行若带正文字号，这一行会被撑成全高行（段距失效且页底裁字）。
        var next = pos + 1;
        if (next < end && next < displayText.length && displayText[next] == lf) {
          next++;
        }
        out.add((
          pos,
          next,
          TextStyle(fontSize: 1, height: separatorGapAt(pos)),
        ));
        pos = next;
      } else {
        var next = pos + 1;
        while (next < end && displayText[next] != zwsp) {
          next++;
        }
        // 缩进字符段：换成补宽样式（精确一个汉字宽），其余保持正文样式。
        // cut == pos（缩进段恰好从本段开头开始，页首段与标题后第一段都是
        // 这样）时整段就是缩进字符，同样要用补宽样式。缩进区首个字符是
        // 零宽锚（U+FEFF），必须单列且字距为 0（行首 span 带字距会让
        // 整行右移 L/2，见 [ReaderTypeSpec.indentPrefixStyle]）。
        final cut = indentOf?.indentStart;
        if (cut != null && cut >= pos && cut < next) {
          if (cut > pos) out.add((pos, cut, spec.bodyStyle));
          out.add((cut, cut + 1, spec.indentPrefixStyle));
          if (cut + 1 < next) {
            out.add((cut + 1, next, spec.indentStyleFor(textScale)));
          }
        } else {
          out.add((pos, next, spec.bodyStyle));
        }
        pos = next;
      }
    }
  }

  /// 某处占位行的间距（像素）；不在占位行里返回 0。
  double separatorGapAt(int display) {
    var lo = 0;
    var hi = separators.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final sep = separators[mid];
      if (display < sep.start) {
        hi = mid - 1;
      } else if (display >= sep.end) {
        lo = mid + 1;
      } else {
        return sep.gap;
      }
    }
    return 0;
  }

  /// 显示坐标 → 章内字符坐标（标注/TTS/进度都用章内坐标）。
  int chapterOfDisplay(int display) {
    if (paragraphs.isEmpty) return 0;
    final p = _paragraphAt(display);
    final local = display - p.displayStart;
    return p.source.start + local.clamp(0, p.source.text.length);
  }

  /// 章内字符坐标 → 显示坐标。
  int displayOfChapter(int chapterOffset) {
    if (paragraphs.isEmpty) return 0;
    var lo = 0;
    var hi = paragraphs.length - 1;
    var idx = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (paragraphs[mid].source.start <= chapterOffset) {
        idx = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    final p = paragraphs[idx];
    final local = chapterOffset - p.source.start;
    if (local < 0) return p.displayStart;
    return p.displayStart + local.clamp(0, p.source.text.length);
  }

  /// 显示坐标是否落在段间占位里。
  bool isSeparator(int display) {
    var lo = 0;
    var hi = separators.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final sep = separators[mid];
      if (display < sep.start) {
        hi = mid - 1;
      } else if (display >= sep.end) {
        lo = mid + 1;
      } else {
        return true;
      }
    }
    return false;
  }

  /// 分页时把页首吸附到段落起点：落在段距占位里就跳到下一段的
  /// **缩进起点**（带上缩进字符，页首段落不丢缩进），避免页顶出现
  /// 一条空白占位行。
  int snapPageStart(int display) {
    final idx = _paragraphIndexAfter(display);
    if (idx >= paragraphs.length) return display;
    final p = paragraphs[idx];
    if (display <= p.indentStart) return p.indentStart;
    return display;
  }

  /// 显示坐标所在的段落（落在段距里时返回前一段）。
  LayoutParagraph _paragraphAt(int display) {
    var lo = 0;
    var hi = paragraphs.length - 1;
    var idx = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (paragraphs[mid].displayStart <= display) {
        idx = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return paragraphs[idx];
  }

  /// 相邻两段的间距：标题用自身上下边距，正文用段间距；取两者较大值，
  /// 避免「标题下边距 + 段间距」叠成一条过大的沟。
  static double _gapBetween(
    NativeParagraph prev,
    NativeParagraph next,
    ReaderTypeSpec spec,
  ) {
    final before = next.isHeading
        ? spec.headingMarginTop
        : spec.paragraphSpacing;
    final after = prev.isHeading ? spec.headingMarginBottom : 0.0;
    return math.max(before, after);
  }
}

/// 一页的渲染片段。
class PageFragment {
  const PageFragment({
    required this.text,
    required this.span,
    required this.rangeStart,
    required this.rangeEnd,
  });

  /// 本页显示文本（已去掉页尾的段间占位）。
  final String text;

  /// 带段落样式的渲染树。
  final TextSpan span;

  /// 本页显示文本在章显示坐标里的起点。
  final int rangeStart;

  /// 终点（不含）。
  final int rangeEnd;
}

/// 取某一页的渲染片段（页尾的换行/占位会裁掉，否则会在页底多出一行）。
PageFragment buildPageFragment(
  ChapterLayout layout,
  int start,
  int end, {
  double textScale = 1,
}) {
  var realEnd = math.min(end, layout.displayText.length);
  while (realEnd > start) {
    final ch = layout.displayText[realEnd - 1];
    if (ch == '\n' || ch == '\u200B' || ch == '\u3000') {
      realEnd--;
    } else {
      break;
    }
  }
  final children = <InlineSpan>[
    for (final (a, b, style) in layout.segmentsOf(start, realEnd, textScale: textScale))
      TextSpan(text: layout.displayText.substring(a, b), style: style),
  ];
  return PageFragment(
    text: layout.displayText.substring(start, realEnd),
    span: TextSpan(style: layout.spec.bodyStyle, children: children),
    rangeStart: start,
    rangeEnd: realEnd,
  );
}

/// 分页缓存键：章 + 版心尺寸 + 系统字号缩放 + 版式签名。
class PaginationKey {
  const PaginationKey({
    required this.chapterIdx,
    required this.width,
    required this.height,
    required this.textScale,
    required this.signature,
  });

  /// 章序号。
  final int chapterIdx;

  /// 版心宽（逻辑像素）。
  final double width;

  /// 版心高（逻辑像素）。
  final double height;

  /// 系统字体缩放。
  final double textScale;

  /// 版式签名（字号/行距/缩进/段距/标题样式等）。
  final int signature;

  @override
  bool operator ==(Object other) =>
      other is PaginationKey &&
      other.chapterIdx == chapterIdx &&
      other.width == width &&
      other.height == height &&
      other.textScale == textScale &&
      other.signature == signature;

  @override
  int get hashCode =>
      Object.hash(chapterIdx, width, height, textScale, signature);
}

/// 分页结果：每页起始的「显示坐标」。
class Pagination {
  const Pagination({
    required this.starts,
    required this.textLength,
    this.pageHeights = const <double>[],
  });

  /// 各页起始显示偏移（升序，首项恒为 0）。
  final List<int> starts;

  /// 显示文本总长。
  final int textLength;

  /// 各页装箱后的实测高度（与 starts 对齐；用于把页底零头摊进行距）。
  /// 保守回退路径不产高度（空表），渲染端按不撑满处理。
  final List<double> pageHeights;

  /// 第 [page] 页装箱高度（无记录返回 0）。
  double heightOf(int page) =>
      page >= 0 && page < pageHeights.length ? pageHeights[page] : 0;

  /// 页数。
  int get pageCount => starts.length;

  /// 第 [page] 页的显示区间（0 基；末页终点 = 显示文本长度）。
  (int, int) rangeOf(int page) {
    final start = starts[page.clamp(0, starts.length - 1)];
    final end = page + 1 < starts.length ? starts[page + 1] : textLength;
    return (start, math.max(start, end));
  }

  /// 显示偏移落在哪一页（二分）。
  int pageOfOffset(int displayOffset) {
    if (starts.isEmpty) return 0;
    var lo = 0;
    var hi = starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (starts[mid] <= displayOffset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}

/// 单段测量结果：断行位置与每行行高。
///
/// 只依赖「文字 + 字体度量 + 版心宽度」，与段距/标题边距无关；因此改段距
/// 时可以整批复用，只重新装箱（见 [ChapterMeasurement.packAll]）。
class ParagraphMeasurement {
  ParagraphMeasurement({
    required this.lineStarts,
    required this.lineHeights,
    required this.height,
  });

  /// 各行起点（相对段落**缩进起点**，首个恒为 0，严格递增）。
  ///
  /// 测量带上了缩进字符（与渲染同一宽度），所以行首基准是缩进起点
  /// 而不是正文起点；换算绝对位置用 `p.indentStart + lineStarts[i]`。
  final List<int> lineStarts;

  /// 各行行高（和 = [height]）。
  final List<double> lineHeights;

  /// 整段高度。
  final double height;

  /// [local] 落在第几行（最后一个起点 <= local）。
  int lineIndexOf(int local) {
    if (lineStarts.isEmpty) return 0;
    var lo = 0;
    var hi = lineStarts.length - 1;
    var ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lineStarts[mid] <= local) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  /// 从第 [index] 行到段尾的高度。
  double heightFromLine(int index) {
    var total = 0.0;
    for (var i = math.max(0, index); i < lineHeights.length; i++) {
      total += lineHeights[i];
    }
    return total;
  }
}

/// 一段的测量（可跨段距变化复用）。
class ChapterMeasurement {
  ChapterMeasurement({
    required this.chapterIdx,
    required this.textMetricsKey,
    required this.width,
    required this.textScale,
    required this.count,
  }) : _items = List<ParagraphMeasurement?>.filled(count, null);

  /// 章序号。
  final int chapterIdx;

  /// 文字度量签名（见 [ReaderTypeSpec.textMetricsSignature]）。
  final int textMetricsKey;

  /// 测量宽度。
  final double width;

  /// 系统字体缩放。
  final double textScale;

  /// 段落数。
  final int count;

  final List<ParagraphMeasurement?> _items;

  int _next = 0;
  int _measured = 0;

  /// 已测量的段落数。
  int get measuredCount => _measured;

  /// 是否全部测完。
  bool get complete => _measured >= count;

  /// 取某段测量（没有就现场测）。
  ParagraphMeasurement ensure(ChapterLayout layout, int index) {
    final cached = _items[index];
    if (cached != null) return cached;
    final measured = _measureParagraph(
      layout,
      layout.paragraphs[index],
      width,
      textScale,
    );
    _items[index] = measured;
    _measured++;
    return measured;
  }

  /// 按顺序测下一段（分帧用）。
  void measureNext(ChapterLayout layout) {
    while (_next < _items.length && _items[_next] != null) {
      _next++;
    }
    if (_next >= _items.length) return;
    ensure(layout, _next);
  }

  /// 从 [startDisplay] 起装一页；只测量这一页用到的段。
  ({int end, int nextIndex}) packPage({
    required ChapterLayout layout,
    required int startDisplay,
    required int startIndex,
    required double maxHeight,
  }) {
    final paragraphs = layout.paragraphs;
    var used = 0.0;
    var index = startIndex;
    LayoutParagraph? prev;
    var firstOnPage = true;

    while (index < paragraphs.length) {
      final p = paragraphs[index];
      final from = math.max(p.indentStart, startDisplay);
      if (from >= p.displayEnd) {
        index++;
        continue;
      }
      final measurement = ensure(layout, index);
      final gap = prev == null ? 0.0 : layout.paragraphGapBetween(prev, p);
      final local = from - p.indentStart;
      final startLine = firstOnPage ? measurement.lineIndexOf(local) : 0;
      final height = measurement.heightFromLine(startLine);

      if (used + gap + height <= maxHeight + 0.01) {
        used += gap + height;
        prev = p;
        firstOnPage = false;
        index++;
        continue;
      }

      // 本段放不下：按整行切分。
      final remaining = maxHeight - used - gap;
      var line = startLine;
      var acc = 0.0;
      while (line < measurement.lineStarts.length &&
          acc + measurement.lineHeights[line] <= remaining + 0.01) {
        acc += measurement.lineHeights[line];
        line++;
      }
      if (line == startLine) {
        if (!firstOnPage) {
          // 页尾落在本段之前（段首起新页，页顶不留段距）。断点取本段的
          // 缩进起点（= 上一段文本结束 + 段距占位），而不是缩进后正文
          // 起点：下一页的 run 才能把缩进带上（断在缩进之后会让页首
          // 段落丢首行缩进）。
          final indentStart = layout.paragraphs[index].indentStart;
          if (indentStart > startDisplay) {
            return (end: indentStart, nextIndex: index);
          }
        }
        // 页首段一行都放不下（异常窄的版心）：强制放一行，避免死循环。
        line = math.min(startLine + 1, measurement.lineStarts.length);
      }
      final end = line >= measurement.lineStarts.length
          ? p.displayEnd
          : p.indentStart + measurement.lineStarts[line];
      return (end: end, nextIndex: end >= p.displayEnd ? index + 1 : index);
    }

    return (end: layout.displayText.length, nextIndex: paragraphs.length);
  }

  /// 一页的精确页尾：逐段行高先算出候选，再用整页测量校正。
  ///
  /// 候选来自缓存的行高（纯算术），校正只需 1 ~ 几次整页测量；与渲染
  /// 完全同一套 run 合并模型，页底不会裁字。页尾变化只影响本页。
  /// 返回的 [height] 是本页按渲染模型的实测高度（纵向撑满用）。
  ({int end, int nextIndex, double height}) packPageExact({
    required ChapterLayout layout,
    required int startDisplay,
    required int startIndex,
    required double maxHeight,
    required double width,
    required double textScale,
  }) {
    final textLength = layout.displayText.length;
    double heightOf(int end) =>
        layout.renderedHeight(startDisplay, end, width, textScale);

    var candidate = packPage(
      layout: layout,
      startDisplay: startDisplay,
      startIndex: startIndex,
      maxHeight: maxHeight,
    );
    var end = candidate.end;
    if (end <= startDisplay) {
      end = math.min(startDisplay + 1, textLength);
    }
    var height = heightOf(end);

    if (height > maxHeight + 0.01) {
      // 合并 run 测量通常比逐段累加略高（段尾换行可能多一行）：回退到
      // 最近的可放行起点。先线性回退几步，仍不行再二分。
      final candidates = <int>[];
      var index = startIndex;
      while (index < layout.paragraphs.length) {
        final p = layout.paragraphs[index];
        if (p.displayStart >= end) break;
        final measurement = ensure(layout, index);
        for (var i = 0; i < measurement.lineStarts.length; i++) {
          // 行首以缩进起点为基准（测量已带上缩进字符）：第 0 行行首就是
          // 缩进起点，断在它上面页首段落才带缩进。
          final abs = p.indentStart + measurement.lineStarts[i];
          if (abs > startDisplay && abs < end) candidates.add(abs);
        }
        index++;
      }
      candidates.sort();
      var chosen = -1;
      var steps = 0;
      for (var i = candidates.length - 1; i >= 0 && steps < 8; i--, steps++) {
        if (heightOf(candidates[i]) <= maxHeight + 0.01) {
          chosen = candidates[i];
          break;
        }
      }
      if (chosen < 0 && candidates.isNotEmpty) {
        var lo = 0;
        var hi = candidates.length - 1;
        while (lo <= hi) {
          final mid = (lo + hi) >> 1;
          if (heightOf(candidates[mid]) <= maxHeight + 0.01) {
            chosen = candidates[mid];
            lo = mid + 1;
          } else {
            hi = mid - 1;
          }
        }
      }
      if (chosen > startDisplay) {
        end = chosen;
      } else {
        // 本页一行都放不下：强制放一行，交给自检兜底。
        final paragraph = layout.paragraphs[startIndex.clamp(
          0,
          layout.paragraphs.length - 1,
        )];
        final measurement = ensure(layout, startIndex.clamp(
          0,
          layout.paragraphs.length - 1,
        ));
        final line = measurement.lineIndexOf(
          math.max(0, startDisplay - paragraph.indentStart),
        );
        final next = line + 1 < measurement.lineStarts.length
            ? paragraph.indentStart + measurement.lineStarts[line + 1]
            : paragraph.displayEnd;
        end = next > startDisplay ? next : math.min(startDisplay + 1, textLength);
      }
    } else if (height < maxHeight - 0.01) {
      // 算术低估了页高（少见）：试着多吃一行。
      var index = _paragraphIndexFor(layout, end);
      var remaining = maxHeight - height;
      var guard = 0;
      while (index < layout.paragraphs.length && guard < 64) {
        final p = layout.paragraphs[index];
        final measurement = ensure(layout, index);
        var extended = false;
        for (var i = 0; i < measurement.lineStarts.length; i++) {
          // 行首以缩进起点为基准（测量已带上缩进字符）。
          final abs = p.indentStart + measurement.lineStarts[i];
          if (abs <= end) continue;
          final lineHeight = measurement.lineHeights[i];
          if (lineHeight > remaining + 0.01) break;
          final h = heightOf(abs);
          if (h <= maxHeight + 0.01) {
            end = abs;
            height = h;
            remaining = maxHeight - height;
            extended = true;
          } else {
            extended = false;
            break;
          }
        }
        if (!extended) break;
        index++;
        guard++;
      }
    }

    return (end: end, nextIndex: _paragraphIndexFor(layout, end), height: height);
  }

  /// 全章装箱（逐页精确）。长章节可分帧调用 [packPageExact] 增量完成。
  Pagination packAllExact(
    ChapterLayout layout, {
    required double maxHeight,
    required double width,
    required double textScale,
  }) {
    final textLength = layout.displayText.length;
    if (textLength == 0) {
      return const Pagination(starts: [0], textLength: 0);
    }
    final starts = <int>[0];
    final heights = <double>[];
    var start = 0;
    var index = 0;
    var guard = 0;
    while (start < textLength) {
      final packed = packPageExact(
        layout: layout,
        startDisplay: start,
        startIndex: index,
        maxHeight: maxHeight,
        width: width,
        textScale: textScale,
      );
      var end = packed.end;
      if (end <= start) end = math.min(start + 1, textLength);
      heights.add(packed.height);
      if (end >= textLength) break;
      starts.add(end);
      start = end;
      index = packed.nextIndex;
      if (++guard > textLength + 2) break;
    }
    return Pagination(
      starts: starts,
      textLength: textLength,
      pageHeights: heights,
    );
  }

  /// 显示偏移落在第几段（第一个 displayEnd > offset）。
  int _paragraphIndexFor(ChapterLayout layout, int offset) {
    var lo = 0;
    var hi = layout.paragraphs.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (layout.paragraphs[mid].displayEnd > offset) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  static ParagraphMeasurement _measureParagraph(
    ChapterLayout layout,
    LayoutParagraph paragraph,
    double width,
    double textScale,
  ) {
    // 测量必须**带上缩进字符**（渲染端 run 从缩进起点起排，见 renderedHeight
    // 的 from 规则）：只量 displayStart 之后正文的话，首行断行位置与渲染
    // 差一个字——测量把行尾字排进本行，渲染却把它挤成孤字行，页尾提前、
    // 页高对不上（2026-11-11 实测：页底忽大忽小的留白 + 孤字「前」）。
    final text = layout.displayText.substring(
      paragraph.indentStart,
      paragraph.displayEnd,
    );
    if (text.isEmpty) {
      return ParagraphMeasurement(
        lineStarts: const <int>[0],
        lineHeights: const <double>[0],
        height: 0,
      );
    }
    // 缩进区（零宽锚 + 补宽 NBSP）与正文的样式分段直接复用 segmentsOf，
    // 与渲染端同一份逻辑——「量出来的行」和「画出来的行」才不会分叉。
    final painter = TextPainter(
      text: TextSpan(
        style: layout.spec.bodyStyle,
        children: [
          for (final (a, b, style) in layout.segmentsOf(
            paragraph.indentStart,
            paragraph.displayEnd,
            textScale: textScale,
          ))
            TextSpan(text: layout.displayText.substring(a, b), style: style),
        ],
      ),
      textDirection: TextDirection.ltr,
      textAlign: paragraph.align,
      textScaler: TextScaler.linear(textScale),
    )..layout(maxWidth: width);

    final metrics = painter.computeLineMetrics();
    final starts = <int>[];
    final heights = <double>[];
    var previous = 0;
    for (final m in metrics) {
      final top = m.baseline - m.ascent;
      var start =
          painter.getPositionForOffset(Offset(0, top + 0.5)).offset;
      if (start < previous) start = previous;
      if (start > text.length) start = text.length;
      starts.add(start);
      heights.add(m.height);
      previous = start;
    }
    final fullHeight = painter.height;
    painter.dispose();

    if (starts.isEmpty) {
      return ParagraphMeasurement(
        lineStarts: const <int>[0],
        lineHeights: <double>[fullHeight],
        height: fullHeight,
      );
    }
    // 首行为 0（居中/右对齐时 getPositionForOffset 给的是首个字形位置）。
    starts[0] = 0;
    // 行高之和与整段高度对齐（消除逐行取整误差）。
    var sum = 0.0;
    for (final h in heights) {
      sum += h;
    }
    if ((sum - fullHeight).abs() > 0.001) {
      heights[heights.length - 1] += fullHeight - sum;
      if (heights.last < 0) heights[heights.length - 1] = 0;
    }
    return ParagraphMeasurement(
      lineStarts: starts,
      lineHeights: heights,
      height: fullHeight,
    );
  }
}

/// 测量缓存键：章 + 文字度量 + 版心宽度 + 缩放（不含段距/颜色）。
class MeasurementKey {
  const MeasurementKey({
    required this.chapter,
    required this.chapterIdx,
    required this.textMetrics,
    required this.width,
    required this.textScale,
  });

  final Object chapter;
  final int chapterIdx;
  final int textMetrics;
  final double width;
  final double textScale;

  @override
  bool operator ==(Object other) =>
      other is MeasurementKey &&
      identical(other.chapter, chapter) &&
      other.chapterIdx == chapterIdx &&
      other.textMetrics == textMetrics &&
      other.width == width &&
      other.textScale == textScale;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(chapter), chapterIdx, textMetrics, width,
          textScale);
}

/// 分页自检：字符守恒、页间连续、页高不溢出。
class PaginationValidator {
  /// 校验 [pagination] 在 [layout] 上是否自洽；失败时调用方应保守重排。
  static bool validate({
    required Pagination pagination,
    required ChapterLayout layout,
    required double maxHeight,
    required double width,
    required double textScale,
  }) {
    final textLength = layout.displayText.length;
    final starts = pagination.starts;
    if (textLength == 0) {
      return starts.length == 1 && starts.first == 0;
    }
    if (starts.isEmpty || starts.first != 0) return false;
    for (var i = 0; i < starts.length; i++) {
      if (starts[i] >= textLength) return false;
      if (i > 0 && starts[i] <= starts[i - 1]) return false;
      final (start, end) = pagination.rangeOf(i);
      // 页间连续 + 字符守恒：rangeOf 用相邻页首做终点，天然连续；
      // 这里仍显式校验非法区间与页高。
      if (end <= start) return false;
      if (end > textLength) return false;
      if (layout.renderedHeight(start, end, width, textScale) >
          maxHeight + 0.01) {
        return false;
      }
    }
    return true;
  }
}

/// 分页任务：先分帧测量，再一次装箱；箱满自检失败自动保守重排。
class PaginationTask {
  PaginationTask({
    required this.paginator,
    required this.layout,
    required this.key,
    required this.measurement,
  });

  final NativePaginator paginator;
  final ChapterLayout layout;
  final PaginationKey key;
  final ChapterMeasurement measurement;

  bool done = false;

  /// 完成后的分页（自检失败时为保守重排结果）。
  Pagination? result;

  /// 是否走了保守回退。
  bool usedSafeFallback = false;

  /// 已装箱的页首与段落下标。
  final List<int> starts = <int>[0];
  int _start = 0;
  int _index = 0;

  /// 各已装页的实测高度（与 starts 对齐）。
  final List<double> _heights = [];

  /// 已装箱的字符比例 0..1（进度展示用）。
  double get progress {
    final length = layout.displayText.length;
    return length == 0 ? 1 : (_start / length).clamp(0.0, 1.0);
  }

  /// 推进 [budget] 时间片：每页先算候选、再整页校正，逐页产出。
  void advance(Duration budget) {
    if (done) return;
    final textLength = layout.displayText.length;
    if (textLength == 0) {
      result = const Pagination(starts: [0], textLength: 0);
      done = true;
      return;
    }
    final sw = Stopwatch()..start();
    while (!done && sw.elapsedMicroseconds < budget.inMicroseconds) {
      final packed = measurement.packPageExact(
        layout: layout,
        startDisplay: _start,
        startIndex: _index,
        maxHeight: key.height + 0.01,
        width: key.width,
        textScale: key.textScale,
      );
      var end = packed.end;
      if (end <= _start) end = math.min(_start + 1, textLength);
      _heights.add(packed.height);
      if (end >= textLength) {
        done = true;
        break;
      }
      starts.add(end);
      _start = end;
      _index = packed.nextIndex;
      if (starts.length > textLength + 2) {
        done = true;
        break;
      }
    }
    if (!done) return;

    final pagination = Pagination(
      starts: starts,
      textLength: textLength,
      pageHeights: _heights,
    );
    final ok = PaginationValidator.validate(
      pagination: pagination,
      layout: layout,
      maxHeight: key.height + 0.01,
      width: key.width,
      textScale: key.textScale,
    );
    NativePaginator.debugComputeCount++;
    if (ok) {
      result = pagination;
    } else {
      usedSafeFallback = true;
      result = NativePaginator.computeSafe(key: key, layout: layout);
    }
    done = true;
  }
}

/// 分页器（带缓存）。
class NativePaginator {
  /// 缓存上限：改字号/边距会不断产生新键，超限直接整体丢弃。
  static const int _maxCacheEntries = 24;

  /// 性能基准用：整章 `_compute` 次数（每次 = 一次全章分页）。
  static int debugComputeCount = 0;


  final Map<PaginationKey, Pagination> _cache = {};
  final Map<MeasurementKey, ChapterMeasurement> _measurements = {};

  /// 取（或创建）某章的测量缓存。
  ChapterMeasurement measurementFor({
    required ChapterLayout layout,
    required int chapterIdx,
    required double width,
    required double textScale,
  }) {
    final key = MeasurementKey(
      chapter: layout.chapter,
      chapterIdx: chapterIdx,
      textMetrics: layout.spec.textMetricsSignature,
      width: width,
      textScale: textScale,
    );
    final cached = _measurements[key];
    if (cached != null && cached.count == layout.paragraphs.length) {
      return cached;
    }
    if (_measurements.length >= 8) _measurements.clear();
    final created = ChapterMeasurement(
      chapterIdx: chapterIdx,
      textMetricsKey: key.textMetrics,
      width: width,
      textScale: textScale,
      count: layout.paragraphs.length,
    );
    _measurements[key] = created;
    return created;
  }

  /// 取（或计算）某章在当前版式下的分页。
  ///
  /// 测量已完成时走「纯算术装箱 + 自检」；否则退回保守算法（逐页整页
  /// 测量）。app 里的分帧重排走 [PaginationTask]，不阻塞 UI。
  Pagination paginate({
    required PaginationKey key,
    required ChapterLayout layout,
  }) {
    final hit = _cache[key];
    if (hit != null) return hit;

    final measurement = measurementFor(
      layout: layout,
      chapterIdx: key.chapterIdx,
      width: key.width,
      textScale: key.textScale,
    );
    Pagination result;
    final packed = measurement.packAllExact(
      layout,
      maxHeight: key.height + 0.01,
      width: key.width,
      textScale: key.textScale,
    );
    if (PaginationValidator.validate(
      pagination: packed,
      layout: layout,
      maxHeight: key.height + 0.01,
      width: key.width,
      textScale: key.textScale,
    )) {
      debugComputeCount++;
      result = packed;
    } else {
      result = computeSafe(key: key, layout: layout);
    }
    if (_cache.length >= _maxCacheEntries) _cache.clear();
    _cache[key] = result;
    return result;
  }

  /// 取已缓存的分页（没有则返回 null）。
  Pagination? cached(PaginationKey key) => _cache[key];

  /// 版式变化后清空缓存。
  void clear() {
    _cache.clear();
    _measurements.clear();
  }

  /// 保守分页：逐页用整页高度验证（慢，但不会裁字）。
  static Pagination computeSafe({
    required PaginationKey key,
    required ChapterLayout layout,
  }) {
    debugComputeCount++;
    final text = layout.displayText;
    if (text.isEmpty) {
      return const Pagination(starts: [0], textLength: 0);
    }
    final paragraphs = layout.paragraphs;
    final maxHeight = key.height + 0.01;
    final starts = <int>[0];
    var pageStart = 0;
    var i = 0;

    void nextPage(int offset) {
      if (offset > starts.last) starts.add(offset);
      pageStart = offset;
    }

    /// 应用精确回退结果；返回 true 表示「剩下的全放进了本页」，外层可结束。
    bool applyExact(({int end, int nextIndex}) exact) {
      if (exact.end <= pageStart) {
        // 一页连一行都放不下：跳过这一段，避免原地打转。
        i = math.max(exact.nextIndex, i + 1);
        return false;
      }
      if (exact.end >= text.length) return true;
      nextPage(exact.end);
      i = exact.nextIndex;
      return false;
    }

    // 逐页贪心。快路径按「段」累加高度（每段只排一次，O(章长)），
    // 每页落定前再用 renderedHeight 整页校验一次——它和渲染是同一套
    // 模型。旧实现每段都从页首重排一次，整章是 O(段数²)，长章节改
    // 字号/行距会卡住 UI 好几秒。
    while (i < paragraphs.length) {
      var used = 0.0;
      var j = i;
      var fitEnd = pageStart;
      LayoutParagraph? prev;

      while (j < paragraphs.length) {
        final p = paragraphs[j];
        final from = math.max(p.indentStart, pageStart);
        if (from < p.displayEnd) {
          final gap = prev == null ? 0.0 : layout.paragraphGapBetween(prev, p);
          final h = layout.measureFragment(p, from, key.width, key.textScale);
          if (used + gap + h > maxHeight) break;
          used += gap + h;
          fitEnd = p.displayEnd;
          prev = p;
        }
        j++;
      }

      // 剩下的段全部放得下：本页就是末页。
      if (j >= paragraphs.length) break;

      // 整页校验：逐段累加与整页合并测量若有差异，退回精确路径。
      if (fitEnd > pageStart &&
          layout.renderedHeight(pageStart, fitEnd, key.width, key.textScale) >
              maxHeight) {
        if (applyExact(
          _exactPageEnd(layout, key, pageStart, i, maxHeight),
        )) {
          break;
        }
        continue;
      }

      // 第 j 段放不下：二分本段能放到第几行。
      final p = paragraphs[j];
      // 片段从缩进起点起测（页首 run 带缩进）：漏掉缩进会让首行多塞
      // 一个字，二分出的行首与渲染断行错位。
      final fragStart = math.max(p.indentStart, pageStart);
      if (fragStart >= p.displayEnd) {
        i = j + 1;
        continue;
      }
      final painter = TextPainter(
        text: TextSpan(
          style: p.style,
          children: [
            // 缩进区（零宽锚 + 补宽 NBSP）与正文分段复用 segmentsOf，
            // 与整段测量/渲染同一份逻辑。
            for (final (a, b, style) in layout.segmentsOf(
              fragStart,
              p.displayEnd,
              textScale: key.textScale,
            ))
              TextSpan(text: text.substring(a, b), style: style),
          ],
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        textScaler: TextScaler.linear(key.textScale),
      )..layout(maxWidth: key.width);
      final metrics = painter.computeLineMetrics();
      if (metrics.isEmpty) {
        painter.dispose();
        i = j + 1;
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

      double measurePage(int end) =>
          layout.renderedHeight(pageStart, end, key.width, key.textScale);

      // 二分用「剩余可用高度」度量本段片段，避免每次都整页重排。
      final gapBefore =
          prev == null ? 0.0 : layout.paragraphGapBetween(prev, p);
      final remaining = maxHeight - used - gapBefore;
      var lo = 1;
      var hi = metrics.length;
      var best = 0;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        final end = mid == metrics.length ? p.displayEnd : lineStarts[mid];
        if (layout.measureRange(
              fragStart,
              end,
              p.align,
              key.width,
              key.textScale,
            ) <=
            remaining + 0.01) {
          best = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }

      if (best == 0) {
        if (fragStart > pageStart) {
          // 断点取本段的缩进起点（而非缩进后正文起点），下一页 run
          // 才能带上首行缩进。
          final indentStart = paragraphs[j].indentStart;
          if (indentStart > pageStart) {
            nextPage(indentStart);
            i = j;
            continue;
          }
        }
        final end = metrics.length == 1 ? p.displayEnd : lineStarts[1];
        if (end <= pageStart) {
          i = j + 1;
          continue;
        }
        if (measurePage(end) > maxHeight) {
          // 一页连一行都放不下（上一页已排满）：精确回退，避免死循环。
          if (applyExact(
            _exactPageEnd(layout, key, pageStart, i, maxHeight),
          )) {
            break;
          }
          continue;
        }
        nextPage(end);
        i = end >= p.displayEnd ? j + 1 : j;
        continue;
      }

      if (best >= metrics.length) {
        // 逐段累加低估了页高（整段其实放得下）：本页走精确路径。
        if (applyExact(
          _exactPageEnd(layout, key, pageStart, i, maxHeight),
        )) {
          break;
        }
        continue;
      }

      final end = lineStarts[best];
      if (end <= pageStart) {
        i = j + 1;
        continue;
      }
      // 页尾落定前整页复核一次：逐段相加与整页合并测量若有亚像素差，
      // 宁可退精确路径，也不能让页底裁字。
      if (measurePage(end) > maxHeight) {
        if (applyExact(
          _exactPageEnd(layout, key, pageStart, i, maxHeight),
        )) {
          break;
        }
        continue;
      }
      nextPage(end);
      i = j;
    }

    return Pagination(starts: starts, textLength: text.length);
  }

  /// 精确求一页的页尾（旧实现：每段都用整页高度验证）。
  ///
  /// 只在逐段累加模型与整页测量不一致时兜底，正常情况下不触发。
  static ({int end, int nextIndex}) _exactPageEnd(
    ChapterLayout layout,
    PaginationKey key,
    int pageStart,
    int fromIndex,
    double maxHeight,
  ) {
    final paragraphs = layout.paragraphs;
    double measure(int end) =>
        layout.renderedHeight(pageStart, end, key.width, key.textScale);

    var j = fromIndex;
    while (j < paragraphs.length) {
      final p = paragraphs[j];
      final fragStart = math.max(p.displayStart, pageStart);
      if (fragStart >= p.displayEnd) {
        j++;
        continue;
      }
      if (measure(p.displayEnd) <= maxHeight) {
        j++;
        continue;
      }

      final painter = TextPainter(
        text: TextSpan(
          text: layout.displayText.substring(fragStart, p.displayEnd),
          style: p.style,
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        textScaler: TextScaler.linear(key.textScale),
      )..layout(maxWidth: key.width);
      final metrics = painter.computeLineMetrics();
      if (metrics.isEmpty) {
        painter.dispose();
        j++;
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
        if (measure(end) <= maxHeight) {
          best = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }

      if (best == 0) {
        if (fragStart > pageStart) {
          // 断点取本段的缩进起点（而非缩进后正文起点），下一页 run
          // 才能带上首行缩进。
          final indentStart = paragraphs[j].indentStart;
          if (indentStart > pageStart) {
            return (end: indentStart, nextIndex: j);
          }
        }
        final end = metrics.length == 1 ? p.displayEnd : lineStarts[1];
        if (end <= pageStart) {
          j++;
          continue;
        }
        return (end: end, nextIndex: end >= p.displayEnd ? j + 1 : j);
      }
      if (best >= metrics.length) {
        j++;
        continue;
      }
      final end = lineStarts[best];
      if (end <= pageStart) {
        j++;
        continue;
      }
      return (end: end, nextIndex: j);
    }

    return (end: layout.displayText.length, nextIndex: paragraphs.length);
  }
}

/// renderedHeight 内部用的临时分组。
class _MeasureRun {
  _MeasureRun({
    required this.start,
    required this.end,
    required this.align,
    required this.gap,
  });

  final int start;
  int end;
  final TextAlign align;
  final double gap;
}

