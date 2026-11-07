/// 阅读进度仓储实现：drift 持久化 + sync_ops 同事务追加。
library;

import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/hlc.dart';
import '../../domain/entities/reading_progress.dart';
import '../../domain/repositories/progress_repository.dart';

/// 生产实现。合并规则：locator LWW；furthest 取 max 永不回退。
class ProgressRepositoryImpl implements ProgressRepository {
  /// 构造：注入数据库、HLC 时钟与设备 id。
  ProgressRepositoryImpl({
    required AppDatabase db,
    required HlcClock hlcClock,
    required this.deviceId,
  })  : _db = db,
        _hlcClock = hlcClock,
        _uuid = const Uuid();

  final AppDatabase _db;
  final HlcClock _hlcClock;
  final String deviceId;
  final Uuid _uuid;

  @override
  Future<ReadingProgressSnapshot?> getProgress(String bookId) async {
    final row = await _db.progressDao.getForBook(bookId);
    if (row == null) return null;
    return ReadingProgressSnapshot(
      bookId: row.bookId,
      locator: row.locator,
      percent: row.percent,
      furthestLocator: row.furthestLocator,
      furthestPercent: row.furthestPercent,
      updatedAt: row.updatedAt,
    );
  }

  @override
  Future<void> saveProgress({
    required String bookId,
    required String locator,
    required double percent,
  }) async {
    final existing = await _db.progressDao.getForBook(bookId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = _hlcClock.tick();

    // 最远进度：max(percent) 永不回退
    final double furthestPercent;
    final String furthestLocator;
    if (existing == null || percent > existing.furthestPercent) {
      furthestPercent = percent;
      furthestLocator = locator;
    } else {
      furthestPercent = existing.furthestPercent;
      furthestLocator = existing.furthestLocator ?? existing.locator;
    }

    await _db.transaction(() async {
      await _db.progressDao.upsert(ReadingProgressRow(
        bookId: bookId,
        locator: locator,
        percent: percent,
        furthestLocator: furthestLocator,
        furthestPercent: furthestPercent,
        updatedAt: now,
        hlc: hlc.encode(),
        deviceId: deviceId,
      ));
      await _db.into(_db.syncOps).insert(
            SyncOpsCompanion.insert(
              opId: _uuid.v4(),
              entity: 'progress',
              entityId: bookId,
              op: 'upsert',
              payload: jsonEncode(<String, dynamic>{
                'bookId': bookId,
                'locator': locator,
                'percent': percent,
                'furthestLocator': furthestLocator,
                'furthestPercent': furthestPercent,
                'hlc': hlc.encode(),
                'deviceId': deviceId,
              }),
              hlc: hlc.encode(),
              createdAt: now,
            ),
          );
    });
  }
}
