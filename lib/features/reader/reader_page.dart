/// 阅读器页面：双 WebView 池 + 原生翻页动画 + chrome。
///
/// 池不变式：隐藏层始终显示可视层的下一页。
/// - 前翻：纯原生动画（隐藏层已预渲染下一页），提交后旧可视层 `syncNext` 补位到 N+2。
/// - 后翻：截屏覆盖层滑动 + 两个视图同时 `prevPage()`，完成后不变式恢复。
/// - 翻页期间不触发 JS 重排：内容先行渲染完成，动画只变换容器。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
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
  bool positioned = false;
  Locator? locator;
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

  String _html = '';
  String _bookBase64 = '';
  bool _booted = false;
  bool _bootTimedOut = false;

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

  @override
  void dispose() {
    _lockTimeout?.cancel();
    _settle.dispose();
    ref.read(readerControllerProvider(widget.bookId).notifier).flushProgress();
    super.dispose();
  }

  _ViewSlot get _visible => _visibleIsA ? _a : _b;
  _ViewSlot get _hidden => _visibleIsA ? _b : _a;
  _ViewSlot _slot(String id) => id == 'A' ? _a : _b;

  ReaderController get _controller =>
      ref.read(readerControllerProvider(widget.bookId).notifier);
  ReaderState get _controllerState =>
      ref.read(readerControllerProvider(widget.bookId));

  Future<void> _boot() async {
    await _controller.init();
    final book = _controllerState.book;
    if (book == null) return;

    _html = await loadReaderHtml();
    final bytes = await File(book.filePath).readAsBytes();
    _bookBase64 = base64Encode(bytes);
    if (!mounted) return;
    setState(() => _booted = true);

    // WebView 平台不可用（无 WebView2 / 插件缺实现）的兜底提示
    Timer(const Duration(seconds: 10), () {
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
    final payload =
        readerStylePayload(ref.read(readingSettingsControllerProvider));
    for (final v in <_ViewSlot>[_a, _b]) {
      if (v.bookReady) v.bridge?.applyStyle(payload);
    }
  }

  Future<void> _reloadViews() async {
    // flow 切换需重建 rendition：整页重载最可靠
    for (final v in <_ViewSlot>[_a, _b]) {
      v.bookReady = false;
      v.positioned = false;
      v.locator = null;
    }
    if (!mounted) return;
    setState(() => _booted = false);
    await Future<void>.delayed(Duration.zero);
    if (mounted) setState(() => _booted = true);
  }

  // ---- 桥事件 ----

  void _onJsEvent(String viewId, List<dynamic> args) {
    final raw = args.isEmpty ? null : args.first as String?;
    if (raw == null) return;
    final event = parseReaderEvent(raw);
    if (event == null) return;
    final slot = _slot(viewId);

    switch (event) {
      case ReaderBridgeReady():
        slot.bridgeReady = true;
      case ReaderBookReady():
        _onBookReady(slot);
      case ReaderLocationsReady():
        _controller.onLocationsReady();
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

    if (slot == _visible) {
      final initial = _controllerState.initialLocator;
      if (initial != null) {
        slot.bridge?.gotoLocatorMap(_locatorMap(initial));
      } else {
        slot.bridge?.gotoStart();
      }
    }
    _syncHiddenIfNeeded();
  }

  void _onRelocated(_ViewSlot slot, Locator locator, bool atStart, bool atEnd) {
    slot.locator = locator;
    slot.positioned = true;

    if (slot == _visible) {
      _controller.onRelocated(locator, atStart: atStart, atEnd: atEnd);
      _syncHiddenIfNeeded();
    } else {
      _hiddenResyncing = false;
      _lockTimeout?.cancel();
    }
    if (_backInFlight && _a.locator != null && _b.locator != null) {
      _backInFlight = false;
      _lockTimeout?.cancel();
    }
  }

  void _syncHiddenIfNeeded() {
    final visible = _visible;
    final hidden = _hidden;
    if (!visible.bookReady ||
        !hidden.bookReady ||
        visible.locator == null ||
        hidden.positioned) {
      return;
    }
    hidden.bridge?.syncNextMap(_locatorMap(visible.locator!));
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
    _visibleIsA = !_visibleIsA;
    // 旧可视层（新隐藏层）补位到新可视层的下一页
    _hiddenResyncing = true;
    _armLockTimeout();
    newVisible.positioned = false;
    if (_visible.locator != null) {
      newVisible.bridge?.syncNextMap(_locatorMap(_visible.locator!));
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
      // 后翻提交：可视层已是 N-1；隐藏层不需要换位（两边都 prev 过，不变式保持）
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
      setState(() => _turn = _Turn(
            isForward: forward,
            t: ((forward ? -dx : dx) / width).clamp(0, 1),
          ));
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
    _resetHiddenAfterJump();
  }

  void _onChapterTap(String href) {
    setState(() {
      _tocOpen = false;
      _chromeVisible = false;
    });
    _visible.bridge?.gotoHref(href);
    _resetHiddenAfterJump();
  }

  void _resetHiddenAfterJump() {
    // 跳转后隐藏层失效，待可视层 relocated 后由 _syncHiddenIfNeeded 补位
    _hidden.positioned = false;
    _hidden.locator = null;
  }

  void _onBack() {
    _controller.flushProgress();
    context.pop();
  }

  Future<void> _showTypesetting() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          ref.read(readingSettingsControllerProvider).theme.chromeSurface,
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

    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Stack(
              children: [
                if (_booted && state.book != null && !_bootTimedOut) ...[
                  _viewLayer(_visible, width, settings, theme),
                  _viewLayer(_hidden, width, settings, theme),
                ] else
                  Center(
                    child: CircularProgressIndicator(color: theme.accent),
                  ),
                // 后翻覆盖层：旧页截图滑出
                if (_backOverlay != null)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: Transform.translate(
                        offset: Offset(width * (_turn?.t ?? 0), 0),
                        child: Image.memory(
                          _backOverlay!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                // 手势观察层（translucent，不消费事件；点击由 JS tap 上报）
                if (!_bootTimedOut)
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
                if (_chromeVisible && state.book != null) ...[
                  _TopBar(state: state, theme: theme, onBack: _onBack),
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
                TocDrawer(
                  open: _tocOpen,
                  theme: theme,
                  chapters: state.chapters,
                  currentHref: _visible.locator?.href,
                  onDismiss: () => setState(() => _tocOpen = false),
                  onChapter: _onChapterTap,
                ),
                if (state.loadError != null)
                  Positioned.fill(
                    child: ColoredBox(
                      color: theme.background,
                      child: Center(
                        child: Text(
                          state.loadError!,
                          style: TextStyle(color: theme.chromeForeground),
                        ),
                      ),
                    ),
                  ),
                if (_bootTimedOut)
                  Positioned.fill(
                    child: ColoredBox(
                      color: theme.background,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            '当前平台暂不支持 WebView 渲染。\n请在 Android 设备上验收阅读器。',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.chromeForeground),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

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

    Widget layer = _WebViewPane(
      slot: slot,
      html: _html,
      bookBase64: _bookBase64,
      onJsEvent: (args) => _onJsEvent(slot.id, args),
    );

    if (isHidden) {
      if (!forwardTurn) {
        // 静止与后翻期间隐藏层不参与绘制（平台视图保持存活）
        return Offstage(child: layer);
      }
      layer = _hiddenTransform(layer, turn.t, width, mode);
    } else if (forwardTurn) {
      layer = _visibleTransform(layer, turn.t, width, mode);
    }
    return Positioned.fill(child: RepaintBoundary(child: layer));
  }

  Widget _visibleTransform(
      Widget child, double t, double width, PageTurnMode mode) {
    switch (mode) {
      case PageTurnMode.slide:
        return Transform.translate(offset: Offset(-width * t, 0), child: child);
      case PageTurnMode.cover:
        return Stack(
          children: [
            Transform.translate(
              offset: Offset(-width * 0.08 * t, 0),
              child: child,
            ),
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.15 * t),
              ),
            ),
          ],
        );
      case PageTurnMode.fade:
        return Opacity(
          opacity: 1 - t,
          child: Transform.translate(offset: Offset(0, -2 * t), child: child),
        );
      case PageTurnMode.none:
        return child;
    }
  }

  Widget _hiddenTransform(
      Widget child, double t, double width, PageTurnMode mode) {
    switch (mode) {
      case PageTurnMode.slide:
        return Transform.translate(
          offset: Offset(width * (1 - t), 0),
          child: Transform(
            alignment: Alignment.centerLeft,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.002)
              ..rotateY(-0.035 * (1 - t)), // ≈ 2° 透视
            child: child,
          ),
        );
      case PageTurnMode.cover:
        return Transform.translate(
          offset: Offset(width * (1 - t), 0),
          child: child,
        );
      case PageTurnMode.fade:
        return Opacity(opacity: t, child: child);
      case PageTurnMode.none:
        return child;
    }
  }
}

/// 单个 WebView 面板。
class _WebViewPane extends StatefulWidget {
  const _WebViewPane({
    required this.slot,
    required this.html,
    required this.bookBase64,
    required this.onJsEvent,
  });

  final _ViewSlot slot;
  final String html;
  final String bookBase64;
  final void Function(List<dynamic> args) onJsEvent;

  @override
  State<_WebViewPane> createState() => _WebViewPaneState();
}

class _WebViewPaneState extends State<_WebViewPane> {
  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialData: InAppWebViewInitialData(
        data: widget.html,
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
        disableContextMenu: true,
        supportZoom: false,
      ),
      onWebViewCreated: (controller) {
        widget.slot.bridge = ReaderBridge(controller);
        controller.addJavaScriptHandler(
          handlerName: 'readerEvent',
          callback: (args) {
            widget.onJsEvent(args);
            return null;
          },
        );
      },
      onLoadStop: (_, __) {
        widget.slot.bridge?.loadBook(widget.bookBase64);
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
                  child:
                      Text('目录', style: TextStyle(color: theme.chromeForeground)),
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
                  child:
                      Text('Aa', style: TextStyle(color: theme.chromeForeground)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
