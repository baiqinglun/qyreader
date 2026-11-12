/// 原生阅读面整体渲染：分页高度与实际排版必须一致（不能溢出/裁字）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/data/parsers/epub/epub_parser.dart';
import 'package:qy_reader/features/reader/native/curl_painter.dart';
import 'package:qy_reader/features/reader/native/free_curl_overlay.dart';
import 'package:qy_reader/features/reader/native/native_chapter_source.dart';
import 'package:qy_reader/features/reader/native/native_paginator.dart';
import 'package:qy_reader/features/reader/native/native_reader_view.dart';
import 'package:qy_reader/features/reader/page_turn_sound_player.dart';
import 'package:qy_reader/features/reader/page_layout.dart';
import 'package:qy_reader/features/reader/reader_settings.dart';

NativeChapter _chapter() {
  final paragraphs = <String>[
    for (var i = 0; i < 30; i++)
      '这是第${i + 1}段正文。' * 8,
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

Widget _host(NativeReaderView view) => MaterialApp(
      home: Scaffold(body: view),
    );

void main() {

  testWidgets('单页：分页内容不溢出、不裁掉字', (tester) async {
    final chapter = _chapter();
    await tester.pumpWidget(_host(
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
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('可选中模式（SelectableText）同样不溢出', (tester) async {
    final chapter = _chapter();
    await tester.pumpWidget(_host(
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
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('双页 + 页眉页脚：两栏各自排版，不溢出', (tester) async {
    final chapter = _chapter();
    await tester.pumpWidget(_host(
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
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('第一章 开端'), findsWidgets);
  });

  testWidgets('选中文字不弹系统菜单（阅读页有自己的划线菜单）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(
      NativeReaderView(
        chapters: [_chapter()],
        settings: const ReadingSettings(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        theme: ReadingTheme.paper,
        initialChapterIndex: 0,
        initialOffset: 0,
        onPosition: (_) {},
        onCenterTap: () {},
        onSelection: (_) {},
      ),
    ));
    await tester.pumpAndSettle();

    final selectable = find.byType(SelectableText).first;
    final widget = tester.widget<SelectableText>(selectable);
    expect(widget.contextMenuBuilder, isNotNull, reason: '必须接管系统选区菜单');

    // 接管后的菜单是空盒子：不再叠一层「复制 / 全选」浮层。
    final state = tester.state<EditableTextState>(find.byType(EditableText).first);
    final menu = widget.contextMenuBuilder!(tester.element(selectable), state);
    expect(menu, isA<SizedBox>());
    expect((menu as SizedBox).width, 0);
    expect(menu.height, 0);
  });

  testWidgets('翻页落定响一次音效；打开书不响', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final played = <String>[];
    PageTurnSoundPlayer.debugPlayOverride = (asset) async => played.add(asset);
    addTearDown(() => PageTurnSoundPlayer.debugPlayOverride = null);

    await tester.pumpWidget(_host(
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
    ));
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

    await tester.pumpWidget(_host(
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
    ));
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
        for (var i = 0; i < 30; i++)
          ParsedBlock(text: '甲乙丙丁戊己庚辛壬癸' * 4),
      ],
      fallbackText: '',
    );

    await tester.pumpWidget(_host(
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
    ));
    await tester.pumpAndSettle();

    final editable =
        tester.state<EditableTextState>(find.byType(EditableText).first);
    final box = editable.renderEditable;
    final r1 = box.getLocalRectForCaret(const TextPosition(offset: 1));
    final r2 = box.getLocalRectForCaret(const TextPosition(offset: 2));
    final origin = box.localToGlobal(Offset.zero);
    // 单字中心右偏 18px：旧实现只给 6px 容差，这种「点偏」会没反应。
    final target = origin +
        Offset((r1.left + r2.left) / 2 + 18, r1.center.dy);
    await tester.tapAt(target);
    await tester.pump();

    expect(tapped, ['m1']);
  });

  group('实时预览', _previewCommitTests);

  testWidgets('翻页效果「无」：点右侧瞬间落到下一页，不走 220ms 过渡', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey<NativeReaderViewState>();
    await tester.pumpWidget(_host(
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
    ));
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

  testWidgets('页眉页脚 + SelectableText：正文不溢出、不可内部滚动', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(
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
    ));
    await _pumpUntil(tester, () => find.byType(EditableText).evaluate().isNotEmpty);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);

    final states = tester.stateList<ScrollableState>(find.byType(Scrollable));
    var checked = 0;
    for (final state in states) {
      if (state.position.axis != Axis.vertical) continue;
      checked++;
      expect(
        state.position.maxScrollExtent,
        lessThanOrEqualTo(0.5),
        reason: '正文 run 的可滚动余量必须为 0：有剩余就会页底裁字、且正文能上下滑',
      );
    }
    expect(checked, greaterThan(0), reason: '应至少有一个正文 run');
  });

  testWidgets('翻页沿横轴：视口主轴右向，横滑前进、竖滑不换页', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(
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
    ));
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
    expect(
      pagePosition.pixels,
      closeTo(afterTurn, 0.5),
      reason: '上下滑不应翻页',
    );
  });

  testWidgets('每页自带不透明白底：覆盖/仿真翻页不会透出上一页文字', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(
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
    ));
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

    await tester.pumpWidget(_host(
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
    ));
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

    await tester.pumpWidget(_host(
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
    ));
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

    await tester.pumpWidget(_host(
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
    ));
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
  late ReadingSettings settings =
      const ReadingSettings(fontSize: 18, lineHeight: 1.7);
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
    key.currentState!.preview.value =
        const ReadingSettings(fontSize: 26, lineHeight: 1.7);
    await _pumpUntil(tester, () => state.debugHasPreviewPage);
    expect(state.debugHasPreviewPage, isTrue);
    expect(
      NativePaginator.debugComputeCount,
      0,
      reason: '拖动中不允许全章重排',
    );
    expect(state.debugReflowActive, isFalse);

    // 松手提交：防抖后启动分帧全章重排，完成后回到正式分页
    key.currentState!.commit(const ReadingSettings(fontSize: 26, lineHeight: 1.7));
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
      ..writeAsBytesSync(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
        '/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=',
      ));
    await tester.pumpWidget(_host(
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
    ));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('随手仿真：从右侧中间起手，纸角在落点高度，松手翻页', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final positions = <NativePosition>[];
    await tester.pumpWidget(_host(
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
    ));
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
    await tester.pumpWidget(_host(
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
    ));
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
    await tester.pumpWidget(_host(
      NativeReaderView(
        key: key,
        chapters: [_chapter()],
        settings: const ReadingSettings(pageTurnSound: PageTurnSound.none),
        pageLayout: PageLayoutSettings.defaults
            .withZone(4, TapZoneAction.nextPage),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        theme: ReadingTheme.paper,
        initialChapterIndex: 0,
        initialOffset: 0,
        onPosition: (_) {},
        onCenterTap: () => centerTaps++,
      ),
    ));
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
    await tester.pumpWidget(_host(
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
    ));
    await tester.pumpAndSettle();
    final before = key.currentState!.currentPageOffset;

    await tester.dragFrom(
      const Offset(350, 420),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    expect(key.currentState!.currentPageOffset, isNot(before));
  });
}