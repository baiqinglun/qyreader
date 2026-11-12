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
import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kDebugMode;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        Clipboard,
        ClipboardData,
        KeyDownEvent,
        LogicalKeyboardKey,
        MethodChannel,
        SystemChrome,
        SystemUiMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Locator;
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart' show readerSearchPath;
import '../../app/theme/motion.dart';
import '../../app/theme/reading_theme.dart';
import '../../core/locator.dart';
import '../../domain/entities/annotation.dart';
import '../../domain/entities/book.dart';
import '../../domain/repositories/book_repository.dart';
import '../../domain/entities/bookmark.dart';
import '../../domain/repositories/search_repository.dart';
import '../../domain/services/annotations_markdown.dart';
import 'reader_bridge.dart';
import 'reader_asset_server.dart';
import 'reader_assets.dart';
import 'reader_boot.dart';
import 'widgets/cloud_download_dialog.dart';
import 'page_turn_sound_player.dart';
import 'reader_bridge_events.dart';
import 'reader_controller.dart';
import 'reader_active_marker.dart';
import 'reader_bookmark.dart';
import 'page_layout.dart';
import 'reader_settings.dart';
import 'fonts/reader_fonts.dart';
import 'native/native_chapter_source.dart';
import 'native/native_reader_view.dart';
import 'native/native_tts_surface.dart';
import 'reading_session_tracker.dart';
import 'widgets/annotation_dialog.dart';
import 'widgets/note_editor_sheet.dart';
import 'tts/tts_playback.dart';
import 'tts/tts_settings.dart';
import 'widgets/selection_menu.dart';
import 'widgets/margin_editor_overlay.dart';
import 'widgets/tts_bar.dart';
import 'widgets/tts_sheet.dart';
import 'widgets/toc_drawer.dart';
import 'widgets/typesetting_panel.dart';

/// 阅读页常亮桥（Android FLAG_KEEP_SCREEN_ON，避免引入额外插件）。
const MethodChannel _screenChannel = MethodChannel('qyreader/screen');

/// 隐藏层（预渲染的下一页）的静止位移（相对内容区左边缘）。
///
/// 隐藏层必须整层落在**屏幕右边界之外**，不能只停在内容区右侧：
/// Android WebView 走虚拟显示（纹理）合成，不受 Flutter Stack 的裁剪约束，
/// 停在内容区右边时它的左侧会压在右边距上——用户看到右侧露出下一页的内容
/// （实测：正文右侧约 20px 处出现下一列的竖向缝隙）。
///
/// [contentWidth] = 正文区宽度；[rightGutter] = 正文区右侧到屏幕右边缘的
/// 空白（右边距 + 系统安全区）。
double hiddenLayerRestDx(double contentWidth, double rightGutter) =>
    contentWidth + rightGutter + 2;

/// 池中一个 WebView 槽位。
class _ViewSlot {
  _ViewSlot(this.id);

  /// 槽位标识（'A' / 'B'）。
  final String id;

  ReaderBridge? bridge;
  bool bridgeReady = false;
  bool bookReady = false;
  Locator? locator;

  /// 等待注入划线（bookReady 时视图尚未滚动到目标列，高亮会画偏；
  /// 首次 relocated（display 落定）后再注入）。
  bool pendingHighlights = true;

  /// 本槽位页面的事件序号去重（__n 按页面各自计数，A/B 不能共享集合，
  /// 否则 B 页事件与 A 全部撞号被丢，隐藏池永不就绪、前翻失效）。
  final Set<int> seenEventSeq = <int>{};

  /// 隐藏层同步簿记：最近一次对齐的可视层位置 / 正在对齐的目标。
  Locator? lastSyncedVisible;
  Locator? pendingSyncVisible;

  /// 同步序号：JS 原样回传，过期回调（seq 不匹配）直接丢弃，防止错页。
  int syncSeq = 0;
  int pendingSeq = 0;

  /// 骨架遮罩：该层内容可能还不是目标页（目标页未就绪时先占位，
  /// 动画不等待异步结果）。
  bool covered = false;

  /// 可视页位是否已确认（relocated / 同步完成）。未确认时不能按它的
  /// locator 给隐藏层对齐下一页——会把隐藏层同步成重复页。
  bool settled = false;

  /// 当前所在章的总页数（判断“下一页”是否跨章用）。
  int pages = 0;

  /// 单槽位同步超时（避免某一个 WebView 卡住后永远不可用）。
  Timer? syncTimer;
}

/// 一次翻页交互（拖拽或弹簧回弹期间）。
class _Turn {
  _Turn({required this.isForward, required this.t});

  /// true 前翻 / false 后翻。
  final bool isForward;

  /// 进度 0..1。
  double t;

  /// 后翻是否已对双池下发 prev（提交后回弹期间不能撤销）。
  bool prevIssued = false;

  /// 抬手时是否已请求提交（连续翻页时新手势要把上一段推进到 1，不能取消）。
  bool commitRequested = false;
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _ViewSlot _a = _ViewSlot('A');
  final _ViewSlot _b = _ViewSlot('B');
  bool _visibleIsA = true;

  final ReaderAssetServer _assetServer = ReaderAssetServer();
  Uri? _readerUri;
  String? _bookUrl;
  String? _initialLocatorJson;
  bool _booted = false;
  bool _bootTimedOut = false;

  /// 书籍仓储 future（`initState` 里取一次）。
  ///
  /// `dispose` 里不能再 `ref.read`（widget 已卸载会抛异常），但「最近打开
  /// 时间」必须在退出阅读器时落库，否则书架顶部的「最近在读」永远不显示
  /// 这本书（v2.35.0 修）。这里提前拿住 future，dispose / 切后台都能用。
  Future<BookRepository>? _bookRepoFuture;

  /// 正在退出（已发起落库 + pop）：避免连点返回键 pop 两次。
  bool _exiting = false;
  int _reloadEpoch = 0;
  final Map<String, GlobalKey> _paneKeys = {};

  _Turn? _turn;

  /// 翻页进度（0..1）。
  ///
  /// 单独用 ValueNotifier 承载：翻页动画每帧都要改它，但整页 setState 会
  /// 连带重建 chrome、目录抽屉与两个 WebView 子树——拖拽时每帧一次，
  /// 直接把帧率拖垮（表现为翻页/跟手卡顿）。改成只驱动变换子树。
  final ValueNotifier<double> _turnProgress = ValueNotifier<double>(0);

  late final AnimationController _settle;

  /// 当前拖拽手势的起始槽位。快速连滑时手势可能跨越池交换：
  /// DOWN 落在旧可视层、交换后该层已隐藏，后续事件仍归它所有，
  /// 必须按起始槽位继续接收，否则第二次滑动会被整段丢弃。
  _ViewSlot? _dragSlot;

  /// JS 拖拽跟手状态。HC 模式下 Flutter 收不到触摸，dx 由 reader.html
  /// 逐帧上报；_turn.t 直接由 dx 驱动，抬手后才交给弹簧收尾。
  bool _dragging = false;

  /// 当前手势累计横向位移（touchcancel 时用来救回被中断的滑动）。
  double _dragDx = 0;

  /// 最近一次拖拽/滑动结束时间（抑制紧随其后的合成 tap）。
  DateTime _lastDragEnd = DateTime.fromMillisecondsSinceEpoch(0);

  /// 最近一次注入 WebView 的样式载荷（避免 didChangeMetrics 重复下发）。
  String? _lastStylePayload;

  /// 两层是否已按同一最终尺寸重排（启动时两次 WebView 可能拿到不同的
  /// 临时尺寸，必须先统一再允许隐藏层同步，否则章页数会差一页）。
  bool _layoutReady = false;
  bool _layoutFlushPending = false;

  Uint8List? _backOverlay;
  bool _backInFlight = false;
  Timer? _lockTimeout;

  // 打开即沉浸（菜单收起，点屏幕中央呼出）：初始可见会让第一次系统返回
  // 被「收起菜单」吃掉——从详情页继续阅读进来时要按三次返回才能回书架，
  // 用户预期是两次（沉浸打开后：reader→详情→书架）。
  bool _chromeVisible = false;
  bool _tocOpen = false;
  bool _diagVisible = false;

  /// 边距直调模式的分组（null = 未开启）。
  MarginGroup? _marginGroup;

  /// 边距直调过程中的草稿（关闭/返回时提交）。
  ReadingSettings? _marginDraft;

  /// 亮度（用页面内遮罩实现，0 = 原始，0.65 = 最暗）。
  double _dim = 0;

  /// 边缘手势 HUD（亮度/字号调节时显示）。
  String? _edgeHud;
  double _edgeHudValue = 0;

  /// 边缘纵向手势：起始槽位与基准值（字号起点 / 亮度起点）。
  _ViewSlot? _edgeSlot;
  double _edgeBaseFont = 18;
  double _edgeBaseDim = 0;
  double _edgePreviewFont = 18;

  /// 首次进入阅读器的操作引导。
  bool _guideVisible = false;
  bool _guideChecked = false;
  static const String _kGuideKey = 'reader.guideShown';

  /// 原生 TTS 高亮（只驱动正文 span，不重建整页）。
  final ValueNotifier<TtsHighlight?> _nativeTtsHighlight =
      ValueNotifier<TtsHighlight?>(null);

  /// 原生 TTS 适配层（章节表就绪后创建）。
  NativeTtsSurface? _nativeTts;

  /// 原生阅读面状态句柄（目录/进度/TTS 跳转用）。
  final GlobalKey<NativeReaderViewState> _nativeKey =
      GlobalKey<NativeReaderViewState>();

  bool _nativeInitialised = false;
  int _nativeStartChapter = 0;
  int _nativeStartOffset = 0;

