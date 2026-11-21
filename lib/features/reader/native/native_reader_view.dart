/// 原生文本阅读面：段落级排版（标题/正文）、页眉页脚、单双页。
///
/// 与 WebView 方案的区别：
/// - 正文是 Flutter 原生文本，不存在“全屏平台视图”；
/// - 翻页是 `PageView` 的图层变换（跟手、可回弹）；
/// - 分页由 `NativePaginator` 用 `TextPainter` 事先算好，翻页时零计算。
///
/// 章节切换用「哨兵页」实现：当前章的第一页前面接上一章末页、最后一页后面
/// 接下一章首页。落到哨兵页时立刻切章并跳到对应的真实页，视觉上是连续的，
/// 不会出现“翻到章末就撞墙”。
///
/// 对齐与选择：Flutter 的一段文本只能有一个 `TextAlign`，所以一页里按
/// 「连续同对齐的段落」拆成若干段（run）分别渲染。正文段落之间仍然共享
/// 同一个 run。选区由阅读视口保存，可跨越版式分段和分页边界。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/reading_theme.dart';
import '../page_turn_sound_player.dart';
import '../page_layout.dart';
import '../reader_settings.dart';
import 'curl_geometry.dart';
import 'curl_painter.dart';
import 'free_curl_geometry.dart';
import 'free_curl_overlay.dart';
import 'native_chapter_source.dart';
import 'native_paginator.dart';
import 'native_tts_surface.dart';

/// 一条划线在本章内的字符区间（原生渲染用）。
class NativeMark {
  const NativeMark({
    required this.id,
    required this.chapterIndex,
    required this.start,
    required this.end,
    required this.color,
    this.underline = false,
  });

  /// 标注 id（点按/编辑用）。
  final String id;

  /// 章序号。
  final int chapterIndex;

  /// 起点（章内字符偏移）。
  final int start;

  /// 终点（不含）。
  final int end;

  /// 底色（已含透明度）；下划线类型时作为下划线颜色。
  final Color color;

  /// true = 下划线（只画线、不铺底色）。
  final bool underline;
}

/// 原生正文的文本选择（长按选字）。
class NativeSelection {
  const NativeSelection({
    required this.chapterIndex,
    required this.start,
    required this.end,
    int? endChapterIndex,
    required this.text,
    required this.anchor,
  }) : endChapterIndex = endChapterIndex ?? chapterIndex;

  /// 章序号。
  final int chapterIndex;

  /// 起点（章内字符偏移）。
  final int start;

  /// 终点所在章。
  final int endChapterIndex;

  /// 终点（终点章内的字符偏移，不含）。
  final int end;

  bool get spansChapters => chapterIndex != endChapterIndex;

  /// 选中文字。
  final String text;

  /// 菜单锚点（全局坐标，取长按位置）。
  final Offset anchor;
}

typedef _SelectionPoint = ({int chapter, int offset});

int _comparePoints(_SelectionPoint a, _SelectionPoint b) =>
    a.chapter == b.chapter
    ? a.offset.compareTo(b.offset)
    : a.chapter.compareTo(b.chapter);

/// 阅读位置（原生模式）。
class NativePosition {
  const NativePosition({
    required this.chapterIndex,
    required this.page,
    required this.pages,
    required this.offset,
    required this.percent,
  });

  /// 章序号（0 基）。
  final int chapterIndex;

  /// 章内页码（1 基）。
  final int page;

  /// 本章总页数。
  final int pages;

  /// 本页起始字符偏移（章内）。
  final int offset;

  /// 全书百分比 0..1。
  final double percent;
}

/// 实时预览的一页（只渲染当前页，不触发全章分页）。
class PreviewPageData {
  const PreviewPageData({
    required this.chapterIdx,
    required this.layout,
    required this.start,
    required this.end,
    required this.page,
    required this.pages,
    required this.headerH,
    required this.footerH,
    required this.width,
    required this.scale,
    required this.settings,
    required this.stretch,
  });

  final int chapterIdx;
  final ChapterLayout layout;
  final int start;
  final int end;
  final int page;
  final int pages;
  final double headerH;
  final double footerH;
  final double width;
  final double scale;
  final ReadingSettings settings;

  /// 纵向撑满系数（装箱零头摊进行距/段距；1 = 不撑）。
  final double stretch;
}

/// 全书进度按**内容字符量**算（v2.48.0）。
///
/// 旧口径按「章序号 / 章数」均摊：长章短章一视同仁，进度与实际读到的
/// 内容对不上（一章顶半本书的书，读完整章进度才走 10%）。这里统一用
/// 字符量：前面章节的字符 + 当前章内偏移，除以全书字符。
/// 章内偏移是章内字符坐标（`ChapterLayout.chapterOfDisplay`）。

/// 全书字符总量。
int bookCharTotal(List<NativeChapter> chapters) {
  var total = 0;
  for (final c in chapters) {
    total += c.text.length;
  }
  return total;
}

/// 全书进度（0..1）：按内容字符量。越界坐标按章长钳制。
double bookContentPercent(
  List<NativeChapter> chapters,
  int chapterIdx,
  int chapterOffset,
) {
  if (chapters.isEmpty || chapterIdx < 0 || chapterIdx >= chapters.length) {
    return 0;
  }
  var before = 0;
  for (var i = 0; i < chapterIdx; i++) {
    before += chapters[i].text.length;
  }
  final total = bookCharTotal(chapters);
  if (total <= 0) return 0;
  final local = chapterOffset.clamp(0, chapters[chapterIdx].text.length);
  return ((before + local) / total).clamp(0.0, 1.0);
}

/// 全书进度 → 落点（章索引, 章内字符偏移）：进度拖动跳转与
/// [bookContentPercent] 同口径，拖到哪就落在内容对应的位置。
(int, int) chapterForContentPercent(List<NativeChapter> chapters, double v) {
  final target = (v.clamp(0.0, 1.0) * bookCharTotal(chapters)).round();
  var before = 0;
  for (var i = 0; i < chapters.length; i++) {
    final len = chapters[i].text.length;
    if (before + len >= target || i == chapters.length - 1) {
      final local = (target - before).clamp(0, len);
      return (i, local);
    }
    before += len;
  }
  return (0, 0);
}

/// 原生文本阅读视图。
class NativeReaderView extends StatefulWidget {
  const NativeReaderView({
    required this.chapters,
    required this.settings,
    this.previewSettings,
    this.previewListenable,
    this.marginPreviewListenable,
    required this.padding,
    required this.theme,
    this.backgroundImage = '',
    this.backgroundFit = BackgroundImageFit.cover,
    required this.initialChapterIndex,
    required this.initialOffset,
    required this.onPosition,
    required this.onCenterTap,
    this.bookPercent = 0,
    this.ttsHighlight,
    this.marks = const [],
    this.pageLayout = const PageLayoutSettings(),
    this.onSelection,
    this.onSelectionClear,
    this.onMarkTap,
    super.key,
  });

  /// 章节文本。
  final List<NativeChapter> chapters;

  /// 已提交的排版设置。
  final ReadingSettings settings;

  /// 拖动排版滑杆时的实时预览设置（不落库）。
  ///
  /// 非空时只排当前页（毫秒级），松手后再由上层提交设置、触发全章分帧重排。
  final ReadingSettings? previewSettings;

  /// 拖动中的预览通道（直接监听，避免每帧重建整棵阅读页）。
  final ValueListenable<ReadingSettings?>? previewListenable;

  /// 边距直调模式的实时预览（正文/页眉/页脚边距）。
  ///
  /// 与 [previewListenable] 分开：边距变化会改变页眉/页脚带高与正文区尺寸，
  /// 需要走 setState 让 build 重新计算版心，再调度当前页预览。
  final ValueListenable<ReadingSettings?>? marginPreviewListenable;

  /// 左右留白（水平安全区，外层已扣）。
  ///
  /// v2.38.3 起页眉/页脚边距不再叠加垂直安全区：上下方向完全由页眉上边距 /
  /// 页脚下边距决定，这里只承担水平留白；正文上下边距分别计入页眉/页脚带
  /// （见 _runningHeight）。
  final EdgeInsets padding;

  /// 阅读主题。
  final ReadingTheme theme;

  /// 自定义阅读背景图（应用内文件路径）；空 = 纯色纸面。
  final String backgroundImage;

  /// 背景图的缩放 / 拉伸方式。
  final BackgroundImageFit backgroundFit;

  /// 打开时的章序号。
  final int initialChapterIndex;

  /// 打开时的章内字符偏移。
  final int initialOffset;

  /// 位置变化回调（翻页 / 切章）。
  final ValueChanged<NativePosition> onPosition;

  /// 点击正文中间区域（切换 chrome）。
  final VoidCallback onCenterTap;

  /// 页面布局（九宫格 + 页眉/页脚点击区域）。
  final PageLayoutSettings pageLayout;

  /// 全书进度（页眉页脚「全文进度」用）。
  final double bookPercent;

  /// 当前朗读句的高亮区间（原生 TTS 用；null = 不高亮）。
  final ValueNotifier<TtsHighlight?>? ttsHighlight;

  /// 本章（及其它章）的划线区间；渲染时按章过滤。
  final List<NativeMark> marks;

  /// 选字完成回调（停顿后才触发，避免拖手柄时菜单乱跳）。
  final ValueChanged<NativeSelection>? onSelection;

  /// 选字进行中或正文取消选中时先收起菜单。
  final VoidCallback? onSelectionClear;

  /// 点击已有划线（弹操作面板：改颜色 / 加想法 / 删除）。
  final ValueChanged<NativeMark>? onMarkTap;

  @override
  State<NativeReaderView> createState() => NativeReaderViewState();
}

