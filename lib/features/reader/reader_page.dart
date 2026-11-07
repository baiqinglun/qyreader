/// 阅读器页面：双 WebView 池 + 原生翻页动画 + chrome。
///
/// 池不变式：隐藏层始终显示可视层的下一页。
/// - 前翻：纯原生动画（隐藏层已预渲染下一页），提交后旧可视层 `syncNext` 补位到 N+2。
/// - 后翻：截屏覆盖层滑动 + 两个视图同时 `prevPage()`，完成后不变式恢复。
/// - 翻页期间不触发 JS 重排：内容先行渲染完成，动画只变换容器。
/// - 渲染页以 file:// 加载；JS→Dart 消息带队列重发（见 reader.html）；
///   首次渲染由 JS 自主完成（loadBook 携带初始定位），不依赖桥时序。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Locator;
import 'package:go_router/go_router.dart';

import '../../app/theme/reading_theme.dart';
import '../../core/locator.dart';
import 'reader_assets.dart';
import 'reader_bridge.dart';
import 'reader_bridge_events.dart';
import 'reader_controller.dart';
import 'reader_settings.dart';
import 'widgets/toc_drawer.dart';
import 'widgets/typesetting_panel.dart';

/// 池中一个 WebView 槽位。
class _ViewSlot {
  _ViewSlot(this.id);

  /// 槽位标识（'A' / 'B'）。
  final String id;

  ReaderBridge? bridge;
  bool bridgeReady = false;
  bool bookReady = false;
  Locator? locator;

  /// 隐藏层同步簿记：最近一次对齐的可视层位置 / 正在对齐的目标。
  Locator? lastSyncedVisible;
  Locator? pendingSyncVisible;
}

/// 一次翻页交互（拖拽或弹簧回弹期间）。
class _Turn {
  _Turn({required this.isForward, required this.t});

  /// true 前翻 / false 后翻。
  final bool isForward;

  /// 进度 0..1。
  double t;
}

