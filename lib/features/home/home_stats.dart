/// 首页的数据整理（纯函数，可单测）。
///
/// 首页不新开数据表：继续阅读 / 今年读完都从书架条目派生，时长来自
/// `StatsRepository.overview()`。
library;

import '../../domain/entities/book.dart';

/// 「继续阅读」：打开过、还没读完的书，按最近打开时间倒序。
///
/// 已读 / 弃读的不算「继续」；置顶在这里不参与排序（置顶是书架的排序
/// 规则，首页只关心最近在读哪本）。
List<ShelfItem> continueReadingItems(List<ShelfItem> items) {
  final list = <ShelfItem>[
    for (final item in items)
      if (_isInProgress(item)) item,
  ]..sort(
      (a, b) => (b.book.lastOpenedAt ?? 0).compareTo(
        a.book.lastOpenedAt ?? 0,
      ),
    );
  return list;
}

bool _isInProgress(ShelfItem item) {
  final book = item.book;
  if (book.lastOpenedAt == null) return false;
  if (book.readStatus == BookReadStatus.finished) return false;
  if (book.readStatus == BookReadStatus.dropped) return false;
  return item.percent < 0.999;
}

/// 已读完的书（阅读状态为已读，或进度已满）。
List<ShelfItem> finishedBooks(List<ShelfItem> items) => [
      for (final item in items)
        if (_isFinished(item)) item,
    ];

bool _isFinished(ShelfItem item) =>
    item.book.readStatus == BookReadStatus.finished || item.percent >= 0.999;

/// 今年读完的书：已读且读完时间落在今年，按读完时间倒序。
///
/// 优先用专门的读完时间戳 `finishedAt`（v2.59.4 起，微信读书导入的书
/// 带真实读完时间，往往是往年——`updatedAt` 只是本机最近一次改动时间，
/// 同步 / 编辑都会刷新它，不能用来判断年份）；旧数据没有 `finishedAt`
/// 时退回 `updatedAt` 近似（改状态那天的更新时间）。
///
/// [now] 可注入，方便测试跨年边界。
List<ShelfItem> finishedThisYear(List<ShelfItem> items, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final start = DateTime(current.year).millisecondsSinceEpoch;
  final end = DateTime(current.year + 1).millisecondsSinceEpoch;
  int finishedMs(ShelfItem item) =>
      item.book.finishedAt ?? item.book.updatedAt;
  final list = <ShelfItem>[
    for (final item in finishedBooks(items))
      if (finishedMs(item) >= start && finishedMs(item) < end) item,
  ]..sort((a, b) => finishedMs(b).compareTo(finishedMs(a)));
  return list;
}

/// 时长文案：`500 小时 38 分钟` / `38 分钟` / `12 秒`。
String formatTotalReadingDuration(int ms) {
  final safe = ms < 0 ? 0 : ms;
  final hours = safe ~/ 3600000;
  final minutes = (safe % 3600000) ~/ 60000;
  if (hours > 0) return '$hours 小时 $minutes 分钟';
  if (minutes > 0) return '$minutes 分钟';
  return '${(safe % 60000) ~/ 1000} 秒';
}

/// 今日计时文案：不到 1 小时是 `分:秒`（如 `2:13`），超过是 `时:分:秒`。
String formatReadingClock(int ms) {
  final totalSeconds = (ms < 0 ? 0 : ms) ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}

/// 百分比文案：`7.18%`（保留两位，整数时省略小数）。
String formatPercent(double percent) {
  final value = (percent.clamp(0.0, 1.0)) * 100;
  if (value >= 100) return '100%';
  final fixed = value.toStringAsFixed(2);
  final trimmed = fixed
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  return '$trimmed%';
}