/// 供外部（目录跳转 / 进度拖动）驱动的状态。
class NativeReaderViewState extends State<NativeReaderView>
    with SingleTickerProviderStateMixin {
  final NativePaginator _paginator = NativePaginator();
  final PageController _pc = PageController();
  int _chapterIdx = 0;
  Pagination? _pagination;

  /// 实时预览页（非空时只画这一页，不跑全章分页）。
  PreviewPageData? _previewPage;

  /// 当前预览设置（来自 previewSettings 或 previewListenable）。
  ReadingSettings? _livePreview;

  /// 边距直调模式的实时预览设置（正文/页眉/页脚边距）。
  ReadingSettings? _liveMarginPreview;

  /// 最近一次布局几何（预览按它排当前页）。
  Size? _lastSize;
  double _lastScale = 1;
  double _lastHeaderH = 0;
  double _lastFooterH = 0;

  /// 设备像素密度（build 时刷新）：渲染逐行取整误差按物理像素走，
  /// 装箱余量与撑满系数都要按它放大。
  double _dpr = 3;

  /// 页面区域刷新记号（预览页/分帧结果只重建页面区域）。
  final ValueNotifier<int> _pageRevision = ValueNotifier<int>(0);

  // ---- 折页翻页（PageTurnMode.curl）----

  /// 阅读面尺寸（build 里刷新，折页几何用）。
  Size? _curlPageSize;

  /// 本段拖动的起始页（小数），用来算折叠进度。
  double? _curlStartPage;

  /// 折页叠加层的当前帧（null = 不画）。
  final ValueNotifier<CurlRenderState?> _curlFrame =
      ValueNotifier<CurlRenderState?>(null);

  // ---- 随手仿真（PageTurnMode.freeCurl）----

  /// 当前随手折页几何（null = 未折起）。
  final ValueNotifier<FreeCurlGeometry?> _freeCurlFrame =
      ValueNotifier<FreeCurlGeometry?>(null);

  /// 拖动开始时的 pointer 位置（局部坐标）。
  Offset? _freeCurlDown;

  /// 本次拖动的方向（null = 还没判断出来）。
  bool? _freeCurlForward;

  /// 本次折页的纸角（按手指落点选上/下角）。
  Offset? _freeCurlCorner;

  /// 松手后要翻到的页索引。
  int? _freeCurlTargetIndex;

  /// 松手后的收尾动画（翻过去 / 弹回去）。
  late final AnimationController _freeCurlSettle;
  bool _freeCurlSettling = false;
  bool _freeCurlCommit = false;
  Offset? _freeCurlSettleFrom;
  Offset? _freeCurlSettleTo;
  double _freeCurlLastX = 0;

  /// 是否在等待/进行随手折页（pointer down 到 up）。
  bool _freeCurlArmed = false;

  /// 盖在滚动区上的两页（鼠标按下后按当前分页即时构建）。
  Widget? _freeCurlOldPage;
  Widget? _freeCurlNewPage;

  /// 按 sliver index 构建整页（build 里刷新），供随手折页现场取页。
  Widget Function(int index)? _spreadBuilder;

  /// `_pagination` 对应的章序号（-1 = 未计算）。
  int _paginationChapter = -1;

  /// 当前章的排版结果（含段落样式与坐标映射）。
  ChapterLayout? _layout;

  /// 排版缓存（当前章 + 前后章，避免哨兵页每帧重排）。
  final Map<int, ChapterLayout> _layoutCache = {};
  int _layoutCacheSignature = 0;

  /// 上次分页用的版式签名（只看行数/行高；换主题不必重排）。
  int _paginationSignature = 0;

  /// 上次分页用的版心尺寸/缩放。
  Size _layoutSize = Size.zero;
  double _layoutScale = 1;

  /// 最近一次 build 的翻页上下文（自定义视口的页变化监听用）。
  ({
    Pagination pag,
    ReaderTypeSpec spec,
    double columnWidth,
    double bodyHeight,
    double scale,
  })?
  _turnCtx;

  /// 最近上报过的页索引（-1 = 尚未初始化）。
  int _lastReportedPage = -1;

  /// 程序化跳页（目录 / 续读 / 重排定位）期间不响翻页音效。
  bool _suppressTurnSound = false;

  /// 划线命中容差（逻辑像素）：单字划线只有 ~18px 宽，手指偏一点也该点得中。
  static const double _markHitSlop = 20;

  /// 端行补偿字距缓存：key = hash(章, run 区间, 版心宽, 缩放, 字体签名)。
  /// 页面每帧重建都会走到 _runSpans，按 key 复用避免重复排版。
  final Map<int, List<_RunJustify>> _runJustifyCache = {};

  /// 最近一次位置回报（重排后回到这里）。
  int _lastOffset = 0;
  bool _everReported = false;

  // 选区生命周期属于整个视口，翻页不销毁正在拖动的手柄。
  final _selectionViewport = GlobalKey();
  final _selectionRuns = <_SelectionRunState>{};
  final _selectionHandles = ValueNotifier<(Offset?, Offset?)>((null, null));
  _SelectionPoint? _selectionStart;
  _SelectionPoint? _selectionEnd;
  bool _selectingFromBody = false;
  bool _mouseSelecting = false;
  _SelectionPoint? _bodySelectionStart;
  _SelectionPoint? _bodySelectionEnd;
  int? _handlePointer;
  bool _draggingStart = false;
  Offset _handleDragOffset = Offset.zero;
  Offset? _handlePointerPosition;
  Timer? _selectionTurnTimer;
  int _selectionEdge = 0;

  bool get _hasSelection => _selectionStart != null;

  /// 选字时暂停朗读跟页，防止正文跳转中断手势。
  bool get isSelectingText => _hasSelection;

  /// 点击判定：按下位置与时间（区分点击 / 拖动翻页）。
  Offset _downAt = Offset.zero;
  DateTime _downTime = DateTime.now();

  bool _pendingJump = false;
  int _pendingPage = 0;
  int _offsetForPending = 0;

  /// 电量（页眉页脚用；null = 未知）。
  int? _battery;

  /// 时间/电量刷新的定时器。
  Timer? _clockTimer;

  /// 当前章序号。
  int get chapterIndex => _chapterIdx;

  /// 当前章序号（供 TTS 适配层读取）。
  int get currentChapter => _chapterIdx;

  /// 当前页首字符偏移（供 TTS「从当前页开始读」）。
  int get currentPageOffset {
    final pag = _pagination;
    final layout = _layout;
    if (pag == null || layout == null || pag.starts.isEmpty) return 0;
    final (start, _) = pag.rangeOf(_currentPage(pag));
    return layout.chapterOfDisplay(start);
  }

  /// 章内偏移是否落在当前可见页（双页取同屏两页；TTS「定位」按钮用）。
  bool isOffsetVisible(int chapterIdx, int offset) {
    if (chapterIdx != _chapterIdx) return false;
    final pag = _pagination;
    final layout = _layout;
    if (pag == null || layout == null || pag.starts.isEmpty) return false;
    if (!_pc.hasClients) return false;
    final raw = _pc.page?.round() ?? 0;
    final spread = (raw - _leadingSentinels).clamp(0, _spreadCount(pag) - 1);
    final display = layout.displayOfChapter(offset);
    for (var k = 0; k < _pagesPerView; k++) {
      final page = (spread * _pagesPerView + k).clamp(0, pag.pageCount - 1);
      final (start, end) = pag.rangeOf(page);
      if (display >= start && display < end) return true;
    }
    return false;
  }

  /// 清掉正文选区（创建或取消划线后调用）。
  void clearTextSelection() {
    if (!_hasSelection) return;
    _selectionStart = null;
    _selectionEnd = null;
    _selectingFromBody = false;
    _bodySelectionStart = null;
    _bodySelectionEnd = null;
    _handlePointer = null;
    _handlePointerPosition = null;
    _cancelSelectionTurn();
    _selectionHandles.value = (null, null);
    _bumpPage();
  }

  void _dismissTextSelection() {
    if (!_hasSelection) return;
    clearTextSelection();
    widget.onSelectionClear?.call();
  }

  /// 下一页（键盘/无障碍/外部按钮用）。
  void nextPage() {
    _dismissTextSelection();
    _animateTo((_pc.hasClients ? _pc.page!.round() : 0) + 1);
  }

  /// 上一页。
  void previousPage() {
    _dismissTextSelection();
    _animateTo((_pc.hasClients ? _pc.page!.round() : 0) - 1);
  }

  /// 跳到本章指定字符偏移所在页（TTS 跟读 / 精确恢复用）。
  void jumpToOffset(int offset) {
    _dismissTextSelection();
    final pag = _pagination;
    final layout = _layout;
    if (pag == null || layout == null || !_pc.hasClients) return;
    final page = pag.pageOfOffset(layout.displayOfChapter(offset));
    // TTS 跟读 / 精确恢复的跳页不算用户翻页：静音。
    _suppressTurnSound = true;
    _pc.jumpToPage(_spreadOf(page) + _leadingSentinels);
    _suppressTurnSound = false;
    _report(pag, page);
  }

  /// 跳到指定章（目录/进度用）。[offset] 为章内字符偏移。
  void jumpToChapter(int chapterIdx, {int offset = 0}) {
    _dismissTextSelection();
    final maxIdx = math.max(0, widget.chapters.length - 1);
    final idx = chapterIdx.clamp(0, maxIdx).toInt();
    _cancelReflow();
    _previewPage = null;
    _previewRequest = null;
    _previewKey = null;
    setState(() {
      _chapterIdx = idx;
      _pendingJump = true;
      _pendingPage = -1; // -1 = 按 offset 换算
      _offsetForPending = offset;
    });
  }

  /// 每屏页数（单双页）。
  int get _pagesPerView => widget.settings.doublePage ? 2 : 1;

  /// 第 [page] 页所在的翻页项（单页 = page；双页 = 第几屏）。
  int _spreadOf(int page) => page ~/ _pagesPerView;

  @override
  void initState() {
    super.initState();
    _livePreview = widget.previewSettings ?? widget.previewListenable?.value;
    widget.previewListenable?.addListener(_onLivePreviewChanged);
    _liveMarginPreview = widget.marginPreviewListenable?.value;
    widget.marginPreviewListenable?.addListener(_onMarginPreviewChanged);
    _pc.addListener(_onScrollPageChanged);
    _pc.addListener(_onCurlTick);
    final maxIdx = math.max(0, widget.chapters.length - 1);
    _chapterIdx = widget.initialChapterIndex.clamp(0, maxIdx).toInt();
    _offsetForPending = widget.initialOffset;
    if (widget.initialOffset > 0) {
      _pendingJump = true;
      _pendingPage = -1;
    }
    _clockTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      if (_needsClock || _needsBattery) setState(() {});
      if (_needsBattery) unawaited(_refreshBattery());
    });
    unawaited(_refreshBattery());
    _freeCurlSettle =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 190),
          )
          ..addListener(_onFreeCurlSettleTick)
          ..addStatusListener(_onFreeCurlSettleStatus);
  }

  bool get _needsClock => _anySlot(widget.settings, RunningContent.time);

  bool get _needsBattery => _anySlot(widget.settings, RunningContent.battery);

  @override
  void dispose() {
    widget.previewListenable?.removeListener(_onLivePreviewChanged);
    widget.marginPreviewListenable?.removeListener(_onMarginPreviewChanged);
    _selectionTurnTimer?.cancel();
    _selectionHandles.dispose();
    _clockTimer?.cancel();
    _reflowDebounce?.cancel();
    _reflowToken++;
    _curlFrame.dispose();
    _freeCurlFrame.dispose();
    _freeCurlSettle.dispose();
    _pc.dispose();
    _pageRevision.dispose();
    super.dispose();
  }

  Future<void> _refreshBattery() async {
    if (!_needsBattery) return;
    try {
      final level = await const MethodChannel(
        'qyreader/battery',
      ).invokeMethod<int>('level');
      if (!mounted) return;
      if (level != _battery) setState(() => _battery = level);
    } on MissingPluginException {
      // 桌面/测试环境没有实现：页眉显示 --
    } catch (_) {}
  }

  bool _headerVisible(ReadingSettings s) =>
      s.headerLeft != RunningContent.none ||
      s.headerCenter != RunningContent.none ||
      s.headerRight != RunningContent.none;

  bool _footerVisible(ReadingSettings s) =>
      s.footerLeft != RunningContent.none ||
      s.footerCenter != RunningContent.none ||
      s.footerRight != RunningContent.none;

  static bool _anySlot(ReadingSettings s, RunningContent c) =>
      s.headerLeft == c ||
      s.headerCenter == c ||
      s.headerRight == c ||
      s.footerLeft == c ||
      s.footerCenter == c ||
      s.footerRight == c;

  /// 页眉/页脚带高度（与渲染处保持一致）。带紧贴文字：
  ///
  /// - 页眉带 = 页眉上边距 + 页眉文字，**带底 = 页眉文字底部**
  ///   （正文的顶边与它在同一条线上）；
  /// - 页脚带 = 页脚文字 + 页脚下边距，**带顶 = 页脚文字顶部**
  ///   （正文的底边与它在同一条线上）。
  /// - 正文上/下边距在正文区内部：分别是「正文文字顶部距页眉文字
  ///   底部」「正文文字底部距页脚文字顶部」的距离（见 _pageContent 与
  ///   build 的 textAreaH）。
  ///
  /// 页眉/页脚边距是**绝对边距**：从屏幕顶/底算起，不再叠加系统安全区
  /// （v2.38.3 按用户要求去掉；会不会贴到挖孔/手势条由用户边距自己决定）。
  double _runningHeight({
    required bool header,
    required double scale,
    required ReadingSettings settings,
  }) {
    final s = settings;
    final visible = header ? _headerVisible(s) : _footerVisible(s);
    final edgeInset = header ? s.headerMarginTop : s.footerMarginBottom;
    final textH = visible ? s.headerFontSize * scale * 1.5 : 0.0;
    return edgeInset + textH;
  }

  /// 纵向撑满系数：把装箱留下的页底零头（下一行塞不下的空隙 + 防裁字
  /// 余量）按比例摊到整页的行距/段距上，正文填满文字区（下边距之前）。
  ///
  /// 行距不影响断行（换行只由宽度决定），页内容不变、选择/TTS 映射不变。
  /// 限幅 1.35：稀疏页（章末、只有一两行）不无限拉行距；0.999 兜住
  /// 亚像素取整，避免撑出一帧裁切。
  double _stretchFor(
    double pageHeight,
    double bodyExpanded,
    double lineHeight,
  ) {
    if (pageHeight <= 0 || bodyExpanded <= 0) return 1;
    // 拉伸系数必须除以「估计渲染高度」而不是测量高度：EditableText 逐行
    // 取整后的实际渲染比 TextPainter 报告高（~0.65 物理 px/行，随 dpr
    // 缩放）。若按测量高度放大，这点误差会被一起乘进去，排满的页刚好
    // 溢出页底几像素（测试实测 4.6~9px；真机《十扇窗》页尾孤行被裁）。
    // 除以估计渲染高度后，撑满的结果正好等于目标高度（含误差）。
    final lines = lineHeight > 0 ? pageHeight / lineHeight : 0.0;
    final renderEstimate = pageHeight + lines * 0.75 * _dpr;
    final k = bodyExpanded / renderEstimate;
    if (k <= 1) return 1;
    return math.min(k * 0.999, 1.35);
  }

  int _currentPage(Pagination pag) {
    if (!_pc.hasClients) return 0;
    final raw = _pc.page?.round() ?? 0;
    final spread = (raw - _leadingSentinels).clamp(0, _spreadCount(pag) - 1);
    return (spread * _pagesPerView).clamp(0, pag.pageCount - 1);
  }

  bool get _hasPrev => _chapterIdx > 0;
  bool get _hasNext => _chapterIdx < widget.chapters.length - 1;
  int get _leadingSentinels => _hasPrev ? 1 : 0;

  int _spreadCount(Pagination pag) =>
      (pag.pageCount / _pagesPerView).ceil().clamp(1, 1 << 30);

  /// 取某章的排版（带缓存；版式变化时整体失效）。
  ChapterLayout _layoutOf(int chapterIdx, ReaderTypeSpec spec) {
    if (_layoutCacheSignature != spec.signature) {
      _layoutCache.clear();
      _layoutCacheSignature = spec.signature;
    }
    final cached = _layoutCache[chapterIdx];
    if (cached != null) return cached;
    if (_layoutCache.length > 8) _layoutCache.clear();
    final layout = ChapterLayout.build(
      chapter: widget.chapters[chapterIdx],
      spec: spec,
    );
    _layoutCache[chapterIdx] = layout;
    return layout;
  }

  ({ChapterLayout layout, Pagination pagination}) _pageOfChapter(
    int chapterIdx,
    ReaderTypeSpec spec,
    double width,
    double height,
    double scale,
  ) {
    final layout = _layoutOf(chapterIdx, spec);
    final key = PaginationKey(
      chapterIdx: chapterIdx,
      width: width,
      height: height,
      textScale: scale,
      signature: spec.metricsSignature,
    );
    return (
      layout: layout,
      pagination: _paginator.paginate(key: key, layout: layout),
    );
  }

  @override
  void didUpdateWidget(covariant NativeReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.previewListenable != widget.previewListenable) {
      oldWidget.previewListenable?.removeListener(_onLivePreviewChanged);
      widget.previewListenable?.addListener(_onLivePreviewChanged);
      _livePreview = widget.previewListenable?.value ?? widget.previewSettings;
      _onLivePreviewSourceChanged();
    } else if (oldWidget.previewSettings != widget.previewSettings) {
      _livePreview = widget.previewSettings ?? widget.previewListenable?.value;
      _onLivePreviewSourceChanged();
    }
    if (oldWidget.marginPreviewListenable != widget.marginPreviewListenable) {
      oldWidget.marginPreviewListenable?.removeListener(
        _onMarginPreviewChanged,
      );
      widget.marginPreviewListenable?.addListener(_onMarginPreviewChanged);
      _liveMarginPreview = widget.marginPreviewListenable?.value;
      // 预览通道换绑后按新值重算版心。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  /// 边距直调预览：边距会改变页眉/页脚带高与正文版心，必须重建
  /// LayoutBuilder 让 `textAreaH`/`size` 重新算，再走预览页刷新。
  void _onMarginPreviewChanged() {
    final next = widget.marginPreviewListenable?.value;
    if (next == _liveMarginPreview) return;
    if (!mounted) return;
    setState(() => _liveMarginPreview = next);
  }

  void _onLivePreviewChanged() {
    final next = widget.previewListenable?.value ?? widget.previewSettings;
    if (next == _livePreview) return;
    _livePreview = next;
    _onLivePreviewSourceChanged();
  }

  void _onLivePreviewSourceChanged() {
    final preview = _livePreview;
    if (preview != null) {
      final size = _lastSize;
      if (size == null) return; // 首帧还没量到版心，build 会调度
      final spec = ReaderTypeSpec.fromSettings(preview, widget.theme);
      final lineHeight =
          (spec.bodyStyle.fontSize ?? 16) * (spec.bodyStyle.height ?? 1.2);
      _schedulePreview(
        preview,
        spec,
        size,
        _lastScale,
        _lastHeaderH,
        _lastFooterH,
        // 与 build 的 bodyExpanded 同口径：装箱上限 + 半行余量。
        size.height + lineHeight * 0.5,
      );
    }
    // 预览结束（value=null）不在这里撤页：等 build 用提交后的设置算出
    // 新预览页再替换，避免先闪回旧排版。面板关闭时由外部调
    // clearLivePreview() 立即撤掉。
  }

  /// 诊断（测试用）：当前是否显示实时预览页。
  bool get debugHasPreviewPage => _previewPage != null;

  /// 诊断（测试用）：是否在分帧重排。
  bool get debugReflowActive => _reflowRunning || _reflowPending;

  /// 立即撤掉实时预览页（面板关闭且未提交时用）。
  void clearLivePreview() {
    _previewPage = null;
    _previewRequest = null;
    _previewKey = null;
    _bumpPage();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.chapters.isEmpty) {
      return Center(
        child: Text(
          '这本书没有可显示的正文',
          style: TextStyle(color: widget.theme.foreground),
        ),
      );
    }
    final preview = _livePreview;
    final marginPreview = _liveMarginPreview;
    final effective = preview ?? marginPreview ?? widget.settings;
    final spec = ReaderTypeSpec.fromSettings(effective, widget.theme);
    final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
    // 渲染取整误差按设备像素密度走（逐行向上取整到物理像素，
    // 平均 ~0.5~0.7 物理 px/行），拉伸与装箱余量都要用它。
    _dpr = View.of(context).devicePixelRatio;
    final headerH = _runningHeight(
      header: true,
      scale: scale,
      settings: effective,
    );
    final footerH = _runningHeight(
      header: false,
      scale: scale,
      settings: effective,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = (constraints.maxWidth - widget.padding.horizontal)
            .clamp(1.0, 1e6);
        final gutter = effective.doublePage ? 20.0 : 0.0;
        final columnWidth = effective.doublePage
            ? ((contentWidth - gutter) / 2).clamp(80.0, 1e6)
            : contentWidth;
        // 正文文字区高度 = 总高 − 页眉带 − 页脚带 − 正文上下边距。
        // 正文上下边距在正文区内部：上边距 = 正文文字顶部到页眉文字
        // 底部（带交界线）的距离，下边距对称。
        // 装箱上限 = 版心 − 半行 − 渲染取整余量：真机 CJK 字体逐行取整
        // 会让实际渲染比 TextPainter 测量略高（~0.65 物理 px/行，随 dpr
        // 缩放），不留余量的话排满的页最后一行会被页底裁掉半截
        // （实测《十扇窗》页尾孤行被裁）。
        final lineHeight =
            (spec.bodyStyle.fontSize ?? 16) * (spec.bodyStyle.height ?? 1.2);
        final textAreaH =
            (constraints.maxHeight -
                    headerH -
                    footerH -
                    effective.marginTop -
                    effective.marginBottom)
                .clamp(40.0, 1e6);
        final renderSlack =
            textAreaH / lineHeight * 0.75 * _dpr + lineHeight * 0.5;
        final bodyHeight = (textAreaH - renderSlack).clamp(40.0, 1e6);
        final size = Size(columnWidth, bodyHeight);
        _lastSize = size;
        _lastScale = scale;
        _lastHeaderH = headerH;
        _lastFooterH = footerH;

        // 拖动滑杆 / 边距直调：只排当前页（预览），不触发全章。
        final previewForPage = preview ?? marginPreview;
        if (previewForPage != null) {
          _schedulePreview(
            previewForPage,
            spec,
            size,
            scale,
            headerH,
            footerH,
            textAreaH,
          );
        } else {
          final stale =
              _pagination == null ||
              _paginationChapter != _chapterIdx ||
              _layoutSize != size ||
              _layoutScale != scale ||
              _paginationSignature != spec.metricsSignature;
          if (stale) {
            // 先把当前页按新设置画出来，再防抖后全章分帧重排。
            _schedulePreview(
              widget.settings,
              spec,
              size,
              scale,
              headerH,
              footerH,
              textAreaH,
            );
            _scheduleReflow(
              widget.settings,
              spec,
              size,
              scale,
              immediate: _pagination == null,
            );
          } else {
            _clearPreview();
            _cancelReflow();
          }
        }

        // 页面内容走 ValueNotifier：预览页 / 分帧分页结果只刷新这一块。
        return ValueListenableBuilder<int>(
          valueListenable: _pageRevision,
          builder: (context, _, __) {
            final previewPage = _previewPage;
            if (previewPage != null) {
              // 双页模式只预览左栏，右栏留白（版心宽度按单栏算）；
              // 页眉页脚整屏一份（页码按预览页口径）。
              if (previewPage.settings.doublePage) {
                final ctx = _PageCtx(
                  chapterIndex: previewPage.chapterIdx,
                  page: previewPage.page,
                  pages: previewPage.pages,
                  chapterTitle: previewPage.layout.chapter.title,
                  bookPercent: widget.bookPercent,
                );
                return _spreadFrame(
                  left: _pageBody(
                    previewPage.chapterIdx,
                    previewPage.layout,
                    previewPage.start,
                    previewPage.end,
                    previewPage.page,
                    previewPage.width,
                    previewPage.scale,
                    previewPage.settings,
                    stretch: previewPage.stretch,
                  ),
                  right: _blankPage(),
                  gutter: 20,
                  headerBand: _runningBand(
                    header: true,
                    ctx: ctx,
                    settings: previewPage.settings,
                    height: previewPage.headerH,
                  ),
                  footerBand: _runningBand(
                    header: false,
                    ctx: ctx,
                    settings: previewPage.settings,
                    height: previewPage.footerH,
                  ),
                );
              }
              final content = _pageContent(
                previewPage.chapterIdx,
                previewPage.layout,
                previewPage.start,
                previewPage.end,
                previewPage.page,
                previewPage.pages,
                previewPage.headerH,
                previewPage.footerH,
                previewPage.width,
                previewPage.scale,
                previewPage.settings,
                stretch: previewPage.stretch,
              );
              return _spreadFrame(left: content, right: null, gutter: 0);
            }

            final pag = _pagination;
            if (pag == null || _layout == null) {
              return _PageBackground(
                color: widget.theme.background,
                imagePath: widget.backgroundImage,
                fit: widget.backgroundFit,
              );
            }
            final spreads = _spreadCount(pag);
            final itemCount = spreads + (_hasPrev ? 1 : 0) + (_hasNext ? 1 : 0);
            if (_pendingJump) _scheduleJump(pag);

            final mode = effective.pageTurnMode;
            // 记录本次 build 的翻页上下文：位置监听器（预构建相邻页的
            // 自定义视口没有 onPageChanged）在页越界时据此上报。
            _turnCtx = (
              pag: pag,
              spec: spec,
              columnWidth: columnWidth,
              bodyHeight: bodyHeight,
              scale: scale,
            );
            if (_lastReportedPage < 0) _lastReportedPage = _leadingSentinels;
            // 折页几何只需要阅读面尺寸，不再截图（纸背用纯纸色）。
            _curlPageSize = Size(constraints.maxWidth, constraints.maxHeight);
            // 随手仿真：手指开始拖时现场构建当前页/下一页，盖在滚动区上。
            _spreadBuilder = (index) => _buildSpread(
              index,
              pag,
              spec,
              columnWidth,
              bodyHeight,
              scale,
              gutter,
              headerH,
              footerH,
              textAreaH,
            );
            if (_hasSelection) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _syncSelectionHandles();
              });
            }
            return Stack(
              key: _selectionViewport,
              fit: StackFit.expand,
              children: [
                Listener(
                  onPointerDown: (e) {
                    _downAt = e.position;
                    _downTime = DateTime.now();
                    _selectingFromBody = false;
                    _mouseSelecting = false;
                    if (!_hasSelection) _onFreeCurlDown(e);
                  },
                  onPointerMove: (e) {
                    if (widget.onSelection != null &&
                        e.kind == PointerDeviceKind.mouse &&
                        e.buttons == kPrimaryMouseButton &&
                        (e.position - _downAt).distance >= 6) {
                      if (!_selectingFromBody) _startTextSelection(_downAt);
                      if (_selectingFromBody) {
                        _mouseSelecting = true;
                        _extendBodySelection(e.position);
                        return;
                      }
                    }
                    _onFreeCurlMove(e);
                  },
                  onPointerCancel: (_) {
                    _resetFreeCurl();
                    if (_selectingFromBody) _dismissTextSelection();
                  },
                  onPointerUp: (e) {
                    _endFreeCurl();
                    if (_selectingFromBody) {
                      if (_mouseSelecting) _publishTextSelection(e.position);
                      return;
                    }
                    final delta = e.position - _downAt;
                    if (mode == PageTurnMode.none &&
                        !_hasSelection &&
                        delta.dx.abs() > 50 &&
                        delta.dx.abs() > delta.dy.abs()) {
                      if (delta.dx < 0) {
                        nextPage();
                      } else {
                        previousPage();
                      }
                      return;
                    }
                    final moved = (e.position - _downAt).distance;
                    final dt = DateTime.now().difference(_downTime);
                    if (moved > 14 || dt > const Duration(milliseconds: 450)) {
                      return;
                    }
                    _handleTap(e.localPosition, constraints, pag);
                  },
                  // 与 PageView 同构的自定义横向视口，但 cacheExtent = 一页：
                  // 相邻页在空闲帧就完成构建（分页/排版/对齐补偿），翻页拖动
                  // 全程只有滚动合成，不再有「拖到一半才建新页」的掉帧尖峰
                  // （实测 build P95 12ms 来自拖动中途的整页构建）。
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onLongPressStart: widget.onSelection == null
                        ? null
                        : (details) {
                            if (!_selectingFromBody) {
                              _startTextSelection(details.globalPosition);
                            }
                          },
                    onLongPressMoveUpdate: widget.onSelection == null
                        ? null
                        : (details) =>
                              _extendBodySelection(details.globalPosition),
                    onLongPressEnd: widget.onSelection == null
                        ? null
                        : (details) {
                            if (_selectingFromBody && !_mouseSelecting) {
                              _publishTextSelection(details.globalPosition);
                            }
                          },
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScrollNotification,
                      child: Scrollable(
                        controller: _pc,
                        axisDirection: AxisDirection.right,
                        // 长按与横滑竞争时，滚动仍从按下的位置开始。
                        dragStartBehavior: widget.onSelection == null
                            ? DragStartBehavior.start
                            : DragStartBehavior.down,
                        // 「无」通过抬手手势瞬间翻页，不让页面跟手滑动。
                        // 有选区时，只有手柄到达边缘才推进分页。
                        physics:
                            mode == PageTurnMode.freeCurl ||
                                mode == PageTurnMode.none ||
                                _freeCurlArmed ||
                                _freeCurlSettling ||
                                _hasSelection
                            ? const NeverScrollableScrollPhysics()
                            : const PageScrollPhysics(
                                parent: ClampingScrollPhysics(),
                              ),
                        viewportBuilder: (context, position) => Viewport(
                          // 视口主轴必须和 Scrollable 显式对齐：Viewport 的
                          // axisDirection 默认是 AxisDirection.down，漏掉它
                          // sliver 会竖向排列、而滚动手势走横向——表现就是
                          // 「左右滑，页面上下翻」。
                          axisDirection: AxisDirection.right,
                          // 预构建前后两页：翻页目标页在空闲时已就绪，拖动全程
                          // 纯滚动合成（单页缓存会让「下一页的下一页」在拖动
                          // 开始的帧里现建）。
                          cacheExtent: constraints.maxWidth * 2,
                          offset: position,
                          slivers: [
                            SliverFillViewport(
                              viewportFraction: 1,
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final content = _buildSpread(
                                  index,
                                  pag,
                                  spec,
                                  columnWidth,
                                  bodyHeight,
                                  scale,
                                  gutter,
                                  headerH,
                                  footerH,
                                  textAreaH,
                                );
                                return AnimatedBuilder(
                                  animation: _pc,
                                  child: content,
                                  builder: (context, child) => _applyTurnEffect(
                                    index,
                                    constraints.maxWidth,
                                    child!,
                                  ),
                                );
                              }, childCount: itemCount),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // 折角叠加层：纸张背面压在新页之上，所以必须画在滚动区外面。
                ValueListenableBuilder<CurlRenderState?>(
                  valueListenable: _curlFrame,
                  builder: (context, frame, _) {
                    if (frame == null) return const SizedBox.shrink();
                    return IgnorePointer(
                      child: CustomPaint(
                        painter: CurlTurnPainter(frame),
                        size: Size.infinite,
                      ),
                    );
                  },
                ),
                // 随手仿真：盖住滚动区，用真实页面现场裁剪/镜像。
                if (_freeCurlOldPage != null && _freeCurlNewPage != null)
                  Positioned.fill(
                    child: FreeCurlOverlay(
                      oldPage: _freeCurlOldPage!,
                      newPage: _freeCurlNewPage!,
                      frame: _freeCurlFrame,
                      background: widget.theme.background,
                    ),
                  ),
                Positioned.fill(
                  child: Listener(
                    onPointerDown: _beginSelectionHandle,
                    onPointerMove: _moveSelectionHandle,
                    onPointerUp: _endSelectionHandle,
                    onPointerCancel: _endSelectionHandle,
                    child: ValueListenableBuilder<(Offset?, Offset?)>(
                      valueListenable: _selectionHandles,
                      builder: (context, handles, _) => Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (handles.$1 case final start?)
                            _selectionHandle(
                              start,
                              leading: true,
                              size: _curlPageSize!,
                            ),
                          if (handles.$2 case final end?)
                            _selectionHandle(
                              end,
                              leading: false,
                              size: _curlPageSize!,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---- 实时预览 / 分帧重排 ----

  /// 页面内容刷新记号：预览页与分帧分页结果只刷新页面区域。
  void _bumpPage() {
    if (mounted) _pageRevision.value++;
  }

  /// 预览页请求（同一帧多次请求只跑最后一次）。
  ({
    ReadingSettings settings,
    ReaderTypeSpec spec,
    Size size,
    double scale,
    double headerH,
    double footerH,
    double bodyExpanded,
  })?
  _previewRequest;
  bool _previewScheduled = false;
  int? _previewKey;

  void _schedulePreview(
    ReadingSettings settings,
    ReaderTypeSpec spec,
    Size size,
    double scale,
    double headerH,
    double footerH,
    double bodyExpanded,
  ) {
    final key = Object.hash(
      settings,
      size,
      scale,
      _chapterIdx,
      _anchorChapterOffset(),
    );
    if (_previewKey == key && _previewPage != null) return;
    _previewKey = key;
    _previewRequest = (
      settings: settings,
      spec: spec,
      size: size,
      scale: scale,
      headerH: headerH,
      footerH: footerH,
      bodyExpanded: bodyExpanded,
    );
    if (_previewScheduled) return;
    _previewScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _previewScheduled = false;
      if (!mounted) return;
      final request = _previewRequest;
      if (request == null) return;
      _previewRequest = null;
      final page = _computePreviewPage(
        request.settings,
        request.spec,
        request.size,
        request.scale,
        request.headerH,
        request.footerH,
        request.bodyExpanded,
      );
      if (!mounted || page == null) return;
      _previewPage = page;
      _bumpPage();
    });
  }

  /// 只排「当前阅读位置所在的一页」。
  PreviewPageData? _computePreviewPage(
    ReadingSettings settings,
    ReaderTypeSpec spec,
    Size size,
    double scale,
    double headerH,
    double footerH,
    double bodyExpanded,
  ) {
    if (_chapterIdx < 0 || _chapterIdx >= widget.chapters.length) return null;
    final total = Stopwatch()..start();
    final layout = _layoutOf(_chapterIdx, spec);
    final layoutUs = total.elapsedMicroseconds;
    final measurement = _paginator.measurementFor(
      layout: layout,
      chapterIdx: _chapterIdx,
      width: size.width,
      textScale: scale,
    );
    var display = layout.displayOfChapter(_anchorChapterOffset());
    display = layout.snapPageStart(display);
    final anchor = _snapDisplayToLine(layout, measurement, display);
    final packed = measurement.packPageExact(
      layout: layout,
      startDisplay: anchor.start,
      startIndex: anchor.index,
      maxHeight: size.height,
      width: size.width,
      textScale: scale,
    );
    final (page, pages) = _pageNumbersFor(anchor.start);
    debugPreviewCount++;
    debugPreviewLayoutUs += layoutUs;
    debugPreviewTotalUs += total.elapsedMicroseconds;
    return PreviewPageData(
      chapterIdx: _chapterIdx,
      layout: layout,
      start: anchor.start,
      end: packed.end,
      page: page,
      pages: pages,
      headerH: headerH,
      footerH: footerH,
      width: size.width,
      scale: scale,
      settings: settings,
      stretch: _stretchFor(
        packed.height,
        bodyExpanded,
        (spec.bodyStyle.fontSize ?? 16) * (spec.bodyStyle.height ?? 1.2),
      ),
    );
  }

  /// 显示偏移吸附到行首（避免预览从一行中间开始）。
  ({int start, int index}) _snapDisplayToLine(
    ChapterLayout layout,
    ChapterMeasurement measurement,
    int display,
  ) {
    final paragraphs = layout.paragraphs;
    if (paragraphs.isEmpty) return (start: 0, index: 0);
    var lo = 0;
    var hi = paragraphs.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (paragraphs[mid].displayEnd > display) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    final index = lo.clamp(0, paragraphs.length - 1);
    final paragraph = paragraphs[index];
    // 锚点落在段距占位/缩进里：从这一段的缩进起点起页（带缩进）。
    if (display <= paragraph.indentStart) {
      return (start: paragraph.indentStart, index: index);
    }
    // 行首以缩进起点为基准（测量已带上缩进字符，见
    // ParagraphMeasurement.lineStarts）。
    final local = (display - paragraph.indentStart).clamp(
      0,
      paragraph.displayEnd - paragraph.indentStart,
    );
    final m = measurement.ensure(layout, index);
    final line = m.lineIndexOf(local);
    // 首行同样从缩进起点起页。
    if (line == 0) {
      return (start: paragraph.indentStart, index: index);
    }
    final start = paragraph.indentStart + m.lineStarts[line];
    return (start: start, index: index);
  }

  /// 诊断：实时预览页的计算次数/总耗时/其中布局耗时（基准用）。
  static int debugPreviewCount = 0;
  static int debugPreviewTotalUs = 0;
  static int debugPreviewLayoutUs = 0;
  static int debugReflowCount = 0;

  /// 当前阅读位置（章内字符偏移）。
  int _anchorChapterOffset() =>
      _everReported ? _lastOffset : widget.initialOffset;

  /// 预览页的页码：沿用当前正式分页里的页码（避免拖动时页码乱跳）。
  (int, int) _pageNumbersFor(int display) {
    final pag = _pagination;
    if (pag != null && _paginationChapter == _chapterIdx) {
      final page = pag.pageOfOffset(display).clamp(0, pag.pageCount - 1);
      return (page + 1, pag.pageCount);
    }
    return (1, 1);
  }

  Timer? _reflowDebounce;
  int _reflowToken = 0;
  int? _reflowKey;
  bool _reflowRunning = false;
  bool _reflowPending = false;

  /// 防抖后启动全章分帧重排（松手/翻页/旋转等）。
  void _scheduleReflow(
    ReadingSettings settings,
    ReaderTypeSpec spec,
    Size size,
    double scale, {
    required bool immediate,
  }) {
    final key = Object.hash(_chapterIdx, size, scale, spec.signature);
    if (_reflowRunning && _reflowKey == key) return;
    if (_reflowPending && _reflowKey == key) return;
    // 版式又变了：让在跑的任务作废，避免用旧结果覆盖新设置。
    if (_reflowRunning && _reflowKey != key) {
      _reflowToken++;
      _reflowRunning = false;
    }
    _reflowKey = key;
    _reflowPending = true;
    _reflowDebounce?.cancel();
    void start() {
      _reflowPending = false;
      if (!mounted) return;
      _startReflow(settings, spec, size, scale);
    }

    if (immediate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => start());
    } else {
      _reflowDebounce = Timer(const Duration(milliseconds: 120), () => start());
    }
  }

  void _cancelReflow() {
    _reflowDebounce?.cancel();
    _reflowDebounce = null;
    if (_reflowRunning || _reflowPending) _reflowToken++;
    _reflowRunning = false;
    _reflowPending = false;
    _reflowKey = null;
  }

  void _clearPreview() {
    if (_previewPage == null && _previewRequest == null) return;
    _previewPage = null;
    _previewRequest = null;
    _previewKey = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pageRevision.value++;
    });
  }

  void _startReflow(
    ReadingSettings settings,
    ReaderTypeSpec spec,
    Size size,
    double scale,
  ) {
    final layout = _layoutOf(_chapterIdx, spec);
    final key = PaginationKey(
      chapterIdx: _chapterIdx,
      width: size.width,
      height: size.height,
      textScale: scale,
      signature: spec.metricsSignature,
    );
    final cached = _paginator.cached(key);
    if (cached != null) {
      _publishPagination(cached, layout, spec, size, scale);
      return;
    }
    final measurement = _paginator.measurementFor(
      layout: layout,
      chapterIdx: _chapterIdx,
      width: size.width,
      textScale: scale,
    );
    final task = PaginationTask(
      paginator: _paginator,
      layout: layout,
      key: key,
      measurement: measurement,
    );
    final token = ++_reflowToken;
    _reflowRunning = true;
    final anchor = _anchorChapterOffset();
    unawaited(_runReflow(token, task, layout, spec, size, scale, anchor));
  }

  Future<void> _runReflow(
    int token,
    PaginationTask task,
    ChapterLayout layout,
    ReaderTypeSpec spec,
    Size size,
    double scale,
    int anchor,
  ) async {
    while (!task.done) {
      task.advance(const Duration(milliseconds: 4));
      if (!mounted || token != _reflowToken) return;
      if (!task.done) {
        // 让出事件循环：测/装一片，画一帧，不长时间占住 UI 线程。
        await Future<void>.delayed(const Duration(milliseconds: 1));
        if (!mounted || token != _reflowToken) return;
      }
    }
    if (!mounted || token != _reflowToken) return;
    final result = task.result;
    _reflowRunning = false;
    if (result == null) return;
    _publishPagination(result, layout, spec, size, scale, anchor: anchor);
  }

  void _publishPagination(
    Pagination pagination,
    ChapterLayout layout,
    ReaderTypeSpec spec,
    Size size,
    double scale, {
    int? anchor,
  }) {
    _layout = layout;
    _pagination = pagination;
    _paginationChapter = _chapterIdx;
    _layoutSize = size;
    _layoutScale = scale;
    _paginationSignature = spec.metricsSignature;
    _pendingJump = true;
    _pendingPage = -1;
    _offsetForPending = anchor ?? _anchorChapterOffset();
    // 正在拖动时不撤预览页（否则松手前会闪回已提交排版一帧）。
    if (_livePreview == null) {
      _previewPage = null;
      _previewRequest = null;
      _previewKey = null;
    }
    debugReflowCount++;
    // 页码切换交给页面区域重建后的 _scheduleJump（此时 PageView 有 clients）。
    _bumpPage();
  }

  /// 翻页项（单页 = 一页；双页 = 左右两页）。
  Widget _buildSpread(
    int index,
    Pagination pag,
    ReaderTypeSpec spec,
    double columnWidth,
    double bodyHeight,
    double scale,
    double gutter,
    double headerH,
    double footerH,
    double bodyExpanded,
  ) {
    final spreads = _spreadCount(pag);
    final leading = _leadingSentinels;
    final dual = widget.settings.doublePage;

    if (_hasPrev && index == 0) {
      final prev = _pageOfChapter(
        _chapterIdx - 1,
        spec,
        columnWidth,
        bodyHeight,
        scale,
      );
      final last = prev.pagination.pageCount - 1;
      if (!dual) {
        return _spreadFrame(
          left: _pageWidget(
            _chapterIdx - 1,
            prev.layout,
            prev.pagination,
            last,
            headerH,
            footerH,
            columnWidth,
            scale,
            bodyExpanded,
          ),
          right: null,
          gutter: 0,
        );
      }
      return _dualSpread(
        gutter: gutter,
        headerH: headerH,
        footerH: footerH,
        ctx: _PageCtx(
          chapterIndex: _chapterIdx - 1,
          page: last,
          pages: prev.pagination.pageCount,
          chapterTitle: prev.layout.chapter.title,
          bookPercent: widget.bookPercent,
        ),
        left: _pageBodyFor(
          _chapterIdx - 1,
          prev.layout,
          prev.pagination,
          last,
          columnWidth,
          scale,
          bodyExpanded,
        ),
        right: _blankPage(),
      );
    }
    if (_hasNext && index == spreads + leading) {
      final next = _pageOfChapter(
        _chapterIdx + 1,
        spec,
        columnWidth,
        bodyHeight,
        scale,
      );
      if (!dual) {
        return _spreadFrame(
          left: _pageWidget(
            _chapterIdx + 1,
            next.layout,
            next.pagination,
            0,
            headerH,
            footerH,
            columnWidth,
            scale,
            bodyExpanded,
          ),
          right: null,
          gutter: 0,
        );
      }
      // 左栏留白，内容在右栏：页眉页脚按右栏（本屏第一张内容页）解析。
      return _dualSpread(
        gutter: gutter,
        headerH: headerH,
        footerH: footerH,
        ctx: _PageCtx(
          chapterIndex: _chapterIdx + 1,
          page: 0,
          pages: next.pagination.pageCount,
          chapterTitle: next.layout.chapter.title,
          bookPercent: widget.bookPercent,
        ),
        left: _blankPage(),
        right: _pageBodyFor(
          _chapterIdx + 1,
          next.layout,
          next.pagination,
          0,
          columnWidth,
          scale,
          bodyExpanded,
        ),
      );
    }

    final spread = (index - leading).clamp(0, spreads - 1);
    if (!dual) {
      return _spreadFrame(
        left: _pageWidget(
          _chapterIdx,
          _layout!,
          pag,
          spread,
          headerH,
          footerH,
          columnWidth,
          scale,
          bodyExpanded,
        ),
        right: null,
        gutter: 0,
      );
    }
    final first = spread * 2;
    final second = first + 1;
    return _dualSpread(
      gutter: gutter,
      headerH: headerH,
      footerH: footerH,
      ctx: _PageCtx(
        chapterIndex: _chapterIdx,
        page: first,
        pages: pag.pageCount,
        chapterTitle: _layout!.chapter.title,
        bookPercent: widget.bookPercent,
      ),
      left: _pageBodyFor(
        _chapterIdx,
        _layout!,
        pag,
        first,
        columnWidth,
        scale,
        bodyExpanded,
      ),
      right: second < pag.pageCount
          ? _pageBodyFor(
              _chapterIdx,
              _layout!,
              pag,
              second,
              columnWidth,
              scale,
              bodyExpanded,
            )
          : _blankPage(),
    );
  }

  Widget _spreadFrame({
    required Widget left,
    required Widget? right,
    required double gutter,
    Widget? headerBand,
    Widget? footerBand,
  }) {
    // 每一页都要自带不透明白底：覆盖/仿真翻页时旧页被钉住、新页滑到它
    // 上面，页面若透明，两页正文会叠在一起（仿真翻页截图里的重影）。
    // 垂直留白并入页眉/页脚带（见 _pageContent），这里只保留左右留白，
    // 三段才能各占满整屏宽度。版心高度见 build 里的 textAreaH。
    Widget content;
    if (headerBand != null) {
      // 双页：页眉/页脚整屏只有一份（页码等按左页口径，与翻页锚点
      // _report(spread * pagesPerView) 一致），两栏正文并排夹在中间。
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          headerBand,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: left),
                if (right != null) ...[
                  SizedBox(width: gutter),
                  Expanded(child: right),
                ],
              ],
            ),
          ),
          footerBand!,
        ],
      );
    } else {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          if (right != null) ...[
            SizedBox(width: gutter),
            Expanded(child: right),
          ],
        ],
      );
    }
    return _PageBackground(
      color: widget.theme.background,
      imagePath: widget.backgroundImage,
      fit: widget.backgroundFit,
      child: Padding(
        padding: EdgeInsets.only(
          left: widget.padding.left,
          right: widget.padding.right,
        ),
        child: content,
      ),
    );
  }

  /// 双页模式下末页不满时的占位（保持左右版式不塌）。
  Widget _blankPage() => const SizedBox.expand(key: ValueKey('blank-page'));

  void _scheduleJump(Pagination pag) {
    _pendingJump = false;
    final layout = _layout!;
    final target = _pendingPage >= 0
        ? _pendingPage.clamp(0, pag.pageCount - 1)
        : pag.pageOfOffset(layout.displayOfChapter(_offsetForPending));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pc.hasClients) return;
      final spread = _spreadOf(target);
      // 目录 / 续读 / 重排定位不算用户翻页：静音并同步落定页。
      _suppressTurnSound = true;
      _pc.jumpToPage(spread + _leadingSentinels);
      _suppressTurnSound = false;
      _report(pag, spread * _pagesPerView);
    });
  }

  /// 按当前设置的翻页模式，给第 [index] 页加变换。
  ///
  /// 所有模式都是**左右翻页**：滑动/覆盖/淡入/仿真的位移与旋转全部
  /// 沿横轴（rotateY 折叠 = 沿竖直装订线折页），不存在上下方向的翻页。
  /// 语义与 M5 WebView 版一致：
  /// - 滑动：两页随手指平移（引擎默认，零变换）。
  /// - 覆盖：旧页原地压暗，新页从右侧滑入盖在上面。
  /// - 淡入：两页原地交叉淡入淡出。
  /// - 仿真：纸角跟手折起，背面（整页纹理的镜像）压在新页上，
  ///   折边内侧投影 + 折痕高光；几何见 [CurlGeometry]。
  Widget _applyTurnEffect(int index, double width, Widget child) {
    final mode = (_livePreview ?? widget.settings).pageTurnMode;
    if (mode == PageTurnMode.slide || mode == PageTurnMode.none) {
      return child;
    }
    double page = index.toDouble();
    if (_pc.hasClients && _pc.position.haveDimensions) {
      page = _pc.page ?? page;
    }
    final rel = index - page;
    if (rel >= 1 || rel <= -1) return child;

    switch (mode) {
      case PageTurnMode.cover:
        if (rel < 0) {
          // 旧页抵消滚动位移（原地不动）+ 压暗；新页自然滑入盖在上面
          final t = -rel;
          return Transform.translate(
            offset: Offset(-rel * width, 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15 * t),
              ),
              child: child,
            ),
          );
        }
        return child;
      case PageTurnMode.fade:
        // 两页都抵消滚动位移（原地），交叉淡入淡出
        return Transform.translate(
          offset: Offset(-rel * width, 0),
          child: Opacity(
            opacity: (1 - rel.abs()).clamp(0.0, 1.0),
            child: child,
          ),
        );
      case PageTurnMode.curl:
      case PageTurnMode.freeCurl:
        if (rel >= 0) return child;
        // 旧页原地不动（覆盖式）；折页纸背由叠加层画在新页之上。
        // 新页滑到折线右侧，折页盖住折线左侧的接缝，
        // 观感是「右缘被掀起、沿竖直折线折过去」。
        return Transform.translate(
          offset: Offset(-rel * width, 0),
          child: child,
        );
      case PageTurnMode.slide:
      case PageTurnMode.none:
        return child;
    }
  }

  /// 一页：页眉 + 正文（按对齐分组）+ 页脚。
  Widget _pageWidget(
    int chapterIdx,
    ChapterLayout layout,
    Pagination pag,
    int page,
    double headerH,
    double footerH,
    double width,
    double scale,
    double bodyExpanded, [
    ReadingSettings? settings,
  ]) {
    final (start, end) = pag.rangeOf(page);
    final content = _pageContent(
      chapterIdx,
      layout,
      start,
      end,
      page,
      pag.pageCount,
      headerH,
      footerH,
      width,
      scale,
      settings ?? widget.settings,
      stretch: _stretchFor(
        pag.heightOf(page),
        bodyExpanded,
        (layout.spec.bodyStyle.fontSize ?? 16) *
            (layout.spec.bodyStyle.height ?? 1.2),
      ),
    );
    return content;
  }

  /// 双页用：一栏正文（不带页眉页脚——带由 [_spreadFrame] 整屏画一份）。
  Widget _pageBodyFor(
    int chapterIdx,
    ChapterLayout layout,
    Pagination pag,
    int page,
    double width,
    double scale,
    double bodyExpanded, [
    ReadingSettings? settings,
  ]) {
    final (start, end) = pag.rangeOf(page);
    return _pageBody(
      chapterIdx,
      layout,
      start,
      end,
      page,
      width,
      scale,
      settings ?? widget.settings,
      stretch: _stretchFor(
        pag.heightOf(page),
        bodyExpanded,
        (layout.spec.bodyStyle.fontSize ?? 16) *
            (layout.spec.bodyStyle.height ?? 1.2),
      ),
    );
  }

  /// 双页翻页项：整屏页眉/页脚 + 左右两栏正文。
  ///
  /// 页眉页脚的内容按 [ctx]（本屏第一张可见内容页）解析。
  Widget _dualSpread({
    required double gutter,
    required double headerH,
    required double footerH,
    required _PageCtx ctx,
    required Widget left,
    required Widget? right,
  }) {
    return _spreadFrame(
      left: left,
      right: right,
      gutter: gutter,
      headerBand: _runningBand(
        header: true,
        ctx: ctx,
        settings: widget.settings,
        height: headerH,
      ),
      footerBand: _runningBand(
        header: false,
        ctx: ctx,
        settings: widget.settings,
        height: footerH,
      ),
    );
  }

  /// 指定起止的一页（预览页也走这里，保证与正式排版同一套渲染）。
  ///
  /// 单页模式/预览单栏用：页眉页脚每页自带。双页模式的整屏单份带
  /// 由 [_spreadFrame] 组装（见 [_buildSpread]）。
  Widget _pageContent(
    int chapterIdx,
    ChapterLayout layout,
    int start,
    int end,
    int page,
    int pages,
    double headerH,
    double footerH,
    double width,
    double scale,
    ReadingSettings settings, {
    double stretch = 1,
  }) {
    final pageCtx = _PageCtx(
      chapterIndex: chapterIdx,
      page: page,
      pages: pages,
      chapterTitle: layout.chapter.title,
      bookPercent: widget.bookPercent,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 页眉带：从屏幕最上沿开始，高度 = max(页眉上边距, 安全区) +
        // 页眉文字；带底 = 页眉文字底部，正文的顶边与它同一条线。
        // 页眉三槽全关时只留同高透明占位（安全区仍要扣）。
        _runningBand(
          header: true,
          ctx: pageCtx,
          settings: settings,
          height: headerH,
        ),
        // 正文上/下边距：分别是「正文文字顶部距页眉文字底部」「正文
        // 文字底部距页脚文字顶部」。
        Expanded(
          child: _pageBody(
            chapterIdx,
            layout,
            start,
            end,
            page,
            width,
            scale,
            settings,
            stretch: stretch,
          ),
        ),
        // 页脚带：高度 = 页脚文字 + max(页脚下边距, 安全区)，带顶 =
        // 页脚文字顶部（与正文底边同一条线），贯到屏幕最下沿。
        _runningBand(
          header: false,
          ctx: pageCtx,
          settings: settings,
          height: footerH,
        ),
      ],
    );
  }

  /// 页眉/页脚带：几何与 [_runningHeight] 一致（带高 = 边距 + 文字）。
  ///
  /// 槽位全关时只留同高透明占位（安全区仍要扣）。
  Widget _runningBand({
    required bool header,
    required _PageCtx ctx,
    required ReadingSettings settings,
    required double height,
  }) {
    final visible = header
        ? _headerVisible(settings)
        : _footerVisible(settings);
    return SizedBox(
      height: height,
      child: visible
          ? Padding(
              padding: EdgeInsets.only(
                top: header ? settings.headerMarginTop : 0,
                bottom: header ? 0 : settings.footerMarginBottom,
              ),
              child: _runningBlock(
                header: header,
                ctx: ctx,
                settings: settings,
              ),
            )
          : null,
    );
  }

  /// 正文区（页眉/页脚带之间的部分），不带 Expanded，由调用方包进
  /// Flex：单页在页 Column 里包 Expanded；双页由 [_spreadFrame] 的
  /// Row 包 Expanded（两栏正文并排，页眉页脚整屏一份）。
  Widget _pageBody(
    int chapterIdx,
    ChapterLayout layout,
    int start,
    int end,
    int page,
    double width,
    double scale,
    ReadingSettings settings, {
    double stretch = 1,
  }) {
    final runs = _buildRuns(layout, start, end, stretch: stretch);
    return Padding(
      padding: EdgeInsets.only(
        top: settings.marginTop,
        bottom: settings.marginBottom,
      ),
      child: ClipRect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < runs.length; i++) ...[
              if (runs[i].gapBefore > 0.5) SizedBox(height: runs[i].gapBefore),
              // 按自然高度渲染，不再用「排版器量出的高度」定死：
              // 真机字体逐行取整会让实际渲染略高于 TextPainter
              // 测量，定高盒子会把最后一行裁掉半个字（实测）。
              // 分页时已在页底留了半行安全余量吸收这部分误差。
              // stretch 把装箱零头摊进行距/段距。
              _runWidget(
                chapterIdx: chapterIdx,
                layout: layout,
                run: runs[i],
                runIndex: i,
                page: page,
                width: width,
                scale: scale,
                stretch: stretch,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 一页按「连续同对齐」分组，每组一个可选中文本块。
  ///
  /// [stretch] 会等比放大组间距（渲染与划线命中共用本方法，保持一致）。
  List<_PageRun> _buildRuns(
    ChapterLayout layout,
    int start,
    int end, {
    double stretch = 1,
  }) {
    final realEnd = math.min(end, layout.displayText.length);
    final runs = <_PageRun>[];
    LayoutParagraph? prev;
    for (final p in layout.paragraphs) {
      if (p.displayEnd <= start) {
        prev = p;
        continue;
      }
      if (p.displayStart >= realEnd) break;
      // 页面从缩进之前开始（断页点在上一段文本末尾）时，run 从缩进
      // 起点开始——页首段落才能带上首行缩进；段中照旧从正文起点开始。
      final from = start <= p.indentStart
          ? p.indentStart
          : math.max(p.displayStart, start);
      final to = math.min(p.displayEnd, realEnd);
      if (to > from) {
        if (runs.isNotEmpty && prev != null && runs.last.align == p.align) {
          runs.last.rangeEnd = to;
          runs.last.paragraphs.add(p);
        } else {
          runs.add(
            _PageRun(
              start: from,
              rangeEnd: to,
              align: p.align,
              gapBefore:
                  (runs.isEmpty || prev == null
                      ? 0
                      : _gapBetween(prev, p, layout.spec)) *
                  stretch,
              paragraphs: [p],
            ),
          );
        }
      }
      prev = p;
    }
    // 页尾的段间占位去掉（否则页底多一行）
    if (runs.isNotEmpty) {
      var e = runs.last.rangeEnd;
      while (e > runs.last.start &&
          (layout.displayText[e - 1] == '\n' ||
              layout.displayText[e - 1] == '\u200B')) {
        e--;
      }
      runs.last.rangeEnd = e;
    }
    return runs;
  }

  static double _gapBetween(
    LayoutParagraph prev,
    LayoutParagraph next,
    ReaderTypeSpec spec,
  ) {
    if (spec.preciseTypesetting) {
      final n = next.source.style;
      final p = prev.source.style;
      final before = n != null
          ? (n.marginTop ?? 0)
          : (next.isHeading ? spec.headingMarginTop : spec.paragraphSpacing);
      final after = p != null
          ? (p.marginBottom ?? 0)
          : (prev.isHeading ? spec.headingMarginBottom : 0.0);
      return math.max(before, after);
    }
    final before = next.isHeading
        ? spec.headingMarginTop
        : spec.paragraphSpacing;
    final after = prev.isHeading ? spec.headingMarginBottom : 0.0;
    return math.max(before, after);
  }

  /// 单个对齐段：带段落样式、划线与朗读高亮的可选中文本。
  Widget _runWidget({
    required int chapterIdx,
    required ChapterLayout layout,
    required _PageRun run,
    required int runIndex,
    required int page,
    required double width,
    required double scale,
    double stretch = 1,
  }) {
    final text = layout.displayText.substring(run.start, run.rangeEnd);
    if (text.isEmpty) return const SizedBox.shrink();
    final spans = _runSpans(
      layout,
      run,
      chapterIdx,
      stretch: stretch,
      justify: _justifyFor(layout, run, chapterIdx, width, scale),
    );
    final content = RichText(
      textAlign: run.align,
      textScaler: TextScaler.linear(scale),
      text: TextSpan(style: layout.spec.bodyStyle, children: spans),
    );
    if (widget.onSelection == null || _previewPage != null) return content;
    return _SelectionRun(
      key: ValueKey('run-$chapterIdx-$page-$runIndex'),
      runs: _selectionRuns,
      chapter: chapterIdx,
      page: page,
      layout: layout,
      run: run,
      child: content,
    );
  }

  RenderBox? get _selectionBox =>
      _selectionViewport.currentContext?.findRenderObject() as RenderBox?;

  // 相邻页提前构建，命中与手柄定位只看当前屏的真实文字。
  Iterable<_SelectionRunState> get _visibleSelectionRuns sync* {
    final pag = _pagination;
    final box = _selectionBox;
    if (pag == null || box == null || !box.hasSize) return;
    final firstPage = _currentPage(pag);
    for (final state in _selectionRuns) {
      final run = state.widget;
      if (run.chapter != _chapterIdx ||
          run.page < firstPage ||
          run.page >= firstPage + _pagesPerView) {
        continue;
      }
      final paragraph = state.paragraph;
      if (paragraph == null || !paragraph.hasSize) continue;
      final origin = box.globalToLocal(paragraph.localToGlobal(Offset.zero));
      if ((origin & paragraph.size).overlaps(Offset.zero & box.size)) {
        yield state;
      }
    }
  }

  _SelectionRunState? _selectionRunAt(Offset global, {bool exact = false}) {
    _SelectionRunState? closest;
    var best = double.infinity;
    for (final state in _visibleSelectionRuns) {
      final paragraph = state.paragraph!;
      final point = paragraph.globalToLocal(global);
      if ((Offset.zero & paragraph.size).contains(point)) return state;
      if (exact) continue;
      final clamped = Offset(
        point.dx.clamp(0.0, paragraph.size.width),
        point.dy.clamp(0.0, paragraph.size.height),
      );
      final distance = (clamped - point).distanceSquared;
      if (distance < best) {
        closest = state;
        best = distance;
      }
    }
    return closest;
  }

  void _startTextSelection(Offset global) {
    final hit = _selectionRunAt(global, exact: true);
    if (hit == null) return;
    final paragraph = hit.paragraph!;
    final local = paragraph.globalToLocal(global);
    final word = paragraph.getWordBoundary(
      paragraph.getPositionForOffset(local),
    );
    if (!word.isValid || word.isCollapsed) return;
    // 正文 run 占满列宽，但长按行尾的大片留白不应选中最后一个字。
    if (!paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: word.start, extentOffset: word.end),
        )
        .any((box) => box.toRect().inflate(8).contains(local))) {
      return;
    }
    final run = hit.widget;
    final start = run.chapterOffset(word.start);
    final end = run.chapterOffset(word.end);
    if (start >= end ||
        widget.chapters[run.chapter].text
            .substring(start, end)
            .trim()
            .isEmpty) {
      return;
    }
    _resetFreeCurl();
    _selectingFromBody = true;
    _bodySelectionStart = _selectionStart = (
      chapter: run.chapter,
      offset: start,
    );
    _bodySelectionEnd = _selectionEnd = (chapter: run.chapter, offset: end);
    widget.onSelectionClear?.call();
    _bumpPage();
  }

  Offset? _selectionHandlePosition(
    _SelectionPoint point, {
    required bool leading,
  }) {
    final box = _selectionBox;
    if (box == null) return null;
    Offset? fallback;
    int? closestBoundary;
    for (final state in _visibleSelectionRuns) {
      final run = state.widget;
      if (run.chapter != point.chapter) continue;
      final display = run.layout.displayOfChapter(point.offset);
      final (pageStart, pageEnd) = _pagination!.rangeOf(run.page);
      if (display < pageStart || display > pageEnd) continue;
      final offset = display - run.run.start;
      final length = run.run.rangeEnd - run.run.start;
      // 段间占位符可能被分页器分到页首/页尾，但没有对应的字形。
      if ((offset < 0 && display != pageStart) ||
          (offset > length && display != pageEnd)) {
        continue;
      }
      final paragraph = state.paragraph!;
      final caret = TextPosition(
        offset: offset.clamp(0, length),
        affinity: leading ? TextAffinity.downstream : TextAffinity.upstream,
      );
      final anchor =
          paragraph.getOffsetForCaret(caret, Rect.zero) +
          Offset(0, paragraph.getFullHeightForCaret(caret));
      final local = box.globalToLocal(paragraph.localToGlobal(anchor));
      if (leading
          ? offset >= 0 && offset < length
          : offset > 0 && offset <= length) {
        return local;
      }
      final distance = (offset - caret.offset).abs();
      if (closestBoundary == null || distance < closestBoundary) {
        closestBoundary = distance;
        fallback = local;
      }
    }
    return fallback;
  }

  void _syncSelectionHandles() {
    final start = _selectionStart;
    final end = _selectionEnd;
    if (start == null || end == null) return;
    final startPos = _selectionHandlePosition(start, leading: true);
    final endPos = _selectionHandlePosition(end, leading: false);
    // 松手前保留当前手柄的命中对象，跨章重建期间也不会丢掉指针。
    final dragPos = _handlePointerPosition;
    final localDrag = dragPos == null
        ? null
        : _selectionBox?.globalToLocal(dragPos);
    _selectionHandles.value = (
      startPos ?? (_draggingStart ? localDrag : null),
      endPos ?? (_draggingStart ? null : localDrag),
    );
  }

  void _beginSelectionHandle(PointerDownEvent event) {
    if (_handlePointer != null || event.buttons != kPrimaryButton) return;
    final box = _selectionBox;
    if (box == null) return;
    final (start, end) = _selectionHandles.value;
    final touch = box.globalToLocal(event.position);
    // 单字选区的两侧触控区域会重叠，选中离手指更近的手柄。
    final leading =
        end == null ||
        (start != null &&
            (touch - start - const Offset(-9, 9)).distanceSquared <
                (touch - end - const Offset(9, 9)).distanceSquared);
    final anchor = leading ? start : end;
    if (anchor == null) return;
    _handlePointer = event.pointer;
    _draggingStart = leading;
    _handlePointerPosition = event.position;
    _handleDragOffset = box.localToGlobal(anchor) - event.position;
    widget.onSelectionClear?.call();
  }

  Widget _selectionHandle(
    Offset anchor, {
    required bool leading,
    required Size size,
  }) {
    const hitSize = 40.0;
    final handleX = anchor.dx + (leading ? -9 : 9);
    final left = (handleX - hitSize / 2).clamp(
      0.0,
      math.max(0.0, size.width - hitSize),
    );
    final top = (anchor.dy - 8).clamp(
      0.0,
      math.max(0.0, size.height - hitSize),
    );
    return Positioned(
      key: ValueKey('selection-handle-${leading ? 'start' : 'end'}'),
      left: left.toDouble(),
      top: top.toDouble(),
      width: hitSize,
      height: hitSize,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: handleX - left - 9,
              top: anchor.dy - top,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.theme.accent,
                  borderRadius: BorderRadius.only(
                    topLeft: leading ? const Radius.circular(9) : Radius.zero,
                    topRight: leading ? Radius.zero : const Radius.circular(9),
                    bottomLeft: const Radius.circular(9),
                    bottomRight: const Radius.circular(9),
                  ),
                ),
                child: const SizedBox(width: 18, height: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _moveSelectionHandle(PointerMoveEvent event) {
    if (event.pointer != _handlePointer) return;
    _handlePointerPosition = event.position;
    final box = _selectionBox;
    if (box == null) return;
    final local = box.globalToLocal(event.position);
    final right = local.dx >= box.size.width - 22;
    final left = local.dx <= 22;
    // 双页左栏的底部应先允许用户拖进右栏；整屏右侧才是向后翻页边缘。
    final top =
        local.dy <= math.max(24, _lastHeaderH + widget.settings.marginTop - 4);
    final bottom =
        local.dy >=
        box.size.height -
            math.max(24, _lastFooterH + widget.settings.marginBottom - 4);
    final edge =
        right ||
            (bottom && (_pagesPerView == 1 || local.dx >= box.size.width / 2))
        ? 1
        : left || (top && (_pagesPerView == 1 || local.dx < box.size.width / 2))
        ? -1
        : 0;
    if (edge != _selectionEdge) {
      _cancelSelectionTurn();
      _selectionEdge = edge;
      if (edge != 0) {
        _selectionTurnTimer = Timer(
          const Duration(milliseconds: 420),
          () => _turnWhileSelecting(edge),
        );
      }
    }
    if (edge != 0) return;

    final point = _selectionPointAt(event.position + _handleDragOffset);
    if (point != null) _setDraggedEndpoint(point);
  }

  _SelectionPoint? _selectionPointAt(Offset global) {
    final hit = _selectionRunAt(global);
    if (hit == null) return null;
    final paragraph = hit.paragraph!;
    final textPosition = paragraph.getPositionForOffset(
      paragraph.globalToLocal(global),
    );
    return (
      chapter: hit.widget.chapter,
      offset: hit.widget.chapterOffset(textPosition.offset),
    );
  }

  void _extendBodySelection(Offset global) {
    if (!_selectingFromBody) return;
    final point = _selectionPointAt(global);
    if (point == null) return;
    final start = _bodySelectionStart!;
    final end = _bodySelectionEnd!;
    final expandedStart = _comparePoints(point, start) < 0 ? point : start;
    final expandedEnd = _comparePoints(point, end) > 0 ? point : end;
    if (_selectionStart == expandedStart && _selectionEnd == expandedEnd) {
      return;
    }
    _selectionStart = expandedStart;
    _selectionEnd = expandedEnd;
    _bumpPage();
  }

  bool _setDraggedEndpoint(_SelectionPoint point) {
    final start = _selectionStart;
    final end = _selectionEnd;
    if (start == null || end == null) return false;
    if (_draggingStart) {
      if (_comparePoints(point, end) >= 0) return false;
      if (start == point) return true;
      _selectionStart = point;
    } else {
      if (_comparePoints(point, start) <= 0) return false;
      if (end == point) return true;
      _selectionEnd = point;
    }
    _bumpPage();
    return true;
  }

  void _turnWhileSelecting(int direction) {
    final pag = _pagination;
    final layout = _layout;
    if (!mounted ||
        _handlePointer == null ||
        pag == null ||
        layout == null ||
        !_pc.hasClients ||
        _pendingJump) {
      return;
    }
    final target = _spreadOf(_currentPage(pag)) + direction;
    final _SelectionPoint boundary;
    if (target < 0) {
      if (!_hasPrev) {
        _setDraggedEndpoint((chapter: _chapterIdx, offset: 0));
        return;
      }
      final chapter = _chapterIdx - 1;
      boundary = (
        chapter: chapter,
        offset: widget.chapters[chapter].text.length,
      );
    } else if (target >= _spreadCount(pag)) {
      if (!_hasNext) {
        _setDraggedEndpoint((
          chapter: _chapterIdx,
          offset: widget.chapters[_chapterIdx].text.length,
        ));
        return;
      }
      boundary = (chapter: _chapterIdx + 1, offset: 0);
    } else {
      final page = direction > 0
          ? target * _pagesPerView
          : math.min((target + 1) * _pagesPerView, pag.pageCount) - 1;
      final (start, end) = pag.rangeOf(page);
      boundary = (
        chapter: _chapterIdx,
        offset: layout.chapterOfDisplay(direction > 0 ? start : end),
      );
    }
    if (_setDraggedEndpoint(boundary)) {
      _pc.jumpToPage(target + _leadingSentinels);
      // 从边缘移回正文后才允许再次触发，防止停住时连跳多页。
      _bumpPage();
    }
  }

  void _cancelSelectionTurn() {
    _selectionTurnTimer?.cancel();
    _selectionTurnTimer = null;
    _selectionEdge = 0;
  }

  void _endSelectionHandle(PointerEvent event) {
    if (event.pointer != _handlePointer) return;
    _handlePointer = null;
    _handlePointerPosition = null;
    _cancelSelectionTurn();
    _bumpPage();
    _publishTextSelection(event.position);
  }

  void _publishTextSelection(Offset anchor) {
    final start = _selectionStart;
    final end = _selectionEnd;
    if (start == null || end == null) return;
    final parts = <String>[];
    for (var i = start.chapter; i <= end.chapter; i++) {
      final text = widget.chapters[i].text;
      parts.add(
        text.substring(
          i == start.chapter ? start.offset : 0,
          i == end.chapter ? end.offset : text.length,
        ),
      );
    }
    final quote = parts.join('\n').trim();
    if (quote.isEmpty) {
      _dismissTextSelection();
      return;
    }
    widget.onSelection?.call(
      NativeSelection(
        chapterIndex: start.chapter,
        endChapterIndex: end.chapter,
        start: start.offset,
        end: end.offset,
        text: quote,
        anchor: anchor,
      ),
    );
  }

  /// 计算 [run] 末行的两端对齐补偿（无补偿返回空表）。
  ///
  /// 用户口径（2026-11-10）：段落默认左对齐（段末行自然收尾），正文
  /// 两端对齐。引擎的 `TextAlign.justify` 已经把段中的整行撑满版心，
  /// 唯一补不到的是 **被页面截断的段中行**——run 的最后一行在引擎眼里
  /// 是「块末行」，但它其实是段落中段（下一段内容在下一页继续），
  /// 不补会右缘参差。做法：按行量出自然宽度，把余量摊成追加字距。
  /// 段末行（页面截断处恰好在段落末尾）一律不补。
  List<_RunJustify> _justifyFor(
    ChapterLayout layout,
    _PageRun run,
    int chapterIdx,
    double width,
    double scale,
  ) {
    if (run.align != TextAlign.justify) return const [];
    final key = Object.hash(
      chapterIdx,
      run.start,
      run.rangeEnd,
      width,
      scale,
      layout.spec.metricsSignature,
    );
    if (_runJustifyCache.containsKey(key)) return _runJustifyCache[key]!;
    final out = <_RunJustify>[];
    final text = layout.displayText.substring(run.start, run.rangeEnd);
    if (text.isNotEmpty) {
      List<InlineSpan> spansOf(int from, int to) => [
        for (final (a, b, style) in layout.segmentsOf(
          from,
          to,
          textScale: scale,
        ))
          TextSpan(
            text: text.substring(a - run.start, b - run.start),
            style: style,
          ),
      ];
      final painter = TextPainter(
        text: TextSpan(
          style: layout.spec.bodyStyle,
          children: spansOf(run.start, run.rangeEnd),
        ),
        textDirection: TextDirection.ltr,
        // 与真实渲染同对齐（justify）：断行与行宽都按 justify 的标点/空白
        // 压缩口径算，补偿后的行宽才与渲染一致（left 口径会差出一个标点）。
        textAlign: run.align,
        textScaler: TextScaler.linear(scale),
      )..layout(maxWidth: width);
      final metrics = painter.computeLineMetrics();
      if (metrics.isNotEmpty) {
        final starts = <int>[
          for (final m in metrics)
            painter
                .getPositionForOffset(Offset(0, m.baseline - m.ascent + 0.5))
                .offset,
        ];
        painter.dispose();
        // (行号, 补偿区间, 候选字距)
        final candidates = <(int, int, int, double)>[];
        // 只看 run 的最后一行：段中整行由引擎 justify，段末行不补。
        // 「段落被截断」= run 终点没到所在段落的末尾（下一段内容在
        // 下一页继续）；截断处恰好在段落末尾时不补（段末行左对齐）。
        final cutMidParagraph =
            run.paragraphs.isNotEmpty &&
            run.rangeEnd < run.paragraphs.last.displayEnd;
        if (cutMidParagraph) {
          final i = starts.length - 1;
          final lineEnd = text.length;
          // 行首缩进空白不进补偿区间：justify 引擎会无视空白字符上的
          // letterSpacing（实测 NBSP 槽位吃不到字距），只把可见字符区
          // 撑开，缩进保持恰好两字。零宽锚（U+FEFF）同样跳过。
          var bumpStart = starts[i];
          while (bumpStart < lineEnd &&
              (text[bumpStart] == '\u00A0' ||
                  text[bumpStart] == '\u3000' ||
                  text[bumpStart] == '\uFEFF')) {
            bumpStart++;
          }
          // 只补前 n-1 个字符：letterSpacing 在末字之后是「尾随间距」，
          // 是看不见的空白（右缘不会因此推进），补进去等于浪费；只补
          // 字与字之间的缝隙，末字的可见右缘才会正好顶到版心。
          if (lineEnd - bumpStart >= 2) {
            // 自然行宽直接取未补偿排版的行宽：与真实渲染完全同口径
            // （justify 的标点/空白压缩、行尾字距都一致）。
            final natural = metrics[i].width;
            // 余量要留出安全边：真机渲染（EditableText/取整）比排版报告的
            // 行宽约宽 5 逻辑像素，按 0.5 字号留边——短行只有一个间隙、
            // 补偿值很大，边留小了整行会折到下一行。
            final safety = 0.5 * (layout.spec.bodyStyle.fontSize ?? 16);
            final leftover = width - natural - safety;
            if (leftover > 1) {
              // 单缝隙补偿封顶 2 字号：补偿值过大会把整行折到下一行，
              // 且观感被拉得太散。
              final fontSize = layout.spec.bodyStyle.fontSize ?? 16;
              final delta = math.min(
                leftover / (lineEnd - 1 - bumpStart),
                fontSize * 2,
              );
              candidates.add((i, bumpStart, lineEnd - 1, delta));
            }
          }
        }
        for (final (_, s, e, d) in candidates) {
          out.add(_RunJustify(s, e, d));
        }
      } else {
        painter.dispose();
      }
    }
    _runJustifyCache[key] = out;
    if (_runJustifyCache.length > 128) _runJustifyCache.clear();
    return out;
  }

  /// 把段落样式与划线/朗读高亮合成为 span 列表。
  ///
  /// [stretch] 等比放大各段的行高（含段距占位行）：行距不影响断行，
  /// 页内容与字符映射不变，只是把页底零头摊进行距（纵向撑满）。
  /// [justify] 非空时给各端行范围内的叶子 span 追加字距（两端对齐补偿）。
  List<InlineSpan> _runSpans(
    ChapterLayout layout,
    _PageRun run,
    int chapterIdx, {
    double stretch = 1,
    List<_RunJustify> justify = const [],
  }) {
    final text = layout.displayText.substring(run.start, run.rangeEnd);
    // 样式分段必须与分页时一致：段距占位行有自己的行高样式
    TextStyle scaled(TextStyle s) => stretch == 1
        ? s
        : s.copyWith(
            height: (s.height ?? layout.spec.bodyStyle.height ?? 1.0) * stretch,
          );
    final segments = <(int, int, TextStyle)>[
      for (final (a, b, style) in layout.segmentsOf(
        run.start,
        run.rangeEnd,
        textScale: _layoutScale,
      ))
        (a - run.start, b - run.start, scaled(style)),
    ];

    final highlights = <(int, int, Color)>[];
    final underlines = <(int, int, Color)>[];
    void addRange(
      List<(int, int, Color)> target,
      int chapterStart,
      int chapterEnd,
      Color color, {
      bool skipLeadingIndent = false,
    }) {
      if (chapterEnd <= chapterStart) return;
      var ds = layout.displayOfChapter(chapterStart) - run.start;
      final de = layout.displayOfChapter(chapterEnd) - run.start;
      var a = math.max(0, math.min(ds, de));
      final b = math.min(text.length, math.max(ds, de));
      if (skipLeadingIndent && b > a) {
        // 段首缩进不参与朗读高亮：起点钳到该段正文首字（跳过零宽锚 /
        // NBSP 补宽 / 全角半角空格等缩进字符），终点至少保持到起点之后。
        for (final p in layout.paragraphs) {
          if (p.displayEnd <= run.start || p.indentStart >= run.rangeEnd) {
            continue;
          }
          final bodyStart = p.displayStart - run.start;
          if (bodyStart > a && bodyStart < b) {
            a = bodyStart;
            ds = math.max(ds, bodyStart);
          }
        }
        while (a < b && _isIndentChar(text.codeUnitAt(a))) {
          a++;
        }
        if (a >= b) return;
      }
      if (b > a) target.add((a, b, color));
    }

    for (final m in widget.marks) {
      if (m.chapterIndex != chapterIdx) continue;
      addRange(m.underline ? underlines : highlights, m.start, m.end, m.color);
    }
    final selectionStart = _selectionStart;
    final selectionEnd = _selectionEnd;
    if (selectionStart != null &&
        selectionEnd != null &&
        chapterIdx >= selectionStart.chapter &&
        chapterIdx <= selectionEnd.chapter) {
      addRange(
        highlights,
        chapterIdx == selectionStart.chapter ? selectionStart.offset : 0,
        chapterIdx == selectionEnd.chapter
            ? selectionEnd.offset
            : layout.chapter.text.length,
        widget.theme.accent.withValues(alpha: 0.32),
      );
    }
    final hl = widget.ttsHighlight?.value;
    if (hl != null && hl.chapterIndex == chapterIdx) {
      addRange(
        highlights,
        hl.start,
        hl.end,
        widget.theme.accent.withValues(alpha: 0.26),
        skipLeadingIndent: true,
      );
    }

    // 统一成互不重叠的扁平片段（段样式 × 高亮底色 / 下划线）。
    final parts = <(int, int, TextStyle, Color?, Color?)>[];
    if (highlights.isEmpty && underlines.isEmpty) {
      parts.addAll([
        for (final (a, b, style) in segments) (a, b, style, null, null),
      ]);
    } else {
      Color? colorAt(List<(int, int, Color)> ranges, int offset) {
        for (final (a, b, color) in ranges) {
          if (offset >= a && offset < b) return color;
        }
        return null;
      }

      for (final (a, b, style) in segments) {
        final cuts = <int>{a, b};
        void addCuts(List<(int, int, Color)> ranges) {
          for (final (ra, rb, _) in ranges) {
            if (rb <= a || ra >= b) continue;
            cuts.add(math.max(a, ra));
            cuts.add(math.min(b, rb));
          }
        }

        addCuts(highlights);
        addCuts(underlines);
        final sorted = cuts.toList()..sort();
        for (var i = 0; i + 1 < sorted.length; i++) {
          final s = sorted[i];
          final e = sorted[i + 1];
          if (e <= s) continue;
          final mid = (s + e) ~/ 2;
          parts.add((
            s,
            e,
            style,
            colorAt(highlights, mid),
            colorAt(underlines, mid),
          ));
        }
      }
    }

    // 端行补偿：每个补偿区间内的叶子 span 追加字距（区间边界处拆开）。
    return _spansWithJustify(
      text,
      parts,
      justify,
      layout.spec.bodyStyle.letterSpacing ?? 0.0,
    );
  }

  /// 缩进类字符：零宽锚 / NBSP / 全角空格 / 半角空格 / 制表符。
  static bool _isIndentChar(int code) =>
      code == 0xFEFF ||
      code == 0x00A0 ||
      code == 0x3000 ||
      code == 0x20 ||
      code == 0x09;

  /// 把扁平片段按端行补偿区间切成 span（区间内叶子追加字距）。
  ///
  /// 叶子 style 未显式带 letterSpacing 时继承根样式（spec.bodyStyle），
  /// 补偿要在该基数上加。渲染与 `_justifyFor` 的自校准共用本方法，
  /// 保证两边字距口径一致。
  List<InlineSpan> _spansWithJustify(
    String text,
    List<(int, int, TextStyle, Color?, Color?)> parts,
    List<_RunJustify> ranges,
    double baseSpacing,
  ) {
    final out = <InlineSpan>[];
    for (final (a, b, style, bg, underline) in parts) {
      TextStyle plain(TextStyle s) {
        var next = s;
        if (bg != null) next = next.copyWith(backgroundColor: bg);
        if (underline != null) {
          next = next.copyWith(
            decoration: TextDecoration.underline,
            decorationColor: underline,
            decorationThickness: 1.6,
          );
        }
        return next;
      }

      if (ranges.isEmpty) {
        out.add(TextSpan(text: text.substring(a, b), style: plain(style)));
        continue;
      }
      var pos = a;
      for (final r in ranges) {
        if (r.end <= pos || r.start >= b) continue;
        final s = math.max(pos, r.start);
        final e = math.min(b, r.end);
        if (s > pos) {
          out.add(TextSpan(text: text.substring(pos, s), style: plain(style)));
        }
        out.add(
          TextSpan(
            text: text.substring(s, e),
            style: plain(
              style.copyWith(
                letterSpacing: (style.letterSpacing ?? baseSpacing) + r.delta,
              ),
            ),
          ),
        );
        pos = e;
      }
      if (pos < b) {
        out.add(TextSpan(text: text.substring(pos, b), style: plain(style)));
      }
    }
    return out;
  }

  /// 页眉 / 页脚：左中右三槽，内容按设置解析。
  Widget _runningBlock({
    required bool header,
    required _PageCtx ctx,
    required ReadingSettings settings,
  }) {
    final s = settings;
    final style = TextStyle(
      color: widget.theme.foreground.withValues(alpha: 0.62),
      fontSize: s.headerFontSize,
      height: 1.2,
      fontFamily: s.fontFamily.isEmpty ? null : s.fontFamily,
    );
    final left = header ? s.headerLeft : s.footerLeft;
    final center = header ? s.headerCenter : s.footerCenter;
    final right = header ? s.headerRight : s.footerRight;
    final marginLeft = header ? s.headerMarginLeft : s.footerMarginLeft;
    final marginRight = header ? s.headerMarginRight : s.footerMarginRight;

    Widget slot(RunningContent c, TextAlign align) => Expanded(
      child: Text(
        _runningText(c, ctx),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: style,
      ),
    );

    // 上下边距不在这里：页眉上边距由页眉带承担，正文上下边距由正文区
    // 内部留白承担，页脚下边距由页脚带承担（见 _pageContent 与 _runningHeight）。
    return Padding(
      padding: EdgeInsets.fromLTRB(marginLeft, 0, marginRight, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          slot(left, TextAlign.left),
          slot(center, TextAlign.center),
          slot(right, TextAlign.right),
        ],
      ),
    );
  }

  String _runningText(RunningContent content, _PageCtx ctx) {
    switch (content) {
      case RunningContent.none:
        return '';
      case RunningContent.time:
        final now = DateTime.now();
        return '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}';
      case RunningContent.chapterName:
        return ctx.chapterTitle;
      case RunningContent.chapterPercent:
        final pct = ctx.pages == 0 ? 0 : ((ctx.page + 1) / ctx.pages * 100);
        return '${pct.round()}%';
      case RunningContent.chapterPages:
        return '${ctx.page + 1}/${ctx.pages}';
      case RunningContent.bookPercent:
        return '${(ctx.bookPercent * 100).round()}%';
      case RunningContent.bookPages:
        final (page, total) = _bookPagesOf(ctx);
        return '$page/$total';
      case RunningContent.battery:
        return _battery == null ? '--' : '$_battery%';
    }
  }

  /// 全书页码估算：用当前章「显示字符数 / 页数」推其它章页数。
  ///
  /// 精确全书页数要排完整本书（几百章 × TextPainter），打开就卡；
  /// 页眉页脚只需要一个稳定近似值。
  (int, int) _bookPagesOf(_PageCtx ctx) {
    final layout = _layout;
    if (layout == null || ctx.pages <= 0) return (ctx.page + 1, ctx.pages);
    final charsPerPage = math.max(1.0, layout.displayText.length / ctx.pages);
    var before = 0;
    var total = 0;
    for (var i = 0; i < widget.chapters.length; i++) {
      final est = i == ctx.chapterIndex
          ? ctx.pages
          : math.max(1, (widget.chapters[i].text.length / charsPerPage).ceil());
      if (i < ctx.chapterIndex) before += est;
      total += est;
    }
    return (before + ctx.page + 1, math.max(total, before + ctx.pages));
  }

  // ---- 折角翻页：截图 + 逐帧几何 ----

  /// 当前生效设置是不是折角模式。
  bool get _curlMode =>
      (_livePreview ?? widget.settings).pageTurnMode == PageTurnMode.curl;

  /// 当前生效设置是不是随手仿真。
  bool get _freeCurlMode =>
      (_livePreview ?? widget.settings).pageTurnMode == PageTurnMode.freeCurl;

  void _onFreeCurlDown(PointerDownEvent e) {
    if (!_freeCurlMode) return;
    if (_freeCurlSettling) {
      _freeCurlSettle.stop();
      _freeCurlSettling = false;
    }
    _freeCurlArmed = true;
    _freeCurlDown = e.localPosition;
    _freeCurlForward = null;
    _freeCurlCorner = null;
    _freeCurlTargetIndex = null;
    _freeCurlLastX = e.localPosition.dx;
    _freeCurlOldPage = null;
    _freeCurlNewPage = null;
    _freeCurlFrame.value = null;
  }

  void _onFreeCurlMove(PointerMoveEvent e) {
    if (!_freeCurlArmed || _freeCurlSettling) return;
    final down = _freeCurlDown;
    if (down == null) return;
    final dx = e.localPosition.dx - down.dx;

    // 方向未定：等横向拖动超过 8px 再决定从哪边掀起。
    if (_freeCurlForward == null) {
      if (dx.abs() < 8) return;
      if (!_prepareFreeCurl(forward: dx < 0)) return;
    }

    final size = _curlPageSize;
    final forward = _freeCurlForward;
    if (size == null || forward == null) return;
    final corner = _freeCurlCorner ??= _freeCurlCornerFor(size, forward, down);
    _freeCurlLastX = e.localPosition.dx;
    _freeCurlFrame.value = FreeCurlGeometry(
      page: size,
      corner: corner,
      finger: e.localPosition,
      forward: forward,
    );
  }

  /// 纸角落在起手点所在的水平高度（不是固定上/下角）。
  ///
  /// 从右侧中间起手时，纸角就是右侧边缘同高度的点；旧实现按上/下半屏
  /// 吸附到右上/右下角，手指在中间会被识别成角落。
  Offset _freeCurlCornerFor(Size size, bool forward, Offset down) {
    final y = down.dy.clamp(0.0, size.height);
    return forward ? Offset(size.width, y) : Offset(0, y);
  }

  /// 构建「被掀起的当前页」和「下面的下一页」；索引越界时返回 false。
  bool _prepareFreeCurl({required bool forward}) {
    final builder = _spreadBuilder;
    final pag = _pagination;
    if (builder == null || pag == null || !_pc.hasClients) return false;
    final spreads = _spreadCount(pag);
    final count = spreads + (_hasPrev ? 1 : 0) + (_hasNext ? 1 : 0);
    final current = (_pc.page?.round() ?? 0).clamp(0, count - 1);
    final target = forward ? current + 1 : current - 1;
    if (target < 0 || target >= count) return false;
    _freeCurlOldPage = builder(current);
    _freeCurlNewPage = builder(target);
    _freeCurlForward = forward;
    _freeCurlTargetIndex = target;
    final size = _curlPageSize;
    final down = _freeCurlDown;
    if (size != null && down != null) {
      _freeCurlCorner = _freeCurlCornerFor(size, forward, down);
    }
    if (mounted) setState(() {});
    return true;
  }

  void _endFreeCurl() {
    if (!_freeCurlArmed && _freeCurlOldPage == null) return;
    if (_freeCurlSettling) return;
    final size = _curlPageSize;
    final forward = _freeCurlForward;
    final geometry = _freeCurlFrame.value;
    final down = _freeCurlDown;
    if (_freeCurlOldPage == null ||
        _freeCurlNewPage == null ||
        size == null ||
        forward == null ||
        geometry == null ||
        down == null) {
      _resetFreeCurl();
      return;
    }

    final dx = _freeCurlLastX - down.dx;
    // 横向拖过约 18% 页宽（或速度很快）就翻过去，否则弹回。
    final commit = forward ? dx < -size.width * 0.18 : dx > size.width * 0.18;
    _freeCurlSettling = true;
    _freeCurlCommit = commit;
    _freeCurlSettleFrom = geometry.finger;
    _freeCurlSettleTo = commit
        ? Offset(forward ? -size.width : size.width * 2, geometry.finger.dy)
        : (_freeCurlCorner ?? geometry.corner);
    _freeCurlSettle.forward(from: 0);
    if (mounted) setState(() {});
  }

  void _onFreeCurlSettleTick() {
    final size = _curlPageSize;
    final from = _freeCurlSettleFrom;
    final to = _freeCurlSettleTo;
    final corner = _freeCurlCorner;
    final forward = _freeCurlForward;
    if (size == null ||
        from == null ||
        to == null ||
        corner == null ||
        forward == null) {
      return;
    }
    final t = Curves.easeOutCubic.transform(_freeCurlSettle.value);
    _freeCurlFrame.value = FreeCurlGeometry(
      page: size,
      corner: corner,
      finger: Offset.lerp(from, to, t)!,
      forward: forward,
      // 翻过去的收尾允许手指越过页框，折线才能扫到页外、整页折完。
      clampFinger: !_freeCurlCommit,
    );
  }

  void _onFreeCurlSettleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final target = _freeCurlTargetIndex;
    if (_freeCurlCommit && target != null && _pc.hasClients) {
      _pc.jumpToPage(target);
    }
    _resetFreeCurl();
  }

  void _resetFreeCurl() {
    final hadOverlay = _freeCurlOldPage != null || _freeCurlNewPage != null;
    final wasSettling = _freeCurlSettling;
    _freeCurlSettle.stop();
    _freeCurlArmed = false;
    _freeCurlSettling = false;
    _freeCurlCommit = false;
    _freeCurlDown = null;
    _freeCurlForward = null;
    _freeCurlCorner = null;
    _freeCurlTargetIndex = null;
    _freeCurlSettleFrom = null;
    _freeCurlSettleTo = null;
    _freeCurlFrame.value = null;
    _freeCurlOldPage = null;
    _freeCurlNewPage = null;
    if (mounted && (hadOverlay || wasSettling)) setState(() {});
  }

  /// 滚动通知：仿真（竖直卷边）按下开始 / 松手收掉卷边。
  bool _onCurlNotification(ScrollNotification n) {
    if (!_curlMode) return false;
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _beginCurlTurn();
    } else if (n is ScrollEndNotification) {
      _endCurlTurn();
    }
    return false;
  }

  void _beginCurlTurn() {
    if (!_pc.hasClients || !_pc.position.haveDimensions) return;
    final page = _pc.page;
    if (page == null) return;
    _curlStartPage = page;
    _curlFrame.value = null;
    _pumpCurlFrame();
  }

  void _onCurlTick() {
    if (!_curlMode) {
      _endCurlTurn();
      return;
    }
    if (_curlStartPage == null) return;
    _pumpCurlFrame();
  }

  /// 按当前滚动进度刷新折页几何。进度 = |当前页 - 起始页|。
  void _pumpCurlFrame() {
    final start = _curlStartPage;
    final size = _curlPageSize;
    if (start == null || size == null || size.isEmpty) return;
    if (!_pc.hasClients || !_pc.position.haveDimensions) return;
    final page = _pc.page;
    if (page == null) return;
    final delta = page - start;
    if (delta <= 0) {
      // 回翻（手指往右）：这版仍按覆盖式处理，不画折页。
      if (_curlFrame.value != null) _curlFrame.value = null;
      return;
    }
    final geometry = CurlGeometry(page: size, progress: delta.clamp(0.0, 1.0));
    if (!geometry.isActive) {
      if (_curlFrame.value != null) _curlFrame.value = null;
      return;
    }
    _curlFrame.value = CurlRenderState(
      geometry: geometry,
      background: widget.theme.background,
    );
  }

  void _endCurlTurn() {
    _curlStartPage = null;
    _curlFrame.value = null;
  }

  /// 滚动通知总入口：折角翻页可能自己消费掉。
  bool _onScrollNotification(ScrollNotification notification) {
    return _onCurlNotification(notification);
  }

  /// 翻页音效：在**页位跨过目标页的那一刻**响，不等滚动落定。
  ///
  /// 旧实现在 ScrollEnd 才响：点击翻页要先等完 220ms 动画、拖动要等回弹
  /// 收尾，听感上声音总慢半拍（用户实测「滞后 0.5s」的主因之一）。
  /// 现在由位置监听器在页索引变化时立即触发；目录 / 续读 / TTS 跳页
  /// 用 [_suppressTurnSound] 静音。
  void _playTurnSound() {
    if (_suppressTurnSound) return;
    final sound = (_livePreview ?? widget.settings).pageTurnSound;
    if (sound == PageTurnSound.none) return;
    unawaited(PageTurnSoundPlayer.instance.play(sound));
  }

  /// 自定义视口的页变化监听：页索引跨过整数时按当前翻页上下文上报
  /// （等价于 PageView 的 onPageChanged）。
  void _onScrollPageChanged() {
    final ctx = _turnCtx;
    if (ctx == null || !mounted || !_pc.hasClients) return;
    final pos = _pc.position;
    if (!pos.haveDimensions || pos.viewportDimension <= 0) return;
    final page = (pos.pixels / pos.viewportDimension).round();
    if (page == _lastReportedPage) return;
    _lastReportedPage = page;
    _playTurnSound();
    _onSpreadChanged(
      page,
      ctx.pag,
      ctx.spec,
      ctx.columnWidth,
      ctx.bodyHeight,
      ctx.scale,
    );
  }

  void _onSpreadChanged(
    int index,
    Pagination pag,
    ReaderTypeSpec spec,
    double columnWidth,
    double bodyHeight,
    double scale,
  ) {
    final spreads = _spreadCount(pag);
    final leading = _leadingSentinels;
    final bool toPrev = _hasPrev && index == 0;
    final bool toNext = _hasNext && index == spreads + leading;
    if (!toPrev && !toNext) {
      final spread = (index - leading).clamp(0, spreads - 1);
      _report(pag, spread * _pagesPerView);
      return;
    }

    // 落到哨兵：切章并跳到对应页（等下一次 build 重排后执行）
    final targetChapter = toPrev ? _chapterIdx - 1 : _chapterIdx + 1;
    final target = _pageOfChapter(
      targetChapter,
      spec,
      columnWidth,
      bodyHeight,
      scale,
    );
    _cancelReflow();
    _previewPage = null;
    _previewRequest = null;
    _previewKey = null;
    setState(() {
      _chapterIdx = targetChapter;
      _paginationChapter = targetChapter;
      _layout = target.layout;
      _pagination = target.pagination;
      _layoutSize = Size(columnWidth, bodyHeight);
      _layoutScale = scale;
      _pendingJump = true;
      _pendingPage = toPrev ? target.pagination.pageCount - 1 : 0;
      _offsetForPending = 0;
    });
  }

  void _report(Pagination pag, int page) {
    final layout = _layout;
    if (layout == null) return;
    final p = page.clamp(0, pag.pageCount - 1);
    final (start, _) = pag.rangeOf(p);
    final offset = layout.chapterOfDisplay(start);
    _lastOffset = offset;
    _everReported = true;
    final pages = pag.pageCount;
    // 全书进度按内容字符量算（每章等权会失真，见 bookContentPercent）
    final percent = bookContentPercent(widget.chapters, _chapterIdx, offset);
    widget.onPosition(
      NativePosition(
        chapterIndex: _chapterIdx,
        page: p + 1,
        pages: pages,
        offset: offset,
        percent: percent,
      ),
    );
  }

  void _handleTap(Offset local, BoxConstraints c, Pagination pag) {
    if (_hasSelection) {
      _dismissTextSelection();
      return;
    }
    final mark = _markAt(local, pag);
    if (mark != null) {
      widget.onMarkTap?.call(mark);
      return;
    }
    final w = c.maxWidth;
    final cur = _spreadOf(_currentPage(pag)) + _leadingSentinels;
    final headerH = _runningHeight(
      header: true,
      scale: _layoutScale,
      settings: widget.settings,
    );
    final footerH = _runningHeight(
      header: false,
      scale: _layoutScale,
      settings: widget.settings,
    );
    final action = widget.pageLayout.actionAt(
      local,
      Size(w, c.maxHeight),
      headerHeight: headerH,
      footerHeight: footerH,
    );
    switch (action) {
      case TapZoneAction.previousPage:
        _animateTo(cur - 1);
      case TapZoneAction.nextPage:
        _animateTo(cur + 1);
      case TapZoneAction.menu:
        widget.onCenterTap();
    }
  }

  /// 点击处是否落在某条划线上（返回该划线）。
  ///
  /// 每个对齐段单独排版做命中（居中标题与左对齐正文的 x 位置不同），
  /// 只在点击时算一次，不影响翻页性能。
  NativeMark? _markAt(Offset local, Pagination pag) {
    final layout = _layout;
    if (widget.marks.isEmpty || layout == null || _layoutSize == Size.zero) {
      return null;
    }
    // 页面局部坐标：x 减去左留白；y 不减（页眉带从 y=0 开始）。正文文字
    // 顶部 = 页眉带高 + 正文上边距。
    final content = local - Offset(widget.padding.left, 0);
    final headerH = _runningHeight(
      header: true,
      scale: _layoutScale,
      settings: widget.settings,
    );
    final top = content.dy - headerH - widget.settings.marginTop;
    if (top < 0) return null;

    final columnWidth = _layoutSize.width;
    final gutter = widget.settings.doublePage ? 20.0 : 0.0;
    var slotPage = _currentPage(pag);
    var x = content.dx;
    if (widget.settings.doublePage) {
      final half = columnWidth + gutter / 2;
      if (content.dx > half) {
        slotPage += 1;
        x = content.dx - (columnWidth + gutter);
      }
      if (slotPage >= pag.pageCount) return null;
    }
    final (start, end) = pag.rangeOf(slotPage);
    // 与渲染同一撑满系数：命中坐标才对得上被拉伸的行距/段距。
    final lineHeight =
        (layout.spec.bodyStyle.fontSize ?? 16) *
        (layout.spec.bodyStyle.height ?? 1.2);
    final stretch = _stretchFor(
      pag.heightOf(slotPage),
      _layoutSize.height + lineHeight * 0.5,
      lineHeight,
    );
    final runs = _buildRuns(layout, start, end, stretch: stretch);
    return _hitMarkInRuns(runs, x, top, columnWidth, layout, stretch: stretch);
  }

  NativeMark? _hitMarkInRuns(
    List<_PageRun> runs,
    double x,
    double y,
    double width,
    ChapterLayout layout, {
    double stretch = 1,
  }) {
    var top = 0.0;
    for (final run in runs) {
      top += run.gapBefore;
      final text = layout.displayText.substring(run.start, run.rangeEnd);
      if (text.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(
          style: layout.spec.bodyStyle,
          children: _runSpans(
            layout,
            run,
            _chapterIdx,
            stretch: stretch,
            justify: _justifyFor(layout, run, _chapterIdx, width, _layoutScale),
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: run.align,
        textScaler: TextScaler.linear(_layoutScale),
      )..layout(maxWidth: width);
      final runHeight = painter.height;
      if (y >= top && y <= top + runHeight) {
        final hit = _markAtInRun(
          painter,
          run,
          Offset(x, y - top),
          text,
          layout,
        );
        if (hit != null) return hit;
      }
      painter.dispose();
      top += runHeight;
    }
    return null;
  }

  NativeMark? _markAtInRun(
    TextPainter painter,
    _PageRun run,
    Offset local,
    String text,
    ChapterLayout layout,
  ) {
    // 单字划线的命中框只有一个字宽，按「离哪条划线最近」补一圈容差：
    // 手指点偏一点也能打开笔记（用户反馈「一个字的笔记点不动」）。
    NativeMark? nearest;
    var nearestDistance = double.infinity;
    for (final m in widget.marks) {
      if (m.chapterIndex != _chapterIdx) continue;
      final a = layout.displayOfChapter(m.start) - run.start;
      final b = layout.displayOfChapter(m.end) - run.start;
      final from = math.max(0, math.min(a, b));
      final to = math.min(text.length, math.max(a, b));
      if (to <= from) continue;
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: from, extentOffset: to),
      );
      if (boxes.isEmpty) {
        // 取不到盒子（零宽字符等）：按最近字符位兜底。
        final pos = painter.getPositionForOffset(local);
        if (pos.offset >= from && pos.offset <= to) return m;
        continue;
      }
      for (final box in boxes) {
        final rect = box.toRect();
        if (rect.inflate(6).contains(local)) return m;
        final dx = local.dx < rect.left
            ? rect.left - local.dx
            : (local.dx > rect.right ? local.dx - rect.right : 0.0);
        final dy = local.dy < rect.top
            ? rect.top - local.dy
            : (local.dy > rect.bottom ? local.dy - rect.bottom : 0.0);
        final distance = math.sqrt(dx * dx + dy * dy);
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearest = m;
        }
      }
    }
    return nearestDistance <= _markHitSlop ? nearest : null;
  }

  void _animateTo(int itemIndex) {
    if (!_pc.hasClients) return;
    final pos = _pc.position;
    if (!pos.hasContentDimensions || pos.maxScrollExtent <= 0) {
      _pc.jumpToPage(itemIndex);
      return;
    }
    final max = pos.maxScrollExtent;
    final target = (itemIndex * pos.viewportDimension).clamp(0.0, max);
    // 翻页效果「无」/「随手仿真」：直接落到目标页，不要 220ms 滑动。
    final mode = (_livePreview ?? widget.settings).pageTurnMode;
    if (mode == PageTurnMode.none || mode == PageTurnMode.freeCurl) {
      _pc.jumpTo(target);
      return;
    }
    _pc.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }
}

