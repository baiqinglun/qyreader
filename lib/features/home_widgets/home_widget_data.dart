/// 桌面组件的数据快照。
///
/// 组件运行在 launcher 进程里，读不到 Flutter 的数据库；App 每次有数据变化
/// 就把一份小型 JSON 快照推给原生侧（`qyreader/home_widgets` 通道），原生
/// 存进 SharedPreferences 后用 RemoteViews 渲染。这里只做纯数据整理，
/// 方便单测。
library;

import 'dart:convert';

import '../../domain/entities/book.dart';
import '../../domain/entities/reading_stats.dart';

/// 组件里展示的一本书（最近阅读 / 书架组件共用）。
class HomeWidgetBookData {
  /// 构造。
  const HomeWidgetBookData({
    required this.id,
    required this.title,
    required this.author,
    required this.coverPath,
    required this.percent,
  });

  /// 书籍 id（点组件打开阅读页用）。
  final String id;

  /// 书名。
  final String title;

  /// 作者（可能为空，原生侧回退「未知作者」）。
  final String author;

  /// 封面在本机的绝对路径；没有封面为 null。
  final String? coverPath;

  /// 阅读进度 0..1。
  final double percent;

  /// 转 JSON（原生侧按 key 读）。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'author': author,
    if (coverPath != null) 'coverPath': coverPath,
    'percent': percent,
  };
}

/// 今日阅读组件的数据。
class HomeWidgetTodayData {
  /// 构造。
  const HomeWidgetTodayData({
    required this.durationMs,
    required this.goalMinutes,
    required this.progress,
  });

  /// 今日阅读时长（ms）。
  final int durationMs;

  /// 每日目标（分钟；0 = 未设目标）。
  final int goalMinutes;

  /// 目标完成比例 0..1。
  final double progress;

  /// 转 JSON。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'durationMs': durationMs,
    'goalMinutes': goalMinutes,
    'progress': progress,
  };
}

/// 推给原生的完整快照。
class HomeWidgetData {
  /// 构造。
  const HomeWidgetData({
    required this.date,
    required this.updatedAt,
    required this.recentBook,
    required this.today,
    required this.shelf,
  });

  /// 快照本地日期（`yyyy-MM-dd`）：原生侧发现不是今天就把今日时长归零。
  final String date;

  /// 快照生成时间（epoch ms）。
  final int updatedAt;

  /// 最近阅读的一本书；没有阅读记录时为 null。
  final HomeWidgetBookData? recentBook;

  /// 今日阅读数据。
  final HomeWidgetTodayData today;

  /// 书架组件展示的书（最多 3 本，最近读的在前）。
  final List<HomeWidgetBookData> shelf;

  /// 转 JSON。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': 1,
    'date': date,
    'updatedAt': updatedAt,
    'recentBook': recentBook?.toJson(),
    'today': today.toJson(),
    'shelf': <Map<String, dynamic>>[for (final book in shelf) book.toJson()],
  };
}

/// 从书架条目 + 统计总览生成组件快照。
///
/// - 最近阅读：打开过的书里 `lastOpenedAt` 最大的一本；
/// - 书架组件：最近打开的前 3 本，不足 3 本时用书架里其余的书补齐；
/// - 今日：时长 / 每日目标 / 完成比例，日期用于跨零点归零。
HomeWidgetData buildHomeWidgetData({
  required List<ShelfItem> items,
  required ReadingStats stats,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final opened = <ShelfItem>[
    for (final item in items)
      if (item.book.lastOpenedAt != null) item,
  ]..sort((a, b) => b.book.lastOpenedAt!.compareTo(a.book.lastOpenedAt!));

  final shelf = <ShelfItem>[...opened.take(3)];
  if (shelf.length < 3) {
    final seen = <String>{for (final item in shelf) item.book.id};
    for (final item in items) {
      if (shelf.length >= 3) break;
      if (seen.add(item.book.id)) shelf.add(item);
    }
  }

  final goal = stats.dailyGoalMinutes;
  final progress = goal <= 0
      ? 0.0
      : (stats.todayDurationMs / 60000 / goal).clamp(0.0, 1.0).toDouble();

  return HomeWidgetData(
    date: _dateKey(current),
    updatedAt: current.millisecondsSinceEpoch,
    recentBook: opened.isEmpty ? null : _bookData(opened.first),
    today: HomeWidgetTodayData(
      durationMs: stats.todayDurationMs < 0 ? 0 : stats.todayDurationMs,
      goalMinutes: goal < 0 ? 0 : goal,
      progress: progress,
    ),
    shelf: <HomeWidgetBookData>[for (final item in shelf) _bookData(item)],
  );
}

/// 序列化成 MethodChannel 传输的 JSON 字符串。
String homeWidgetJson(HomeWidgetData data) => jsonEncode(data.toJson());

HomeWidgetBookData _bookData(ShelfItem item) {
  final title = item.book.title.trim();
  return HomeWidgetBookData(
    id: item.book.id,
    title: title.isEmpty ? '未命名' : title,
    author: item.book.author?.trim() ?? '',
    coverPath: item.book.coverPath,
    percent: item.percent.clamp(0.0, 1.0).toDouble(),
  );
}

String _dateKey(DateTime now) {
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '${now.year.toString().padLeft(4, '0')}-$month-$day';
}
