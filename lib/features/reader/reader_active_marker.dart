/// 记录「当前正在阅读的书」的轻量标记。
///
/// 用途：Android 厂商 ROM 常在退后台后杀掉进程（Activity 一并销毁，
/// Flutter 状态全丢）。回前台时应用冷启动到书架，用户得重新点开书——
/// 这个标记让应用在冷启动时自动回到上次的阅读页。阅读页 initState 时
/// 写入、dispose 时清除：主动退出阅读器不会误恢复。
library;

import 'package:shared_preferences/shared_preferences.dart';

const String _kKey = 'reader.activeBook';

/// 进程内同步副本：阅读页 initState 里立刻可查，不用等 prefs 写入完成
/// （切后台再点桌面图标时可能只差这一拍）。
String? _activeInMemory;

// 串行化读写，避免「initState 的写入」与「dispose 的清除」乱序残留。
Future<void> _chain(Future<void> Function(SharedPreferences prefs) op) async {
  final prefs = await SharedPreferences.getInstance();
  await op(prefs);
}

/// 标记某本书正在阅读。
Future<void> markReaderActive(String bookId) {
  _activeInMemory = bookId;
  return _chain((prefs) async {
    await prefs.setString(_kKey, bookId);
  });
}

/// 清除标记（退出阅读器时）。
Future<void> clearReaderActive() {
  _activeInMemory = null;
  return _chain((prefs) async {
    await prefs.remove(_kKey);
  });
}

/// 正在阅读的书（同步；只在阅读页存活期间有效）。
String? activeReaderBookSync() => _activeInMemory;

/// 当前正在阅读的书（没有则 null）。
Future<String?> activeReaderBook() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kKey);
}