/// 注册已挂载的正文段，直接用渲染对象做字符命中及手柄定位。
class _SelectionRun extends StatefulWidget {
  const _SelectionRun({
    required super.key,
    required this.runs,
    required this.chapter,
    required this.page,
    required this.layout,
    required this.run,
    required this.child,
  });

  final Set<_SelectionRunState> runs;
  final int chapter;
  final int page;
  final ChapterLayout layout;
  final _PageRun run;
  final RichText child;

  int chapterOffset(int offset) => layout.chapterOfDisplay(run.start + offset);

  @override
  State<_SelectionRun> createState() => _SelectionRunState();
}

class _SelectionRunState extends State<_SelectionRun> {
  RenderParagraph? get paragraph =>
      context.findRenderObject() as RenderParagraph?;

  @override
  void initState() {
    super.initState();
    widget.runs.add(this);
  }

  @override
  void dispose() {
    widget.runs.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 一页内「连续同对齐」的段落组。
class _PageRun {
  _PageRun({
    required this.start,
    required this.rangeEnd,
    required this.align,
    required this.gapBefore,
    required this.paragraphs,
  });

  /// 显示坐标起点。
  final int start;

  /// 显示坐标终点（可变：同对齐的后续段落会并进来）。
  int rangeEnd;

  /// 对齐方式。
  final TextAlign align;

  /// 与上一组之间的段距（跨对齐分组时用 SizedBox 补）。
  final double gapBefore;

  /// 覆盖的段落。
  final List<LayoutParagraph> paragraphs;
}

/// 一条「两端对齐补偿」记录（页面截断的段中行）。
///
/// 引擎的 `TextAlign.justify` 不拉伸文本块的末行——如果页面截断处
/// 落在段落中间，run 的末行其实是段中行，不该按段末行收尾。给该行
/// 范围内的字符追加 [delta] 字距，把右缘撑到版心——不改文本、不拆行，
/// 分页/选字/TTS/划线的字符偏移全部不受影响。段末行（用户口径：
/// 段落默认左对齐）不产生补偿记录。
class _RunJustify {
  const _RunJustify(this.start, this.end, this.delta);

  /// 行起点（相对 run 文本）。
  final int start;

  /// 行终点（相对 run 文本，含行尾换行符，补偿对其不可见）。
  final int end;

  /// 每个字符追加的字距（含行尾的尾随字距，公式已按字符数摊平）。
  final double delta;
}

/// 页眉页脚内容所需的页上下文。
class _PageCtx {
  const _PageCtx({
    required this.chapterIndex,
    required this.page,
    required this.pages,
    required this.chapterTitle,
    required this.bookPercent,
  });

  final int chapterIndex;
  final int page;
  final int pages;
  final String chapterTitle;
  final double bookPercent;
}

/// 阅读页纸面：纯色，或「背景图 + 纸色蒙层」保证文字可读。
class _PageBackground extends StatelessWidget {
  const _PageBackground({
    required this.color,
    required this.imagePath,
    this.fit = BackgroundImageFit.cover,
    this.child,
  });

  final Color color;
  final String imagePath;
  final BackgroundImageFit fit;
  final Widget? child;

  BoxFit get _boxFit => switch (fit) {
    BackgroundImageFit.cover => BoxFit.cover,
    BackgroundImageFit.contain => BoxFit.contain,
    BackgroundImageFit.fill => BoxFit.fill,
    BackgroundImageFit.fitWidth => BoxFit.fitWidth,
    BackgroundImageFit.fitHeight => BoxFit.fitHeight,
  };

  @override
  Widget build(BuildContext context) {
    if (imagePath.isEmpty) return ColoredBox(color: color, child: child);
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(imagePath),
          fit: _boxFit,
          errorBuilder: (_, __, ___) => ColoredBox(color: color),
        ),
        ColoredBox(color: color.withValues(alpha: 0.35)),
        if (child != null) child!,
      ],
    );
  }
}
