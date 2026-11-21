/// 首页偏好：年度阅读目标（册数）。
///
/// 只落 shared_preferences，不进库、不参与同步——和书架设置一样属于
/// 本机展示偏好。每日目标仍走 `StatsRepository`（统计页共用）。
library;

import 'package:shared_preferences/shared_preferences.dart';

/// 首页偏好读写。
class HomePrefs {
  HomePrefs._();

  /// 年度阅读目标（册）的 prefs key。
  static const String yearlyGoalKey = 'home.yearlyGoalBooks';

  /// 首页卡片默认顺序。
  static const List<String> defaultCards = [
    'overview',
    'continue',
    'recommendations',
    'today',
    'year',
  ];
  static const String cardsKey = 'home.cards.order';
  static const String hiddenCardsKey = 'home.cards.hidden';

  /// 默认年度目标（册）。
  static const int defaultYearlyGoal = 24;

  /// 读取年度目标；未设置时返回 [defaultYearlyGoal]，越界值夹回 1..999。
  static Future<int> loadYearlyGoal() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(yearlyGoalKey) ?? defaultYearlyGoal;
    return value.clamp(1, 999);
  }

  /// 写入年度目标（夹在 1..999）。
  static Future<void> saveYearlyGoal(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(yearlyGoalKey, value.clamp(1, 999));
  }
}
