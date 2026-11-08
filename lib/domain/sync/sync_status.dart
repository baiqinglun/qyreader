/// 同步状态与结果（纯数据，页面层展示用）。
library;

/// 同步状态快照。
class SyncStatus {
  const SyncStatus({
    this.pendingOps = 0,
    this.lastSyncAt,
    this.lastError,
    this.running = false,
    this.deviceId = '',
    this.spaceId = '',
  });

  /// 待上传操作数。
  final int pendingOps;

  /// 上次成功同步时间；null = 从未同步。
  final DateTime? lastSyncAt;

  /// 上次失败原因；null = 无错误。
  final String? lastError;

  /// 是否同步中。
  final bool running;

  /// 本机设备 id（展示「本设备」标识）。
  final String deviceId;

  /// 同步空间 id（多设备共享同一空间即互相同步）。
  final String spaceId;

  /// 拷贝。
  SyncStatus copyWith({
    int? pendingOps,
    Object? lastSyncAt = _sentinel,
    Object? lastError = _sentinel,
    bool? running,
    String? deviceId,
    String? spaceId,
  }) =>
      SyncStatus(
        pendingOps: pendingOps ?? this.pendingOps,
        lastSyncAt: lastSyncAt == _sentinel
            ? this.lastSyncAt
            : lastSyncAt as DateTime?,
        lastError:
            lastError == _sentinel ? this.lastError : lastError as String?,
        running: running ?? this.running,
        deviceId: deviceId ?? this.deviceId,
        spaceId: spaceId ?? this.spaceId,
      );

  static const Object _sentinel = Object();
}

/// 一次同步的结果。
class SyncResult {
  const SyncResult({
    this.pushed = 0,
    this.pulled = 0,
    this.applied = 0,
    this.skipped = 0,
    this.error,
  });

  /// 上传的操作数。
  final int pushed;

  /// 拉取到的远端操作数（含已被本地跳过的）。
  final int pulled;

  /// 实际合并进本地库的操作数。
  final int applied;

  /// 因已存在而跳过的操作数（幂等去重）。
  final int skipped;

  /// 失败原因；null = 成功。
  final String? error;

  /// 是否成功。
  bool get ok => error == null;
}
