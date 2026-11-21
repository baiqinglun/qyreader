/// 原生阅读面整体渲染：分页高度与实际排版必须一致（不能溢出/裁字）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/data/parsers/epub/epub_parser.dart';
import 'package:qy_reader/features/reader/native/curl_painter.dart';
import 'package:qy_reader/features/reader/native/free_curl_overlay.dart';
import 'package:qy_reader/features/reader/native/native_chapter_source.dart';
import 'package:qy_reader/features/reader/native/native_paginator.dart';
import 'package:qy_reader/features/reader/native/native_reader_view.dart';
import 'package:qy_reader/features/reader/native/native_tts_surface.dart';
import 'package:qy_reader/features/reader/page_turn_sound_player.dart';
import 'package:qy_reader/features/reader/page_layout.dart';
import 'package:qy_reader/features/reader/reader_settings.dart';

NativeChapter _chapter() {
  final paragraphs = <String>[
    for (var i = 0; i < 30; i++) '这是第${i + 1}段正文。' * 8,
  ];
  final blocks = <ParsedBlock>[
    const ParsedBlock(text: '第一章 开端', level: 1),
    for (final p in paragraphs) ParsedBlock(text: p),
  ];
  return NativeChapter.fromBlocks(
    idx: 0,
    title: '第一章 开端',
    href: 'c1.xhtml',
    blocks: blocks,
    fallbackText: '',
  );
}

/// 指定章号/段数的多章夹具（每章一个段落块，text 长度可控）。
NativeChapter _chapterAt(int idx, int paragraphCount) {
  final paragraphs = <String>[
    for (var i = 0; i < paragraphCount; i++) '这是第${i + 1}段正文。' * 8,
  ];
  final blocks = <ParsedBlock>[
    const ParsedBlock(text: '章标题', level: 1),
    for (final p in paragraphs) ParsedBlock(text: p),
  ];
  return NativeChapter.fromBlocks(
    idx: idx,
    title: '第${idx + 1}章',
    href: 'c${idx + 1}.xhtml',
    blocks: blocks,
    fallbackText: '',
  );
}

Widget _host(NativeReaderView view) => MaterialApp(home: Scaffold(body: view));

bool _hasUnderline(InlineSpan span) {
  if (span is! TextSpan) return false;
  if (span.style?.decoration == TextDecoration.underline) return true;
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (_hasUnderline(child)) return true;
  }
  return false;
}

