/// 阅读器启动前的书源恢复判断。
///
/// 打开一本书时，只有本地书源文件缺失（按需下载 / 清过缓存）才需要从同步库
/// 拉回。本地文件还在时**不能**走同步仓储：冷启动首次读取 OSS 配置 /
/// 安全存储可能很慢，会把「正在打开…」一直卡住（v2.20.2 修复）。
///
/// v2.33.0 起不再静默下载：先问用户「要不要从云端下载」，同意后才拉取。
library;

import 'dart:async';
import 'dart:io';

import '../../domain/entities/book.dart';

/// 书源文件是否已在本地。
Future<bool> isBookFileLocal(Book book) => File(book.filePath).exists();

/// 本地书源缺失时调用 [restoreFromCloud]；返回是否真的触发了恢复。
///
/// [syncTimeout] 是恢复整体上限：同步库初始化或网络卡住时，超时后让调用方
/// 继续启动（章节解析会给出「文件不存在」的错误，至少不会无限转圈）。
///
/// 需要「先确认再下载」的界面请直接用 [isBookFileLocal] 判断，不要调这个
/// 函数（它会立刻开始下载）。
Future<bool> restoreBookFileIfNeeded({
  required Future<Book?> Function() loadBook,
  required Future<void> Function() restoreFromCloud,
  Duration syncTimeout = const Duration(seconds: 20),
}) async {
  final book = await loadBook();
  if (book != null && await isBookFileLocal(book)) return false;
  await restoreFromCloud().timeout(syncTimeout);
  return true;
}
