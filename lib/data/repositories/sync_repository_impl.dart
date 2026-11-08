/// 同步引擎：日志复制式多设备同步（M4，LocalObjectStore 打底）。
///
/// 推送：sync_ops 中未上传的操作 → 对象 `ops/{opId}.json`；书籍操作额外
///       把书源文件传到 `books/{sha256}.epub`（内容寻址，天然去重）。
/// 拉取：列举 ops/ 下全部对象 → opId 已在本地 sync_ops 的跳过（幂等）→
///       按实体规则合并 → 拉到的操作也写入 sync_ops（标记已上传，不再回推）。
///
/// 合并规则（与设计文档一致）：
/// - book：LWW（HLC 字符串比较）更新元数据；本地无此书则从桶拷回书源文件、
///   重新解析章节与检索索引；删除为墓碑 LWW。
/// - progress：locator/percent LWW；furthestPercent 取 max 永不回退。
/// - annotation / bookmark：整行 LWW；删除墓碑参与 LWW。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../core/db/app_database.dart';
import '../../core/hlc.dart';
import '../../data/parsers/epub/epub_parser.dart';
import '../../domain/entities/book.dart';
import '../../domain/repositories/sync_repository.dart';
import '../../domain/sync/object_store.dart';
import '../../domain/sync/sync_status.dart';

/// 同步引擎实现。
class SyncRepositoryImpl implements SyncRepository {
  /// 构造。
  SyncRepositoryImpl({
    required AppDatabase db,
    required ObjectStore store,
    required String spaceId,
    required String deviceId,
    required Directory libraryDir,
    required HlcClock hlcClock,
  })  : _db = db,
        _store = store,
        _spaceId = spaceId,
        _deviceId = deviceId,
        _libraryDir = libraryDir,
        _hlcClock = hlcClock;

  final AppDatabase _db;
  final ObjectStore _store;
  final String _spaceId;
  final String _deviceId;
  final Directory _libraryDir;
  final HlcClock _hlcClock;

  static const String _kLastSyncAt = 'sync.lastAt';
  static const String _kLastError = 'sync.lastError';

  String get _opsPrefix => 'spaces/$_spaceId/ops/';
  String get _booksPrefix => 'spaces/$_spaceId/books/';

  @override
  Future<SyncStatus> status() async {
    final pending = await _pendingOps();
    final lastRaw = await _stateOf(_kLastSyncAt);
    final error = await _stateOf(_kLastError);
    return SyncStatus(
      pendingOps: pending.length,
      lastSyncAt: lastRaw == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(int.tryParse(lastRaw) ?? 0),
      lastError: error,
      deviceId: _deviceId,
      spaceId: _spaceId,
    );
  }

  @override
  Future<SyncResult> syncNow() async {
    try {
      await _ensureDirs();
      final pushed = await _push();
      final pull = await _pull();
      await _setState(_kLastSyncAt, '${DateTime.now().millisecondsSinceEpoch}');
      await _setState(_kLastError, '');
      return SyncResult(
        pushed: pushed,
        pulled: pull.pulled,
        applied: pull.applied,
        skipped: pull.skipped,
      );
    } catch (e) {
      await _setState(_kLastError, '$e');
      return SyncResult(error: '$e');
    }
  }

  // ---- 推送 ----

  Future<int> _push() async {
    final ops = await _pendingOps();
    var pushed = 0;
    for (final op in ops) {
      // 书籍操作先把书源文件传到桶（内容寻址；已存在则跳过）
      if (op.entity == 'book') {
        await _uploadBookBlob(op.entityId);
      }
      final wrapper = jsonEncode(<String, dynamic>{
        'opId': op.opId,
        'entity': op.entity,
        'entityId': op.entityId,
        'op': op.op,
        'payload': op.payload,
        'hlc': op.hlc,
        'deviceId': _deviceId,
        'createdAt': op.createdAt,
      });
      await _store.put('$_opsPrefix${op.opId}.json', utf8.encode(wrapper));
      await (_db.update(_db.syncOps)..where((r) => r.seq.equals(op.seq)))
          .write(SyncOpsCompanion(
        uploadedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));
      pushed++;
    }
    return pushed;
  }

