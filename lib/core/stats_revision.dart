/// 统计数据修订号：reading_sessions / daily_stats 有写入时 +1。
///
/// 首页 / 统计页监听它：可见时立即重拉数据（刚读完书回到首页数字马上
/// 跟上，不依赖路由时序；同步合并远端会话也会触发）。
library;

import 'package:flutter/foundation.dart';

/// 统计数据修订号（每次统计相关写入 +1）。
final ValueNotifier<int> statsRevision = ValueNotifier<int>(0);

/// 统计有写入（会话落库 / 合并重算）后调用，通知可见页面重拉。
void bumpStatsRevision() => statsRevision.value++;