void main() {
  testWidgets('恢复章节内偏移时显示对应页面', (tester) async {
    final positions = <NativePosition>[];
    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [_chapter()],
          settings: const ReadingSettings(
            fontSize: 18,
            lineHeight: 1.7,
            paragraphSpacing: 0.4,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 900,
          onPosition: positions.add,
          onCenterTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(positions, isNotEmpty);
    expect(positions.last.page, greaterThan(1));
    expect(positions.last.offset, greaterThan(0));
  });

  testWidgets('单页：分页内容不溢出、不裁掉字', (tester) async {
    final chapter = _chapter();
    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [chapter],
          settings: const ReadingSettings(
            fontSize: 18,
            lineHeight: 1.7,
            paragraphSpacing: 0.4,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('可选中模式同样不溢出', (tester) async {
    final chapter = _chapter();
    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [chapter],
          settings: const ReadingSettings(
            fontSize: 18,
            lineHeight: 1.7,
            paragraphSpacing: 0.4,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () {},
          onSelection: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('双页 + 页眉页脚：两栏各自排版，页眉页脚整屏一份，不溢出', (tester) async {
    final chapter = _chapter();
    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [chapter],
          settings: const ReadingSettings(
            fontSize: 18,
            lineHeight: 1.7,
            doublePage: true,
            headerLeft: RunningContent.chapterName,
            headerRight: RunningContent.chapterPages,
            headerMarginTop: 4,
            footerLeft: RunningContent.bookPercent,
            footerRight: RunningContent.chapterPercent,
            footerMarginBottom: 4,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('第一章 开端'), findsWidgets);
    // 页眉页脚整屏一份：章页码「N/M」与全书进度「0%」都只出现一次
    // （正文是「这是第N段正文。」，不含这两类字符串）。
    expect(find.textContaining(RegExp(r'^\d+/\d+$')), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
  });

  test('全书进度按内容字符量算：长短章不再均摊', () {
    // 短章 100 字符 + 长章 300 字符（单块，text 无分隔符）
    NativeChapter fixed(int idx, int len) => NativeChapter.fromBlocks(
      idx: idx,
      title: '章$idx',
      href: 'c$idx.xhtml',
      blocks: [ParsedBlock(text: '字' * len)],
      fallbackText: '',
    );
    final chapters = [fixed(0, 100), fixed(1, 300)];

    expect(bookCharTotal(chapters), 400);
    expect(bookContentPercent(chapters, 0, 0), 0);
    expect(bookContentPercent(chapters, 0, 100), closeTo(0.25, 1e-9));
    expect(bookContentPercent(chapters, 1, 150), closeTo(0.625, 1e-9));
    // 越界偏移钳到章长
    expect(bookContentPercent(chapters, 1, 999), 1.0);
    expect(bookContentPercent(chapters, 5, 0), 0);

    // 进度拖动反解：与上报口径互逆
    expect(chapterForContentPercent(chapters, 0.25), (0, 100));
    expect(chapterForContentPercent(chapters, 0.5), (1, 100));
    expect(chapterForContentPercent(chapters, 1.0), (1, 300));
    final (idx, offset) = chapterForContentPercent(chapters, 0.4);
    expect(bookContentPercent(chapters, idx, offset), closeTo(0.4, 0.001));
  });

  testWidgets('上报的全书进度按内容字符量算（旧口径是章数均摊 0.5）', (tester) async {
    final tiny = _chapterAt(0, 1);
    final huge = _chapterAt(1, 30);
    NativePosition? reported;
    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [tiny, huge],
          settings: const ReadingSettings(fontSize: 18, lineHeight: 1.7),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 1,
          initialOffset: 0,
          onPosition: (p) => reported = p,
          onCenterTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(reported, isNotNull);
    // 旧口径：(1 + 0) / 2 = 0.5；内容口径 = 短章字符 / 全书字符（很小）
    final total = tiny.text.length + huge.text.length;
    expect(reported!.percent, closeTo(tiny.text.length / total, 1e-6));
    expect(reported!.percent, lessThan(0.2));
  });

  Offset textPoint(
    WidgetTester tester,
    int chapter,
    int page,
    int offset, {
    int run = 0,
  }) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byKey(ValueKey('run-$chapter-$page-$run')),
    );
    final rect = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: offset, extentOffset: offset + 1),
        )
        .first
        .toRect();
    return paragraph.localToGlobal(rect.center);
  }

  testWidgets('按住末端手柄触发翻页，继续选字后松手得到跨页原文', (tester) async {
    tester.view.physicalSize = const Size(390, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chapter = _chapter();
    final positions = <NativePosition>[];
    final selections = <NativeSelection>[];
    var clears = 0;
    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [chapter],
          settings: const ReadingSettings(
            pageTurnMode: PageTurnMode.none,
            pageTurnSound: PageTurnSound.none,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: positions.add,
          onCenterTap: () {},
          onSelection: selections.add,
          onSelectionClear: () => clears++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPressAt(textPoint(tester, 0, 0, 2));
    await tester.pumpAndSettle();
    expect(selections, hasLength(1));
    expect(find.byType(EditableText), findsNothing);
    final initial = selections.single;

    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('selection-handle-end'))),
    );
    await drag.moveTo(const Offset(200, 618));
    await tester.pump(const Duration(milliseconds: 200));
    expect(positions.last.page, 1);
    await drag.moveTo(textPoint(tester, 0, 0, 3));
    await tester.pump(const Duration(milliseconds: 500));
    expect(positions.last.page, 1, reason: '离开边缘应撤销待触发的翻页');

    await drag.moveTo(const Offset(200, 618));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(positions.last.page, 2);
    final nextPageStart = positions.last.offset;
    await tester.pump(const Duration(seconds: 1));
    expect(positions.last.page, 2, reason: '停留在同一处不应连跳多页');
    expect(selections, hasLength(1), reason: '拖动中不应重新弹出菜单');
    expect(clears, 2);

    await drag.moveTo(textPoint(tester, 0, 1, 45));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(selections, hasLength(2));
    final selection = selections.last;
    expect(selection.start, initial.start);
    expect(selection.end, greaterThan(nextPageStart));
    expect(
      selection.text,
      chapter.text.substring(selection.start, selection.end).trim(),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('手柄拖过章尾后可继续选中下一章文字', (tester) async {
    tester.view.physicalSize = const Size(390, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final first = _chapterAt(0, 1);
    final second = _chapterAt(1, 2);
    final positions = <NativePosition>[];
    final selections = <NativeSelection>[];
    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [first, second],
          settings: const ReadingSettings(pageTurnSound: PageTurnSound.none),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: positions.add,
          onCenterTap: () {},
          onSelection: selections.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(positions.last.pages, 1);
    await tester.longPressAt(textPoint(tester, 0, 0, 1));
    await tester.pumpAndSettle();
    final initial = selections.single;

    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('selection-handle-end'))),
    );
    await drag.moveTo(const Offset(388, 300));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(positions.last.chapterIndex, 1);
    await drag.moveTo(textPoint(tester, 1, 0, 8, run: 1));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    final selection = selections.last;
    expect(selection.chapterIndex, 0);
    expect(selection.endChapterIndex, 1);
    expect(selection.start, initial.start);
    expect(selection.end, greaterThan(0));
    expect(
      selection.text,
      '${first.text.substring(selection.start)}\n${second.text.substring(0, selection.end)}'
          .trim(),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('双页向前翻后可拖起点手柄回翻上一屏', (tester) async {
    tester.view.physicalSize = const Size(780, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chapter = _chapter();
    final key = GlobalKey<NativeReaderViewState>();
    final positions = <NativePosition>[];
    final selections = <NativeSelection>[];
    await tester.pumpWidget(
      _host(
        NativeReaderView(
          key: key,
          chapters: [chapter],
          settings: const ReadingSettings(
            doublePage: true,
            pageTurnMode: PageTurnMode.none,
            pageTurnSound: PageTurnSound.none,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: positions.add,
          onCenterTap: () {},
          onSelection: selections.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    key.currentState!.nextPage();
    await tester.pumpAndSettle();
    expect(positions.last.page, 3);
    final secondSpreadStart = positions.last.offset;
    await tester.longPressAt(textPoint(tester, 0, 2, 20));
    await tester.pumpAndSettle();
    final initial = selections.single;

    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('selection-handle-start'))),
    );
    await drag.moveTo(const Offset(2, 300));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(positions.last.page, 1);
    await drag.moveTo(textPoint(tester, 0, 1, 50));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(selections, hasLength(2));
    final selection = selections.last;
    expect(selection.start, lessThan(secondSpreadStart));
    expect(selection.end, initial.end);
    expect(
      selection.text,
      chapter.text.substring(selection.start, selection.end).trim(),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('翻页落定响一次音效；打开书不响', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final played = <String>[];
    PageTurnSoundPlayer.debugPlayOverride = (asset) async => played.add(asset);
    addTearDown(() => PageTurnSoundPlayer.debugPlayOverride = null);

    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [_chapter()],
          settings: const ReadingSettings(pageTurnSound: PageTurnSound.second),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(played, isEmpty, reason: '打开书（定位跳页）不应该响');

    await tester.tapAt(const Offset(370, 420)); // 右侧三分之一：下一页
    await tester.pumpAndSettle();

    expect(played, hasLength(1));
    expect(played.single, contains('page_turn_2'));
  });

  testWidgets('音效「无」：翻页不响', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final played = <String>[];
    PageTurnSoundPlayer.debugPlayOverride = (asset) async => played.add(asset);
    addTearDown(() => PageTurnSoundPlayer.debugPlayOverride = null);

    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [_chapter()],
          settings: const ReadingSettings(pageTurnSound: PageTurnSound.none),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(370, 420));
    await tester.pumpAndSettle();

    expect(played, isEmpty);
  });

  testWidgets('单个字划线：点偏一点也能打开笔记', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final tapped = <String>[];
    final chapter = NativeChapter.fromBlocks(
      idx: 0,
      title: '无标题',
      href: 'c0.xhtml',
      blocks: <ParsedBlock>[
        for (var i = 0; i < 30; i++) ParsedBlock(text: '甲乙丙丁戊己庚辛壬癸' * 4),
      ],
      fallbackText: '',
    );

    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [chapter],
          settings: const ReadingSettings(
            fontSize: 18,
            lineHeight: 1.7,
            paragraphSpacing: 0,
            bodyIndent: ParagraphIndent.none,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          marks: const [
            NativeMark(
              id: 'm1',
              chapterIndex: 0,
              start: 1,
              end: 2,
              color: Color(0xFFFFEB3B),
            ),
          ],
          onMarkTap: (m) => tapped.add(m.id),
          onSelection: (_) {},
          onPosition: (_) {},
          onCenterTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 单字中心右偏 18px：旧实现只给 6px 容差，这种「点偏」会没反应。
    final target = textPoint(tester, 0, 0, 1) + const Offset(18, 0);
    await tester.tapAt(target);
    await tester.pump();

    expect(tapped, ['m1']);
  });

  testWidgets('下划线标注：画下划线而不是整块底色', (tester) async {
    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [_chapter()],
          settings: const ReadingSettings(
            fontSize: 18,
            lineHeight: 1.7,
            paragraphSpacing: 0,
            bodyIndent: ParagraphIndent.none,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          marks: const [
            NativeMark(
              id: 'u1',
              chapterIndex: 0,
              start: 0,
              end: 4,
              color: Color(0xFF2F6FD0),
              underline: true,
            ),
          ],
          onPosition: (_) {},
          onCenterTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    expect(richTexts.any((w) => _hasUnderline(w.text)), isTrue);
  });

  group('实时预览', _previewCommitTests);

  testWidgets('翻页效果「无」：点右侧瞬间落到下一页，不走 220ms 过渡', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey<NativeReaderViewState>();
    await tester.pumpWidget(
      _host(
        NativeReaderView(
          key: key,
          chapters: [_chapter()],
          settings: const ReadingSettings(pageTurnMode: PageTurnMode.none),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = key.currentState!.currentPageOffset;
    await tester.tapAt(const Offset(370, 420)); // 右侧三分之一：下一页
    // 只给一帧：动画模式下这时还停在过渡里，页位不会变。
    await tester.pump();

    expect(
      key.currentState!.currentPageOffset,
      isNot(before),
      reason: '「无」效果要瞬间换页，不能留滑动动画',
    );
  });

  testWidgets('页眉页脚 + 可选中正文：正文不溢出、不可内部滚动', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [_chapter()],
          settings: const ReadingSettings(
            fontSize: 22,
            lineHeight: 1.7,
            paragraphSpacing: 1.0,
            headerLeft: RunningContent.time,
            headerCenter: RunningContent.chapterName,
            headerRight: RunningContent.chapterPercent,
            footerCenter: RunningContent.bookPercent,
            footerRight: RunningContent.bookPages,
            headerFontSize: 10,
            headerMarginTop: 6,
            footerMarginBottom: 6,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () {},
          onSelection: (_) {},
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.byKey(const ValueKey('run-0-0-0')).evaluate().isNotEmpty,
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);

    expect(
      tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .map((state) => state.position.axis),
      [Axis.horizontal],
    );
  });

  testWidgets('翻页沿横轴：视口主轴右向，横滑前进、竖滑不换页', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [_chapter()],
          settings: const ReadingSettings(fontSize: 18, lineHeight: 1.7),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () {},
        ),
      ),
    );
    final state = tester.state<NativeReaderViewState>(
      find.byType(NativeReaderView),
    );
    await _pumpUntil(tester, () => !state.debugReflowActive);
    await tester.pumpAndSettle();

    final viewport = tester.widget<Viewport>(find.byType(Viewport).first);
    expect(
      viewport.axisDirection,
      AxisDirection.right,
      reason: 'Viewport 主轴默认是 down；漏传会把页面竖排，表现为「左右滑、上下翻」',
    );

    final pagePosition = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .map((s) => s.position)
        .firstWhere((p) => p.axis == Axis.horizontal);

    final before = pagePosition.pixels;
    await tester.dragFrom(const Offset(300, 400), const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(
      pagePosition.pixels,
      greaterThan(before + 1),
      reason: '手指从右往左滑应翻到下一页（横向位移）',
    );

    final afterTurn = pagePosition.pixels;
    await tester.dragFrom(const Offset(200, 400), const Offset(0, -280));
    await tester.pumpAndSettle();
    expect(pagePosition.pixels, closeTo(afterTurn, 0.5), reason: '上下滑不应翻页');
  });

  testWidgets('每页自带不透明白底：覆盖/仿真翻页不会透出上一页文字', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [_chapter()],
          settings: const ReadingSettings(
            fontSize: 18,
            lineHeight: 1.7,
            pageTurnMode: PageTurnMode.curl,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boxes = tester.widgetList<ColoredBox>(
      find.descendant(
        of: find.byType(NativeReaderView),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(
      boxes.any((b) => b.color == ReadingTheme.paper.background),
      isTrue,
      reason: '每个翻页单元要有纸色底，否则新页盖上来时旧页文字会透出来',
    );
  });

  testWidgets('随手仿真：拖起时盖出折页层，松手收起', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [_chapter()],
          settings: const ReadingSettings(
            fontSize: 18,
            lineHeight: 1.7,
            pageTurnMode: PageTurnMode.freeCurl,
            pageTurnSound: PageTurnSound.none,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () {},
        ),
      ),
    );
    final state = tester.state<NativeReaderViewState>(
      find.byType(NativeReaderView),
    );
    await _pumpUntil(tester, () => !state.debugReflowActive);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(300, 600));
    await gesture.moveBy(const Offset(-40, -20));
    await tester.pump(const Duration(milliseconds: 32));
    expect(find.byType(FreeCurlOverlay), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(FreeCurlOverlay), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('仿真翻页：拖动照常横向推进，折角层不抛异常', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [_chapter()],
          settings: const ReadingSettings(
            fontSize: 18,
            lineHeight: 1.7,
            pageTurnMode: PageTurnMode.curl,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () {},
        ),
      ),
    );
    final state = tester.state<NativeReaderViewState>(
      find.byType(NativeReaderView),
    );
    await _pumpUntil(tester, () => !state.debugReflowActive);
    await tester.pumpAndSettle();

    final pagePosition = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .map((s) => s.position)
        .firstWhere((p) => p.axis == Axis.horizontal);

    final before = pagePosition.pixels;
    await tester.dragFrom(const Offset(300, 400), const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(pagePosition.pixels, greaterThan(before + 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('仿真翻页：拖动中会挂出折角绘制层', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [_chapter()],
          settings: const ReadingSettings(
            fontSize: 18,
            lineHeight: 1.7,
            pageTurnMode: PageTurnMode.curl,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () {},
        ),
      ),
    );
    final state = tester.state<NativeReaderViewState>(
      find.byType(NativeReaderView),
    );
    await _pumpUntil(tester, () => !state.debugReflowActive);
    await tester.pumpAndSettle();

    bool hasCurlLayer() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .any((w) => w.painter is CurlTurnPainter);

    final gesture = await tester.startGesture(const Offset(300, 400));
    await gesture.moveBy(const Offset(-80, 0));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(hasCurlLayer(), isTrue, reason: '拖动中应出现折角层（背面纹理）');

    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(hasCurlLayer(), isFalse, reason: '松手落定后折角层要收掉');
    expect(tester.takeException(), isNull);
  });
}

/// 拖动预览 → 松手提交 的宿主：预览走 ValueNotifier，不重建整页。
class _PreviewHost extends StatefulWidget {
  const _PreviewHost({super.key, required this.chapter});

  final NativeChapter chapter;

  @override
  State<_PreviewHost> createState() => _PreviewHostState();
}

class _PreviewHostState extends State<_PreviewHost> {
  late ReadingSettings settings = const ReadingSettings(
    fontSize: 18,
    lineHeight: 1.7,
  );
  final ValueNotifier<ReadingSettings?> preview = ValueNotifier(null);

  void commit(ReadingSettings next) {
    setState(() => settings = next);
    preview.value = null;
  }

  @override
  void dispose() {
    preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: NativeReaderView(
          chapters: [widget.chapter],
          settings: settings,
          previewListenable: preview,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () {},
        ),
      ),
    );
  }
}

/// 等待异步分帧任务推进（测试环境用 pump 推进计时器）。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int maxPumps = 400,
}) async {
  for (var i = 0; i < maxPumps && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void _previewCommitTests() {
  testWidgets('拖动只排当前页；松手后分帧全章重排', (tester) async {
    final chapter = _chapter();
    final key = GlobalKey<_PreviewHostState>();
    await tester.pumpWidget(_PreviewHost(key: key, chapter: chapter));
    final state = tester.state<NativeReaderViewState>(
      find.byType(NativeReaderView),
    );

    // 首屏预览页先出来，再等首次全章分帧完成
    await _pumpUntil(tester, () => state.debugHasPreviewPage);
    await _pumpUntil(tester, () => !state.debugReflowActive);

    NativePaginator.debugComputeCount = 0;
    key.currentState!.preview.value = const ReadingSettings(
      fontSize: 26,
      lineHeight: 1.7,
    );
    await _pumpUntil(tester, () => state.debugHasPreviewPage);
    expect(state.debugHasPreviewPage, isTrue);
    expect(NativePaginator.debugComputeCount, 0, reason: '拖动中不允许全章重排');
    expect(state.debugReflowActive, isFalse);

    // 松手提交：防抖后启动分帧全章重排，完成后回到正式分页
    key.currentState!.commit(
      const ReadingSettings(fontSize: 26, lineHeight: 1.7),
    );
    await _pumpUntil(
      tester,
      () => NativePaginator.debugComputeCount > 0 && !state.debugReflowActive,
    );
    expect(NativePaginator.debugComputeCount, greaterThan(0));
    expect(state.debugHasPreviewPage, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自定义背景图：铺到纸面上且不溢出', (tester) async {
    final dir = Directory.systemTemp.createTempSync('qy-bg-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/bg.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
          '/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=',
        ),
      );
    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [_chapter()],
          settings: const ReadingSettings(
            fontSize: 18,
            lineHeight: 1.7,
            paragraphSpacing: 0.4,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          backgroundImage: file.path,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsWidgets);
    expect(tester.widget<Image>(find.byType(Image).first).fit, BoxFit.cover);
    expect(tester.takeException(), isNull);
  });

  testWidgets('背景图缩放方式：五种模式映射到对应 BoxFit', (tester) async {
    final dir = Directory.systemTemp.createTempSync('qy-bg-fit-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/bg.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
          '/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=',
        ),
      );
    const expected = <BackgroundImageFit, BoxFit>{
      BackgroundImageFit.cover: BoxFit.cover,
      BackgroundImageFit.contain: BoxFit.contain,
      BackgroundImageFit.fill: BoxFit.fill,
      BackgroundImageFit.fitWidth: BoxFit.fitWidth,
      BackgroundImageFit.fitHeight: BoxFit.fitHeight,
    };
    for (final entry in expected.entries) {
      await tester.pumpWidget(
        _host(
          NativeReaderView(
            key: ValueKey(entry.key),
            chapters: [_chapter()],
            settings: const ReadingSettings(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            theme: ReadingTheme.paper,
            backgroundImage: file.path,
            backgroundFit: entry.key,
            initialChapterIndex: 0,
            initialOffset: 0,
            onPosition: (_) {},
            onCenterTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Image>(find.byType(Image).first).fit,
        entry.value,
        reason: entry.key.name,
      );
    }
  });

  testWidgets('随手仿真：从右侧中间起手，纸角在落点高度，松手翻页', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final positions = <NativePosition>[];
    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [_chapter()],
          settings: const ReadingSettings(
            fontSize: 18,
            lineHeight: 1.7,
            pageTurnMode: PageTurnMode.freeCurl,
            pageTurnSound: PageTurnSound.none,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: positions.add,
          onCenterTap: () {},
        ),
      ),
    );
    final state = tester.state<NativeReaderViewState>(
      find.byType(NativeReaderView),
    );
    await _pumpUntil(tester, () => !state.debugReflowActive);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(380, 420));
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump(const Duration(milliseconds: 32));

    final overlay = tester.widget<FreeCurlOverlay>(
      find.byType(FreeCurlOverlay),
    );
    expect(overlay.frame.value!.corner.dx, 390);
    expect(overlay.frame.value!.corner.dy, 420);
    final scrollable = tester.widget<Scrollable>(find.byType(Scrollable).first);
    expect(scrollable.physics, isA<NeverScrollableScrollPhysics>());

    await gesture.moveBy(const Offset(-220, 0));
    await tester.pump(const Duration(milliseconds: 32));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(FreeCurlOverlay), findsNothing);
    expect(positions.last.page, greaterThan(1));
  });

  testWidgets('随手仿真：点击右侧直接跳页，不走滑动', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final positions = <NativePosition>[];
    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [_chapter()],
          settings: const ReadingSettings(
            fontSize: 18,
            lineHeight: 1.7,
            pageTurnMode: PageTurnMode.freeCurl,
            pageTurnSound: PageTurnSound.none,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: positions.add,
          onCenterTap: () {},
        ),
      ),
    );
    final state = tester.state<NativeReaderViewState>(
      find.byType(NativeReaderView),
    );
    await _pumpUntil(tester, () => !state.debugReflowActive);
    await tester.pumpAndSettle();
    final before = positions.last.page;

    await tester.tapAt(const Offset(350, 400));
    await tester.pump();

    // freeCurl 下是 jumpTo，不是 220ms 滑动，一帧后就已到下一页。
    expect(positions.last.page, before + 1);
  });

  testWidgets('页面布局：中间区域设为下一页，点击中间不打开菜单', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var centerTaps = 0;
    final key = GlobalKey<NativeReaderViewState>();
    await tester.pumpWidget(
      _host(
        NativeReaderView(
          key: key,
          chapters: [_chapter()],
          settings: const ReadingSettings(pageTurnSound: PageTurnSound.none),
          pageLayout: PageLayoutSettings.defaults.withZone(
            4,
            TapZoneAction.nextPage,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () => centerTaps++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = key.currentState!.currentPageOffset;

    await tester.tapAt(const Offset(195, 420));
    await tester.pumpAndSettle();

    expect(key.currentState!.currentPageOffset, isNot(before));
    expect(centerTaps, 0);
  });

  testWidgets('翻页效果「无」也能拖动滑动翻页', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey<NativeReaderViewState>();
    await tester.pumpWidget(
      _host(
        NativeReaderView(
          key: key,
          chapters: [_chapter()],
          settings: const ReadingSettings(
            pageTurnMode: PageTurnMode.none,
            pageTurnSound: PageTurnSound.none,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = key.currentState!.currentPageOffset;

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final pixels = position.pixels;
    final gesture = await tester.startGesture(const Offset(350, 420));
    await gesture.moveBy(const Offset(-300, 0));
    await tester.pump();
    expect(position.pixels, pixels);
    await gesture.up();
    await tester.pump();
    expect(key.currentState!.currentPageOffset, isNot(before));
  });
  testWidgets('isOffsetVisible：页内偏移可见，他页/他章不可见（TTS 定位按钮）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final chapter1 = _chapter();
    final chapter2 = NativeChapter.fromBlocks(
      idx: 1,
      title: '第2章',
      href: 'c2.xhtml',
      blocks: const [ParsedBlock(text: '另一章的正文内容。', level: 0)],
      fallbackText: '',
    );
    final key = GlobalKey<NativeReaderViewState>();
    await tester.pumpWidget(
      _host(
        NativeReaderView(
          key: key,
          chapters: [chapter1, chapter2],
          settings: const ReadingSettings(fontSize: 18, lineHeight: 1.7),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final view = key.currentState!;
    expect(view.currentChapter, 0);
    // 当前页首偏移可见；他章不可见
    final pageStart = view.currentPageOffset;
    expect(view.isOffsetVisible(0, pageStart), isTrue);
    expect(view.isOffsetVisible(1, 0), isFalse);

    // 跳到章末所在页：页首偏移不再可见，章末偏移可见
    final endOffset = chapter1.text.length - 1;
    view.jumpToOffset(endOffset);
    await tester.pumpAndSettle();
    expect(view.isOffsetVisible(0, pageStart), isFalse);
    expect(view.isOffsetVisible(0, endOffset), isTrue);
  });

  testWidgets('TTS 朗读高亮：段首句不含缩进字符（零宽锚/NBSP）', (tester) async {
    final chapter = NativeChapter.fromBlocks(
      idx: 0,
      title: '章',
      href: 'c.xhtml',
      blocks: const [ParsedBlock(text: '　　第一句话。后面内容。', level: 0)],
      fallbackText: '',
    );
    await tester.pumpWidget(
      _host(
        NativeReaderView(
          chapters: [chapter],
          settings: const ReadingSettings(fontSize: 18, lineHeight: 1.7),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () {},
          ttsHighlight: ValueNotifier(
            const TtsHighlight(chapterIndex: 0, start: 0, end: 5),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bgSpans = <String>[];
    void walk(InlineSpan span) {
      if (span is TextSpan) {
        if (span.style?.backgroundColor != null) {
          bgSpans.add(span.toPlainText());
        }
        span.children?.forEach(walk);
      }
    }

    for (final r in tester.widgetList<RichText>(find.byType(RichText))) {
      walk(r.text);
    }
    // 高亮落在段首句上：带背景的 span 都不能含缩进字符
    expect(bgSpans, isNotEmpty);
    for (final s in bgSpans) {
      expect(
        s.codeUnits.any((c) => c == 0xFEFF || c == 0x00A0 || c == 0x3000),
        isFalse,
        reason: '高亮 span 含缩进字符: $s',
      );
    }
  });
}