/// 阅读器页面。
class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({required this.bookId, super.key});

  /// 书籍 id。
  final String bookId;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with SingleTickerProviderStateMixin {
  final _ViewSlot _a = _ViewSlot('A');
  final _ViewSlot _b = _ViewSlot('B');
  bool _visibleIsA = true;

  Uri? _readerUri;
  String _bookBase64 = '';
  String? _initialLocatorJson;
  bool _booted = false;
  bool _bootTimedOut = false;
  bool _windowsBlocked = false;
  int _reloadEpoch = 0;
  final Map<String, GlobalKey> _paneKeys = {};

  _Turn? _turn;
  late final AnimationController _settle;

  Offset? _pointerStart;
  Duration _pointerStartAt = Duration.zero;

  Uint8List? _backOverlay;
  bool _backInFlight = false;
  bool _hiddenResyncing = false;
  Timer? _lockTimeout;

  bool _chromeVisible = true;
  bool _tocOpen = false;

  /// 启动诊断（看门狗触发时展示在兜底面板）
  final List<String> _diag = <String>[];
  void _diagLog(String line) {
    debugPrint('reader-diag: $line');
    _diag.add(line);
    if (_diag.length > 24) _diag.removeAt(0);
    if (_bootTimedOut && mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(vsync: this);
    _settle.addListener(() {
      if (_turn != null) setState(() => _turn!.t = _settle.value);
    });
    _settle.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finalizeTurn();
    });
    _boot();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final settings = ref.read(readingSettingsControllerProvider);
    if (settings.flow == ReadingFlow.scrolled) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goForward();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goBackward();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _lockTimeout?.cancel();
    _settle.dispose();
    ref.read(readerControllerProvider(widget.bookId).notifier).flushProgress();
    super.dispose();
  }

  _ViewSlot get _visible => _visibleIsA ? _a : _b;
  _ViewSlot get _hidden => _visibleIsA ? _b : _a;

  ReaderController get _controller =>
      ref.read(readerControllerProvider(widget.bookId).notifier);
  ReaderState get _controllerState =>
      ref.read(readerControllerProvider(widget.bookId));

  GlobalKey _paneKeyFor(_ViewSlot slot) => _paneKeys.putIfAbsent(
    '$_reloadEpoch-${slot.id}',
    () => GlobalKey(debugLabel: 'reader-pane-${slot.id}'),
  );

  Future<void> _boot() async {
    _diagLog('boot start');
    // flutter_inappwebview_windows 0.6.0（beta）在 Flutter 子树重排时
    // 丢失 WebView2 合成内容（本机实测：首次渲染后任何重排即白屏）。
    // Windows 明确禁用，待插件稳定后评估（见 M6）。
    if (!kIsWeb && Platform.isWindows) {
      if (mounted) setState(() => _windowsBlocked = true);
      return;
    }
    await _controller.init();
    final state = _controllerState;
    final book = state.book;
    if (book == null) return;

    _readerUri = await ensureReaderHtmlFile();
    _diagLog('reader html file: $_readerUri');
    final bytes = await File(book.filePath).readAsBytes();
    _bookBase64 = base64Encode(bytes);
    final initial = state.initialLocator;
    _initialLocatorJson = initial == null ? null : locatorToJson(initial);
    _diagLog(
      'book loaded (${bytes.length}B), initial locator: $_initialLocatorJson',
    );
    if (!mounted) return;
    setState(() => _booted = true);

    // WebView 平台不可用（无 WebView2 / 插件缺实现）的兜底提示
    Timer(const Duration(seconds: 12), () {
      if (mounted && !_a.bridgeReady && !_b.bridgeReady) {
        setState(() => _bootTimedOut = true);
      }
    });

    // 设置变化 → 样式热更新；flow 切换 → 重建视图
    ref.listenManual(readingSettingsControllerProvider, (prev, next) {
      if (prev == null) return;
      if (prev.flow != next.flow) {
        _reloadViews();
      } else {
        _applyStyleToAll();
      }
    });
  }

  void _applyStyleToAll() {
    final payload = readerStylePayload(
      ref.read(readingSettingsControllerProvider),
    );
    for (final v in <_ViewSlot>[_a, _b]) {
      if (v.bookReady) v.bridge?.applyStyle(payload);
    }
  }

  Future<void> _reloadViews() async {
    // flow 切换需重建 rendition：换 GlobalKey 强制重新膨胀 WebView
    for (final v in <_ViewSlot>[_a, _b]) {
      v.bookReady = false;
      v.bridgeReady = false;
      v.locator = null;
      v.lastSyncedVisible = null;
      v.pendingSyncVisible = null;
    }
    _reloadEpoch++;
    if (!mounted) return;
    setState(() => _booted = false);
    await Future<void>.delayed(Duration.zero);
    if (mounted) setState(() => _booted = true);
  }

  // ---- 桥事件 ----

  void _onJsEvent(_ViewSlot slot, List<dynamic> args) {
    final raw = args.isEmpty ? null : args.first as String?;
    if (raw == null) return;
    final event = parseReaderEvent(raw);
    if (event == null) return;

    switch (event) {
      case ReaderBridgeReady():
        slot.bridgeReady = true;
      case ReaderBookReady():
        _onBookReady(slot);
      case ReaderLocationsReady():
        _controller.onLocationsReady();
        // locations 就绪后让可视层重报位置，补齐 percent（进度保存依赖它）
        if (slot == _visible) {
          slot.bridge?.reportLocation();
        }
      case ReaderRelocated(:final locator, :final atStart, :final atEnd):
        _onRelocated(slot, locator, atStart, atEnd);
      case ReaderTap(:final x, :final y):
        _onContentTap(x, y);
      case ReaderError(:final code, :final message):
        debugPrint('reader[${slot.id}] error($code): $message');
    }
    if (mounted) setState(() {});
  }

  void _onBookReady(_ViewSlot slot) {
    slot.bookReady = true;
    final settings = ref.read(readingSettingsControllerProvider);
    slot.bridge?.applyStyle(readerStylePayload(settings));
    _syncHiddenIfNeeded();
  }

  void _onRelocated(_ViewSlot slot, Locator locator, bool atStart, bool atEnd) {
    slot.locator = locator;

    if (slot == _visible) {
      _controller.onRelocated(locator, atStart: atStart, atEnd: atEnd);
      _syncHiddenIfNeeded();
    } else {
      // 隐藏层：完成一次对齐
      if (slot.pendingSyncVisible != null) {
        slot.lastSyncedVisible = slot.pendingSyncVisible;
        slot.pendingSyncVisible = null;
      }
      _hiddenResyncing = false;
      _lockTimeout?.cancel();
    }
    // 后翻等待的两个 prev relocated：两边都到位即解锁
    if (_backInFlight && _a.locator != null && _b.locator != null) {
      _backInFlight = false;
      _lockTimeout?.cancel();
    }
  }

  /// 让隐藏层对齐到可视层的下一页。
  void _syncHiddenIfNeeded() {
    final visible = _visible;
    final hidden = _hidden;
    final target = visible.locator;
    if (!visible.bookReady ||
        !hidden.bookReady ||
        target == null ||
        hidden.pendingSyncVisible != null ||
        hidden.lastSyncedVisible == target) {
      return;
    }
    hidden.pendingSyncVisible = target;
    hidden.bridge?.syncNextMap(_locatorMap(target));
  }

  Map<String, dynamic> _locatorMap(Locator l) =>
      jsonDecode(locatorToJson(l)) as Map<String, dynamic>;

  // ---- 翻页命令 ----

  bool get _canForward {
    if (_turn != null || _hiddenResyncing) return false;
    if (_controllerState.atEnd) return false;
    return _hidden.bookReady && _hidden.locator != null;
  }

  bool get _canBackward =>
      _turn == null && !_backInFlight && !_controllerState.atStart;

  void _goForward() {
    if (!_canForward) return;
    if (ref.read(readingSettingsControllerProvider).pageTurnMode ==
        PageTurnMode.none) {
      _completeForwardInstant();
      return;
    }
    setState(() => _turn = _Turn(isForward: true, t: 0));
    _settleTurn(commit: true);
  }

  void _goBackward() {
    if (!_canBackward) return;
    if (ref.read(readingSettingsControllerProvider).pageTurnMode ==
        PageTurnMode.none) {
      _turnBothViews();
      return;
    }
    _captureAndTurnBack();
  }

  Future<void> _captureAndTurnBack() async {
    Uint8List? shot;
    try {
      shot = await _visible.bridge?.screenshot();
    } catch (_) {
      shot = null;
    }
    if (!mounted) return;
    if (shot != null) setState(() => _backOverlay = shot);
    _turnBothViews();
  }

  /// 两个视图同时 prev（后翻），进入 in-flight 锁。
  void _turnBothViews() {
    _backInFlight = true;
    _armLockTimeout();
    _a.bridge?.prevPage();
    _b.bridge?.prevPage();
  }

  void _settleTurn({required bool commit}) {
    final turn = _turn;
    if (turn == null) return;
    const spring = SpringDescription(mass: 1, stiffness: 180, damping: 18);
    _settle
      ..reset()
      ..animateWith(SpringSimulation(spring, turn.t, commit ? 1 : 0, 0));
  }

  void _completeForwardInstant() {
    final newVisible = _hidden;
    final oldVisible = _visible;
    _visibleIsA = !_visibleIsA;
    // 旧可视层（新隐藏层）补位到新可视层的下一页
    oldVisible.lastSyncedVisible = null;
    oldVisible.pendingSyncVisible = null;
    _hiddenResyncing = true;
    _armLockTimeout();
    final target = newVisible.locator;
    if (target != null) {
      oldVisible.pendingSyncVisible = target;
      oldVisible.bridge?.syncNextMap(_locatorMap(target));
    }
    setState(() {});
  }

  void _armLockTimeout() {
    _lockTimeout?.cancel();
    _lockTimeout = Timer(const Duration(milliseconds: 1500), () {
      _hiddenResyncing = false;
      _backInFlight = false;
    });
  }

  void _finalizeTurn() {
    final turn = _turn;
    _turn = null;
    if (turn == null) return;
    final committed = turn.t > 0.5;
    if (turn.isForward) {
      if (committed) {
        _completeForwardInstant();
      } else {
        setState(() {});
      }
      return;
    }
    if (committed) {
      // 后翻提交：可视层已是 N-1；隐藏层（也 prev 过）现显示 N，不变式保持
      setState(() => _backOverlay = null);
    } else {
      // 取消：内容已 prev 过，两个视图 next 恢复
      _a.bridge?.nextPage();
      _b.bridge?.nextPage();
      setState(() => _backOverlay = null);
    }
  }

  // ---- 手势 ----

  void _onPointerDown(PointerDownEvent e) {
    _pointerStart = e.position;
    _pointerStartAt = e.timeStamp;
  }

  void _onPointerMove(PointerMoveEvent e, double width) {
    final start = _pointerStart;
    if (start == null) return;
    final dx = e.position.dx - start.dx;

    final turn = _turn;
    if (turn == null) {
      if (dx.abs() < 12) return;
      if (_settle.isAnimating) return;
      final settings = ref.read(readingSettingsControllerProvider);
      if (settings.flow == ReadingFlow.scrolled) return;
      final forward = dx < 0;
      if (forward && !_canForward) return;
      if (!forward && !_canBackward) return;
      setState(
        () => _turn = _Turn(
          isForward: forward,
          t: ((forward ? -dx : dx) / width).clamp(0, 1),
        ),
      );
      if (!forward) {
        // 后翻：先截屏再驱动两个视图 prev
        _captureAndTurnBack();
      }
      return;
    }

    if (_settle.isAnimating) return;
    final t = ((turn.isForward ? -dx : dx) / width).clamp(0.0, 1.0);
    setState(() => turn.t = t);
  }

  void _onPointerUp(PointerUpEvent e, double width) {
    final start = _pointerStart;
    _pointerStart = null;
    final turn = _turn;
    if (turn == null || start == null) return;
    final ms = (e.timeStamp - _pointerStartAt).inMilliseconds.clamp(1, 100000);
    final vx = (e.position.dx - start.dx) / ms * 1000;
    final draggingForward = turn.isForward;
    final sameDirection = vx.sign == (draggingForward ? -1.0 : 1.0);
    final committed = turn.t > 0.5 || (sameDirection && vx.abs() > 800);
    _settleTurn(commit: committed);
  }

  // ---- 点击分区 ----

  void _onContentTap(double x, double y) {
    if (_turn != null || _settle.isAnimating) return;
    final width = MediaQuery.sizeOf(context).width;
    final settings = ref.read(readingSettingsControllerProvider);
    if (settings.flow == ReadingFlow.scrolled) {
      setState(() => _chromeVisible = !_chromeVisible);
      return;
    }
    if (x < width / 3) {
      if (_chromeVisible) {
        setState(() => _chromeVisible = false);
        return;
      }
      _goBackward();
    } else if (x > width * 2 / 3) {
      if (_chromeVisible) {
        setState(() => _chromeVisible = false);
        return;
      }
      _goForward();
    } else {
      setState(() => _chromeVisible = !_chromeVisible);
    }
  }

  // ---- 跳转 ----

  void _onSeek(double percent) {
    _visible.bridge?.gotoPercent(percent);
    _resetHiddenSync();
  }

  void _onChapterTap(String href) {
    setState(() {
      _tocOpen = false;
      _chromeVisible = false;
    });
    _visible.bridge?.gotoHref(href);
    _resetHiddenSync();
  }

  void _resetHiddenSync() {
    // 跳转后隐藏层失效，待可视层 relocated 后由 _syncHiddenIfNeeded 补位
    _hidden.lastSyncedVisible = null;
    _hidden.pendingSyncVisible = null;
  }

  void _onBack() {
    _controller.flushProgress();
    context.pop();
  }

  Future<void> _showTypesetting() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ref
          .read(readingSettingsControllerProvider)
          .theme
          .chromeSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const TypesettingPanel(),
    );
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerControllerProvider(widget.bookId));
    final settings = ref.watch(readingSettingsControllerProvider);
    final theme = settings.theme;

    final contentReady = _booted &&
        state.book != null &&
        !_bootTimedOut &&
        !_windowsBlocked &&
        _readerUri != null;

    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Focus(
          autofocus: true,
          onKeyEvent: _onKeyEvent,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              // 根 Stack 的 children 恒定（数量/类型/顺序不变）：
              // Windows 平台视图对子树重排敏感，显隐只在层内部处理。
              return Stack(
                children: [
                  // [0] 内容层
                  Positioned.fill(
                    child: contentReady
                        ? Stack(
                            children: [
                              _viewLayer(_visible, width, settings, theme),
                              _viewLayer(_hidden, width, settings, theme),
                            ],
                          )
                        : Center(
                            child: CircularProgressIndicator(
                              color: theme.accent,
                            ),
                          ),
                  ),
                  // [1] 后翻覆盖层：旧页截图滑出
                  Positioned.fill(
                    child: _backOverlay != null
                        ? RepaintBoundary(
                            child: Transform.translate(
                              offset: Offset(width * (_turn?.t ?? 0), 0),
                              child: Image.memory(
                                _backOverlay!,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  // [2] 手势观察层（translucent；点击由 JS tap 上报）
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: _onPointerDown,
                      onPointerMove: (e) => _onPointerMove(e, width),
                      onPointerUp: (e) => _onPointerUp(e, width),
                      onPointerCancel: (_) {
                        _pointerStart = null;
                        if (_turn != null && !_settle.isAnimating) {
                          _settleTurn(commit: false);
                        }
                      },
                    ),
                  ),
                  // [3] chrome 层（内部显隐，不动内容层）
                  Positioned.fill(
                    child: (_chromeVisible && state.book != null)
                        ? Stack(
                            children: [
                              _TopBar(
                                state: state,
                                theme: theme,
                                onBack: _onBack,
                              ),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: _BottomBar(
                                  state: state,
                                  theme: theme,
                                  onToc: () => setState(() => _tocOpen = true),
                                  onTypesetting: _showTypesetting,
                                  onSeek: _onSeek,
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                  // [4] 目录抽屉（内部 AnimatedSwitcher 恒定）
                  TocDrawer(
                    open: _tocOpen,
                    theme: theme,
                    chapters: state.chapters,
                    currentHref: _visible.locator?.href,
                    onDismiss: () => setState(() => _tocOpen = false),
                    onChapter: _onChapterTap,
                  ),
                  // [5] 全屏遮罩：装载错误 / WebView 不可用诊断
                  Positioned.fill(child: _buildOverlay(state, theme)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 全屏遮罩：装载错误或 WebView 启动诊断（恒定占位，内部条件渲染）。
  Widget _buildOverlay(ReaderState state, ReadingTheme theme) {
    if (_windowsBlocked) {
      return ColoredBox(
        color: theme.background,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Windows 桌面端的 WebView2 插件（flutter_inappwebview_windows '
              '0.6.0 beta）存在合成缺陷：任何界面重排都会丢失已渲染内容。'
              '\n\n阅读器请安装 Android 安装包验收（qyreader/ 目录下的 APK）；'
              'Windows 支持待插件稳定后评估。',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.chromeForeground, height: 1.6),
            ),
          ),
        ),
      );
    }
    final message = state.loadError;
    if (message != null) {
      return ColoredBox(
        color: theme.background,
        child: Center(
          child: Text(message, style: TextStyle(color: theme.chromeForeground)),
        ),
      );
    }
    if (_bootTimedOut) {
      return ColoredBox(
        color: theme.background,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'WebView 未能启动（诊断信息）',
              style: TextStyle(
                color: theme.chromeForeground,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            for (final line in _diag)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  line,
                  style: TextStyle(
                    color: theme.chromeForeground.withValues(alpha: 0.8),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  /// 构造某一层。所有状态（静止/翻页中/隐藏）共享同一棵 widget 结构
  /// （Positioned.fill > RepaintBoundary > Opacity > Transform.translate >
  /// Stack[Transform > pane, 遮罩]），只改数值参数——避免 Windows 平台
  /// 视图在子树结构变化时丢内容。隐藏态 = 恒定位移到屏幕外右侧。
  Widget _viewLayer(
    _ViewSlot slot,
    double width,
    ReadingSettings settings,
    ReadingTheme theme,
  ) {
    final isHidden = slot != _visible;
    final turn = _turn;
    final forwardTurn = turn != null && turn.isForward;
    final mode = settings.pageTurnMode;
    final t = turn?.t ?? 0;

    // 数值化变换参数（无结构分支）
    double dx = 0;
    double dy = 0;
    double dim = 0;
    double rotY = 0;
    double opacity = 1;
    if (isHidden) {
      if (forwardTurn) {
        switch (mode) {
          case PageTurnMode.slide:
            dx = width * (1 - t);
            rotY = -0.035 * (1 - t); // ≈ 2° 透视
          case PageTurnMode.cover:
            dx = width * (1 - t);
          case PageTurnMode.fade:
            opacity = t;
          case PageTurnMode.none:
            dx = width;
        }
      } else {
        // 静止/后翻期间：恒定位移到屏幕外右侧（结构不变）
        dx = width;
      }
    } else {
      if (forwardTurn) {
        switch (mode) {
          case PageTurnMode.slide:
            dx = -width * t;
          case PageTurnMode.cover:
            dx = -width * 0.08 * t;
            dim = 0.15 * t;
          case PageTurnMode.fade:
            opacity = 1 - t;
            dy = -2 * t;
          case PageTurnMode.none:
            dx = 0;
        }
      }
    }

    return Positioned.fill(
      child: RepaintBoundary(
        child: Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(dx, dy),
            child: Stack(
              children: [
                Transform(
                  alignment: Alignment.centerLeft,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.002)
                    ..rotateY(rotY),
                  child: _WebViewPane(
                    key: _paneKeyFor(slot),
                    slot: slot,
                    htmlUri: _readerUri!,
                    bookBase64: _bookBase64,
                    // JS 自主首渲：可视层带初始定位，隐藏层从头显示
                    locatorJson: slot == _visible ? _initialLocatorJson : null,
                    onJsEvent: (args) => _onJsEvent(slot, args),
                    onDiag: _diagLog,
                  ),
                ),
                // cover 模式：可视层压暗
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: dim),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 单个 WebView 面板。
class _WebViewPane extends StatefulWidget {
  const _WebViewPane({
    required this.slot,
    required this.htmlUri,
    required this.bookBase64,
    required this.locatorJson,
    required this.onJsEvent,
    required this.onDiag,
    super.key,
  });

  final _ViewSlot slot;

  /// 渲染页 file:// 地址。
  final Uri htmlUri;

  /// 书籍 base64。
  final String bookBase64;

  /// 初始定位 JSON（可空）。
  final String? locatorJson;
  final void Function(List<dynamic> args) onJsEvent;
  final void Function(String line) onDiag;

  @override
  State<_WebViewPane> createState() => _WebViewPaneState();
}

class _WebViewPaneState extends State<_WebViewPane> {
  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.htmlUri.toString())),
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
        disableContextMenu: true,
        supportZoom: false,
      ),
      onWebViewCreated: (controller) {
        widget.onDiag('webview created (${widget.slot.id})');
        widget.slot.bridge = ReaderBridge(controller);
        controller.addJavaScriptHandler(
          handlerName: 'readerEvent',
          callback: (args) {
            widget.onJsEvent(args);
            return null;
          },
        );
      },
      onLoadStart: (_, __) => widget.onDiag('[${widget.slot.id}] loadStart'),
      onLoadStop: (_, __) {
        widget.onDiag('[${widget.slot.id}] loadStop → loadBook');
        widget.slot.bridge?.loadBook(
          widget.bookBase64,
          locatorJson: widget.locatorJson,
        );
      },
      onReceivedError: (_, request, error) => widget.onDiag(
        '[${widget.slot.id}] receivedError ${error.type} ${error.description} url=${request.url}',
      ),
      onReceivedHttpError: (_, request, response) => widget.onDiag(
        '[${widget.slot.id}] receivedHttpError ${response.statusCode} url=${request.url}',
      ),
      onConsoleMessage: (_, message) {
        widget.onDiag(
          '[${widget.slot.id}] js(${message.messageLevel}): ${message.message}',
        );
      },
    );
  }
}

/// 顶部栏。
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.state,
    required this.theme,
    required this.onBack,
  });

  final ReaderState state;
  final ReadingTheme theme;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final percent = state.percent;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: theme.chromeSurface,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                BackButton(color: theme.chromeForeground, onPressed: onBack),
                Expanded(
                  child: Text(
                    state.book?.title ?? '阅读器',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: theme.chromeForeground),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    percent == null
                        ? ''
                        : '${(percent * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: theme.chromeForeground.withValues(alpha: 0.7),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部栏：目录 / 进度 / 排版。
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.state,
    required this.theme,
    required this.onToc,
    required this.onTypesetting,
    required this.onSeek,
  });

  final ReaderState state;
  final ReadingTheme theme;
  final VoidCallback onToc;
  final VoidCallback onTypesetting;
  final void Function(double percent) onSeek;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: theme.chromeSurface,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                TextButton(
                  onPressed: onToc,
                  child: Text(
                    '目录',
                    style: TextStyle(color: theme.chromeForeground),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: (state.percent ?? 0).clamp(0.0, 1.0),
                    onChanged: state.locationsReady ? onSeek : null,
                    activeColor: theme.accent,
                  ),
                ),
                TextButton(
                  onPressed: onTypesetting,
                  child: Text(
                    'Aa',
                    style: TextStyle(color: theme.chromeForeground),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
