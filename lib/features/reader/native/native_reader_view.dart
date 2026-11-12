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
/// 同一个 run，跨段选择照常；只有跨标题（居中）这种对齐变化处选择会断开。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  });

  /// 标注 id（点按/编辑用）。
  final String id;

  /// 章序号。
  final int chapterIndex;

  /// 起点（章内字符偏移）。
  final int start;

  /// 终点（不含）。
  final int end;

  /// 底色（已含透明度）。
  final Color color;
}

/// 原生正文的文本选择（长按选字）。
class NativeSelection {
  const NativeSelection({
    required this.chapterIndex,
    required this.start,
    required this.end,
    required this.text,
    required this.anchor,
  });

  /// 章序号。
  final int chapterIndex;

  /// 起点（章内字符偏移）。
  final int start;

  /// 终点（不含）。
  final int end;

  /// 选中文字。
  final String text;

  /// 菜单锚点（全局坐标，取长按位置）。
  final Offset anchor;
}

/// 压掉 EditableText 自动派生 strut 的显式 strut（见 _runWidget）。
const StrutStyle _noStrut = StrutStyle(fontSize: 0.1, height: 0.1);

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

  /// 选字进行中（拖手柄/重新长按）→ 先收起菜单。
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
  })? _turnCtx;

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

  /// 最近一次按下的全局坐标（选字菜单锚点；SelectableText 不给位置）。
  Offset _lastPress = Offset.zero;

  /// 选字菜单防抖：拖动手柄时选区每帧都在变，立刻弹菜单会盖住手柄、
  /// 还会让手柄跳位（用户体感就是“只能一个字一个字挪”）。
  Timer? _selTimer;

  /// 当前有选区的 run（某个 run 清空不影响别的 run）。
  final Set<Key> _selectedRuns = <Key>{};

  bool get _hasSelection => _selectedRuns.isNotEmpty;

  /// 选区代次：换值重建 SelectableText，可清掉系统选区。
  int _selectionEpoch = 0;

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

  /// 清掉正文里的系统选区（创建/取消划线后调用）。
  void clearTextSelection() {
    _selectedRuns.clear();
    _selTimer?.cancel();
    if (mounted) setState(() => _selectionEpoch++);
  }

  /// 下一页（键盘/无障碍/外部按钮用）。
  void nextPage() => _animateTo((_pc.hasClients ? _pc.page!.round() : 0) + 1);

  /// 上一页。
  void previousPage() =>
      _animateTo((_pc.hasClients ? _pc.page!.round() : 0) - 1);

  /// 跳到本章指定字符偏移所在页（TTS 跟读 / 精确恢复用）。
  void jumpToOffset(int offset) {
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
    _clockTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      if (_needsClock || _needsBattery) setState(() {});
      if (_needsBattery) unawaited(_refreshBattery());
    });
    unawaited(_refreshBattery());
    _freeCurlSettle = AnimationController(
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
    _selTimer?.cancel();
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
      final level = await const MethodChannel('qyreader/battery')
          .invokeMethod<int>('level');
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
      oldWidget.marginPreviewListenable?.removeListener(_onMarginPreviewChanged);
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
    final headerH =
        _runningHeight(header: true, scale: scale, settings: effective);
    final footerH =
        _runningHeight(header: false, scale: scale, settings: effective);

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth =
            (constraints.maxWidth - widget.padding.horizontal).clamp(1.0, 1e6);
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
        final textAreaH = (constraints.maxHeight -
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
          _schedulePreview(previewForPage, spec, size, scale, headerH, footerH,
              textAreaH);
        } else {
          final stale = _pagination == null ||
              _paginationChapter != _chapterIdx ||
              _layoutSize != size ||
              _layoutScale != scale ||
              _paginationSignature != spec.metricsSignature;
          if (stale) {
            // 先把当前页按新设置画出来，再防抖后全章分帧重排。
            _schedulePreview(widget.settings, spec, size, scale, headerH,
                footerH, textAreaH);
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
              // 双页模式只预览左栏，右栏留白（版心宽度按单栏算）。
              return previewPage.settings.doublePage
                  ? _spreadFrame(
                      left: content,
                      right: _blankPage(),
                      gutter: 20,
                    )
                  : _spreadFrame(left: content, right: null, gutter: 0);
            }

            final pag = _pagination;
            if (pag == null || _layout == null) {
              return _PageBackground(
                color: widget.theme.background,
                imagePath: widget.backgroundImage,
              );
            }
            final spreads = _spreadCount(pag);
            final itemCount =
                spreads + (_hasPrev ? 1 : 0) + (_hasNext ? 1 : 0);
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
            return Stack(
              fit: StackFit.expand,
              children: [
                Listener(
                  onPointerDown: (e) {
                    _downAt = e.position;
                    _downTime = DateTime.now();
                    _onFreeCurlDown(e);
                  },
                  onPointerMove: _onFreeCurlMove,
                  onPointerCancel: (_) => _resetFreeCurl(),
                  onPointerUp: (e) {
                    _endFreeCurl();
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
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScrollNotification,
                    child: Scrollable(
                      controller: _pc,
                      axisDirection: AxisDirection.right,
                      // 滑动翻页在任何翻页效果下都可用；「无」只是点击时
                      // 瞬间跳跳，不阻止手指拖动。有文本选区时必须禁掉滚动：
                      // 拖选框手柄会被 PageScrollPhysics 抢走当翻页拖动，
                      // 选区刚拖一个字就被取消（用户体感「只能一个字一个字挪」）。
                      physics: mode == PageTurnMode.freeCurl ||
                              _freeCurlArmed ||
                              _freeCurlSettling ||
                              _hasSelection
                          ? const NeverScrollableScrollPhysics()
                          : const PageScrollPhysics(
                              parent: ClampingScrollPhysics()),
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
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
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
                                  builder: (context, child) =>
                                      _applyTurnEffect(
                                    index,
                                    constraints.maxWidth,
                                    child!,
                                  ),
                                );
                              },
                              childCount: itemCount,
                            ),
                          ),
                        ],
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
  })? _previewRequest;
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
        settings, size, scale, _chapterIdx, _anchorChapterOffset());
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
    final local = (display - paragraph.indentStart)
        .clamp(0, paragraph.displayEnd - paragraph.indentStart);
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
      _reflowDebounce =
          Timer(const Duration(milliseconds: 120), () => start());
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

    if (_hasPrev && index == 0) {
      final prev = _pageOfChapter(
        _chapterIdx - 1,
        spec,
        columnWidth,
        bodyHeight,
        scale,
      );
      final last = prev.pagination.pageCount - 1;
      return _spreadFrame(
        left: _pageWidget(_chapterIdx - 1, prev.layout, prev.pagination, last,
            headerH, footerH, columnWidth, scale, bodyExpanded),
        right: widget.settings.doublePage
            ? _blankPage()
            : null,
        gutter: gutter,
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
      return _spreadFrame(
        left: widget.settings.doublePage
            ? _blankPage()
            : _pageWidget(_chapterIdx + 1, next.layout, next.pagination, 0,
                headerH, footerH, columnWidth, scale, bodyExpanded),
        right: widget.settings.doublePage
            ? _pageWidget(_chapterIdx + 1, next.layout, next.pagination, 0,
                headerH, footerH, columnWidth, scale, bodyExpanded)
            : null,
        gutter: gutter,
      );
    }

    final spread = (index - leading).clamp(0, spreads - 1);
    if (!widget.settings.doublePage) {
      return _spreadFrame(
        left: _pageWidget(_chapterIdx, _layout!, pag, spread, headerH, footerH,
            columnWidth, scale, bodyExpanded),
        right: null,
        gutter: 0,
      );
    }
    final first = spread * 2;
    final second = first + 1;
    return _spreadFrame(
      left: _pageWidget(_chapterIdx, _layout!, pag, first, headerH, footerH,
          columnWidth, scale, bodyExpanded),
      right: second < pag.pageCount
          ? _pageWidget(_chapterIdx, _layout!, pag, second, headerH, footerH,
              columnWidth, scale, bodyExpanded)
          : _blankPage(),
      gutter: gutter,
    );
  }

  Widget _spreadFrame({
    required Widget left,
    required Widget? right,
    required double gutter,
  }) {
    // 每一页都要自带不透明白底：覆盖/仿真翻页时旧页被钉住、新页滑到它
    // 上面，页面若透明，两页正文会叠在一起（仿真翻页截图里的重影）。
    // 垂直留白并入页眉/页脚带（见 _pageContent），这里只保留左右留白，
    // 三段才能各占满整屏宽度。版心高度见 build 里的 textAreaH。
    return _PageBackground(
      color: widget.theme.background,
      imagePath: widget.backgroundImage,
      child: Padding(
        padding: EdgeInsets.only(
          left: widget.padding.left,
          right: widget.padding.right,
        ),
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
          child: Opacity(opacity: (1 - rel.abs()).clamp(0.0, 1.0), child: child),
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

  /// 指定起止的一页（预览页也走这里，保证与正式排版同一套渲染）。
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
    final runs = _buildRuns(layout, start, end, stretch: stretch);
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
        SizedBox(
          height: headerH,
          child: _headerVisible(settings)
              ? Padding(
                  padding: EdgeInsets.only(
                    top: settings.headerMarginTop,
                  ),
                  child: _runningBlock(
                      header: true, ctx: pageCtx, settings: settings),
                )
              : null,
        ),
        Expanded(
          // 正文上/下边距：分别是「正文文字顶部距页眉文字底部」「正文
          // 文字底部距页脚文字顶部」。
          child: Padding(
            padding: EdgeInsets.only(
              top: settings.marginTop,
              bottom: settings.marginBottom,
            ),
            child: Listener(
              onPointerDown: (e) => _lastPress = e.position,
              child: ClipRect(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < runs.length; i++) ...[
                      if (runs[i].gapBefore > 0.5)
                        SizedBox(height: runs[i].gapBefore),
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
            ),
          ),
        ),
        // 页脚带：高度 = 页脚文字 + max(页脚下边距, 安全区)，带顶 =
        // 页脚文字顶部（与正文底边同一条线），贯到屏幕最下沿。
        SizedBox(
          height: footerH,
          child: _footerVisible(settings)
              ? Padding(
                  padding: EdgeInsets.only(
                    bottom: settings.footerMarginBottom,
                  ),
                  child: _runningBlock(
                      header: false, ctx: pageCtx, settings: settings),
                )
              : null,
        ),
      ],
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
          runs.add(_PageRun(
            start: from,
            rangeEnd: to,
            align: p.align,
            gapBefore: (runs.isEmpty || prev == null
                    ? 0
                    : _gapBetween(prev, p, layout.spec)) *
                stretch,
            paragraphs: [p],
          ));
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
    final before =
        next.isHeading ? spec.headingMarginTop : spec.paragraphSpacing;
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
    final key = ValueKey('run-$chapterIdx-$page-$runIndex-$_selectionEpoch');
    if (widget.onSelection == null) {
      return RichText(
        key: key,
        textAlign: run.align,
        textScaler: TextScaler.linear(scale),
        text: TextSpan(style: layout.spec.bodyStyle, children: spans),
      );
    }
    return SelectableText.rich(
      key: key,
      TextSpan(style: layout.spec.bodyStyle, children: spans),
      textAlign: run.align,
      textScaler: TextScaler.linear(scale),
      // 压掉 EditableText 自动派生的 strut：派生 strut 会把段距占位行
      // 也撑成整行高（段距滑块失效、页底裁字、正文可滑）。显式给一个
      // 比任何行都矮的 strut，渲染就回到与分页测量完全相同的自然高度。
      strutStyle: _noStrut,
      // 正文高度由分页器精确定死；禁止 TextField 内部再滚动（否则正文能上下滑）
      scrollPhysics: const NeverScrollableScrollPhysics(),
      // 选中文字时不要系统自带的「复制 / 全选」浮层：阅读页有自己的
      // 四色划线菜单（SelectionMenu），两套弹窗会叠在一起。
      contextMenuBuilder: (_, __) => const SizedBox.shrink(),
      onSelectionChanged: (selection, cause) => _onRunSelection(
        run,
        layout,
        chapterIdx,
        text,
        selection,
        key,
        cause: cause,
      ),
    );
  }

  /// 选区回调：run 内局部偏移 → 章内字符偏移。
  void _onRunSelection(
    _PageRun run,
    ChapterLayout layout,
    int chapterIdx,
    String runText,
    TextSelection selection,
    Key runKey, {
    SelectionChangedCause? cause,
  }) {
    // 禁用双击选中单词：双击选中的区段立即清掉（长按选字不受影响）。
    if (cause == SelectionChangedCause.doubleTap) {
      _selectedRuns.remove(runKey);
      _selTimer?.cancel();
      widget.onSelectionClear?.call();
      if (mounted) setState(() => _selectionEpoch++);
      return;
    }
    final a = selection.start.clamp(0, runText.length);
    final b = selection.end.clamp(0, runText.length);
    if (selection.isCollapsed || b <= a) {
      _selectedRuns.remove(runKey);
      _selTimer?.cancel();
      widget.onSelectionClear?.call();
      return;
    }
    _selectedRuns.add(runKey);
    // 先收菜单：手柄被菜单盖住就没法顺畅拖范围
    widget.onSelectionClear?.call();
    _selTimer?.cancel();
    _selTimer = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      final from = layout.chapterOfDisplay(run.start + a);
      final to = layout.chapterOfDisplay(run.start + b);
      final chapter = widget.chapters[chapterIdx];
      final start = math.min(from, to).clamp(0, chapter.text.length);
      final end = math.max(from, to).clamp(0, chapter.text.length);
      if (end <= start) return;
      final quote = chapter.text.substring(start, end).trim();
      if (quote.isEmpty) return;
      widget.onSelection?.call(NativeSelection(
        chapterIndex: chapterIdx,
        start: start,
        end: end,
        text: quote,
        anchor: _lastPress,
      ));
    });
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
        for (final (a, b, style) in layout.segmentsOf(from, to, textScale: scale))
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
                .getPositionForOffset(
                  Offset(0, m.baseline - m.ascent + 0.5),
                )
                .offset,
        ];
        painter.dispose();
        // (行号, 补偿区间, 候选字距)
        final candidates = <(int, int, int, double)>[];
        // 只看 run 的最后一行：段中整行由引擎 justify，段末行不补。
        // 「段落被截断」= run 终点没到所在段落的末尾（下一段内容在
        // 下一页继续）；截断处恰好在段落末尾时不补（段末行左对齐）。
        final cutMidParagraph = run.paragraphs.isNotEmpty &&
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
      for (final (a, b, style) in layout.segmentsOf(run.start, run.rangeEnd,
          textScale: _layoutScale))
        (a - run.start, b - run.start, scaled(style)),
    ];

    final highlights = <(int, int, Color)>[];
    void addRange(int chapterStart, int chapterEnd, Color color) {
      if (chapterEnd <= chapterStart) return;
      final ds = layout.displayOfChapter(chapterStart) - run.start;
      final de = layout.displayOfChapter(chapterEnd) - run.start;
      final a = math.max(0, math.min(ds, de));
      final b = math.min(text.length, math.max(ds, de));
      if (b > a) highlights.add((a, b, color));
    }

    for (final m in widget.marks) {
      if (m.chapterIndex != chapterIdx) continue;
      addRange(m.start, m.end, m.color);
    }
    final hl = widget.ttsHighlight?.value;
    if (hl != null && hl.chapterIndex == chapterIdx) {
      addRange(hl.start, hl.end, widget.theme.accent.withValues(alpha: 0.26));
    }

    // 统一成互不重叠的扁平片段（段样式 × 高亮背景），再一起应用末行补偿。
    final parts = <(int, int, TextStyle, Color?)>[];
    if (highlights.isEmpty) {
      parts.addAll([
        for (final (a, b, style) in segments) (a, b, style, null),
      ]);
    } else {
      highlights.sort((x, y) => x.$1.compareTo(y.$1));
      for (final (a, b, style) in segments) {
        var pos = a;
        for (final (ha, hb, color) in highlights) {
          if (hb <= pos || ha >= b) continue;
          final hs = math.max(pos, ha);
          final he = math.min(b, hb);
          if (hs > pos) parts.add((pos, hs, style, null));
          parts.add((hs, he, style, color));
          pos = he;
        }
        if (pos < b) parts.add((pos, b, style, null));
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

  /// 把扁平片段按端行补偿区间切成 span（区间内叶子追加字距）。
  ///
  /// 叶子 style 未显式带 letterSpacing 时继承根样式（spec.bodyStyle），
  /// 补偿要在该基数上加。渲染与 `_justifyFor` 的自校准共用本方法，
  /// 保证两边字距口径一致。
  List<InlineSpan> _spansWithJustify(
    String text,
    List<(int, int, TextStyle, Color?)> parts,
    List<_RunJustify> ranges,
    double baseSpacing,
  ) {
    final out = <InlineSpan>[];
    for (final (a, b, style, bg) in parts) {
      TextStyle plain(TextStyle s) =>
          bg == null ? s : s.copyWith(backgroundColor: bg);
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
          out.add(
            TextSpan(text: text.substring(pos, s), style: plain(style)),
          );
        }
        out.add(TextSpan(
          text: text.substring(s, e),
          style: plain(
            style.copyWith(
              letterSpacing: (style.letterSpacing ?? baseSpacing) + r.delta,
            ),
          ),
        ));
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
    final corner = _freeCurlCorner ??= _freeCurlCornerFor(
      size,
      forward,
      down,
    );
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
    final commit = forward
        ? dx < -size.width * 0.18
        : dx > size.width * 0.18;
    _freeCurlSettling = true;
    _freeCurlCommit = commit;
    _freeCurlSettleFrom = geometry.finger;
    _freeCurlSettleTo = commit
        ? Offset(
            forward ? -size.width : size.width * 2,
            geometry.finger.dy,
          )
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
    final hadOverlay =
        _freeCurlOldPage != null || _freeCurlNewPage != null;
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
    final geometry = CurlGeometry(
      page: size,
      progress: delta.clamp(0.0, 1.0),
    );
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
    final chapterCount = widget.chapters.length;
    final percent = chapterCount == 0
        ? 0.0
        : ((_chapterIdx + p / pages) / chapterCount).clamp(0.0, 1.0);
    widget.onPosition(NativePosition(
      chapterIndex: _chapterIdx,
      page: p + 1,
      pages: pages,
      offset: offset,
      percent: percent.toDouble(),
    ));
  }

  void _handleTap(Offset local, BoxConstraints c, Pagination pag) {
    if (_hasSelection) return;
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
    final lineHeight = (layout.spec.bodyStyle.fontSize ?? 16) *
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
    this.child,
  });

  final Color color;
  final String imagePath;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (imagePath.isEmpty) return ColoredBox(color: color, child: child);
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(imagePath),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ColoredBox(color: color),
        ),
        ColoredBox(color: color.withValues(alpha: 0.35)),
        if (child != null) child!,
      ],
    );
  }
}