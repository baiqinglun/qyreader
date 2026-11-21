/// 阅读进度仓储实现：drift 持久化 + sync_ops 同事务追加。
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/hlc.dart';
import '../../core/locator.dart';
import '../../domain/entities/reading_progress.dart';
import '../../domain/repositories/progress_repository.dart';

/// 生产实现。合并规则：locator LWW；furthest 取 max 永不回退。
class ProgressRepositoryImpl implements ProgressRepository {
  /// 构造：注入数据库、HLC 时钟与设备 id。
  ProgressRepositoryImpl({
    required AppDatabase db,
    required HlcClock hlcClock,
    required this.deviceId,
  }) : _db = db,
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

  /// 百分比 → 章索引 + 章内偏移。
  ///
  /// 章节按 [idx] 升序；按各章 `charCount` 占比找落点。没有章节字数时
  /// 返回 null（调用方写一个只有 percent 的兜底 locator）。
  static ({int chapterIndex, int offset, String href})? positionForPercent(
    List<({int charCount, String href})> chapters,
    double percent,
  ) {
    if (chapters.isEmpty) return null;
    final total = chapters.fold<int>(
      0,
      (sum, chapter) => sum + math.max(0, chapter.charCount),
    );
    if (total <= 0) {
      // 旧书/同步书的 char_count 可能还没回填；至少按章节数落到大致的章，
      // 不要永远停在第一章。
      final index = (percent.clamp(0.0, 1.0) * chapters.length).floor().clamp(
        0,
        chapters.length - 1,
      );
      return (chapterIndex: index, offset: 0, href: chapters[index].href);
    }
    final target = ((percent.clamp(0.0, 1.0)) * total).round();
    var before = 0;
    for (var i = 0; i < chapters.length; i++) {
      final length = math.max(0, chapters[i].charCount);
      final isLast = i == chapters.length - 1;
      if (target < before + length || isLast) {
        final offset = (target - before).clamp(0, length);
        return (chapterIndex: i, offset: offset, href: chapters[i].href);
      }
      before += length;
    }
    return (
      chapterIndex: chapters.length - 1,
      offset: chapters.last.charCount,
      href: chapters.last.href,
    );
  }

  @override
  Future<void> saveExternalProgress({
    required String bookId,
    required double percent,
  }) async {
    final clamped = percent.clamp(0.0, 1.0).toDouble();
    final rows = await (_db.select(
      _db.chapters,
    )..where((chapter) => chapter.bookId.equals(bookId))).get();
    rows.sort((a, b) => a.idx.compareTo(b.idx));
    final position = positionForPercent(<({int charCount, String href})>[
      for (final row in rows) (charCount: row.charCount, href: row.href),
    ], clamped);
    final locator = position == null
        ? Locator(percent: clamped, pos: clamped)
        : Locator(
            href: position.href,
            chapterIndex: position.chapterIndex,
            offset: position.offset,
            percent: clamped,
            pos: clamped,
          );
    await saveProgress(
      bookId: bookId,
      locator: locatorToJson(locator),
      percent: clamped,
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
      await _db.progressDao.upsert(
        ReadingProgressRow(
          bookId: bookId,
          locator: locator,
          percent: percent,
          furthestLocator: furthestLocator,
          furthestPercent: furthestPercent,
          updatedAt: now,
          hlc: hlc.encode(),
          deviceId: deviceId,
        ),
      );
      await _db
          .into(_db.syncOps)
          .insert(
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
