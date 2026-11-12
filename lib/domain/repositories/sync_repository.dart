/// 同步仓储接口（领域层）。
///
/// 同步 = 操作日志复制：本地 sync_ops 上传为对象，拉取远端对象后按实体
/// 规则合并（LWW / max），拉到的操作也写入 sync_ops（opId 幂等去重）。
library;

import '../sync/sync_status.dart';

/// 同步仓储。
abstract interface class SyncRepository {
  /// 查询当前状态。
  Future<SyncStatus> status();

  /// 执行一次同步（推送待上传 → 拉取并合并）。
  ///
  /// 不抛异常：失败信息放在 [SyncResult.error]。
  /// 立即同步；[onProgress] 用于界面进度条。
  Future<SyncResult> syncNow({void Function(SyncProgress progress)? onProgress});

  /// 待上传分片的书（界面展示「哪些文件要同步」）。
  Future<List<String>> pendingShardBooks();

  /// 书源文件是否已在同步库有备份（内容寻址 blob）。
  Future<bool> isBookBackedUp(String bookId);

  /// 立即把书源文件上传到同步库（清除本地缓存前调用）。
  ///
  /// 已有备份则跳过；返回上传是否成功（书存在且本地文件可读）。
  Future<bool> uploadBookBlobNow(String bookId);

  /// 清除某本书的本地缓存（只删书源文件）。
  ///
  /// 云端书籍、封面、分片，以及本地的封面和数据库记录都保留；下次打开书
  /// 会从同步库自动拉回。清除前会确保云端已有备份；没有备份/同步不可用
  /// 时返回 false，不删本地文件（避免不可恢复）。
  Future<bool> clearLocalBookCache(String bookId);

  /// 删除云端的一本书：书源、封面与按书分片（删除书籍时调用）。
  ///
  /// 未配置同步或网络失败时静默返回；云端清理也会在下次同步推送墓碑时重试。
  Future<void> deleteCloudBook(String bookId, {String? fileSha256});

  /// 确保书源文件在本地：缺失时从同步库拉回（清除缓存后再次阅读）。
  ///
  /// 返回文件最终是否可用；拉回静默进行，失败不抛异常。
  Future<bool> ensureBookFileLocal(String bookId);
}