  /// 转场是否结束：书封展开动画期间不挂载正文（章节解析、首次分页
  /// 都是重活，会打断动画帧），只显示 loading；转场完成后才开始加载，
  /// 加载完成再淡入正文。无路由动画（测试/嵌入）时直接视为完成。
  bool _contentRevealed = false;
  Animation<double>? _routeAnim;
  bool _routeAnimHooked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeAnimHooked) return;
    _routeAnimHooked = true;
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null) {
      _contentRevealed = true;
      return;
    }
    _routeAnim = anim;
    anim.addStatusListener(_onRouteAnimStatus);
    if (anim.status == AnimationStatus.completed) _contentRevealed = true;
  }

  void _onRouteAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_contentRevealed) {
      setState(() => _contentRevealed = true);
    }
  }

  /// 划线底色（与旧覆盖层观感一致）。
  static const Map<String, Color> _markFills = {
    'yellow': Color(0x73F7D774),
    'green': Color(0x73A9D98B),
    'blue': Color(0x6B9CC3F5),
    'rose': Color(0x6BF2A9B8),
  };

  /// 已尝试过锚点迁移的标注 id。
  final Set<String> _anchored = {};

  /// 是否走原生文本阅读面。
  bool _useNative(ReadingSettings s) => true; // 只保留原生阅读面

  // ---- M2 标注/书签/检索 ----

  /// 标注与书签的本地镜像（仓储 watch 流驱动，动作做定点桥同步）。
  List<Annotation> _annotations = const [];
  List<Bookmark> _bookmarks = const [];
  StreamSubscription<List<Annotation>>? _annotationsSub;
  StreamSubscription<List<Bookmark>>? _bookmarksSub;

  /// 当前文本选区（非空 = 显示标注菜单）。
  ReaderSelected? _selection;

  /// 选区产生时的可视层页位（页位没变的 relocated 不收选区菜单）。
  Locator? _selectionAnchor;

  /// 正在操作的既有划线（非空 = 显示划线操作面板）。
  Annotation? _activeAnnotation;

  /// TTS 播放控制器（句级朗读 + 跟读高亮 + 自动翻页/续章）。
  late final TtsPlaybackController _tts;

  /// 阅读会话跟踪（统计时长/字数）。
  ReadingSessionTracker? _session;

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
    WidgetsBinding.instance.addObserver(this);
    // 提前拿住仓储：dispose / 切后台时不能再 ref.read（见 _bookRepoFuture）。
    _bookRepoFuture = ref.read(bookRepositoryProvider.future);
    // 记录「正在读这本书」：进程在后台被杀后冷启动可自动回到阅读页
    // （dispose 时清除，主动退出不会误恢复）。
    unawaited(markReaderActive(widget.bookId));
    // 沉浸式 + 常亮（阅读页）
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    unawaited(
      _screenChannel.invokeMethod<void>('keepAwake', true).catchError((_) {}),
    );
    _settle = AnimationController(vsync: this);
    _settle.addListener(() {
      // 只推进进度，不整页重建（见 _turnProgress 注释）。
      if (_turn == null) return;
      _turn!.t = _settle.value;
      _turnProgress.value = _settle.value;
    });
    _settle.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finalizeTurn();
    });
    _tts = TtsPlaybackController(
      bridge: () => _useNative(ref.read(readingSettingsControllerProvider))
          ? (_nativeTts ??= _makeNativeTts())
          : _visible.bridge,
      onFinishedChapter: () {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已朗读到全书末尾')));
      },
    );
    unawaited(_restoreThenBoot());
  }

  /// 打开书前的本地文件检查（按需下载，v2.33.0）。
  ///
  /// 本地没有书源文件时**先问用户**要不要从云端下载，同意后再拉，避免一开
  /// 所有书都把整本 epub 拉下来。拉完（或本地本来就有）再继续启动：章节解析
  /// provider 读不到文件会抛「书籍文件不存在」并被 FutureProvider 缓存、
  /// 不再重试——所以恢复必须在解析之前完成。
  ///
  /// 本地文件还在时**不要**去初始化同步仓储：冷启动首次读取 OSS 配置 /
  /// 安全存储可能很慢，会一直卡在「正在打开…」。
  Future<void> _restoreThenBoot() async {
    Book? book;
    try {
      final repo = await ref
          .read(bookRepositoryProvider.future)
          .timeout(const Duration(seconds: 4));
      book = await repo.getById(widget.bookId);
    } catch (e) {
      // 同步库不可用：按没有缓存场景继续（文件在就正常打开）
      _diagLog('restore skipped: $e');
    }
    if (!mounted) return;

    var local = book == null ? true : await isBookFileLocal(book);
    if (book != null && !local) {
      final confirmed = await _confirmCloudDownload(book);
      if (!mounted) return;
      if (!confirmed) {
        // 用户取消：不下载，直接退出阅读页
        context.pop();
        return;
      }
      local = await _downloadBookWithProgress(book);
      if (!mounted) return;
      if (!local) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('下载失败：检查同步设置或云端备份后再试')),
        );
        context.pop();
        return;
      }
    }

    try {
      // 兜底：任何一步卡住（插件回调丢失等）都不能让「正在打开…」无限转，
      // 25s 后走诊断面板，至少能退出/重试。
      await _boot().timeout(const Duration(seconds: 25));
    } catch (e) {
      _diagLog('boot failed: $e');
      if (mounted) setState(() => _bootTimedOut = true);
    }
  }

  /// 询问是否从云端下载这本书的书源文件；返回用户是否同意。
  Future<bool> _confirmCloudDownload(Book book) =>
      showCloudDownloadConfirm(context, book);

  /// 拉取书源文件，期间显示「正在下载《书名》的书籍…」；返回是否成功。
  Future<bool> _downloadBookWithProgress(Book book) async {
    final dialogContext = ValueNotifier<BuildContext?>(null);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContextValue) {
          dialogContext.value = dialogContextValue;
          return PopScope(
            canPop: false,
            child: cloudDownloadProgress(book),
          );
        },
      ),
    );
    var ok = false;
    try {
      final sync = await ref
          .read(syncRepositoryProvider.future)
          .timeout(const Duration(seconds: 5));
      ok = await sync
          .ensureBookFileLocal(widget.bookId)
          .timeout(const Duration(seconds: 120));
    } catch (e) {
      _diagLog('download failed: $e');
    } finally {
      final ctx = dialogContext.value;
      if (ctx != null && ctx.mounted) Navigator.of(ctx).pop();
      dialogContext.dispose();
    }
    return ok;
  }

  /// 把本次打开的「最近打开时间」落库（退出 / 切后台时调用，重复安全）。
  ///
  /// 必须用 `initState` 里缓存的仓储 future：`dispose` 阶段 widget 已卸载，
  /// `ref.read` 会抛异常，flush 被静默丢掉 → 书架「最近在读」永远不出现
  /// 这本书（v2.35.0 修）。
  void _flushOpened() {
    final repo = _bookRepoFuture;
    if (repo == null) return;
    unawaited(
      repo.then((r) {
        return r.flushOpened(widget.bookId);
      }).catchError((Object _) {}),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 切后台 / 关闭窗口也要落库：只靠 dispose 的话，桌面端关窗口或进程被
    // 系统回收时「最近在读」会漏记。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _flushOpened();
    }
  }

  /// 旋转/系统栏高度变化：安全区会变，重新注入样式并按新尺寸重排。
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyStyleToAll();
      _flushViewports();
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_marginGroup != null) return KeyEventResult.handled;
    final settings = ref.read(readingSettingsControllerProvider);
    if (settings.flow == ReadingFlow.scrolled) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _requestForward();
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
    _routeAnim?.removeStatusListener(_onRouteAnimStatus);
    unawaited(clearReaderActive());
    // 退出阅读器才把「最近打开」时间落库：书架此刻重排（打开瞬间落库
    // 会让转场下的书架闪动，用户口径：退出时才重新渲染位置）。
    _flushOpened();
    liveReaderTypesetPreview.value = null;
    liveReaderMarginPreview.value = null;
    ref.read(liveReaderMarginsProvider.notifier).state = null;
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    unawaited(
      _screenChannel.invokeMethod<void>('keepAwake', false).catchError((_) {}),
    );
    _lockTimeout?.cancel();
    for (final v in <_ViewSlot>[_a, _b]) {
      v.syncTimer?.cancel();
    }
    _settle.dispose();
    _nativeTtsHighlight.dispose();
    _turnProgress.dispose();
    unawaited(_annotationsSub?.cancel());
    unawaited(_bookmarksSub?.cancel());
    unawaited(_tts.dispose());
    final session = _session;
    if (session != null) {
      unawaited(session.flush());
      session.dispose();
    }
    unawaited(_assetServer.stop());
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
    await _controller.init();
    final state = _controllerState;
    final book = state.book;
    if (book == null) return;

    // 正文入口要尽早放出来：统计/标注/字体/音效都是附属步骤，
    // 任何一步慢（或插件首次初始化慢）都不能继续挡住「正在打开…」。
    final nativeMode = _useNative(ref.read(readingSettingsControllerProvider));
    _readerUri = Uri.parse('assets/reader/reader.html');
    final initial = state.initialLocator;
    _initialLocatorJson = initial == null ? null : locatorToJson(initial);
    _diagLog('book ${book.fileSize}B, initial locator: $_initialLocatorJson');

    // 设置变化 → 样式热更新；flow 切换 → 重建视图。
    // 字号/行距/边距变化属于重排类：松手后统一 flush + display(原 CFI)；
    // 拖动中的边距预览只改外层 padding（见 build 的 AnimatedPadding）。
    ref.listenManual(readingSettingsControllerProvider, (prev, next) {
      if (prev == null) return;
      if (prev.flow != next.flow) {
        _reloadViews();
        return;
      }
      final fontChanged =
          prev.fontSize != next.fontSize ||
          prev.lineHeight != next.lineHeight ||
          prev.fontFamily != next.fontFamily;
      final marginsChanged =
          prev.marginLeft != next.marginLeft ||
          prev.marginRight != next.marginRight ||
          prev.marginTop != next.marginTop ||
          prev.marginBottom != next.marginBottom;
      _applyStyleToAll();
      if (fontChanged || marginsChanged) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future<void>.delayed(const Duration(milliseconds: 90), () {
            if (!mounted) return;
            _flushViewports(relayout: fontChanged);
          });
        });
      }
    });

    if (nativeMode) {
      // 原生阅读面自己会显示「正在打开…」；这里先放开外层，
      // 后面的字体/统计/标注加载完再各自生效。
      if (mounted) setState(() => _booted = true);
    }
    unawaited(_finishBoot(book, nativeMode: nativeMode));
  }

  /// 启动的收尾工作：都是「有更好、没有也能读」的附属步骤，逐个限时，
  /// 任何一个卡住都不影响正文显示。
  Future<void> _finishBoot(Book book, {required bool nativeMode}) async {
    // M5：阅读会话计时（字数按 relocated 正增量估算）
    try {
      final statsRepo = await ref
          .read(statsRepositoryProvider.future)
          .timeout(const Duration(seconds: 4));
      _session = ReadingSessionTracker(
        repository: statsRepo,
        bookId: widget.bookId,
        wordCount: book.wordCount,
      )..start();
    } catch (e) {
      _diagLog('stats skipped: $e');
    }

    // M2：标注/书签流（watch 实时刷新列表；桥定点同步在动作处做）
    try {
      final annRepo = await ref
          .read(annotationRepositoryProvider.future)
          .timeout(const Duration(seconds: 4));
      _annotationsSub = annRepo.watchForBook(widget.bookId).listen((list) {
        _diagLog('watch: annotations=${list.length}');
        _annotations = list;
        if (mounted) setState(() {});
      });
      _bookmarksSub = annRepo.watchBookmarks(widget.bookId).listen((list) {
        _bookmarks = list;
        if (mounted) setState(() {});
      });
    } catch (e) {
      _diagLog('annotations skipped: $e');
    }

    // 自定义字体：原生面允许先用系统字体排一遍，字体就绪后自动重排；
    // 仍然限制等待时间，避免字体加载把启动拖死。
    try {
      await _preloadReadingFont().timeout(const Duration(seconds: 5));
    } catch (e) {
      _diagLog('font skipped: $e');
    }

    if (!nativeMode) {
      // 旧 WebView 路径：页面/书籍服务必须就绪，再放正文。
      try {
        await _assetServer.start(
          html: await loadReaderHtml(),
          bookPath: book.filePath,
        );
        _bookUrl =
            _assetServer.pageUri!.replace(path: '/book.epub').toString();
        _diagLog('page: $_readerUri book: $_bookUrl');
        if (mounted) setState(() => _booted = true);
      } catch (e) {
        _diagLog('webview boot failed: $e');
        if (mounted) setState(() => _bootTimedOut = true);
      }
    }

    // 预载当前翻页音效（SoundPool 解码）：让第一次翻页就没有加载延迟。
    unawaited(
      PageTurnSoundPlayer.instance.preload(
        ref.read(readingSettingsControllerProvider).pageTurnSound,
      ),
    );

    // 看门狗只服务 WebView；原生面没有桥，跳过（否则必然误判超时）。
    Timer(const Duration(seconds: 8), () async {
      if (!nativeMode && mounted && !_a.bridgeReady && !_b.bridgeReady) {
        _diagLog('watchdog: bridgeReady 超时');
        await _dumpPageDiag();
        if (mounted) setState(() => _bootTimedOut = true);
      }
    });
    Timer(const Duration(seconds: 45), () async {
      if (!nativeMode && mounted && !_a.bookReady && !_b.bookReady) {
        _diagLog('watchdog: bookReady 超时');
        await _dumpPageDiag();
        if (mounted) setState(() => _bootTimedOut = true);
      }
    });
  }

  /// 从渲染页拉取内部诊断（页面错误文本、桥/书状态）。
  Future<void> _dumpPageDiag() async {
    for (final slot in <_ViewSlot>[_a, _b]) {
      final bridge = slot.bridge;
      if (bridge == null) continue;
      try {
        final dump = await bridge.dumpDiag();
        _diagLog('[${slot.id}] pageDump: $dump');
      } catch (e) {
        _diagLog('[${slot.id}] dumpDiag failed: $e');
      }
    }
  }

  /// 首帧前注册当前选中字体。
  ///
  /// 字体列表与排版设置都是异步恢复的，这里按顺序等两个恢复完成，
  /// 再把选中的字体交给 FontLoader——正文第一次排版就能用上正确字形。
  Future<void> _preloadReadingFont() async {
    final fonts = ref.read(readerFontsControllerProvider.notifier);
    try {
      await ref.read(readingSettingsControllerProvider.notifier).waitRestored();
      await fonts.waitRestored();
    } catch (_) {
      return;
    }
    final family = ref.read(readingSettingsControllerProvider).fontFamily;
    if (family.isEmpty) return;
    final font = findReaderFont(
      ref.read(readerFontsControllerProvider),
      family,
    );
    if (font == null) return;
    try {
      await fonts.ensureLoaded(font);
    } catch (_) {
      // 注册失败：正文回退系统字体（_nativeSettings 兜底）
    }
  }

  /// 原生阅读面用的设置：字体只交给「已处理过」的 family。
  ///
  /// 正常路径（启动 preload / 选择面板先注册再写设置）首帧就已就绪；
  /// 万一还没就绪（恢复慢、字体文件缺失），先按系统字体排版，注册
  /// 完成后再重建一次——family 从空变非空，阅读面会按页首偏移重排。
  ReadingSettings _nativeSettings(ReadingSettings settings) {
    final family = settings.fontFamily;
    if (family.isEmpty) return settings;
    final font = findReaderFont(
      ref.watch(readerFontsControllerProvider),
      family,
    );
    if (font == null) return settings.copyWith(fontFamily: '');
    final notifier = ref.read(readerFontsControllerProvider.notifier);
    if (notifier.hasLoaded(font)) return settings;
    unawaited(
      notifier.ensureLoaded(font).then((_) {
        if (mounted) setState(() {});
      }),
    );
    return settings.copyWith(fontFamily: '');
  }

  /// 样式载荷（主题/字号/行距；边距由 Flutter 外层 padding 实现）。
  String _stylePayload() =>
      readerStylePayload(ref.read(readingSettingsControllerProvider));

  void _applyStyleToAll() {
    final payload = _stylePayload();
    if (payload == _lastStylePayload) return;
    _lastStylePayload = payload;
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
      v.pendingHighlights = true;
    }
    // 新页面 JS 侧 __n 从 0 重新计数，不清空会把新页面事件全部当成
    // 旧页面的重复而丢弃（实测：切换排版后 relocated/bookReady 全失效）
    for (final v in <_ViewSlot>[_a, _b]) {
      v.seenEventSeq.clear();
    }
    _settle.stop();
    _turn = null;
    _turnProgress.value = 0;
    _dragging = false;
    _dragSlot = null;
    _backOverlay = null;
    _backInFlight = false;
    _lastStylePayload = null;
    _layoutReady = false;
    _layoutFlushPending = false;
    _reloadEpoch++;
    if (!mounted) return;
    setState(() => _booted = false);
    await Future<void>.delayed(Duration.zero);
    if (mounted) setState(() => _booted = true);
  }

  // ---- 桥事件 ----

  /// 三通道（console.error/console.log/callHandler）并发投递，按 __n 去重
  ///（序号按槽位页面各自计数，集合随槽位隔离）。
  int? _eventSeq(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return (decoded['__n'] as num?)?.toInt();
      }
    } catch (_) {}
    return null;
  }

  void _onJsEvent(_ViewSlot slot, List<dynamic> args) {
    final raw = args.isEmpty ? null : args.first as String?;
    if (raw == null) return;
    final seq = _eventSeq(raw);
    if (seq != null) {
      if (!slot.seenEventSeq.add(seq)) return; // 三路重复，丢弃
      while (slot.seenEventSeq.length > 128) {
        slot.seenEventSeq.remove(slot.seenEventSeq.first);
      }
    }
    final event = parseReaderEvent(raw);
    if (event == null) return;

    switch (event) {
      case ReaderBridgeReady():
        _diagLog('[${slot.id}] bridgeReady=true');
        slot.bridgeReady = true;
      case ReaderBookReady():
        _diagLog('[${slot.id}] bookReady=true');
        _onBookReady(slot);
        // 诊断：WebView 内部截图（绕过 Flutter 合成层）
        Future<void>.delayed(const Duration(milliseconds: 2500), () async {
          final shot = await slot.bridge?.screenshot();
          _diagLog(
            '[${slot.id}] internal screenshot: ${shot == null ? "null" : "${shot.lengthInBytes}B"}',
          );
          if (shot != null) {
            try {
              final dir = await Directory.systemTemp.createTemp('qyshot');
              final f = File('${dir.path}/webview_${slot.id}.png');
              await f.writeAsBytes(shot);
              _diagLog('[${slot.id}] saved: ${f.path}');
            } catch (e) {
              _diagLog('[${slot.id}] save failed: $e');
            }
          }
        });
      case ReaderLocationsReady():
        _controller.onLocationsReady();
        // locations 就绪后让可视层重报位置，补齐 percent（进度保存依赖它）
        if (slot == _visible) {
          slot.bridge?.reportLocation();
        }
      case final ReaderRelocated rel:
        _diagLog(
          '[${slot.id}] relocated ch=${rel.locator.chapterIndex} '
          'page=${rel.page}/${rel.pages} cfi=${rel.locator.cfi != null}',
        );
        _onRelocated(slot, rel);
      case ReaderTap(:final x, :final y):
        _diagLog('[${slot.id}] tap ($x,$y) chrome=$_chromeVisible');
        if (slot != _visible) break;
        _onContentTap(x, y);
      case final ReaderSelected sel:
        // 文本选区完成：弹出标注菜单（双池都会报，仅可视层处理）。
        // 记录产生选区时的页位：选字期间 WebView 会因选择工具条显隐
        // 补发 relocated（页位没变），不能据此收菜单。
        if (slot == _visible) {
          _selectionAnchor = slot.locator;
          setState(() => _selection = sel);
        }
      case ReaderSwipe(:final dx):
        // JS 检测的横向滑动（touchmove 稀疏时的兜底）：向左=前翻，向右=后翻
        if (slot != _visible) break;
        _lastDragEnd = DateTime.now();
        if (dx < 0) {
          _requestForward();
        } else {
          _goBackward();
        }
      case ReaderDragStart():
        _onDragStart(slot);
      case ReaderDragMove(:final dx):
        _onDragMove(slot, dx);
      case ReaderDragEnd(:final dx, :final vx):
        _onDragEnd(slot, dx, vx);
      case ReaderDragCancel():
        _onDragCancel(slot);
      case final ReaderSyncDone sync:
        _onSyncDone(slot, sync);
      case ReaderEdgeStart(:final edge):
        _onEdgeStart(slot, edge);
      case ReaderEdgeMove(:final edge, :final dy):
        _onEdgeMove(slot, edge, dy);
      case ReaderEdgeEnd(:final edge, :final dy):
        _onEdgeEnd(slot, edge, dy);
      case ReaderEdgeCancel():
        _onEdgeCancel(slot);
      case ReaderMarkClicked(:final annotationId, :final cfiRange):
        _diagLog('[${slot.id}] markClicked id=$annotationId');
        if (slot != _visible) break;
        final match = _matchAnnotation(annotationId, cfiRange);
        if (match != null) {
          unawaited(_showAnnotationDialog(match));
        }
      case ReaderError(:final code, :final message):
        _diagLog('[${slot.id}] error($code): $message');
        // 书籍打开/渲染失败 → 屏幕可见（此前静默白屏）
        if (code.startsWith('book') || code.startsWith('render')) {
          _controller.onLoadError('打开失败：$code $message');
        }
    }
    // relocated/拖拽逐帧事件每条都 setState 会让 HC 平台视图整帧重绘
    //（长按选字期间表现为屏幕闪动），位置类事件由内部方法按需 setState。
    if (mounted &&
        (event is! ReaderRelocated &&
            event is! ReaderDragMove &&
            event is! ReaderEdgeMove &&
            event is! ReaderSyncDone)) {
      setState(() {});
    }
  }

  /// 按事件携带的 id（或 CFI 兜底）匹配既有标注。
  Annotation? _matchAnnotation(String? id, String cfiRange) {
    for (final a in _annotations) {
      if (id != null && a.id == id) return a;
    }
    for (final a in _annotations) {
      if (a.locatorStart.contains(cfiRange)) return a;
    }
    return null;
  }

  void _onBookReady(_ViewSlot slot) {
    slot.bookReady = true;
    slot.bridge?.applyStyle(_stylePayload());
    if (!_layoutReady && !_layoutFlushPending && _a.bookReady && _b.bookReady) {
      // 两次 WebView 可能以不同临时尺寸完成首渲；先按同一最终尺寸重排
      // 两层，再允许隐藏层同步（否则章页数差一页，第一次前翻会越过章末）。
      _layoutFlushPending = true;
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        _layoutFlushPending = false;
        // 用 relayout（两次 resize 强制重建分栏）而不是 flushViewport，
        // 清掉首渲恢复路径产生的多余列（章页数会比真实多一页）。
        _flushViewports(relayout: true);
        _layoutReady = true;
        _scheduleSyncHidden();
      });
    } else if (_layoutReady) {
      _scheduleSyncHidden();
    }
    if (!_guideChecked) {
      _guideChecked = true;
      unawaited(_maybeShowGuide());
    }
  }

  /// 把既有划线批量注入某槽位。必须在视图滚动到目标列（relocated）之后：
  /// pane 高亮按注入瞬间的列偏移定位，注入过早会画到屏幕外一整列（实测）。
  void _applyHighlightsTo(_ViewSlot slot) {
    if (_annotations.isEmpty || !slot.pendingHighlights) return;
    slot.pendingHighlights = false;
    slot.bridge?.applyHighlights(
      jsonEncode([
        for (final a in _annotations)
          {'id': a.id, 'cfiRange': _cfiRangeOf(a), 'color': a.color.token},
      ]),
    );
  }

  /// 取标注的选区 CFI（locatorStart JSON 里的 cfi 字段）。
  String _cfiRangeOf(Annotation a) {
    final loc = locatorFromJson(a.locatorStart);
    return loc?.cfi ?? '';
  }

  void _onRelocated(_ViewSlot slot, ReaderRelocated event) {
    final locator = event.locator;
    slot.locator = locator;
    slot.settled = true;
    if (event.pages > 0) slot.pages = event.pages;

    // 首次 relocated = display 已落定到目标列，此时注入高亮坐标才正确
    _applyHighlightsTo(slot);

    // 统计：按可视层 percent 正增量累计字数
    if (slot == _visible) {
      _session?.onPercent(locator.pos ?? locator.percent);
      _controller.onRelocated(
        locator,
        atStart: event.atStart,
        atEnd: event.atEnd,
        chapterPage: event.page,
        chapterPages: event.pages,
        bookPage: event.bookPage,
        bookPages: event.bookPages,
      );
    }

    // 翻页/跳转后选区已失效：收菜单并清 WebView 选区。选字期间 WebView
    // 会因系统选择工具条显隐补发 relocated（页位没变），页位没变不清选区。
    if (slot == _visible &&
        _selection != null &&
        !_sameLocator(slot.locator, _selectionAnchor)) {
      _dismissAnnotationUi();
    }

    // 位置落定且没有待完成的同步 → 揭开骨架
    if (slot.covered && slot.pendingSeq == 0) {
      slot.covered = false;
      if (mounted) setState(() {});
    }

    // 可视层落定后，隐藏层才能按它的最新位置对齐“下一页”
    if (slot == _visible) _scheduleSyncHidden();

    // 后翻等待的两个 prev relocated：两边都到位即解锁
    if (_backInFlight && _a.locator != null && _b.locator != null) {
      _backInFlight = false;
      _lockTimeout?.cancel();
    }
  }

  /// 位置等价（CFI + 章内页号）：epub.js 同一章各页的 CFI 可能都是章首，
  /// 必须用 page 区分，否则隐藏层会被对齐成重复页。
  bool _sameLocator(Locator? a, Locator? b) {
    if (a == null || b == null) return false;
    if (a.cfi != null && b.cfi != null) {
      if (a.cfi != b.cfi) return false;
    } else if (a.href != null && b.href != null) {
      if (a.href != b.href || a.percent != b.percent) return false;
    } else {
      return a.percent != null && a.percent == b.percent;
    }
    if (a.page != null && b.page != null && a.page != b.page) return false;
    return true;
  }

  /// 隐藏层实际页位是否正好是可视页的下一页。
  ///
  /// 判定只用「章索引 + 页号」两条直接规则，**不依赖章总页数**：
  /// 总页数来自页面的 truePageCount，章节还没排版完时会偏小（实测 7 页算成
  /// 1 页），用它来判断「可视页是不是本章末页」就会走错分支 → 隐藏层被误判
  /// 为「不是下一页」→ 翻页时出骨架白屏。
  bool _isNextPage(_ViewSlot next, _ViewSlot current) {
    final a = next.locator;
    final b = current.locator;
    if (a == null || b == null) return false;
    // 页号信息缺失（旧进度/未知）时不阻断
    if (a.page == null || b.page == null) return true;
    if (a.chapterIndex == null || b.chapterIndex == null) return true;
    // 同章的下一页
    if (a.chapterIndex == b.chapterIndex && a.page == b.page! + 1) return true;
    // 跨章的第一页
    return a.chapterIndex == b.chapterIndex! + 1 && a.page == 1;
  }

  /// 给槽位下发“对齐到 target 再前进一页”；seq 用于丢弃过期回调。
  void _syncSlotNext(_ViewSlot slot, Locator target) {
    _diagLog('sync ${slot.id} target=${_shortCfi(target.cfi)}');
    slot.syncTimer?.cancel();
    final seq = ++slot.syncSeq;
    slot.pendingSeq = seq;
    slot.pendingSyncVisible = target;
    slot.bridge?.syncNextMap(_locatorMap(target), seq: seq);
    slot.syncTimer = Timer(const Duration(milliseconds: 5000), () {
      if (slot.pendingSeq != seq) return;
      slot.pendingSeq = 0;
      slot.pendingSyncVisible = null;
      slot.covered = false;
      // 超时按当前位置继续（best effort），避免永久遮挡/无法翻页。
      // 5s 是下限：大章一次对齐可能要走多页，低于它会让正常同步被误判超时。
      slot.settled = true;
      if (mounted) setState(() {});
      _scheduleSyncHidden();
    });
  }

  /// 让隐藏层对齐到可视层的下一页。可视层带骨架时先不对齐
  /// （它还没落定，按旧 locator 对齐会得到错页）。
  void _scheduleSyncHidden() {
    if (!_layoutReady) return;
    final visible = _visible;
    final hidden = _hidden;
    final target = visible.locator;
    if (!visible.bookReady || !hidden.bookReady || target == null) return;
    if (!visible.settled || visible.covered) return;
    if (hidden.pendingSeq != 0) return;
    if (!hidden.covered && _sameLocator(hidden.lastSyncedVisible, target)) {
      return;
    }
    _diagLog(
      'schedule v=${visible.id} settled=${visible.settled} '
      'target=${_shortCfi(target.cfi)}',
    );
    _syncSlotNext(hidden, target);
  }

  String _shortCfi(String? cfi) {
    if (cfi == null || cfi.isEmpty) return '-';
    return cfi.length <= 26 ? cfi : '…${cfi.substring(cfi.length - 26)}';
  }

  /// 同步完成（seq 不匹配 = 过期回调，直接丢弃，防止错页）。
  void _onSyncDone(_ViewSlot slot, ReaderSyncDone event) {
    if (event.seq != slot.pendingSeq) {
      _diagLog(
        '[${slot.id}] syncDone stale seq=${event.seq} '
        'want=${slot.pendingSeq}',
      );
      return;
    }
    final target = slot.pendingSyncVisible;
    slot.pendingSeq = 0;
    slot.syncTimer?.cancel();
    slot.pendingSyncVisible = null;
    slot.lastSyncedVisible = event.ok ? target : null;
    // 成功或失败都揭开骨架：失败时宁可露出内容，也不永久白块
    slot.covered = false;
    final loc = event.locator;
    if (event.ok && loc != null) {
      slot.locator = loc;
      slot.settled = true;
      if (event.pages > 0) slot.pages = event.pages;
      if (slot == _visible) {
        _session?.onPercent(loc.pos ?? loc.percent);
        _controller.onRelocated(
          loc,
          atStart: event.atStart,
          atEnd: event.atEnd,
          chapterPage: event.page,
          chapterPages: event.pages,
          bookPage: event.bookPage,
          bookPages: event.bookPages,
        );
      }
    } else {
      slot.settled = false;
    }
    _diagLog(
      '[${slot.id}] syncDone ok=${event.ok} seq=${event.seq} '
      'page=${event.page}/${event.pages}',
    );
    _scheduleSyncHidden();
    if (mounted) setState(() {});
  }

  Map<String, dynamic> _locatorMap(Locator l) =>
      jsonDecode(locatorToJson(l)) as Map<String, dynamic>;

  // ---- 翻页命令 ----

  /// 后翻要求隐藏层确实停在下一页（两个视图同时 prev 才能保持池不变式）。
  bool get _canBackward {
    if (_turn != null || _backInFlight || _controllerState.atStart) {
      return false;
    }
    final visible = _visible;
    final hidden = _hidden;
    return visible.locator != null &&
        hidden.pendingSeq == 0 &&
        !hidden.covered &&
        _sameLocator(hidden.lastSyncedVisible, visible.locator);
  }

  /// 请求前翻：下一页没备好也直接翻（骨架占位，动画不等待异步结果）。
  void _requestForward() {
    if (!mounted || _controllerState.atEnd) return;
    // 上一段还在动：直接推到提交点，从新页继续（连续翻页不复位）
    if (_turn != null) {
      if (_turn!.isForward) {
        _settle.stop();
        _finalizeTurn();
      } else {
        return;
      }
    }
    _goForward();
  }

  void _goForward() {
    if (_controllerState.atEnd) return;
    if (ref.read(readingSettingsControllerProvider).pageTurnMode ==
        PageTurnMode.none) {
      _completeForwardInstant();
      return;
    }
    setState(() => _turn = _Turn(isForward: true, t: 0));
    _turnProgress.value = 0;
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
  /// 在途同步全部作废（seq 递增），页位变化后由 relocated 重新对齐。
  void _turnBothViews() {
    for (final v in <_ViewSlot>[_a, _b]) {
      v.syncSeq++;
      v.pendingSeq = 0;
      v.pendingSyncVisible = null;
      v.syncTimer?.cancel();
      v.lastSyncedVisible = null;
      v.covered = false;
      v.settled = false;
    }
    _backInFlight = true;
    _armLockTimeout();
    // 骨架遮罩等槽位状态变了要立刻反映到画面（翻页动画不再整页重建，
    // 这里必须显式触发一次）。
    if (mounted) setState(() {});
    _a.bridge?.prevPage();
    _b.bridge?.prevPage();
  }

  void _settleTurn({required bool commit}) {
    final turn = _turn;
    if (turn == null) return;
    turn.commitRequested = commit;
    // 先把控制器对齐到当前拖拽进度：animateTo 以控制器当前值为起点，
    // 上一段结束后控制器停在 1.0，直接 animateTo(1.0) 会“立即完成”，
    // 导致连续翻页时 turn.t 还停在拖拽值、finalize 误判为取消。
    _settle.value = turn.t;
    // 80ms 短补间（不用弹簧：弹簧可能停在 0.999 不触发 completed）。
    _settle.animateTo(
      commit ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOutCubic,
    );
  }

  /// 前翻提交：交换池。新可视层若还不是下一页 → 骨架占位并补对齐；
  /// 动画/手势不等待异步结果，连续翻页不会卡住。
  void _completeForwardInstant() {
    final oldVisible = _visible;
    final newVisible = _hidden;
    final oldLocator = oldVisible.locator;
    _visibleIsA = !_visibleIsA;

    final ready =
        oldLocator != null &&
        newVisible.pendingSeq == 0 &&
        _sameLocator(newVisible.lastSyncedVisible, oldLocator) &&
        _isNextPage(newVisible, oldVisible);
    _diagLog(
      'swap old=${oldVisible.id} new=${newVisible.id} ready=$ready '
      'pending=${newVisible.pendingSeq} '
      'oldPage=${oldLocator?.page} oldCh=${oldLocator?.chapterIndex} '
      'oldPages=${oldLocator?.pages} oldSlotPages=${oldVisible.pages} '
      'newPage=${newVisible.locator?.page} '
      'newCh=${newVisible.locator?.chapterIndex} '
      'newPages=${newVisible.locator?.pages} '
      'lastPage=${newVisible.lastSyncedVisible?.page} '
      'lastCh=${newVisible.lastSyncedVisible?.chapterIndex} '
      'same=${_sameLocator(newVisible.lastSyncedVisible, oldLocator)} '
      'isNext=${_isNextPage(newVisible, oldVisible)}',
    );
    newVisible.settled = ready;
    if (!ready) {
      newVisible.covered = true;
      if (oldLocator != null) {
        // 无论隐藏层有没有在途同步，都要下发一条新的 syncNext：
        // ① 新链会作废旧链（JS 侧 syncGen），旧链的目标是「旧可视页 + 1」，
        //    交换后这一层自己变成了可视页，旧链跑完会把它推到错误页（跳页）；
        // ② 没有在途同步时，这条新链就是把它对齐到正确页。
        _syncSlotNext(newVisible, oldLocator);
      }
    }

    // 旧可视层（新隐藏层）在途同步的目标已过期：seq 递增丢弃其回调
    oldVisible.syncSeq++;
    oldVisible.pendingSeq = 0;
    oldVisible.pendingSyncVisible = null;
    oldVisible.syncTimer?.cancel();
    oldVisible.lastSyncedVisible = null;
    oldVisible.settled = false;

    // 新可视层自隐藏期起未再上报位置：立即重报，避免进度/书首书末用旧值。
    // 已确认页位时可直接给隐藏层对齐；未确认则等 relocated/syncDone。
    newVisible.bridge?.reportLocation();
    if (ready) _scheduleSyncHidden();
    setState(() {});
  }

  void _armLockTimeout() {
    _lockTimeout?.cancel();
    _lockTimeout = Timer(const Duration(milliseconds: 900), () {
      _backInFlight = false;
    });
  }

  void _finalizeTurn() {
    final turn = _turn;
    _turn = null;
    if (turn == null) return;
    _diagLog(
      'finalize forward=${turn.isForward} t=${turn.t.toStringAsFixed(2)}',
    );
    if (turn.isForward) {
      if (turn.t > 0.5) {
        _completeForwardInstant();
      } else {
        setState(() {});
      }
      return;
    }
    // 后翻：prev 已在抬手时下发，这里只收尾（不能对已 prev 的池再 next）
    setState(() => _backOverlay = null);
  }

  // ---- 跟手拖拽（dx 由 reader.html 逐帧上报）----

  void _onDragStart(_ViewSlot slot) {
    if (!mounted || _edgeSlot != null) return;
    if (ref.read(readingSettingsControllerProvider).flow ==
        ReadingFlow.scrolled) {
      return;
    }
    if (_selection != null || _activeAnnotation != null) return;
    // 上一段手势没收到 end/cancel（WebView 重开触摸序列）：先撤销其残余位移
    if (_dragging) {
      _dragging = false;
      _settle.stop();
      if (_turn != null) {
        _turn = null;
        _turnProgress.value = 0;
        setState(() {});
      }
    }
    // 上一段前翻动画还在走：已请求提交就推进到 1（不能取消已提交的翻页），
    // 未请求提交则按当前进度收尾。
    if (_turn != null) {
      if (_turn!.isForward) {
        _settle.stop();
        if (_turn!.commitRequested) _turn!.t = 1.0;
        _finalizeTurn();
      } else {
        return;
      }
    }
    // 接受任意槽位：快速连滑时 DOWN 落在旧可视层，事件到达前池已交换，
    // 按槽位过滤会把整段手势丢掉。
    _dragSlot = slot;
    _dragging = true;
    _dragDx = 0;
    _diagLog('[${slot.id}] dragStart t=${_turn?.t.toStringAsFixed(2)}');
  }

  void _onDragMove(_ViewSlot slot, double dx) {
    if (!_dragging || !mounted || slot != _dragSlot) return;
    _dragDx = dx;
    final width = _contentWidth();
    if (width <= 0) return;
    final forward = dx < 0;

    if (_turn == null) {
      if (forward) {
        if (_controllerState.atEnd) return;
        setState(() => _turn = _Turn(isForward: true, t: 0));
        _turnProgress.value = 0;
      } else {
        if (!_canBackward) return;
        setState(() => _turn = _Turn(isForward: false, t: 0));
        _turnProgress.value = 0;
      }
    }
    final turn = _turn;
    if (turn == null) return;
    if (turn.isForward != forward) {
      // 拖回起点：取消位移
      if (turn.t > 0) {
        turn.t = 0;
        _turnProgress.value = 0;
      }
      return;
    }
    final signed = turn.isForward ? -dx : dx;
    final t = (signed / width).clamp(0.0, 1.0).toDouble();
    if ((t - turn.t).abs() > 0.0005) {
      // 只推进进度（不整页重建）：跟手拖拽每帧都会走到这里。
      turn.t = t;
      _turnProgress.value = t;
    }
  }

  void _onDragEnd(_ViewSlot slot, double dx, double vx) {
    if (!_dragging || !mounted || slot != _dragSlot) return;
    _dragging = false;
    _dragSlot = null;
    _lastDragEnd = DateTime.now();
    final width = _contentWidth();
    final accumulated = _dragDx;
    _dragDx = 0;
    final turn = _turn;
    if (turn == null) {
      // 手势极快（DragStart 与 End 之间没有 move 事件）：按位移/速度直接翻页
      final effective = accumulated.abs() > dx.abs() ? accumulated : dx;
      if (effective < -width * 0.12 || vx < -0.35) _goForward();
      return;
    }
    // 距离或快速轻扫（px/ms）都算提交；触摸序列被系统打断时以累计位移为准
    final effectiveDx = accumulated.abs() > dx.abs() ? accumulated : dx;
    final committed =
        turn.t > 0.32 ||
        (turn.t > 0.03 && vx.abs() > 0.35) ||
        effectiveDx.abs() > width * 0.30;
    _diagLog(
      '[${slot.id}] dragEnd dx=${dx.toStringAsFixed(0)} '
      'acc=${accumulated.toStringAsFixed(0)} '
      't=${turn.t.toStringAsFixed(2)} vx=${vx.toStringAsFixed(2)} '
      'commit=$committed',
    );
    if (turn.isForward) {
      // 目标页未就绪也没关系：提交时骨架占位，动画不等待
      _settleTurn(commit: committed);
      return;
    }
    // 后翻没有预渲染页：抬手时才下发 prev；提交时先让当前页滑出，
    // 到 t=1 后 _finalizeTurn 归位（切换时页面在屏幕外）
    if (committed) {
      turn.prevIssued = true;
      _turnBothViews();
      _settleTurn(commit: true);
    } else {
      _settleTurn(commit: false);
    }
  }

  void _onDragCancel(_ViewSlot slot) {
    if (!_dragging || slot != _dragSlot) return;
    _dragging = false;
    _dragSlot = null;
    _lastDragEnd = DateTime.now();
    final dx = _dragDx;
    _dragDx = 0;
    _diagLog('[${slot.id}] dragCancel dx=${dx.toStringAsFixed(0)}');
    final turn = _turn;
    final width = _contentWidth();
    if (turn != null) {
      // 手势被系统取消（如 WebView 重渲染），位移够大仍按提交处理
      final committed = dx.abs() > width * 0.32;
      _settleTurn(commit: turn.isForward && committed);
      return;
    }
    // 还没开始跟手就被取消：位移已足够时救回一次前翻
    if (dx < -width * 0.12) _requestForward();
  }

  /// 正文区宽度（WebView 逻辑像素 = Flutter 逻辑像素）。
  double _contentWidth() {
    if (!mounted) return 1;
    final margins = _pagePadding(ref.read(readingSettingsControllerProvider));
    final w =
        MediaQuery.sizeOf(context).width -
        _safeHorizontal() -
        margins.horizontal;
    return w > 1 ? w : 1;
  }

  /// 水平安全区宽度。
  ///
  /// 外层 `SafeArea(top: false, bottom: false)` 已经把水平安全区扣掉一次，
  /// 这里的 [_pagePadding] 绝不能再加一次（否则左右各算两次，有刘海/挖孔
  /// 的机型左边空得比右边多，阅读界面看着不居中）。
  double _safeHorizontal() =>
      MediaQuery.maybePaddingOf(context)?.horizontal ?? 0;

  /// 沉浸模式下垂直安全区的保底值（部分 ROM 上报 0 时页眉/页脚贴边）。
  static const double kMinReadingTopInset = 32;
  static const double kMinReadingBottomInset = 20;

  /// 正文区四边 padding：用户边距。
  ///
  /// v2.38.3 起**不再叠加垂直系统安全区**：页眉/页脚边距是绝对边距，从屏幕
  /// 顶/底算起（用户要求「不考虑安全区」）。水平方向仍由外层 SafeArea 承担。
  EdgeInsets _pagePadding(ReadingSettings settings, [EdgeInsets? liveMargins]) {
    final live = liveMargins ?? ref.read(liveReaderMarginsProvider);
    return live ??
        EdgeInsets.fromLTRB(
          settings.marginLeft,
          settings.marginTop,
          settings.marginRight,
          settings.marginBottom,
        );
  }

  /// 阅读页的垂直安全区（含保底）。
  ///
  /// 沉浸模式下部分 ROM 会把 viewPadding 上报成 0：页眉会贴到挖孔摄像头
  /// 那条线、页脚和正文最后一行贴到屏幕底边（被手势条压住）。这里给
  /// 上下各一个保底值，观感与有系统栏时一致。
  EdgeInsets _readingVerticalInsets() {
    final insets = MediaQuery.maybeViewPaddingOf(context) ?? EdgeInsets.zero;
    return EdgeInsets.only(
      top: math.max(insets.top, kMinReadingTopInset),
      bottom: math.max(insets.bottom, kMinReadingBottomInset),
    );
  }

  // ---- 左右边缘手势（左=亮度，右=字号）----

  void _onEdgeStart(_ViewSlot slot, String edge) {
    if (!mounted) return;
    if (_turn != null || _dragging) return;
    final settings = ref.read(readingSettingsControllerProvider);
    if (edge == 'left') {
      _edgeSlot = slot;
      _edgeBaseDim = _dim;
      setState(() {
        _edgeHud = 'brightness';
        _edgeHudValue = 1 - _dim / 0.65;
      });
    } else if (edge == 'right') {
      _edgeSlot = slot;
      _edgeBaseFont = settings.fontSize;
      _edgePreviewFont = settings.fontSize;
      setState(() {
        _edgeHud = 'font';
        _edgeHudValue = settings.fontSize;
      });
    }
  }

  void _onEdgeMove(_ViewSlot slot, String edge, double dy) {
    if (_edgeSlot != slot) return;
    final height = MediaQuery.sizeOf(context).height;
    if (height <= 0) return;
    if (edge == 'left') {
      // 上滑变亮、下滑变暗（页面内遮罩，不改系统亮度）
      final dim = (_edgeBaseDim + dy / height * 1.2)
          .clamp(0.0, 0.65)
          .toDouble();
      setState(() {
        _dim = dim;
        _edgeHud = 'brightness';
        _edgeHudValue = 1 - dim / 0.65;
      });
    } else if (edge == 'right') {
      // 上滑字号变大、下滑变小；拖动期间只预览，松手后统一重排
      final size = (_edgeBaseFont - dy / height * 16)
          .clamp(14.0, 28.0)
          .toDouble();
      setState(() {
        _edgePreviewFont = size;
        _edgeHud = 'font';
        _edgeHudValue = size;
      });
    }
  }

  void _onEdgeEnd(_ViewSlot slot, String edge, double dy) {
    if (_edgeSlot != slot) return;
    _edgeSlot = null;
    final settings = ref.read(readingSettingsControllerProvider);
    if (edge == 'right') {
      final size = _edgePreviewFont.roundToDouble();
      if (size != settings.fontSize) {
        unawaited(
          ref
              .read(readingSettingsControllerProvider.notifier)
              .patch(fontSize: size),
        );
      }
    }
    setState(() => _edgeHud = null);
  }

  void _onEdgeCancel(_ViewSlot slot) {
    if (_edgeSlot != slot) return;
    _edgeSlot = null;
    setState(() => _edgeHud = null);
  }

  // ---- 点击分区 ----

  void _onContentTap(double x, double y) {
    if (_turn != null || _settle.isAnimating || _dragging) return;
    // 拖拽/滑动后紧随的合成 tap 不处理
    if (DateTime.now().difference(_lastDragEnd) <
        const Duration(milliseconds: 320)) {
      return;
    }
    // 标注菜单/划线面板打开时，任意正文点击先收起
    if (_selection != null || _activeAnnotation != null) {
      _dismissAnnotationUi();
      return;
    }
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
      _requestForward();
    } else {
      setState(() => _chromeVisible = !_chromeVisible);
    }
  }

  // ---- 跳转 ----

  void _onSeek(double value) {
    final v = value.clamp(0.0, 1.0);
    if (!_useNative(ref.read(readingSettingsControllerProvider))) {
      // WebView：按页级位置跳转（应用里的 percent 就是 pos，字符级
      // locations 不再生成，gotoPercent 那条路已经不适用）。
      _visible.bridge?.gotoPos(v);
      _resetHiddenSync();
      return;
    }
    final book = _controllerState.book;
    final chapters = book == null
        ? null
        : ref.read(nativeChaptersProvider(NativeChaptersKey.of(book))).value;
    final state = _nativeKey.currentState;
    if (chapters == null || chapters.isEmpty || state == null) return;
    final scope = ref.read(readingSettingsControllerProvider).progressScope;
    if (scope == ProgressScope.chapter) {
      // 本章进度：直接按章内字符比例定位（跳到章首会让人以为"没反应"）
      final len = chapters[state.currentChapter].text.length;
      state.jumpToOffset((v * len).round());
      return;
    }
    // 全书进度：章索引 + 章内比例，落到章中间而不是章首
    final total = chapters.length;
    final pos = v * total;
    var idx = pos.floor();
    if (idx >= total) idx = total - 1;
    final frac = (pos - idx).clamp(0.0, 1.0);
    final len = chapters[idx].text.length;
    state.jumpToChapter(idx, offset: (frac * len).round());
  }

  void _onChapterTap(String href) {
    setState(() {
      _tocOpen = false;
      _chromeVisible = false;
    });
    if (_useNative(ref.read(readingSettingsControllerProvider))) {
      final book = _controllerState.book;
      final chapters = book == null
          ? null
          : ref.read(nativeChaptersProvider(NativeChaptersKey.of(book))).value;
      if (chapters != null) {
        for (var i = 0; i < chapters.length; i++) {
          if (chapters[i].href == href) {
            _nativeKey.currentState?.jumpToChapter(i);
            return;
          }
        }
      }
      return;
    }
    _visible.bridge?.gotoHref(href);
    _resetHiddenSync();
  }

  void _resetHiddenSync() {
    // 跳转/重排后隐藏层失效：作废在途同步（seq 递增），
    // 待可视层 relocated 后由 _scheduleSyncHidden 重新对齐。
    final hidden = _hidden;
    hidden.syncSeq++;
    hidden.pendingSeq = 0;
    hidden.pendingSyncVisible = null;
    hidden.syncTimer?.cancel();
    hidden.lastSyncedVisible = null;
    hidden.covered = false;
  }

  /// 松手后按新尺寸统一重排并回到原 CFI（拖动期间不调用，避免逐帧重排跳页）。
  ///
  /// 可见层与隐藏层必须一起重排：只重排可见层会让隐藏层保留旧分页
  /// （章页数不同，第一次前翻会直接跳过章末）。隐藏层不恢复位置，
  /// 随后由 _scheduleSyncHidden 按可见页重新对齐。
  void _flushViewports({bool relayout = false}) {
    final visible = _visible;
    final hidden = _hidden;
    if (!visible.bookReady) return;
    final loc = visible.locator;
    final json = loc == null ? null : locatorToJson(loc);
    for (final v in <_ViewSlot>[visible, hidden]) {
      if (!v.bookReady) continue;
      if (relayout) {
        v.bridge?.relayout(v == visible ? json : null);
      } else {
        v.bridge?.flushViewport(v == visible ? json : null);
      }
    }
    _resetHiddenSync();
  }

  Future<void> _onBack() async {
    if (_exiting) return;
    _exiting = true;
    liveReaderTypesetPreview.value = null;
    // 退出前先取一次最终位置（见 _captureFinalPosition）。
    await _captureFinalPosition();
    if (!mounted) return;
    context.pop();
  }

  /// 退出阅读时「再渲染一次位置」并落库。
  ///
  /// 打开书籍时不再渲染整本书的位置表（locations），位置一律用页级 pos；
  /// 退出这一步向渲染页要一次**当前真实页位**（最后一条 relocated 可能
  /// 还没送达 Dart：改字号、跳页、翻章之后都会这样），落库保证下次打开
  /// 回到用户最后看到的那一页。
  Future<void> _captureFinalPosition() async {
    final bridge = _visible.bridge;
    if (bridge == null) {
      await _controller.flushProgress();
      return;
    }
    String? json;
    try {
      // WebView 正忙时这句可能迟迟不回：超时就走常规落库，别把退出卡住。
      json = await bridge
          .currentLocatorJson()
          .timeout(const Duration(milliseconds: 800));
    } catch (e) {
      _diagLog('final locator failed: $e');
      json = null;
    }
    final loc = json == null ? null : locatorFromJson(json);
    if (loc == null) {
      await _controller.flushProgress();
      return;
    }
    await _controller.saveLocator(loc);
  }

  /// 页脚是否已经显示页码/页数（是则不再显示右下角页码 HUD）。
  static bool _footerShowsPageNumbers(ReadingSettings s) {
    bool isPages(RunningContent c) =>
        c == RunningContent.chapterPages || c == RunningContent.bookPages;
    return isPages(s.footerLeft) ||
        isPages(s.footerCenter) ||
        isPages(s.footerRight);
  }

  Future<void> _showTypesetting() async {
    final sheetTheme = ref.read(readingSettingsControllerProvider).theme;
    final marginGroup = await showModalBottomSheet<MarginGroup>(
      context: context,
      sheetAnimationStyle: kSmoothSheetAnimation,
      backgroundColor: sheetTheme.chromeSurface,
      // 顶部拖拽条：明确「这是可下拉关闭的弹层」，也顺手把面板和正文分开。
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const TypesettingPanel(),
    );
    // 面板关闭：清掉拖动中的预览（未松手就关面板时不残留旧字号）
    liveReaderTypesetPreview.value = null;
    _nativeKey.currentState?.clearLivePreview();
    if (marginGroup != null && mounted) _openMarginEditor(marginGroup);
  }

  /// 进入边距直调模式：正文 / 页眉 / 页脚三页。
  void _openMarginEditor(MarginGroup group) {
    setState(() {
      _marginGroup = group;
      _marginDraft = null;
      _chromeVisible = false;
      _tocOpen = false;
      _selection = null;
      _activeAnnotation = null;
    });
  }

  /// 边距直调：实时预览（不落库）。
  void _previewMargins(ReadingSettings draft) {
    _marginDraft = draft;
    liveReaderMarginPreview.value = draft;
    // 正文左右边距走外层 padding（内容宽度随之变化，预览即时）。
    ref.read(liveReaderMarginsProvider.notifier).state = EdgeInsets.fromLTRB(
      draft.marginLeft,
      draft.marginTop,
      draft.marginRight,
      draft.marginBottom,
    );
  }

  /// 边距直调：提交草稿并清掉预览。
  void _commitMargins(ReadingSettings draft) {
    _marginDraft = draft;
    // patch 在第一个 await 前就同步更新 state，页面不会先闪回旧值。
    unawaited(
      ref.read(readingSettingsControllerProvider.notifier).patch(
            marginLeft: draft.marginLeft,
            marginRight: draft.marginRight,
            marginTop: draft.marginTop,
            marginBottom: draft.marginBottom,
            headerMarginTop: draft.headerMarginTop,
            headerMarginLeft: draft.headerMarginLeft,
            headerMarginRight: draft.headerMarginRight,
            footerMarginLeft: draft.footerMarginLeft,
            footerMarginRight: draft.footerMarginRight,
            footerMarginBottom: draft.footerMarginBottom,
          ),
    );
    liveReaderMarginPreview.value = null;
    ref.read(liveReaderMarginsProvider.notifier).state = null;
  }

  /// 退出边距直调（返回键 / 勾选都走这里）：提交后关闭。
  void _closeMarginEditor() {
    final draft = _marginDraft;
    if (draft != null) _commitMargins(draft);
    liveReaderMarginPreview.value = null;
    ref.read(liveReaderMarginsProvider.notifier).state = null;
    if (!mounted) return;
    setState(() {
      _marginGroup = null;
      _marginDraft = null;
    });
  }

  /// 跳页面板：全书按百分比跳转（全书页码标「约」，字号一变就会变）。
  Future<void> _showJumpPanel() async {
    final state = _controllerState;
    final theme = _theme;
    var percent = (state.percent ?? 0).clamp(0.0, 1.0).toDouble();
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: kSmoothSheetAnimation,
      backgroundColor: theme.chromeSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final bookPages = state.bookPages;
          final targetPage = bookPages > 0
              ? (percent * bookPages).round().clamp(1, bookPages)
              : 0;
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        '跳转',
                        style: TextStyle(
                          color: theme.chromeForeground,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        bookPages > 0
                            ? '约 $targetPage / $bookPages 页'
                            : '${(percent * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: theme.chromeForeground.withValues(alpha: 0.7),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '本章 ${state.chapterPage} / ${state.chapterPages}'
                    '${state.book == null ? '' : ' · ${state.book!.title}'}',
                    style: TextStyle(
                      color: theme.chromeForeground.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                  Slider(
                    value: percent,
                    activeColor: theme.accent,
                    onChanged: (v) => setSheet(() => percent = v),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.accent,
                          ),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _onSeek(percent);
                          },
                          child: const Text('跳转'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 从头再读（读完卡片）。
  void _restartBook() {
    _visible.bridge?.gotoStart();
    _resetHiddenSync();
    setState(() => _chromeVisible = false);
  }

  Future<void> _maybeShowGuide() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kGuideKey) == true) return;
    if (!mounted) return;
    setState(() => _guideVisible = true);
  }

  Future<void> _dismissGuide() async {
    if (mounted) setState(() => _guideVisible = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGuideKey, true);
  }

  // ---- M2 标注/书签 ----

  /// 收起标注菜单/划线面板并清掉 WebView 里的文本选区。
  void _dismissAnnotationUi() {
    if (_selection == null && _activeAnnotation == null) return;
    _nativeKey.currentState?.clearTextSelection();
    setState(() {
      _selection = null;
      _activeAnnotation = null;
      _selectionAnchor = null;
      _nativeSelection = null;
    });
    for (final v in [_a, _b]) {
      unawaited(v.bridge?.clearSelection());
    }
  }

  /// 按选区创建划线（4 色 / 笔记共用入口）。
  Future<void> _createHighlight(
    AnnotationColor color,
    ReaderSelected sel, {
    String note = '',
  }) async {
    final repo = await ref.read(annotationRepositoryProvider.future);
    // 原生模式：锚点是「章索引 + 字符区间」，渲染时不需要迁移
    final nsel = _nativeSelection;
    final isNative =
        nsel != null &&
        sel.cfiRange == '@${nsel.chapterIndex}:${nsel.start}:${nsel.end}';
    final created = await repo.addHighlight(
      bookId: widget.bookId,
      cfiRange: isNative ? '' : sel.cfiRange,
      color: color,
      quotedText: sel.text,
      href: isNative ? _nativeHrefOf(nsel.chapterIndex) : null,
      chapterIndex: isNative ? nsel.chapterIndex : null,
      offset: isNative ? nsel.start : null,
      offsetEnd: isNative ? nsel.end : null,
    );
    if (note.isNotEmpty) {
      await repo.setNote(created.id, note);
    }
    // 双池定点注入（watch 流刷新列表 UI）
    final cfi = _cfiRangeOf(created);
    for (final v in [_a, _b]) {
      unawaited(
        v.bridge?.addHighlight(
          id: created.id,
          cfiRange: cfi,
          colorToken: created.color.token,
        ),
      );
    }
    _dismissAnnotationUi();
  }

  /// 划线操作弹窗（屏幕中间）：改颜色 / 写想法 / 删除。
  Future<void> _showAnnotationDialog(Annotation a) async {
    setState(() => _activeAnnotation = a);
    try {
      final result = await showAnnotationEditDialog(
        context,
        annotation: a,
        theme: _theme,
      );
      if (result == null || !mounted) return;
      final repo = await ref.read(annotationRepositoryProvider.future);

      if (result.delete) {
        await repo.remove(a.id);
        final cfi = _cfiRangeOf(a);
        for (final v in [_a, _b]) {
          unawaited(v.bridge?.removeHighlight(cfi));
        }
        return;
      }

      if (result.color != a.color) {
        await repo.setColor(a.id, result.color);
        final cfi = _cfiRangeOf(a);
        for (final v in [_a, _b]) {
          unawaited(v.bridge?.removeHighlight(cfi));
          unawaited(
            v.bridge?.addHighlight(
              id: a.id,
              cfiRange: cfi,
              colorToken: result.color.token,
            ),
          );
        }
      }
      if ((a.note ?? '') != result.note) {
        await repo.setNote(a.id, result.note);
      }
    } finally {
      if (mounted) setState(() => _activeAnnotation = null);
    }
  }

  /// 删除划线（软删 + 双池移除绘制）。
  Future<void> _deleteAnnotation(Annotation a) async {
    final repo = await ref.read(annotationRepositoryProvider.future);
    await repo.remove(a.id);
    final cfi = _cfiRangeOf(a);
    for (final v in [_a, _b]) {
      unawaited(v.bridge?.removeHighlight(cfi));
    }
    setState(() => _activeAnnotation = null);
  }

  /// 编辑笔记（模态输入）。
  Future<void> _editAnnotationNote(Annotation a) async {
    final note = await showNoteEditorSheet(
      context,
      theme: _theme,
      initial: a.note,
    );
    if (note == null || !mounted) return;
    final repo = await ref.read(annotationRepositoryProvider.future);
    await repo.setNote(a.id, note);
    setState(() => _activeAnnotation = null);
  }

  /// 当前页是否已加书签（CFI 或原生章节/页定位匹配）。
  bool get _currentPageBookmarked {
    final key = bookmarkKeyFor(
      _controllerState.currentLocator ?? _controllerState.initialLocator,
    );
    if (key == null) return false;
    return _bookmarks.any(
      (b) => bookmarkKeyFor(locatorFromJson(b.locator)) == key,
    );
  }

  /// 书签开关。
  Future<void> _toggleBookmark() async {
    final repo = await ref.read(annotationRepositoryProvider.future);
    final loc =
        _controllerState.currentLocator ?? _controllerState.initialLocator;
    final key = bookmarkKeyFor(loc);
    debugPrint(
      'reader-diag: toggleBookmark loc=${loc != null} key=$key '
      'bookmarks=${_bookmarks.length}',
    );
    if (key == null || loc == null) return;
    final existing = _bookmarks
        .where((b) => bookmarkKeyFor(locatorFromJson(b.locator)) == key)
        .firstOrNull;
    if (existing != null) {
      await repo.removeBookmark(existing.id);
    } else {
      await repo.addBookmark(
        bookId: widget.bookId,
        locatorJson: locatorToJson(loc),
      );
    }
  }

  /// 目录跳转到标注/书签的 locator。
  void _gotoLocatorJson(String locatorJson) {
    setState(() => _tocOpen = false);
    final loc = locatorFromJson(locatorJson);
    if (loc == null) return;
    // 原生阅读面：按 href / 章索引定位到章，再按章内字符偏移定位到页。
    // （旧实现走 _visible.bridge，原生模式下 bridge 恒为 null，点了没反应。）
    final book = _controllerState.book;
    final chapters = book == null
        ? null
        : ref.read(nativeChaptersProvider(NativeChaptersKey.of(book))).value;
    if (chapters != null) {
      final chapter = nativeChapterForLocator(chapters, loc);
      if (chapter != null) {
        _nativeKey.currentState?.jumpToChapter(
          chapter.idx,
          offset: loc.offset ?? 0,
        );
        return;
      }
    }
  }

  /// 全书搜索入口。
  Future<void> _openSearch() async {
    final hit = await context.push<BookSearchHit>(
      readerSearchPath(widget.bookId),
    );
    if (hit == null) return;
    unawaited(_visible.bridge?.gotoHref(hit.href));
    _resetHiddenSync();
  }

  /// 标注导出 Markdown：写入应用文档目录 exports/，SnackBar 给出路径。
  Future<void> _exportAnnotations() async {
    final state = _controllerState;
    final book = state.book;
    if (book == null) return;
    final md = annotationsToMarkdown(book, _annotations);
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'QYReader', 'exports'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final safe = book.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File(p.join(dir.path, '$safe-标注-$stamp.md'));
    await file.writeAsString(md, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已导出：${file.path}')));
  }

  /// 朗读入口：设置面板 → 开始朗读。
  Future<void> _showTtsSheet() async {
    // 朗读时收起 chrome 与抽屉，避免遮挡正文
    final started = await showTtsSheet(
      context,
      theme: _theme,
      loadVoices: _tts.availableVoices,
    );
    if (started != true || !mounted) return;
    setState(() => _chromeVisible = false);
    await _tts.start(ref.read(ttsSettingsControllerProvider));
    if (_tts.value.error != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_tts.value.error!)));
    }
  }

  ReadingTheme get _theme => ref.read(readingSettingsControllerProvider).theme;

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerControllerProvider(widget.bookId));
    final settings = ref.watch(readingSettingsControllerProvider);
    final liveMargins = ref.watch(liveReaderMarginsProvider);
    final theme = settings.theme;
    final insets = _readingVerticalInsets();
    final safePadding = MediaQuery.maybePaddingOf(context) ?? EdgeInsets.zero;
    final padding = _pagePadding(settings, liveMargins);
    // 正文区宽度：屏宽 - 水平安全区（外层 SafeArea 扣一次）- 用户边距。
    final contentWidth =
        (MediaQuery.sizeOf(context).width -
                safePadding.horizontal -
                padding.horizontal)
            .clamp(1.0, double.infinity);
    // 内容区右侧到屏幕右边缘的空白（右边距 + 系统安全区）。
    //
    // 隐藏层必须停在**屏幕右边界之外**，只停在内容区右侧是不够的：
    // 平台视图（Android WebView 走虚拟显示纹理）不会被 Flutter 的 Stack
    // 裁剪到内容区，停在内容区右边时它的左侧会压在右边距上——用户看到
    // 右侧露出下一页的内容（实测：正文右侧 16px 处出现下一列的竖向缝隙）。
    // 静止位改成 contentWidth + rightGutter，隐藏层整层在屏幕之外。
    final rightGutter = padding.right + safePadding.right;

    final contentReady =
        _booted &&
        state.book != null &&
        !_bootTimedOut &&
        _readerUri != null;

    // 底部进度条：按设置显示全书或本章进度
    final progressScope = settings.progressScope;
    final chapterFraction = state.chapterPages > 0
        ? ((state.chapterPage - 1) / state.chapterPages).clamp(0.0, 1.0)
        : 0.0;
    final bookFraction = (state.percent ?? 0).clamp(0.0, 1.0);
    final progressValue = progressScope == ProgressScope.chapter
        ? chapterFraction
        : bookFraction;
    final progressLabel = progressScope == ProgressScope.chapter
        ? '本章 ${(chapterFraction * 100).round()}%'
        : '${(bookFraction * 100).toStringAsFixed(1)}%';

    // 章末不再弹「下一章」卡片（用户要求去掉了这个底部跳转提示）：
    // 继续往后翻就是下一章（原生阅读面的哨兵页），不需要额外按钮。
    // 只在全书读完时保留提示（从头再读 / 回书架）。
    final showPageCard =
        contentReady &&
        _selection == null &&
        _activeAnnotation == null &&
        state.atEnd;

    return PopScope(
      // 返回键分层：选区/抽屉/诊断/chrome 依次收起，最后才退出阅读器
      canPop:
          !_tocOpen &&
          !_chromeVisible &&
          !_diagVisible &&
          _marginGroup == null &&
          _selection == null &&
          _activeAnnotation == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_marginGroup != null) {
          _closeMarginEditor();
          return;
        }
        if (_selection != null || _activeAnnotation != null) {
          _dismissAnnotationUi();
          return;
        }
        if (_diagVisible) {
          setState(() => _diagVisible = false);
          return;
        }
        if (_tocOpen) {
          setState(() => _tocOpen = false);
          return;
        }
        if (_chromeVisible) setState(() => _chromeVisible = false);
      },
      child: Scaffold(
        backgroundColor: theme.background,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Focus(
            autofocus: true,
            onKeyEvent: _onKeyEvent,
            child: Stack(
              children: [
                // [0] 内容层：边距 = WebView 外层 padding（拖动只改 padding，
                // 不触发布局；松手后由设置监听统一重排并回到原 CFI）
                Positioned.fill(
                  child: contentReady
                      ? AnimatedPadding(
                          duration: const Duration(milliseconds: 60),
                          curve: Curves.easeOut,
                          // 原生阅读面自带四边留白（含安全区，页眉/页脚色带
                          // 也靠它贯通到屏幕上下边缘），外层不能再叠一遍，
                          // 否则上下各多出一条双重留白（色带标注下实测）。
                          // WebView 路径仍靠外层 padding 做拖边距实时预览。
                          padding:
                              _useNative(settings) ? EdgeInsets.zero : padding,
                          child: Stack(
                            children: [
                              // 固定槽位顺序：交换可视/隐藏时不要让 Stack
                              // 子项换位（GlobalKey 重排会重新挂载平台视图，
                              // 手势被 ACTION_CANCEL 打断）。z 序固定 A 在下。
                              // 原生文本阅读面（默认）：纯 Flutter 原生文本
                              // + PageView，可切换 slide/cover/fade/curl/none
                              // 五种翻页效果。
                              if (_useNative(settings))
                                Positioned.fill(
                                  // 转场动画期间不挂载正文：章节解析与首次
                                  // 分页是重活，会在展开动画里掉帧。先显示
                                  // loading，转场结束后才开始加载，加载完成
                                  // 后在 _buildNativeReader 里淡入。
                                  child: _contentRevealed
                                      ? _buildNativeReader(
                                          state,
                                          settings,
                                          theme,
                                          // 原生视图的上下只吃安全区保底：正文
                                          // 上下边距由页眉/页脚色带承担（页眉上
                                          // 边距/页脚下边距同理），这里混进去会
                                          // 双重计高。
                                          EdgeInsets.fromLTRB(
                                            padding.left,
                                            insets.top,
                                            padding.right,
                                            insets.bottom,
                                          ),
                                        )
                                      : _openingPanel(
                                          theme,
                                          title: state.book?.title,
                                        ),
                                ),
                              if (!_useNative(settings))
                                _viewLayer(
                                  _a,
                                  contentWidth,
                                  rightGutter,
                                  settings,
                                  theme,
                                ),
                              if (!_useNative(settings))
                                _viewLayer(
                                  _b,
                                  contentWidth,
                                  rightGutter,
                                  settings,
                                  theme,
                                ),
                              // 首次渲染完成前给出可见状态，杜绝纯白屏。
                              // 进度恢复（多页定位）期间 WebView 内部把视图
                              // visibility:hidden，落定后才显示最终页——
                              // 用户打开书直接看到目标页，没有逐页滚动过程。
                              // 原生模式没有 WebView 定位状态，这块遮罩
                              // 会永久盖住正文（实测）
                              if (!_useNative(settings) &&
                                  _visible.locator == null &&
                                  !_visible.settled)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: ColoredBox(
                                      color: theme.background,
                                      child: Center(
                                        child: Text(
                                          '正在打开书籍…',
                                          style: TextStyle(
                                            color: theme.chromeForeground,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        )
                      : _openingPanel(
                          theme,
                          title: state.book?.title,
                        ),
                ),
                // [1] 后翻覆盖层：旧页截图滑出
                Positioned.fill(
                  child: _backOverlay != null
                      ? RepaintBoundary(
                          child: Transform.translate(
                            offset: Offset(contentWidth * (_turn?.t ?? 0), 0),
                            child: Image.memory(
                              _backOverlay!,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                // [2] 亮度遮罩（左边缘上下滑动调节，不拦截触摸）
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: _dim),
                    ),
                  ),
                ),
                // [2.5] 页码 HUD：页脚已经显示页码时不再叠一个（避免双份）
                if (!_footerShowsPageNumbers(settings))
                  Positioned(
                    // Stack 在 SafeArea 内，水平安全区已扣过，这里只加用户边距
                    right: settings.marginRight,
                    bottom: insets.bottom + 2,
                    child: AnimatedOpacity(
                      opacity: (!_chromeVisible && contentReady && !_tocOpen)
                          ? 1
                          : 0,
                      duration: const Duration(milliseconds: 220),
                      child: IgnorePointer(
                        ignoring: _chromeVisible || !contentReady,
                        child: _PageNumber(
                          page: state.chapterPage,
                          pages: state.chapterPages,
                          bookPage: state.bookPage,
                          bookPages: state.bookPages,
                          theme: theme,
                          onTap: _showJumpPanel,
                        ),
                      ),
                    ),
                  ),
                // [2.6] 全书读完卡片（章末的「下一章」提示已去掉：
                // 继续翻页就是下一章）
                if (showPageCard)
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: insets.bottom + 40,
                    child: _EndCard(
                      theme: theme,
                      onRestart: _restartBook,
                      onBack: _onBack,
                    ),
                  ),
                // [2.7] 边缘手势指示（亮度/字号）
                if (_edgeHud != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: _EdgeHud(
                          theme: theme,
                          brightness: _edgeHud == 'brightness',
                          value: _edgeHudValue,
                        ),
                      ),
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
                              bookmarked: _currentPageBookmarked,
                              onBack: _onBack,
                              onToggleBookmark: _toggleBookmark,
                              onSearch: _openSearch,
                              onExport: _exportAnnotations,
                              onDiag: () async {
                                setState(() => _diagVisible = true);
                                await _dumpPageDiag();
                              },
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 控制条是独立层（chrome 隐藏时仍可见），
                                  // 此处留出底栏高度避免遮挡
                                  SizedBox(height: _tts.value.active ? 64 : 0),
                                  _BottomBar(
                                    state: state,
                                    theme: theme,
                                    progressValue: progressValue,
                                    progressLabel: progressLabel,
                                    ttsActive: _tts.value.active,
                                    onToc: () =>
                                        setState(() => _tocOpen = true),
                                    onJump: _showJumpPanel,
                                    onTypesetting: _showTypesetting,
                                    onTts: _showTtsSheet,
                                    onSeek: _onSeek,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
                // [3.5] 朗读控制条：独立于 chrome（朗读时 chrome 自动隐藏，
                // 控制条必须仍然可见可操作）
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: (_chromeVisible && state.book != null) ? 96 : 8,
                      ),
                      child: ValueListenableBuilder<TtsPlaybackState>(
                        valueListenable: _tts,
                        builder: (context, ttsState, _) {
                          if (!ttsState.active) {
                            return const SizedBox.shrink();
                          }
                          return TtsBar(
                            state: ttsState,
                            theme: theme,
                            onPause: _tts.pause,
                            onResume: _tts.resume,
                            onStop: _tts.stop,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                // [4] 目录抽屉（目录/书签/标注三 Tab）。
                // 必须 Positioned.fill：Stack 尺寸由非定位子节点决定，
                // 收起时的 SizedBox.shrink 会把整个根 Stack 塌缩成 0×0，
                // 连带所有 Positioned.fill 子树（含 WebView 平台视图）归零。
                Positioned.fill(
                  child: TocDrawer(
                    open: _tocOpen,
                    theme: theme,
                    chapters: state.chapters,
                    currentHref: _visible.locator?.href,
                    bookmarks: _bookmarks,
                    annotations: _annotations,
                    onDismiss: () => setState(() => _tocOpen = false),
                    onChapter: _onChapterTap,
                    onGotoLocator: _gotoLocatorJson,
                    onDeleteBookmark: (id) async {
                      final repo = await ref.read(
                        annotationRepositoryProvider.future,
                      );
                      await repo.removeBookmark(id);
                    },
                    onEditNote: (a) {
                      setState(() => _tocOpen = false);
                      unawaited(_editAnnotationNote(a));
                    },
                    onDeleteAnnotation: (id) async {
                      final a = _annotations
                          .where((x) => x.id == id)
                          .firstOrNull;
                      if (a != null) await _deleteAnnotation(a);
                    },
                    onExport: _exportAnnotations,
                  ),
                ),
                // [4.5] 选区标注菜单（锚定选区矩形上方/下方，z 序高于抽屉）
                if (_selection != null)
                  SelectionMenu(
                    rect: _selection!.rect,
                    theme: theme,
                    onColor: (c) => _createHighlight(c, _selection!),
                    onNote: () async {
                      final sel = _selection;
                      if (sel == null) return;
                      final note = await showNoteEditorSheet(
                        context,
                        theme: theme,
                      );
                      if (note == null) return;
                      if (!mounted) return;
                      await _createHighlight(
                        AnnotationColor.yellow,
                        sel,
                        note: note,
                      );
                    },
                    onCopy: () {
                      Clipboard.setData(
                        ClipboardData(text: _selection?.text ?? ''),
                      );
                      _dismissAnnotationUi();
                    },
                  ),
                // [4.7] 首次进入引导
                if (_guideVisible)
                  Positioned.fill(
                    child: _ReaderGuide(theme: theme, onDismiss: _dismissGuide),
                  ),
                // [5] 全屏遮罩：装载错误 / WebView 不可用诊断
                Positioned.fill(child: _buildOverlay(state, theme)),
                // [6] 边距直调（正文 / 页眉 / 页脚三页）
                if (_marginGroup != null)
                  Positioned.fill(
                    child: MarginEditorOverlay(
                      key: const ValueKey('margin-editor'),
                      settings: settings,
                      textScale: MediaQuery.textScalerOf(context).scale(100) /
                          100,
                      initialGroup: _marginGroup!,
                      onPreview: _previewMargins,
                      onCommit: _commitMargins,
                      onClose: _closeMarginEditor,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 原生文本阅读面。
  ///
  /// 章节文本来自 `nativeChaptersProvider`（复用 EPUB 解析，isolate 内跑）。
  /// 位置回报走和 WebView 同一条通道（`_controller.onRelocated`），
  /// 所以页码 HUD、进度保存、阅读时长统计都不必改。
  Widget _buildNativeReader(
    ReaderState state,
    ReadingSettings settings,
    ReadingTheme theme,
    EdgeInsets padding,
  ) {
    final book = state.book;
    if (book == null) return const SizedBox.shrink();
    final async = ref.watch(nativeChaptersProvider(NativeChaptersKey.of(book)));
    // 加载面板 → 正文交叉淡入：AnimatedSwitcher 同时淡出旧子、淡入新子。
    // 不能只做「正文从 0 淡入」——正文全透明的那几帧底下是纯背景，加载
    // 面板被换走的瞬间整页空一帧，打开书时会闪一下（录屏实测 2.71s 处
    // 中心区域 cstd=0 的空帧）。
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: async.when(
        loading: () => KeyedSubtree(
          key: const ValueKey('reader-opening'),
          child: _openingPanel(theme, title: book.title),
        ),
        error: (e, _) => KeyedSubtree(
          key: const ValueKey('reader-error'),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '正文解析失败：$e',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.foreground),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => ref.invalidate(
                      nativeChaptersProvider(NativeChaptersKey.of(book)),
                    ),
                    icon: Icon(Icons.refresh, color: theme.accent),
                    label: Text('重新加载', style: TextStyle(color: theme.accent)),
                  ),
                ],
              ),
            ),
          ),
        ),
        data: (chapters) {
          if (_nativeInitialised == false) {
            _nativeInitialised = true;
            _nativeStartChapter = _nativeChapterFor(chapters);
            _nativeStartOffset = _nativeOffsetFor(chapters);
          }
          return KeyedSubtree(
            key: const ValueKey('native-reader'),
            child: NativeReaderView(
              key: _nativeKey,
              chapters: chapters,
              settings: _nativeSettings(settings),
              pageLayout: ref.watch(pageLayoutControllerProvider),
              previewListenable: liveReaderTypesetPreview,
              marginPreviewListenable: liveReaderMarginPreview,
              padding: padding,
              theme: theme,
              backgroundImage: settings.backgroundImage,
              // 页眉/页脚「全文进度」用；控制器里的 percent 是当前书位
              bookPercent: (state.percent ?? 0).clamp(0.0, 1.0),
              initialChapterIndex: _nativeStartChapter,
              initialOffset: _nativeStartOffset,
              ttsHighlight: _nativeTtsHighlight,
              marks: _nativeMarks(chapters),
              // 长按选字 → 四色/笔记/复制菜单（原生模式的标注入口）
              onSelection: _onNativeSelection,
              // 拖手柄/重新选字时先把菜单收起来（否则菜单盖住手柄，
              // 用户只能一个字一个字点，没法顺畅拖范围）
              onSelectionClear: () {
                if (!mounted || _selection == null) return;
                setState(() => _selection = null);
              },
              // 点已有划线 → 操作面板（改色/加想法/删除）
              onMarkTap: _onNativeMarkTap,
              onPosition: _onNativePosition,
              onCenterTap: () {
                if (mounted) setState(() => _chromeVisible = !_chromeVisible);
              },
            ),
          );
        },
      ),
    );
  }

  /// 打开书籍的加载面板：菊花 + 书名 + 「正在打开…」。
  ///
  /// 三处加载态共用（转场结束前、控制器启动中、章节解析中）：同一套
  /// 排版，从加载到正文之间不会跳版。
  Widget _openingPanel(ReadingTheme theme, {String? title}) {
    final name = (title ?? _controllerState.book?.title ?? '').trim();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: theme.accent,
              ),
            ),
            const SizedBox(height: 24),
            if (name.isNotEmpty) ...[
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.foreground,
                  fontSize: 17,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              '正在打开…',
              style: TextStyle(
                color: theme.foreground.withValues(alpha: 0.55),
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 用保存的 href / 章索引对齐到原生章节表。
  int _nativeChapterFor(List<NativeChapter> chapters) {
    final loc =
        _controllerState.initialLocator ?? _controllerState.currentLocator;
    final href = loc?.href;
    if (href != null) {
      for (var i = 0; i < chapters.length; i++) {
        if (chapters[i].href == href) return i;
      }
    }
    final idx = loc?.chapterIndex;
    if (idx != null) return idx.clamp(0, chapters.length - 1);
    // 新书：跳过扉页/版权页/目录等前置页，避免打开像空白
    return firstReadableChapterIndex(chapters);
  }

  int _nativeOffsetFor(List<NativeChapter> chapters) {
    final loc =
        _controllerState.initialLocator ?? _controllerState.currentLocator;
    return (loc?.offset ?? 0).clamp(0, 1 << 30);
  }

  /// 原生正文长按选字 → 弹标注菜单。
  ///
  /// 复用 WebView 时代那套 `SelectionMenu`（四色/笔记/复制），只是锚点
  /// 用长按位置（SelectableText 不回调选区矩形）。
  void _onNativeSelection(NativeSelection sel) {
    if (!mounted) return;
    setState(() {
      _nativeSelection = sel;
      _selection = ReaderSelected(
        // 编码成 @章:起:止，创建划线时再解回偏移
        cfiRange: '@${sel.chapterIndex}:${sel.start}:${sel.end}',
        text: sel.text,
        rect: SelectionRect(
          left: sel.anchor.dx,
          top: sel.anchor.dy,
          width: 1,
          height: 1,
        ),
      );
    });
  }

  /// 点击正文里的已有划线 → 打开操作面板。
  void _onNativeMarkTap(NativeMark mark) {
    final match = _annotations.where((a) => a.id == mark.id).firstOrNull;
    if (match == null) return;
    unawaited(_showAnnotationDialog(match));
  }

  /// 当前原生选区（原生模式创建划线用）。
  NativeSelection? _nativeSelection;

  void _onNativePosition(NativePosition p) {
    final atStart = p.chapterIndex == 0 && p.page <= 1;
    final atEnd =
        p.chapterIndex >=
            (ref
                        .read(nativeChaptersProvider(NativeChaptersKey.of(_controllerState.book!)))
                        .value
                        ?.length ??
                    1) -
                1 &&
        p.page >= p.pages;
    final locator = Locator(
      href: _nativeHrefOf(p.chapterIndex),
      chapterIndex: p.chapterIndex,
      offset: p.offset,
      page: p.page,
      pages: p.pages,
      percent: p.percent,
      pos: p.percent,
    );
    _session?.onPercent(p.percent);
    _controller.onRelocated(
      locator,
      atStart: atStart,
      atEnd: atEnd,
      chapterPage: p.page,
      chapterPages: p.pages,
    );
  }

  String? _nativeHrefOf(int chapterIdx) {
    final book = _controllerState.book;
    if (book == null) return null;
    final chapters = ref.read(nativeChaptersProvider(NativeChaptersKey.of(book))).value;
    if (chapters == null || chapterIdx < 0 || chapterIdx >= chapters.length) {
      return null;
    }
    return chapters[chapterIdx].href;
  }

  /// 原生阅读面的位置回报 → 控制器（页码 HUD / 进度 / 统计共用）。
  /// 构造原生 TTS 适配层（章节表来自同一 provider）。
  NativeTtsSurface _makeNativeTts() {
    final book = _controllerState.book;
    final chapters = book == null
        ? null
        : ref.read(nativeChaptersProvider(NativeChaptersKey.of(book))).value;
    return NativeTtsSurface(
      chapters: chapters ?? const [],
      currentChapter: () => _nativeKey.currentState?.currentChapter ?? 0,
      currentOffset: () => _nativeKey.currentState?.currentPageOffset ?? 0,
      onHighlight: (h) => _nativeTtsHighlight.value = h,
      onJumpTo: (chapterIdx, offset) {
        final state = _nativeKey.currentState;
        if (state == null) return;
        if (state.currentChapter != chapterIdx) {
          state.jumpToChapter(chapterIdx, offset: offset);
        } else {
          state.jumpToOffset(offset);
        }
      },
    );
  }

  /// 解析划线在本章内的字符区间（原生渲染用）。
  ///
  /// 锚点优先用 `offset/offsetEnd`；老数据只有 CFI，就用 `quotedText` 在
  /// 章正文里搜一次并**回写**成偏移（幂等：迁移成功后不再重复）。
  List<NativeMark> _nativeMarks(List<NativeChapter> chapters) {
    if (_annotations.isEmpty) return const [];
    final out = <NativeMark>[];
    for (final a in _annotations) {
      final loc = locatorFromJson(a.locatorStart);
      if (loc == null) continue;
      final chapter = nativeChapterForLocator(chapters, loc);
      if (chapter == null) continue;
      var start = loc.offset;
      var end = loc.offsetEnd;
      if (start == null || end == null || end <= start) {
        final quote = (a.quotedText ?? '').trim();
        if (quote.isEmpty) continue;
        final at = chapter.text.indexOf(quote);
        if (at < 0) continue; // 找不到就跳过（不误画）
        start = at;
        end = at + quote.length;
        _persistAnchor(a.id, chapter, start, end);
      }
      out.add(
        NativeMark(
          id: a.id,
          chapterIndex: chapter.idx,
          start: start,
          end: end,
          color: _markFills[a.color.token] ?? _markFills['yellow']!,
        ),
      );
    }
    return out;
  }


  /// 把 CFI 锚点迁移成「章索引 + 字符偏移」并回写数据库（每个标注只写一次）。
  void _persistAnchor(String id, NativeChapter chapter, int start, int end) {
    if (!_anchored.add(id)) return;
    final json = locatorToJson(
      Locator(
        href: chapter.href,
        chapterIndex: chapter.idx,
        offset: start,
        offsetEnd: end,
      ),
    );
    unawaited(() async {
      try {
        final repo = await ref.read(annotationRepositoryProvider.future);
        await repo.setAnchor(id, json);
        _diagLog('anchor migrated id=$id ch=${chapter.idx} $start..$end');
      } catch (e) {
        _diagLog('anchor migrate failed id=$id: $e');
      }
    }());
  }

  /// 全屏遮罩：装载错误或 WebView 启动诊断（恒定占位，内部条件渲染）。
  Widget _buildOverlay(ReaderState state, ReadingTheme theme) {
    if (_diagVisible) {
      return _diagPanel(theme);
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
      return _diagPanel(theme);
    }
    return const SizedBox.shrink();
  }

  /// 启动超时后的手动重试：换一个干净的控制器，并让章节缓存重新解析。
  void _retryBoot() {
    if (!mounted) return;
    final book = _controllerState.book;
    setState(() {
      _bootTimedOut = false;
      _booted = false;
      _nativeInitialised = false;
      _nativeStartChapter = 0;
      _nativeStartOffset = 0;
    });
    ref.invalidate(readerControllerProvider(widget.bookId));
    if (book != null) {
      ref.invalidate(nativeChaptersProvider(NativeChaptersKey.of(book)));
    }
    unawaited(_restoreThenBoot());
  }

  /// 诊断面板：全链路事件日志（看门狗触发或手动打开）。
  Widget _diagPanel(ReadingTheme theme) {
    return ColoredBox(
      color: theme.background,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '诊断信息（${_diag.length} 条）',
                  style: TextStyle(
                    color: theme.chromeForeground,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _diagVisible = false),
                icon: Icon(Icons.close, color: theme.chromeForeground),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _retryBoot,
              icon: Icon(Icons.refresh, color: theme.chromeForeground),
              label: Text(
                '重新加载',
                style: TextStyle(color: theme.chromeForeground),
              ),
            ),
          ),
          const SizedBox(height: 8),
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

  /// 构造某一层。所有状态（静止/翻页中/隐藏）共享同一棵 widget 结构
  /// （Positioned.fill > RepaintBoundary > ValueListenableBuilder >
  /// Opacity > Transform.translate > Stack[Transform > pane, 遮罩]），
  /// 只改数值参数——避免 Windows 平台视图在子树结构变化时丢内容。
  /// 隐藏态 = 恒定位移到屏幕外右侧。
  ///
  /// 动画进度由 [_turnProgress] 驱动：ValueListenableBuilder 的 child 参数
  /// 缓存平台视图子树，翻页每帧只重建变换与遮罩，WebView 子树完全不参与
  /// 逐帧重建（原来整页 setState，拖拽时每帧重建 chrome/目录抽屉/双 WebView）。
  Widget _viewLayer(
    _ViewSlot slot,
    double width,
    double rightGutter,
    ReadingSettings settings,
    ReadingTheme theme,
  ) {
    final isHidden = slot != _visible;
    final turn = _turn;
    final forwardTurn = turn != null && turn.isForward;
    final mode = settings.pageTurnMode;

    // 隐藏层静止位：内容区宽度 + 右侧空白 → 整层落在屏幕右边界之外
    // （+2px 余量，防亚像素取整让边缘漏进 1~2px）。
    // 前翻时从屏幕右边缘滑入（不是从内容区右边缘），两页之间始终留
    // (rightGutter+2)*(1-t) 的缝——正好是右边距被新页吃掉的过程，收尾严丝合缝。
    final restDx = hiddenLayerRestDx(width, rightGutter);

    return Positioned.fill(
      child: RepaintBoundary(
        child: ValueListenableBuilder<double>(
          valueListenable: _turnProgress,
          builder: (context, t, pane) {
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
                    dx = restDx * (1 - t);
                    // 不要给平台视图挂透视旋转：WebView 是纹理合成
                    // （initSurfaceAndroidView），一旦矩阵含 3D 透视分量，
                    // Flutter 每帧都要把 WebView 重新光栅化进一张新纹理
                    // （实测每帧 125~150ms，翻页动画变成幻灯片）。
                    // 纯 2D 平移可以直接复用缓存纹理，只做合成偏移。
                    rotY = 0;
                  case PageTurnMode.cover:
                    dx = restDx * (1 - t);
                  case PageTurnMode.fade:
                    opacity = t;
                  case PageTurnMode.curl:
                  case PageTurnMode.freeCurl:
                    dx = 0; // 下一页原地露出，由旧页折叠揭开
                  case PageTurnMode.none:
                    dx = restDx;
                }
              } else {
                // 静止/后翻期间：整层停在屏幕右边界之外（结构不变）
                dx = restDx;
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
                  case PageTurnMode.curl:
                  case PageTurnMode.freeCurl:
                    // 沿左缘折叠翻起：透视旋转 + 轻微左移；折线由下方阴影层画
                    rotY = -1.15 * t;
                    dx = -width * 0.03 * t;
                    dim = 0.22 * t;
                  case PageTurnMode.none:
                    dx = 0;
                }
              } else if (turn != null) {
                // 后翻跟手：当前页右移（无预渲染前页，露出主题背景），
                // 抬手提交时两个视图同时 prev，回弹期间内容已切到上一页
                dx = width * t;
              }
            }

            return Opacity(
              opacity: opacity,
              child: Transform.translate(
                offset: Offset(dx, dy),
                child: Stack(
                  children: [
                    // 平台视图的渲染对象是无子节点的代理盒，松约束下会收缩为 0×0
                    //（表现为 WebView 事件全通但永远不出像素，relocated 也不触发）。
                    // 必须用 Positioned.fill 强制满尺寸紧约束。
                    Positioned.fill(
                      child: Transform(
                        alignment: Alignment.centerLeft,
                        // 无 3D 旋转时用单位矩阵：透视矩阵会让平台视图走
                        // 变换合成路径，静止时白白多一次合成开销。
                        transform: rotY == 0
                            ? Matrix4.identity()
                            : (Matrix4.identity()
                                ..setEntry(3, 2, 0.002)
                                ..rotateY(rotY)),
                        child: pane,
                      ),
                    ),
                    // 目标页未就绪：同尺寸骨架占位，动画不等待异步结果
                    if (slot.covered)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: _PageSkeleton(theme: theme),
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
                    // curl 模式：折缝阴影（右缘抬起处最深，向内渐变消散）
                    if (!isHidden && forwardTurn && mode == PageTurnMode.curl)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerRight,
                                end: Alignment.centerLeft,
                                colors: [
                                  Colors.black.withValues(alpha: 0.30 * t),
                                  Colors.black.withValues(alpha: 0.10 * t),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.16, 0.55],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
          // 平台视图子树：整段动画期间复用同一实例，不参与逐帧重建。
          child: _WebViewPane(
            key: _paneKeyFor(slot),
            slot: slot,
            pageUri: _readerUri!,
            bookUrl: _bookUrl!,
            // JS 自主首渲：可视层带初始定位，隐藏层从头显示
            locatorJson: slot == _visible ? _initialLocatorJson : null,
            // 首帧前注入主题/字号，避免先白底再换色
            styleJson: _stylePayload(),
            // 全书字数（导入时解析得到）：页面用它估算全书页数，
            // 不必生成整本书的 locations（那要把全书渲染一遍）。
            totalChars: _controllerState.book?.wordCount ?? 0,
            onJsEvent: (args) => _onJsEvent(slot, args),
            onDiag: _diagLog,
          ),
        ),
      ),
    );
  }
}

/// 单个 WebView 面板（webview_flutter 官方插件实现）。
class _WebViewPane extends StatefulWidget {
  const _WebViewPane({
    required this.slot,
    required this.pageUri,
    required this.bookUrl,
    required this.locatorJson,
    required this.styleJson,
    required this.totalChars,
    required this.onJsEvent,
    required this.onDiag,
    super.key,
  });

  final _ViewSlot slot;

  /// 渲染页地址（Flutter assets）。
  final Uri pageUri;

  /// 书籍地址（同源 file）。
  final String bookUrl;

  /// 初始定位 JSON（可空）。
  final String? locatorJson;

  /// 初始排版载荷（仅在页面加载完成时读取一次）。
  final String styleJson;

  /// 全书字数（0 = 未知）。
  final int totalChars;

  final void Function(List<dynamic> args) onJsEvent;
  final void Function(String line) onDiag;

  @override
  State<_WebViewPane> createState() => _WebViewPaneState();
}

class _WebViewPaneState extends State<_WebViewPane> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      // chrome://inspect 远程调试 WebView（仅 debug 构建）
      AndroidWebViewController.enableDebugging(true);
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => widget.onDiag('[${widget.slot.id}] loadStart'),
          onPageFinished: (_) {
            widget.onDiag('[${widget.slot.id}] loadStop → loadBook');
            widget.slot.bridge?.loadBook(
              widget.bookUrl,
              locatorJson: widget.locatorJson,
              styleJson: widget.styleJson,
            );
            // 全书字数：页面用它估算全书页数（替代 locations 的字数反推）
            if (widget.totalChars > 0) {
              widget.slot.bridge?.setTotalChars(widget.totalChars);
            }
          },
          onHttpError: (e) => widget.onDiag(
            '[${widget.slot.id}] httpError ${e.response?.statusCode ?? "?"}',
          ),
          onNavigationRequest: (request) {
            // 正文内链接跳外链/其他源时拦截（M2 脚注处理，避免污染渲染页）
            final url = request.url;
            if (url.startsWith('file://') ||
                url.startsWith('http://127.0.0.1')) {
              return NavigationDecision.navigate;
            }
            widget.onDiag('[${widget.slot.id}] nav blocked: $url');
            return NavigationDecision.prevent;
          },
        ),
      )
      ..addJavaScriptChannel(
        'readerEvent',
        onMessageReceived: (message) {
          widget.onJsEvent([message.message]);
        },
      )
      ..setOnConsoleMessage((message) {
        final text = message.message;
        final idx = text.indexOf('QYEVT:');
        if (idx >= 0) {
          widget.onJsEvent([text.substring(idx + 6)]);
        } else if (text.startsWith('QYERR:')) {
          widget.onDiag('[${widget.slot.id}] ${text.substring(6)}');
        } else if (text.isNotEmpty) {
          widget.onDiag('[${widget.slot.id}] js: $text');
        }
      })
      ..loadFlutterAsset(widget.pageUri.path);
    widget.slot.bridge = ReaderBridge(_controller);
  }

  @override
  Widget build(BuildContext context) {
    // Android 用 HC（Hybrid Composition）：WebView 作为真实 Android 子视图
    // 实时接收原生触摸——长按选字（原生选区 + 选择手柄）是 M2 标注的硬前提；
    // TLHC 的触摸为竞技场裁决后批量转发，WebView 收到时已错过自身长按判定，
    // 文本选择永远无法触发（实测）。代价是 Flutter 收不到任何触摸：滑动
    // 翻页下沉到 reader.html JS 检测（swipe 事件），点击经 click 兜底上报。
    if (defaultTargetPlatform == TargetPlatform.android) {
      return WebViewWidget.fromPlatformCreationParams(
        params: AndroidWebViewWidgetCreationParams(
          controller: _controller.platform,
          displayWithHybridComposition: true,
        ),
      );
    }
    return WebViewWidget(controller: _controller);
  }
}

/// 顶部栏：返回 / 书名 / 搜索 / 书签 / 更多。
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.state,
    required this.theme,
    required this.bookmarked,
    required this.onBack,
    required this.onToggleBookmark,
    required this.onSearch,
    required this.onExport,
    required this.onDiag,
  });

  final ReaderState state;
  final ReadingTheme theme;
  final bool bookmarked;
  final VoidCallback onBack;
  final VoidCallback onToggleBookmark;
  final VoidCallback onSearch;
  final VoidCallback onExport;
  final VoidCallback onDiag;

  @override
  Widget build(BuildContext context) {
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
                IconButton(
                  tooltip: '全书搜索',
                  onPressed: onSearch,
                  icon: Icon(Icons.search, color: theme.chromeForeground),
                ),
                IconButton(
                  tooltip: bookmarked ? '移除书签' : '添加书签',
                  onPressed: onToggleBookmark,
                  icon: Icon(
                    bookmarked ? Icons.bookmark : Icons.bookmark_border,
                    color: bookmarked ? theme.accent : theme.chromeForeground,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '更多',
                  icon: Icon(Icons.more_horiz, color: theme.chromeForeground),
                  onSelected: (v) {
                    if (v == 'export') onExport();
                    if (v == 'diag') onDiag();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'export', child: Text('导出标注')),
                    PopupMenuItem(value: 'diag', child: Text('诊断信息')),
                  ],
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部栏：进度条 + 目录 / 进度 / 排版 / 朗读（主题入口在排版面板首个页签）。
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.state,
    required this.theme,
    required this.progressValue,
    required this.progressLabel,
    required this.ttsActive,
    required this.onToc,
    required this.onJump,
    required this.onTypesetting,
    required this.onTts,
    required this.onSeek,
  });

  final ReaderState state;
  final ReadingTheme theme;

  /// 进度条当前值（0..1，按设置是全书或本章）。
  final double progressValue;

  /// 进度条左侧文案。
  final String progressLabel;

  /// 是否正在朗读（图标高亮）。
  final bool ttsActive;
  final VoidCallback onToc;
  final VoidCallback onJump;
  final VoidCallback onTypesetting;
  final VoidCallback onTts;
  final void Function(double percent) onSeek;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: theme.chromeSurface,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  children: [
                    Text(
                      progressLabel,
                      style: TextStyle(
                        color: theme.chromeForeground.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: progressValue.clamp(0.0, 1.0),
                        // 原生模式没有 epub.js 的 locationsReady 事件，
                        // 之前这里恒为 null → 进度条一直是禁用状态（点了没反应）。
                        onChanged: onSeek,
                        activeColor: theme.accent,
                      ),
                    ),
                    Text(
                      '${state.chapterPage}/${state.chapterPages}',
                      style: TextStyle(
                        color: theme.chromeForeground.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 52,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _BarItem(
                      icon: Icons.menu_book_outlined,
                      label: '目录',
                      theme: theme,
                      onTap: onToc,
                    ),
                    _BarItem(
                      icon: Icons.linear_scale,
                      label: '进度',
                      theme: theme,
                      onTap: onJump,
                    ),
                    _BarItem(
                      icon: Icons.tune,
                      label: '排版',
                      theme: theme,
                      onTap: onTypesetting,
                    ),
                    _BarItem(
                      icon: Icons.headphones,
                      label: '朗读',
                      theme: theme,
                      onTap: onTts,
                      active: ttsActive,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.icon,
    required this.label,
    required this.theme,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final ReadingTheme theme;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? theme.accent : theme.chromeForeground;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(
        width: 60,
        height: 48,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}

/// 右下角页码：章内 12 / 34（等宽数字），点击打开跳页面板。
class _PageNumber extends StatelessWidget {
  const _PageNumber({
    required this.page,
    required this.pages,
    required this.bookPage,
    required this.bookPages,
    required this.theme,
    required this.onTap,
  });

  final int page;
  final int pages;
  final int bookPage;
  final int bookPages;
  final ReadingTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (page <= 0 || pages <= 0) return const SizedBox.shrink();
    final fg = theme.chromeForeground.withValues(alpha: 0.55);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: Text(
            bookPages > 0
                ? '$page / $pages · 约 $bookPage / $bookPages'
                : '$page / $pages',
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

/// 全书「读完」卡片。
class _EndCard extends StatelessWidget {
  const _EndCard({
    required this.theme,
    required this.onRestart,
    required this.onBack,
  });

  final ReadingTheme theme;
  final VoidCallback onRestart;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.chromeSurface,
      elevation: 4,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: theme.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '全书读完',
                style: TextStyle(
                  color: theme.chromeForeground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: onRestart,
              child: Text(
                '从头再读',
                style: TextStyle(color: theme.chromeForeground),
              ),
            ),
            TextButton(
              onPressed: onBack,
              child: Text(
                '书架',
                style: TextStyle(color: theme.chromeForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 边缘手势指示（亮度百分比 / 字号）。
class _EdgeHud extends StatelessWidget {
  const _EdgeHud({
    required this.theme,
    required this.brightness,
    required this.value,
  });

  final ReadingTheme theme;
  final bool brightness;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 124,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            brightness ? Icons.brightness_6 : Icons.format_size,
            color: Colors.white,
            size: 26,
          ),
          const SizedBox(height: 8),
          Text(
            brightness ? '${(value * 100).round()}%' : value.round().toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            brightness ? '亮度' : '字号',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// 首次进入阅读器的操作引导。
class _ReaderGuide extends StatelessWidget {
  const _ReaderGuide({required this.theme, required this.onDismiss});

  final ReadingTheme theme;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.8),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '阅读操作',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 22),
              const _GuideRow(icon: Icons.touch_app, text: '轻点屏幕中间呼出 / 收起菜单'),
              const _GuideRow(icon: Icons.swipe, text: '左右滑动翻页，可连续快速滑动'),
              const _GuideRow(icon: Icons.brightness_6, text: '左边缘上下滑动调亮度'),
              const _GuideRow(icon: Icons.format_size, text: '右边缘上下滑动调字号'),
              const _GuideRow(
                icon: Icons.format_list_numbered,
                text: '点右下角页码跳转章节 / 全书位置',
              ),
              const _GuideRow(icon: Icons.edit_note, text: '长按正文选字，做划线 / 笔记'),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: onDismiss,
                child: const Text('开始阅读'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// 目标页未就绪时的同尺寸骨架（文字行占位，不闪白）。
class _PageSkeleton extends StatelessWidget {
  const _PageSkeleton({required this.theme});

  final ReadingTheme theme;

  @override
  Widget build(BuildContext context) {
    final color = theme.foreground.withValues(alpha: 0.07);
    const widths = <double>[
      0.92,
      0.86,
      0.95,
      0.78,
      0.90,
      0.88,
      0.93,
      0.82,
      0.90,
      0.62,
    ];
    return ColoredBox(
      color: theme.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final w in widths)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: FractionallySizedBox(
                  widthFactor: w,
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