  /// 上传书源文件（按 sha256 内容寻址）。
  Future<void> _uploadBookBlob(String bookId) async {
    final row = await _db.bookDao.getById(bookId);
    if (row == null) return;
    final blobKey = '$_booksPrefix${row.fileSha256}.epub';
    if (await _store.get(blobKey) != null) return;
    final file = File(row.filePath);
    if (!await file.exists()) return;
    await _store.put(blobKey, await file.readAsBytes());
  }

  // ---- 拉取 ----

  Future<({int pulled, int applied, int skipped})> _pull() async {
    final keys = await _store.list(_opsPrefix);
    var pulled = 0;
    var applied = 0;
    var skipped = 0;
    for (final key in keys) {
      if (!key.endsWith('.json')) continue;
      final bytes = await _store.get(key);
      if (bytes == null) continue;
      pulled++;
      Map<String, dynamic> op;
      try {
        op = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      } catch (_) {
        continue; // 坏对象跳过，不阻塞其它操作
      }
      final opId = op['opId'] as String?;
      if (opId == null) continue;
      if (await _hasOp(opId)) {
        skipped++;
        continue;
      }
      await _applyRemoteOp(op);
      await _db.into(_db.syncOps).insert(
            SyncOpsCompanion.insert(
              opId: opId,
              entity: op['entity'] as String? ?? 'unknown',
              entityId: op['entityId'] as String? ?? '',
              op: op['op'] as String? ?? 'upsert',
              payload: op['payload'] as String? ?? '{}',
              hlc: op['hlc'] as String? ?? _hlcClock.tick().encode(),
              createdAt: (op['createdAt'] as num?)?.toInt() ??
                  DateTime.now().millisecondsSinceEpoch,
              uploadedAt: Value(DateTime.now().millisecondsSinceEpoch),
            ),
            mode: InsertMode.insertOrIgnore,
          );
      applied++;
    }
    return (pulled: pulled, applied: applied, skipped: skipped);
  }

