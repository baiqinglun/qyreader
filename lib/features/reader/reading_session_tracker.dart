/// 阅读会话跟踪：计时 + 字数估算，退出/切后台时落库。
///
/// 统计口径（M5 定义）：
/// - 会话 = 阅读器页面处于前台的一段连续时间；切后台/离开立即结算。
/// - 字数 = 期间 relocated 的 percent 正增量 × 全书字数（负向翻回不计），
///   单次增量上限 5%（避免异常跳转放大）。
/// - 短于 10 秒或零增量的会话由仓储侧丢弃。
/// - **单页最长计时（v2.48.0）**：一页上停留的时间按
///   [pageCapMinutes] 封顶（0 = 不限制），超出部分不计——
///   开着书离开/睡着不会把时长灌爆。两次 relocated 之间算「在一页上」，
///   会话内计入时长 = 每页停留 min(实际, 上限) 之和。
/// - **何时计时（v2.48.1）**：阅读页在最上层（前台）或在听书播放中才算；
///   被其它路由盖住且没在听书、切后台且没在听书 → 不计时。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../domain/repositories/stats_repository.dart';

/// 阅读会话跟踪器。
class ReadingSessionTracker with WidgetsBindingObserver {
  /// 构造。
  ///
  /// [pageCapMinutes]：单页最长计时（分钟，0 = 不限制）；
  /// [isListening]：听书是否在播放——**播放中 = 在读**，阅读页被盖住 /
  /// App 切后台都继续计时（null = 没在听书）；
  /// [isCovered]：阅读页当前是否被其它路由盖住（盖住且没在听书 → 不计时）；
  /// [now]：时钟注入（测试用，默认真实时钟）。
  ReadingSessionTracker({
    required this.repository,
    required this.bookId,
    required this.wordCount,
    this.pageCapMinutes = 0,
    bool Function()? isListening,
    bool Function()? isCovered,
    DateTime Function()? now,
  }) : _isListening = isListening,
       _isCovered = isCovered,
       _nowFn = now;

  /// 统计仓储。
  final StatsRepository repository;

  /// 书籍 id。
  final String bookId;

  /// 全书字数（估算）。
  final int wordCount;

  /// 单页最长计时（分钟；0 = 不限制）。
  final int pageCapMinutes;

  final bool Function()? _isListening;
  final bool Function()? _isCovered;

  final DateTime Function()? _nowFn;
  DateTime _now() => _nowFn?.call() ?? DateTime.now();

  DateTime? _startedAt;

  /// 当前页开始计时的时刻（进入会话或最近一次位置变化）。
  DateTime? _lastPageAt;
  double? _lastPercent;
  int _charsAccum = 0;

  /// 本会话已计入的时长（每页封顶后累加；落库时随会话写入）。
  int _countedMs = 0;
  bool _bound = false;

  /// 开始/恢复计时（进入阅读器或回到前台）。
  void start() {
    if (_startedAt != null) return;
    final now = _now();
    _startedAt = now;
    _lastPageAt = now;
    if (!_bound) {
      WidgetsBinding.instance.addObserver(this);
      _bound = true;
    }
  }

  /// 记录一次位置变化（relocated）用于字数估算与单页计时。
  /// [position] 优先传 Locator.pos（页级精度），无则退回 percent。
  void onPercent(double? position) {
    if (position == null) return;
    final last = _lastPercent;
    _lastPercent = position;
    // 页没变（同页内多次回报）不算新的一页；其余（含首次回报）把
    // 上一页的停留时间封顶计入。
    final samePage = last != null && last == position;
    if (!samePage) _countPageStint(_now());
    if (last == null) return;
    final delta = position - last;
    if (delta <= 0) return;
    final capped = delta > 0.05 ? 0.05 : delta;
    _charsAccum += (capped * wordCount).round();
  }

  /// 把当前页的停留时间封顶计入，并从 [to] 起算下一页。
  void _countPageStint(DateTime to) {
    final since = _lastPageAt;
    _lastPageAt = to;
    if (since == null) return;
    var stint = to.difference(since).inMilliseconds;
    if (stint <= 0) return;
    if (pageCapMinutes > 0) {
      final capMs = pageCapMinutes * 60000;
      if (stint > capMs) stint = capMs;
    }
    _countedMs += stint;
  }

  /// 结算当前会话并写入统计（幂等：结算后计时清零）。
  Future<void> flush() async {
    final started = _startedAt;
    if (started == null) return;
    _startedAt = null;
    final endedAt = _now();
    final chars = _charsAccum;
    _charsAccum = 0;
    _lastPercent = null;
    _countPageStint(endedAt);
    final counted = _countedMs;
    _countedMs = 0;
    await repository.recordSession(
      bookId: bookId,
      startedAt: started.millisecondsSinceEpoch,
      endedAt: endedAt.millisecondsSinceEpoch,
      charsRead: chars,
      countedDurationMs: counted,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 计时规则（v2.48.1）：阅读页在最上层（且前台）或在听书播放中 = 在读；
    // 其余（被盖住且没在听书、切后台没在听书）不计。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // 听书播放中：会话不结算，后台收听也计入（回来后接着算）
      if (_isListening?.call() ?? false) return;
      unawaited(flush());
    } else if (state == AppLifecycleState.resumed) {
      final covered = _isCovered?.call() ?? false;
      if (!covered || (_isListening?.call() ?? false)) start();
    }
  }

  /// 解绑（阅读器销毁时调用；先 flush 再 dispose）。
  void dispose() {
    if (_bound) {
      WidgetsBinding.instance.removeObserver(this);
      _bound = false;
    }
  }
}
