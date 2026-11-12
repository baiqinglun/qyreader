/// 标注与书签仓储实现：drift 持久化 + sync_ops 同事务追加。
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/hlc.dart';
import '../../domain/entities/annotation.dart';
import '../../domain/entities/bookmark.dart';
import '../../domain/repositories/annotation_repository.dart';

/// 生产实现。删除一律软删（墓碑），增改同事务追加 sync_ops。
class AnnotationRepositoryImpl implements AnnotationRepository {
  /// 构造：注入数据库、HLC 时钟与设备 id。
  AnnotationRepositoryImpl({
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

  // ---- 标注 ----

  @override
  Future<List<Annotation>> listForBook(String bookId) async =>
      (await _db.annotationDao.listForBook(bookId)).map(_rowToEntity).toList();

  @override
  Stream<List<Annotation>> watchForBook(String bookId) =>
      _db.annotationDao.watchForBook(bookId).map(
            (rows) => rows.map(_rowToEntity).toList(),
          );

  @override
  Future<Annotation> addHighlight({
    required String bookId,
    required String cfiRange,
    required AnnotationColor color,
    required String quotedText,
    String? href,
    int? chapterIndex,
    int? offset,
    int? offsetEnd,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = _hlcClock.tick();
    // 选区范围 CFI 直接存入 locatorStart.cfi（epub.js annotations API
    // 消费的正是这个值）；locatorEnd v1 与起始相同，预留拆分。
    final locatorJson = jsonEncode(<String, dynamic>{
      'v': 1,
      if (href != null) 'href': href,
      if (cfiRange.isNotEmpty) 'cfi': cfiRange,
      if (chapterIndex != null) 'chapterIndex': chapterIndex,
      if (offset != null) 'offset': offset,
      if (offsetEnd != null) 'offsetEnd': offsetEnd,
    });
    await _db.transaction(() async {
      await _db.annotationDao.upsert(AnnotationRow(
        id: id,
        bookId: bookId,
        type: AnnotationType.highlight.token,
        color: color.token,
        locatorStart: locatorJson,
        locatorEnd: locatorJson,
        quotedText: quotedText,
        createdAt: now,
        updatedAt: now,
        hlc: hlc.encode(),
        deviceId: deviceId,
      ));
      await _appendSyncOp(
        entity: 'annotation',
        entityId: id,
        op: 'upsert',
        payload: jsonEncode(<String, dynamic>{
          'id': id,
          'bookId': bookId,
          'type': AnnotationType.highlight.token,
          'color': color.token,
          'locatorStart': locatorJson,
          'locatorEnd': locatorJson,
          'quotedText': quotedText,
          'href': href,
          'chapterIndex': chapterIndex,
          'hlc': hlc.encode(),
          'deviceId': deviceId,
        }),
        hlc: hlc.encode(),
        createdAt: now,
      );
    });
    return Annotation(
      id: id,
      bookId: bookId,
      type: AnnotationType.highlight,
      color: color,
      locatorStart: locatorJson,
      locatorEnd: locatorJson,
      quotedText: quotedText,
      href: href,
      chapterIndex: chapterIndex,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<void> setColor(String id, AnnotationColor color) =>
      _updateAnnotation(id, (row) => row.copyWith(color: color.token));

  @override
  Future<void> setNote(String id, String note) => _updateAnnotation(
        id,
        (row) => row.copyWith(
          note: Value(note.isEmpty ? null : note),
          type: note.isEmpty
              ? AnnotationType.highlight.token
              : AnnotationType.note.token,
        ),
      );

  @override
  Future<void> setAnchor(String id, String locatorJson) => _updateAnnotation(
        id,
        (row) => row.copyWith(locatorStart: locatorJson),
      );

  @override
  Future<void> remove(String id) => _softDelete(id);

  // ---- 书签 ----

  @override
  Future<List<Bookmark>> listBookmarks(String bookId) async =>
      (await _db.bookmarkDao.listForBook(bookId)).map(_bookmarkRowToEntity).toList();

  @override
  Stream<List<Bookmark>> watchBookmarks(String bookId) =>
      _db.bookmarkDao.watchForBook(bookId).map(
            (rows) => rows.map(_bookmarkRowToEntity).toList(),
          );

  @override
  Future<Bookmark> addBookmark({
    required String bookId,
    required String locatorJson,
    String? label,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = _hlcClock.tick();
    await _db.transaction(() async {
      await _db.bookmarkDao.upsert(BookmarkRow(
        id: id,
        bookId: bookId,
        locator: locatorJson,
        label: label,
        createdAt: now,
        hlc: hlc.encode(),
        deviceId: deviceId,
      ));
      await _appendSyncOp(
        entity: 'bookmark',
        entityId: id,
        op: 'upsert',
        payload: jsonEncode(<String, dynamic>{
          'id': id,
          'bookId': bookId,
          'locator': locatorJson,
          'label': label,
          'hlc': hlc.encode(),
          'deviceId': deviceId,
        }),
        hlc: hlc.encode(),
        createdAt: now,
      );
    });
    return Bookmark(
      id: id,
      bookId: bookId,
      locator: locatorJson,
      label: label,
      createdAt: now,
    );
  }

  @override
  Future<void> removeBookmark(String id) => _softDeleteBookmark(id);

  // ---- 内部 ----

  Annotation _rowToEntity(AnnotationRow row) => Annotation(
        id: row.id,
        bookId: row.bookId,
        type: AnnotationType.fromToken(row.type),
        color: AnnotationColor.fromToken(row.color),
        locatorStart: row.locatorStart,
        locatorEnd: row.locatorEnd,
        quotedText: row.quotedText,
        note: row.note,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );

  Bookmark _bookmarkRowToEntity(BookmarkRow row) => Bookmark(
        id: row.id,
        bookId: row.bookId,
        locator: row.locator,
        label: row.label,
        createdAt: row.createdAt,
      );

  /// 通用标注更新：读旧行 → 变换 → 全列写回 + sync_ops（LWW 时间戳）。
  /// 必须走 writeById（companion 显式携带 null）——insertOnConflictUpdate
  /// 的冲突更新会把 null 列标记 absent 不写入，无法清空可空字段。
  Future<void> _updateAnnotation(
    String id,
    AnnotationRow Function(AnnotationRow) transform,
  ) async {
    final row = await _db.annotationDao.getById(id);
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = _hlcClock.tick();
    final updated = transform(
      row.copyWith(updatedAt: now, hlc: hlc.encode(), deviceId: deviceId),
    );
    await _db.transaction(() async {
      await _db.annotationDao.writeById(id, _fullCompanion(updated));
      await _appendSyncOp(
        entity: 'annotation',
        entityId: id,
        op: 'upsert',
        payload: jsonEncode(<String, dynamic>{
          'id': id,
          'bookId': updated.bookId,
          'type': updated.type,
          'color': updated.color,
          'locatorStart': updated.locatorStart,
          'locatorEnd': updated.locatorEnd,
          'quotedText': updated.quotedText,
          'note': updated.note,
          'hlc': hlc.encode(),
          'deviceId': deviceId,
        }),
        hlc: hlc.encode(),
        createdAt: now,
      );
    });
  }

  /// 软删标注（墓碑 + sync_ops delete）。
  Future<void> _softDelete(String id) async {
    final row = await _db.annotationDao.getById(id);
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = _hlcClock.tick();
    final deleted = row.copyWith(
      updatedAt: now,
      deletedAt: Value(now),
      hlc: hlc.encode(),
      deviceId: deviceId,
    );
    await _db.transaction(() async {
      await _db.annotationDao.writeById(id, _fullCompanion(deleted));
      await _appendSyncOp(
        entity: 'annotation',
        entityId: id,
        op: 'delete',
        payload: jsonEncode(<String, dynamic>{
          'id': id,
          'bookId': deleted.bookId,
          // 墓碑时间必须随 payload 同步，远端据此判定删除
          'deletedAt': deleted.deletedAt,
          'hlc': hlc.encode(),
          'deviceId': deviceId,
        }),
        hlc: hlc.encode(),
        createdAt: now,
      );
    });
  }

  /// 软删书签。
  Future<void> _softDeleteBookmark(String id) async {
    final row = await _db.bookmarkDao.getById(id);
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = _hlcClock.tick();
    final deleted = row.copyWith(
      deletedAt: Value(now),
      hlc: hlc.encode(),
      deviceId: deviceId,
    );
    await _db.transaction(() async {
      await _db.bookmarkDao.writeById(
        id,
        BookmarksCompanion(
          deletedAt: Value(deleted.deletedAt),
          hlc: Value(deleted.hlc),
          deviceId: Value(deleted.deviceId),
        ),
      );
      await _appendSyncOp(
        entity: 'bookmark',
        entityId: id,
        op: 'delete',
        payload: jsonEncode(<String, dynamic>{
          'id': id,
          'bookId': deleted.bookId,
          'deletedAt': deleted.deletedAt,
          'hlc': hlc.encode(),
          'deviceId': deviceId,
        }),
        hlc: hlc.encode(),
        createdAt: now,
      );
    });
  }

  /// 标注行 → 全列 companion（显式携带 null，供 writeById 清空可空字段）。
  AnnotationsCompanion _fullCompanion(AnnotationRow r) => AnnotationsCompanion(
        bookId: Value(r.bookId),
        type: Value(r.type),
        color: Value(r.color),
        locatorStart: Value(r.locatorStart),
        locatorEnd: Value(r.locatorEnd),
        quotedText: Value(r.quotedText),
        note: Value(r.note),
        createdAt: Value(r.createdAt),
        updatedAt: Value(r.updatedAt),
        deletedAt: Value(r.deletedAt),
        hlc: Value(r.hlc),
        deviceId: Value(r.deviceId),
      );

  /// sync_ops 追加（与业务写在同一事务内调用）。
  Future<void> _appendSyncOp({
    required String entity,
    required String entityId,
    required String op,
    required String payload,
    required String hlc,
    required int createdAt,
  }) async {
    await _db.into(_db.syncOps).insert(
          SyncOpsCompanion.insert(
            opId: _uuid.v4(),
            entity: entity,
            entityId: entityId,
            op: op,
            payload: payload,
            hlc: hlc,
            createdAt: createdAt,
          ),
        );
  }
}