  /// 合并一条远端操作（整次调用包一层事务，实体级原子）。
  Future<void> _applyRemoteOp(Map<String, dynamic> op) async {
    final entity = op['entity'] as String? ?? '';
    final payloadRaw = op['payload'] as String? ?? '{}';
    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(payloadRaw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final remoteHlc = payload['hlc'] as String? ?? op['hlc'] as String? ?? '';
    await _db.transaction(() async {
      switch (entity) {
        case 'book':
          await _mergeBook(payload, remoteHlc);
        case 'progress':
          await _mergeProgress(payload, remoteHlc);
        case 'annotation':
          await _mergeAnnotation(payload, remoteHlc);
        case 'bookmark':
          await _mergeBookmark(payload, remoteHlc);
        default:
          break; // 未知实体（未来版本）静默跳过，向前兼容
      }
    });
  }

  // ---- 实体合并 ----

  Future<void> _mergeBook(Map<String, dynamic> payload, String remoteHlc) async {
    final Book remote;
    try {
      remote = bookFromJson(payload);
    } catch (_) {
      return;
    }
    final local = await _db.bookDao.getById(remote.id);
    if (local != null) {
      // LWW：远端更新才覆盖元数据（书源文件保留本地路径）
      if (_isNewer(remoteHlc, local.hlc)) {
        await (_db.update(_db.books)..where((r) => r.id.equals(remote.id)))
            .write(BooksCompanion(
          title: Value(remote.title),
          author: Value(remote.author),
          language: Value(remote.language),
          description: Value(remote.description),
          updatedAt: Value(remote.updatedAt),
          lastOpenedAt: Value(remote.lastOpenedAt),
          isFinished: Value(remote.isFinished),
          isArchived: Value(remote.isArchived),
          deletedAt: Value(remote.deletedAt),
          hlc: Value(remote.hlc),
          deviceId: Value(remote.deviceId),
        ));
      }
      return;
    }
    // 本地没有：从桶取书源文件、落库并重建章节/检索索引
    if (remote.deletedAt != null) return; // 墓碑且本地无实体，无需处理
    final blob = await _store.get('$_booksPrefix${remote.fileSha256}.epub');
    if (blob == null) return; // 文件尚未上传（对方未同步完成），下次再同步
    final bookPath = p.join(_libraryDir.path, 'books', '${remote.id}.epub');
    final file = File(bookPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(blob, flush: true);

    var chapters = const <ParsedChapter>[];
    try {
      final parsed = await parseEpubInIsolate(
          Uint8List.fromList(blob), remote.title);
      chapters = parsed.chapters;
    } catch (_) {
      // 解析失败仍保留书籍行（可重试）
    }
    await _db.into(_db.books).insert(
          _bookRowCompanion(remote, bookPath),
          mode: InsertMode.insertOrIgnore,
        );
    for (final c in chapters) {
      await _db.into(_db.chapters).insert(
            ChaptersCompanion.insert(
              bookId: remote.id,
              idx: c.idx,
              href: c.href,
              title: Value(c.title),
              level: Value(c.level),
              startOffset: Value(c.startOffset),
              charCount: Value(c.charCount),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    // 检索索引（派生数据）
    final indexed = <String>{};
    for (final c in chapters) {
      if (c.bodyText.isEmpty || !indexed.add(c.href)) continue;
      await _db.customInsert(
        'INSERT INTO book_fts(book_id, chapter_idx, href, title, body) '
        'VALUES(?, ?, ?, ?, ?)',
        variables: [
          Variable(remote.id),
          Variable(c.idx),
          Variable(c.href),
          Variable(c.title),
          Variable(c.bodyText),
        ],
      );
    }
  }

  BooksCompanion _bookRowCompanion(Book b, String filePath) =>
      BooksCompanion.insert(
        id: b.id,
        title: b.title,
        author: Value(b.author),
        series: Value(b.series),
        seriesIndex: Value(b.seriesIndex),
        language: Value(b.language),
        description: Value(b.description),
        format: b.format.name,
        filePath: filePath,
        fileSha256: b.fileSha256,
        fileSize: b.fileSize,
        chapterCount: Value(b.chapterCount),
        wordCount: Value(b.wordCount),
        addedAt: b.addedAt,
        updatedAt: b.updatedAt,
        lastOpenedAt: Value(b.lastOpenedAt),
        isFinished: Value(b.isFinished),
        isArchived: Value(b.isArchived),
        deletedAt: Value(b.deletedAt),
        metaJson: Value(b.metaJson),
        hlc: b.hlc,
        deviceId: b.deviceId,
      );

  Future<void> _mergeProgress(
    Map<String, dynamic> payload,
    String remoteHlc,
  ) async {
    final bookId = payload['bookId'] as String?;
    if (bookId == null) return;
    final remotePercent = (payload['percent'] as num?)?.toDouble() ?? 0;
    final remoteFurthest =
        (payload['furthestPercent'] as num?)?.toDouble() ?? 0;
    final local = await _db.progressDao.getForBook(bookId);

    if (local == null) {
      await _db.progressDao.upsert(ReadingProgressRow(
        bookId: bookId,
        locator: payload['locator'] as String? ?? '{}',
        percent: remotePercent,
        furthestLocator: payload['furthestLocator'] as String?,
        furthestPercent: remoteFurthest,
        updatedAt: (payload['createdAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        hlc: remoteHlc,
        deviceId: payload['deviceId'] as String? ?? '',
      ));
      return;
    }

    // 当前进度 LWW
    final lww = _isNewer(remoteHlc, local.hlc);
    // 最远进度取 max，永不回退
    final takeFurthest = remoteFurthest > local.furthestPercent;
    if (!lww && !takeFurthest) return;
    await _db.progressDao.upsert(local.copyWith(
      locator: lww ? (payload['locator'] as String? ?? local.locator)
          : local.locator,
      percent: lww ? remotePercent : local.percent,
      furthestLocator: Value(takeFurthest
          ? (payload['furthestLocator'] as String? ??
              local.furthestLocator)
          : local.furthestLocator),
      furthestPercent:
          takeFurthest ? remoteFurthest : local.furthestPercent,
      hlc: lww ? remoteHlc : local.hlc,
      deviceId: lww
          ? (payload['deviceId'] as String? ?? local.deviceId)
          : local.deviceId,
    ));
  }

  Future<void> _mergeAnnotation(
    Map<String, dynamic> payload,
    String remoteHlc,
  ) async {
    final id = payload['id'] as String?;
    final bookId = payload['bookId'] as String?;
    if (id == null || bookId == null) return;
    final existing = await _annotationById(id);
    if (existing != null && !_isNewer(remoteHlc, existing.hlc)) return;
    final deleted = payload['deletedAt'] as num?;
    await _db.into(_db.annotations).insertOnConflictUpdate(
          AnnotationRow(
            id: id,
            bookId: bookId,
            type: payload['type'] as String? ?? 'highlight',
            color: payload['color'] as String? ?? 'yellow',
            locatorStart: payload['locatorStart'] as String? ?? '{}',
            locatorEnd: payload['locatorEnd'] as String? ?? '{}',
            quotedText: payload['quotedText'] as String?,
            note: payload['note'] as String?,
            createdAt: (payload['createdAt'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
            updatedAt: (payload['createdAt'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
            deletedAt: deleted?.toInt(),
            hlc: remoteHlc,
            deviceId: payload['deviceId'] as String? ?? '',
          ),
        );
  }

  Future<void> _mergeBookmark(
    Map<String, dynamic> payload,
    String remoteHlc,
  ) async {
    final id = payload['id'] as String?;
    final bookId = payload['bookId'] as String?;
    if (id == null || bookId == null) return;
    final existing = await _bookmarkById(id);
    if (existing != null && !_isNewer(remoteHlc, existing.hlc)) return;
    final deleted = payload['deletedAt'] as num?;
    await _db.into(_db.bookmarks).insertOnConflictUpdate(
          BookmarkRow(
            id: id,
            bookId: bookId,
            locator: payload['locator'] as String? ?? '{}',
            label: payload['label'] as String?,
            createdAt: (payload['createdAt'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
            deletedAt: deleted?.toInt(),
            hlc: remoteHlc,
            deviceId: payload['deviceId'] as String? ?? '',
          ),
        );
  }

  // ---- 内部工具 ----

  Future<List<SyncOpRow>> _pendingOps() => (_db.select(_db.syncOps)
        ..where((r) => r.uploadedAt.isNull())
        ..orderBy([(r) => OrderingTerm.asc(r.seq)]))
      .get();

  Future<bool> _hasOp(String opId) async {
    final row = await (_db.select(_db.syncOps)
          ..where((r) => r.opId.equals(opId))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  Future<AnnotationRow?> _annotationById(String id) =>
      (_db.select(_db.annotations)..where((r) => r.id.equals(id)))
          .getSingleOrNull();

  Future<BookmarkRow?> _bookmarkById(String id) =>
      (_db.select(_db.bookmarks)..where((r) => r.id.equals(id)))
          .getSingleOrNull();

  /// HLC 字符串定宽可排序：比较即时间序。
  bool _isNewer(String remote, String local) =>
      remote.isNotEmpty && remote.compareTo(local) > 0;

  Future<String?> _stateOf(String key) async {
    final row = await (_db.select(_db.syncState)
          ..where((r) => r.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> _setState(String key, String value) async {
    await _db.into(_db.syncState).insertOnConflictUpdate(
          SyncStateRow(key: key, value: value),
        );
  }

  Future<void> _ensureDirs() async {
    await Directory(p.join(_libraryDir.path, 'books')).create(recursive: true);
  }
}
