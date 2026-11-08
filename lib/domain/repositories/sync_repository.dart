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
  Future<SyncResult> syncNow();
}
