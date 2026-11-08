/// 阅读会话跟踪：计时 + 字数估算，退出/切后台时落库。
///
/// 统计口径（M5 定义）：
/// - 会话 = 阅读器页面处于前台的一段连续时间；切后台/离开立即结算。
/// - 字数 = 期间 relocated 的 percent 正增量 × 全书字数（负向翻回不计），
///   单次增量上限 5%（避免异常跳转放大）。
/// - 短于 10 秒或零增量的会话由仓储侧丢弃。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../domain/repositories/stats_repository.dart';

/// 阅读会话跟踪器。
class ReadingSessionTracker with WidgetsBindingObserver {
  /// 构造。
  ReadingSessionTracker({
    required this.repository,
    required this.bookId,
    required this.wordCount,
  });

  /// 统计仓储。
  final StatsRepository repository;

  /// 书籍 id。
  final String bookId;

  /// 全书字数（估算）。
  final int wordCount;

  DateTime? _startedAt;
  double? _lastPercent;
  int _charsAccum = 0;
  bool _bound = false;

  /// 开始/恢复计时（进入阅读器或回到前台）。
  void start() {
    if (_startedAt != null) return;
    _startedAt = DateTime.now();
    if (!_bound) {
      WidgetsBinding.instance.addObserver(this);
      _bound = true;
    }
  }

  /// 记录一次位置变化（relocated）用于字数估算。
  /// [position] 优先传 Locator.pos（页级精度），无则退回 percent。
  void onPercent(double? position) {
    if (position == null) return;
    final last = _lastPercent;
    _lastPercent = position;
    if (last == null) return;
    final delta = position - last;
    if (delta <= 0) return;
    final capped = delta > 0.05 ? 0.05 : delta;
    _charsAccum += (capped * wordCount).round();
  }

  /// 结算当前会话并写入统计（幂等：结算后计时清零）。
  Future<void> flush() async {
    final started = _startedAt;
    if (started == null) return;
    _startedAt = null;
    final endedAt = DateTime.now();
    final chars = _charsAccum;
    _charsAccum = 0;
    _lastPercent = null;
    await repository.recordSession(
      bookId: bookId,
      startedAt: started.millisecondsSinceEpoch,
      endedAt: endedAt.millisecondsSinceEpoch,
      charsRead: chars,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切后台立即结算（避免把后台时间算进阅读时长）；回前台重新起算
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(flush());
    } else if (state == AppLifecycleState.resumed) {
      start();
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
