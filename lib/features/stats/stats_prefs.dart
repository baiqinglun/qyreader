/// 统计设置（只落 shared_preferences，不进库、不同步）：
/// 单页最长计时——在一页停留超过上限的部分不计入统计，
/// 防止开着书离开/睡着把时长灌爆。
library;

import 'package:shared_preferences/shared_preferences.dart';

/// prefs key：单页最长计时（分钟）。
const String kPageCapPrefsKey = 'stats.pageCapMinutes';

/// 默认单页最长计时（分钟）。正常翻页远短于此，超过基本是忘了关书。
const int kDefaultPageCapMinutes = 10;

/// 单页最长计时选项（分钟；0 = 不限制）。
const List<int> kPageCapOptions = <int>[0, 1, 2, 3, 5, 10, 15, 20, 30];

/// 读单页最长计时（分钟；0 = 不限制）。
Future<int> loadPageCapMinutes() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(kPageCapPrefsKey) ?? kDefaultPageCapMinutes;
}

/// 写单页最长计时（分钟；0 = 不限制）。
Future<void> savePageCapMinutes(int minutes) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(kPageCapPrefsKey, minutes);
}

/// 文案：0 显示「不限制」，其余「N 分钟」。
String pageCapLabel(int minutes) =>
    minutes <= 0 ? '不限制' : '$minutes 分钟';
