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
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/db/app_database.dart';
import '../../core/hlc.dart';
import '../../domain/entities/book.dart';
import '../../domain/repositories/sync_repository.dart';
import '../../domain/sync/object_store.dart';
import '../sync/book_shard.dart';
import '../sync/background_sync.dart';
import '../sync/font_sync.dart';
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

  /// 上次拉取到的对象修改时间（服务端时间；增量拉取的水位线）。
  static const String _kLastPullAt = 'sync.lastPullAt';

  /// 上次拉取分片的时间（分片也走增量，避免每次把所有书的进度都拉一遍）。
  static const String _kLastShardPullAt = 'sync.lastShardPullAt';

  /// 水位线回看窗口：设备/服务端时钟有偏差时，宁可多拉几条也不能漏。
  static const int _pullLookbackMs = 10 * 60 * 1000;

  String get _opsPrefix => 'spaces/$_spaceId/ops/';
  String get _booksPrefix => 'spaces/$_spaceId/books/';
  String get _coversPrefix => 'spaces/$_spaceId/covers/';
  /// 分片位置：`<配置前缀>/shards/<bookId>.json`。
  String get _shardsPrefix => 'shards/';

  /// 上传 sqlite3 数据库快照与封面目录（`spaces/<id>/web/`）。
  ///
  /// 用 `VACUUM INTO` 生成一致快照（WAL 里未落盘的内容也包含），
  /// 传完立刻删临时文件。备份失败只跳过，不影响增量同步。
  @override
  Future<List<String>> pendingShardBooks() async {
    try {
      final rows = await _db.customSelect(
        'SELECT entity, entity_id, payload FROM sync_ops '
        'WHERE uploaded_at IS NULL',
      ).get();
      return _bookIdsOf(rows).toList()..sort();
    } catch (_) {
      return const [];
    }
  }

  /// sync_ops 行 -> 涉及的书 id。
  Set<String> _bookIdsOf(List<QueryRow> rows) {
    final ids = <String>{};
    for (final r in rows) {
      final entity = r.data['entity'] as String? ?? '';
      if (entity == 'book') {
        final id = r.data['entity_id'] as String?;
        if (id != null && id.isNotEmpty) ids.add(id);
        continue;
      }
      try {
        final payload = jsonDecode(r.data['payload'] as String? ?? '{}');
        final id = payload is Map ? payload['bookId'] as String? : null;
        if (id != null && id.isNotEmpty) ids.add(id);
      } catch (_) {}
    }
    return ids;
  }

  Future<({int books, int bytes, String? error})> _uploadShards(
    int sinceMs, {
    void Function(SyncProgress progress)? onProgress,
  }) async {
    final touched = <String>{};
    try {
      final rows = await _db.customSelect(
        'SELECT entity, entity_id, payload FROM sync_ops '
        'WHERE uploaded_at >= ?',
        variables: [Variable.withInt(sinceMs)],
      ).get();
      for (final r in rows) {
        final entity = r.data['entity'] as String? ?? '';
        if (entity == 'book') {
          final id = r.data['entity_id'] as String?;
          if (id != null && id.isNotEmpty) touched.add(id);
          continue;
        }
        try {
          final payload = jsonDecode(r.data['payload'] as String? ?? '{}');
          final id = payload is Map ? payload['bookId'] as String? : null;
          if (id != null && id.isNotEmpty) touched.add(id);
        } catch (_) {
          // payload 不是 JSON 就跳过
        }
      }
    } catch (_) {
      // 读日志失败：本次不传分片
    }
    var bytes = 0;
    var done = 0;
    for (final id in touched) {
      done++;
      onProgress?.call(SyncProgress(
        '正在上传《${await _bookTitle(id)}》的阅读数据',
        done,
        touched.length,
      ));
      try {
        // 已删除的书（只剩墓碑 op）不再生成空分片，否则刚清掉的云端分片
        // 又会被传回来。
        if (await _db.bookDao.getById(id) == null) continue;
        final shard = await BookShard.export(_db, id);
        final data = BookShard.encode(shard);
        await _store.put('$_shardsPrefix$id.json', data);
        bytes += data.length;
      } catch (_) {
        // 单本失败不影响其他书
      }
    }
    return (books: touched.length, bytes: bytes, error: null);
  }

  /// 补齐本地有、云端没有的书源文件与封面。
  ///
  /// 先列举云端 `books/`、`covers/` 的 key，再逐本比对；文件缺失（本地已清
  /// 缓存）就跳过。书源按 sha256 内容寻址去重，封面按书 id 存放（导入即定，
  /// 不会变）。一次同步最多列举两个前缀，不做逐本 HEAD。
  Future<({int files, int bytes, String? error})> _backupLocalBlobs({
    void Function(SyncProgress progress)? onProgress,
  }) async {
    var files = 0;
    var bytes = 0;
    String? error;
    try {
      final existingBooks = (await _store.list(_booksPrefix)).toSet();
      final existingCovers = (await _store.list(_coversPrefix)).toSet();
      final rows = await _db.customSelect(
        'SELECT id, file_path, file_sha256, cover_path FROM books '
        'WHERE deleted_at IS NULL',
      ).get();
      var done = 0;
      for (final row in rows) {
        final id = row.data['id'] as String? ?? '';
        if (id.isEmpty) continue;
        done++;
        // 书源文件（内容寻址）
        final sha = row.data['file_sha256'] as String? ?? '';
        if (sha.isNotEmpty) {
          final key = _bookBlobKey(sha);
          if (!existingBooks.contains(key)) {
            onProgress?.call(SyncProgress(
              '正在上传《${await _bookTitle(id)}》的书籍',
              done,
              rows.length,
            ));
            try {
              final data =
                  await _readFileIfExists(row.data['file_path'] as String?);
              if (data != null) {
                await _store.put(key, data);
                files++;
                bytes += data.length;
              }
            } catch (e) {
              error ??= '$e';
            }
          }
        }
        // 封面（每本固定 `<id>.jpg`）
        final coverKey = _coverBlobKey(id);
        if (!existingCovers.contains(coverKey)) {
          onProgress?.call(SyncProgress(
            '正在上传《${await _bookTitle(id)}》的封面',
            done,
            rows.length,
          ));
          try {
            final data =
                await _readFileIfExists(row.data['cover_path'] as String?);
            if (data != null) {
              await _store.put(coverKey, data);
              files++;
              bytes += data.length;
            }
          } catch (e) {
            error ??= '$e';
          }
        }
      }
    } catch (e) {
      return (files: files, bytes: bytes, error: '$e');
    }
    return (files: files, bytes: bytes, error: error);
  }

  /// 读本地文件；路径为空或文件不存在返回 null。
  Future<List<int>?> _readFileIfExists(String? path) async {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// 拉取云端分片：**增量**——只下载上次拉取之后被改写的分片，且只有云端
  /// 比本地新（`books.updated_at` 更大）才覆盖该书。
  ///
  /// 旧实现每次列举并下载 `shards/` 下所有分片，导致「只读了一本书，其他书
  /// 的进度也一起同步」，同步面板还会逐本刷「正在同步《某书》」（v2.34.0）。
  Future<int> _pullShards({
    void Function(SyncProgress progress)? onProgress,
  }) async {
    var applied = 0;
    try {
      final entries = await _store.listDetailed(_shardsPrefix);
      final watermarkRaw = await _stateOf(_kLastShardPullAt);
      final watermark = int.tryParse(watermarkRaw ?? '') ?? 0;
      final cutoff = watermark - _pullLookbackMs;
      final candidates = [
        for (final entry in entries)
          if (entry.key.endsWith('.json') &&
              (entry.modifiedAtMs == 0 || entry.modifiedAtMs > cutoff))
            entry,
      ];
      var maxSeen = watermark;
      var done = 0;
      for (final entry in candidates) {
        final bytes = await _store.get(entry.key);
        if (bytes == null) continue; // 下载失败：下次再试
        if (entry.modifiedAtMs > maxSeen) maxSeen = entry.modifiedAtMs;
        final shard = BookShard.decode(bytes);
        if (shard == null) continue;
        final id = shard['bookId'] as String?;
        if (id == null || id.isEmpty) continue;
        final remoteRows = shard['books'];
        final remoteUpdated = remoteRows is List && remoteRows.isNotEmpty
            ? (remoteRows.first is Map
                ? (remoteRows.first as Map)['updated_at'] as int? ?? 0
                : 0)
            : 0;
        final local = await _db.customSelect(
          'SELECT updated_at FROM books WHERE id = ?',
          variables: [Variable.withString(id)],
        ).getSingleOrNull();
        if (local != null &&
            (local.data['updated_at'] as int? ?? 0) >= remoteUpdated) {
          // 元数据已是最新。按需下载的新设备这里本地没有章节行——
          // 分片里的目录元数据补上，书详情的目录/章数才不是空的。
          final chapterCount = await _db.customSelect(
            'SELECT COUNT(*) AS n FROM chapters WHERE book_id = ?',
            variables: [Variable.withString(id)],
          ).getSingleOrNull();
          if ((chapterCount?.data['n'] as int? ?? 0) == 0) {
            await BookShard.applyChapters(_db, shard);
          }
          continue;
        }
        done++;
        // 只给真正会写入本地的书报进度，别把没变化的书也刷一遍。
        onProgress?.call(SyncProgress(
          '正在同步《${await _bookTitle(id)}》的阅读数据',
          done,
          candidates.length,
        ));
        await BookShard.apply(_db, shard);
        await _ensureCoverForBook(id);
        applied++;
      }
      if (maxSeen > watermark) {
        await _setState(_kLastShardPullAt, '$maxSeen');
      }
    } catch (_) {
      // 列分片失败按没有处理
    }
    return applied;
  }

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
  Future<SyncResult> syncNow({
    void Function(SyncProgress progress)? onProgress,
  }) async {
    try {
      await _ensureDirs();
      final startedAt = DateTime.now().millisecondsSinceEpoch;
      final pendingOps = (await _pendingOps()).length;
      final pendingBooks = (await pendingShardBooks()).length;
      final total = pendingOps + pendingBooks;
      onProgress?.call(SyncProgress('正在准备同步', 0, total));
      final pushed = await _push(onProgress: onProgress);
      // 云端 -> 本地：先拉操作日志，再按书同步分片
      final pull = await _pull(onProgress: onProgress);
      final pulledShards = await _pullShards(onProgress: onProgress);
      // 分片/远端带来的 file_path 是别的设备的路径：归一化成本机计划路径
      // （书籍按需下载，首次打开时才拉书源文件）。
      await _normalizeCloudBookPaths();
      // 云端有封面、本地文件缺失（旧版本拉取 / 清过缓存）：补回本地
      await _restoreLocalCovers(onProgress: onProgress);
      onProgress?.call(SyncProgress('正在核对云端数据', total, total));
      // 本地 -> 云端：只传本次有写入的那些书
      final backup = await _uploadShards(startedAt, onProgress: onProgress);
      // 本地有、云端没有的书源与封面：补齐上传（含之前同步失败/换桶的情况）
      onProgress?.call(SyncProgress('正在补齐本地文件', total, total));
      final files = await _backupLocalBlobs(onProgress: onProgress);
      // 自定义字体也走同步：文件按 sha256 上传，清单拉回来补进本机字体库
      onProgress?.call(SyncProgress('正在同步字体', total, total));
      final fonts = await _syncFonts(onProgress: onProgress);
      onProgress?.call(SyncProgress('正在同步背景', total, total));
      final backgrounds = await _syncBackgrounds(onProgress: onProgress);
      await _setState(_kLastSyncAt, '${DateTime.now().millisecondsSinceEpoch}');
      await _setState(_kLastError, '');
      return SyncResult(
        pushed: pushed,
        pulled: pull.pulled,
        applied: pull.applied + pulledShards,
        skipped: pull.skipped,
        dbBytes: backup.bytes,
        dbError: backup.error,
        backedUpFiles: files.files,
        backedUpBytes: files.bytes,
        backupError: files.error,
        fontsSynced: fonts.uploaded + fonts.downloaded,
        backgroundsSynced: backgrounds.uploaded + backgrounds.downloaded,
      );
    } catch (e) {
      await _setState(_kLastError, '$e');
      return SyncResult(error: '$e');
    }
  }

  // ---- 推送 ----

  Future<int> _push({
    void Function(SyncProgress progress)? onProgress,
  }) async {
    final ops = await _pendingOps();
    var pushed = 0;
    for (final op in ops) {
      final title = await _bookTitleOfOp(op);
      final what = _entityLabel(op.entity);
      onProgress?.call(SyncProgress(
        title.isEmpty ? '正在上传本机改动' : '正在上传《$title》的$what',
        pushed,
        ops.length,
      ));
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
      // 墓碑推上去后再清云端书源/封面/分片；失败下次同步重试。
      if (op.entity == 'book' && op.op == 'delete') {
        String? sha;
        try {
          final payload = jsonDecode(op.payload);
          if (payload is Map) sha = payload['fileSha256'] as String?;
        } catch (_) {}
        await deleteCloudBook(op.entityId, fileSha256: sha);
      }
      pushed++;
    }
    return pushed;
  }

  /// 书源文件的桶 key（内容寻址；扩展名固定 .epub 仅为历史惯例）。
  String _bookBlobKey(String fileSha256) => '$_booksPrefix$fileSha256.epub';

  /// 封面的桶 key（按书 id；导入时写一次，之后不变）。
  String _coverBlobKey(String bookId) => '$_coversPrefix$bookId.jpg';

  /// 把云端的封面拉到本地标准路径；本地已有或云端没有时返回 null/路径。
  Future<String?> _downloadCover(String bookId) async {
    final path = p.join(_libraryDir.path, 'covers', '$bookId.jpg');
    final file = File(path);
    if (await file.exists()) return path;
    try {
      final blob = await _store.get(_coverBlobKey(bookId));
      if (blob == null) return null;
      await file.parent.create(recursive: true);
      await file.writeAsBytes(blob, flush: true);
      return path;
    } catch (_) {
      return null;
    }
  }

  /// 分片应用后确保本地有封面（并把行里的 cover_path 指到本地文件）。
  Future<void> _ensureCoverForBook(String bookId) async {
    final row = await _db.customSelect(
      'SELECT cover_path FROM books WHERE id = ?',
      variables: [Variable.withString(bookId)],
    ).getSingleOrNull();
    if (row == null) return;
    final current = row.data['cover_path'] as String?;
    final local = await _downloadCover(bookId);
    if (local == null || local == current) return;
    await (_db.update(_db.books)..where((b) => b.id.equals(bookId)))
        .write(BooksCompanion(coverPath: Value(local)));
  }

  /// 本地有书、封面文件却不在时，从云端补回（旧版本拉取 / 清过缓存）。
  Future<void> _restoreLocalCovers({
    void Function(SyncProgress progress)? onProgress,
  }) async {
    try {
      final rows = await _db.customSelect(
        'SELECT id, cover_path FROM books WHERE deleted_at IS NULL',
      ).get();
      var done = 0;
      for (final row in rows) {
        final id = row.data['id'] as String? ?? '';
        if (id.isEmpty) continue;
        done++;
        final current = row.data['cover_path'] as String?;
        if (current != null &&
            current.isNotEmpty &&
            await File(current).exists()) {
          continue;
        }
        onProgress?.call(SyncProgress(
          '正在同步《${await _bookTitle(id)}》的封面',
          done,
          rows.length,
        ));
        await _ensureCoverForBook(id);
      }
    } catch (_) {
      // 封面补拉失败不阻塞同步
    }
  }

  /// 上传书源文件（按 sha256 内容寻址）。
  Future<void> _uploadBookBlob(String bookId) async {
    final row = await _db.bookDao.getById(bookId);
    if (row == null) return;
    final blobKey = _bookBlobKey(row.fileSha256);
    if (await _store.exists(blobKey)) return;
    final file = File(row.filePath);
    if (!await file.exists()) return;
    await _store.put(blobKey, await file.readAsBytes());
  }

  @override
  Future<bool> isBookBackedUp(String bookId) async {
    final row = await _db.bookDao.getById(bookId);
    if (row == null) return false;
    return _store.exists(_bookBlobKey(row.fileSha256));
  }

  @override
  Future<bool> uploadBookBlobNow(String bookId) async {
    await _uploadBookBlob(bookId);
    return isBookBackedUp(bookId);
  }

  @override
  Future<bool> clearLocalBookCache(String bookId) async {
    final row = await _db.bookDao.getById(bookId);
    if (row == null) return false;
    // 先确保云端有备份；没有就绝不动本地文件（否则不可恢复）。
    await _uploadBookBlob(bookId);
    if (!await isBookBackedUp(bookId)) return false;
    try {
      final file = File(row.filePath);
      if (await file.exists()) await file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> deleteCloudBook(String bookId, {String? fileSha256}) async {
    try {
      if (fileSha256 != null && fileSha256.isNotEmpty) {
        await _store.delete(_bookBlobKey(fileSha256));
      }
      // 封面与分片都按书 id 存放。
      await _store.delete(_coverBlobKey(bookId));
      await _store.delete('$_shardsPrefix$bookId.json');
    } catch (_) {
      // 云端删除失败不影响本地删除；下次同步推送墓碑时会再次尝试
    }
  }

  @override
  Future<bool> ensureBookFileLocal(String bookId) async {
    final row = await _db.bookDao.getById(bookId);
    if (row == null) return false;
    final file = File(row.filePath);
    if (await file.exists()) return true;
    try {
      final blob = await _store.get(_bookBlobKey(row.fileSha256));
      if (blob == null) return false;
      await file.parent.create(recursive: true);
      await file.writeAsBytes(blob, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---- 拉取 ----

  /// 拉取云端 ops：**增量**——按对象的服务端修改时间过滤，只下载比上次
  /// 拉取新的 op。旧实现每次把 `ops/` 下全部对象下载一遍再逐条比对
  /// opId，读了几百个对象却一条也不应用（用户看到「每次都拉 500 多条」）。
  ///
  /// 水位线存 `sync.lastPullAt`（取已成功下载对象的最大修改时间），
  /// 并回看 10 分钟兜底设备时钟偏差；opId 幂等比对改为一次性读出
  /// 本地全部 opId（原来一条 op 一次 DB 查询）。
  Future<({int pulled, int applied, int skipped})> _pull({
    void Function(SyncProgress progress)? onProgress,
  }) async {
    final entries = await _store.listDetailed(_opsPrefix);
    var pulled = 0;
    var applied = 0;
    var skipped = 0;
    final watermarkRaw = await _stateOf(_kLastPullAt);
    final watermark = int.tryParse(watermarkRaw ?? '') ?? 0;
    final cutoff = watermark - _pullLookbackMs;
    final known = await _knownOpIds();
    var maxSeen = watermark;
    for (final entry in entries) {
      if (!entry.key.endsWith('.json')) continue;
      // 修改时间取不到（0）时按「可能更新」处理，宁可多拉。
      if (entry.modifiedAtMs > 0 && entry.modifiedAtMs <= cutoff) continue;
      final bytes = await _store.get(entry.key);
      if (bytes == null) continue; // 下载失败：不推进水位线，下次重试
      pulled++;
      if (entry.modifiedAtMs > maxSeen) maxSeen = entry.modifiedAtMs;
      Map<String, dynamic> op;
      try {
        op = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      } catch (_) {
        continue; // 坏对象跳过，不阻塞其它操作
      }
      final opId = op['opId'] as String?;
      if (opId == null) continue;
      final entityId = op['entityId'] as String? ?? '';
      // 新设备本地还没有这本书：优先用 op 里带的标题，别显示 id。
      onProgress?.call(SyncProgress(
        entityId.isEmpty
            ? '正在同步云端数据'
            : '正在同步《${await _titleOfRemoteOp(op, entityId)}》'
                '的${_entityLabel(op['entity'] as String? ?? '')}',
        pulled,
        entries.length,
      ));
      if (known.contains(opId)) {
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
      known.add(opId);
      applied++;
    }
    if (maxSeen > watermark) {
      await _setState(_kLastPullAt, '$maxSeen');
    }
    return (pulled: pulled, applied: applied, skipped: skipped);
  }

  /// 本地 sync_ops 里已见过的全部 opId（一次查询，替代逐条 `_hasOp`）。
  Future<Set<String>> _knownOpIds() async {
    final rows = await _db.select(_db.syncOps).get();
    return {
      for (final row in rows)
        if (row.opId.isNotEmpty) row.opId,
    };
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
    // 删除墓碑：payload 只有 id/deletedAt/fileSha256（没有完整书籍字段），
    // 不能走 bookFromJson。按 HLC 判断后删除本地整本书及关联数据。
    final tombstoneId = payload['id'] as String?;
    final deletedAt = (payload['deletedAt'] as num?)?.toInt();
    if (tombstoneId != null && deletedAt != null && payload['title'] == null) {
      final local = await _db.bookDao.getById(tombstoneId);
      if (local == null || !_isNewer(remoteHlc, local.hlc)) return;
      await (_db.delete(_db.readingProgress)
            ..where((t) => t.bookId.equals(tombstoneId)))
          .go();
      await (_db.delete(_db.readingSessions)
            ..where((t) => t.bookId.equals(tombstoneId)))
          .go();
      await (_db.delete(_db.chapters)
            ..where((t) => t.bookId.equals(tombstoneId)))
          .go();
      await (_db.delete(_db.annotations)
            ..where((t) => t.bookId.equals(tombstoneId)))
          .go();
      await (_db.delete(_db.bookmarks)
            ..where((t) => t.bookId.equals(tombstoneId)))
          .go();
      await (_db.delete(_db.books)..where((t) => t.id.equals(tombstoneId)))
          .go();
      try {
        await _db.customStatement(
          'DELETE FROM book_fts WHERE book_id = ?',
          [tombstoneId],
        );
      } catch (_) {
        // FTS 是派生表，删不掉不影响主流程
      }
      try {
        final f = File(local.filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      try {
        final c = local.coverPath;
        if (c != null && c.isNotEmpty) {
          final f = File(c);
          if (await f.exists()) await f.delete();
        }
      } catch (_) {}
      return;
    }
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
          rating: Value(remote.rating),
          review: Value(remote.review),
          tags: Value(
            remote.tags.isEmpty ? null : jsonEncode(remote.tags),
          ),
          category: Value(remote.category),
          pinnedAt: Value(remote.pinnedAt),
          deletedAt: Value(remote.deletedAt),
          hlc: Value(remote.hlc),
          deviceId: Value(remote.deviceId),
        ));
      }
      if (remote.deletedAt == null) await _ensureCoverForBook(remote.id);
      return;
    }
    // 本地没有：**按需下载**——同步只落书籍元数据（含封面），书源文件
    // 留在云端；首次打开时由 `ensureBookFileLocal` 拉回。新设备同步
    // 不再把所有书源文件一口气下载到本地（v2.30.0）。
    if (remote.deletedAt != null) return; // 墓碑且本地无实体，无需处理
    final bookPath = _plannedBookPath(remote.id);

    // 封面：优先从桶拉（小文件，书架展示需要）；旧版本同步的远端路径
    // 若在本机存在则兜底。
    final downloadedCover = await _downloadCover(remote.id);
    final remoteCover = remote.coverPath;
    final coverPath = downloadedCover ??
        (remoteCover != null &&
                remoteCover.isNotEmpty &&
                await File(remoteCover).exists()
            ? remoteCover
            : null);

    await _db.into(_db.books).insert(
          _bookRowCompanion(remote, bookPath, coverPath: coverPath),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// 本地书源文件的计划路径（按需下载时落在这里）。
  String _plannedBookPath(String bookId) =>
      p.join(_libraryDir.path, 'books', '$bookId.epub');

  /// 归一化云端书籍的本地路径：分片/远端带来的 `file_path` 是别的设备
  /// 上的路径，本机文件不在时改写为本机计划路径，按需下载才落对地方。
  Future<void> _normalizeCloudBookPaths() async {
    try {
      final rows = await _db.customSelect(
        'SELECT id, file_path FROM books WHERE deleted_at IS NULL',
      ).get();
      for (final row in rows) {
        final id = row.data['id'] as String? ?? '';
        if (id.isEmpty) continue;
        final path = row.data['file_path'] as String? ?? '';
        if (path.isEmpty) {
          await (_db.update(_db.books)..where((b) => b.id.equals(id)))
              .write(BooksCompanion(filePath: Value(_plannedBookPath(id))));
          continue;
        }
        if (await File(path).exists()) continue;
        final planned = _plannedBookPath(id);
        if (path == planned) continue;
        await (_db.update(_db.books)..where((b) => b.id.equals(id)))
            .write(BooksCompanion(filePath: Value(planned)));
      }
    } catch (_) {
      // 归一化失败不阻塞同步（下次同步再试）
    }
  }

  BooksCompanion _bookRowCompanion(
    Book b,
    String filePath, {
    String? coverPath,
  }) =>
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
        coverPath: Value(coverPath),
        chapterCount: Value(b.chapterCount),
        wordCount: Value(b.wordCount),
        addedAt: b.addedAt,
        updatedAt: b.updatedAt,
        lastOpenedAt: Value(b.lastOpenedAt),
        isFinished: Value(b.isFinished),
        readStatus: Value(b.readStatus.name),
        isArchived: Value(b.isArchived),
        rating: Value(b.rating),
        review: Value(b.review),
        tags: Value(b.tags.isEmpty ? null : jsonEncode(b.tags)),
        category: Value(b.category),
        pinnedAt: Value(b.pinnedAt),
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

  Future<AnnotationRow?> _annotationById(String id) =>
      (_db.select(_db.annotations)..where((r) => r.id.equals(id)))
          .getSingleOrNull();

  Future<BookmarkRow?> _bookmarkById(String id) =>
      (_db.select(_db.bookmarks)..where((r) => r.id.equals(id)))
          .getSingleOrNull();

  /// 同步进度里的「在同步什么」：书籍信息 / 阅读进度 / 笔记 / 书签。
  String _entityLabel(String entity) => switch (entity) {
        'book' => '书籍信息',
        'progress' => '阅读进度',
        'annotation' => '笔记',
        'bookmark' => '书签',
        _ => '阅读数据',
      };

  /// 同步自定义阅读字体（字体文件 + 清单）。
  ///
  /// 字体不是书籍数据，不进 `sync_ops`：上传按 sha256 内容寻址，清单放在
  /// `spaces/<空间>/fonts/manifest.json`；拉取侧补进本机字体目录与 prefs
  /// `reader.fonts`，`ReaderFontsController` 同步后刷新即可选到。
  Future<FontSyncResult> _syncFonts({
    void Function(SyncProgress progress)? onProgress,
  }) async {
    try {
      final support = await getApplicationSupportDirectory();
      final prefs = await SharedPreferences.getInstance();
      final sync = FontSync(
        store: _store,
        spaceId: _spaceId,
        prefs: prefs,
        dir: Directory(p.join(support.path, 'fonts')),
      );
      return await sync.run(onProgress: onProgress);
    } catch (e) {
      return FontSyncResult(error: '$e');
    }
  }

  /// 背景图也走同步：spaces/<空间>/backgrounds/* + manifest。
  Future<BackgroundSyncResult> _syncBackgrounds({
    void Function(SyncProgress progress)? onProgress,
  }) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final sync = BackgroundSync(
        store: _store,
        spaceId: _spaceId,
        dir: Directory(p.join(docs.path, 'QYReader', 'backgrounds')),
      );
      return await sync.run(onProgress: onProgress);
    } catch (e) {
      return BackgroundSyncResult(error: '');
    }
  }

  /// 书名缓存（同步进度文案用；一次同步内同一本书只查一次）。
  final Map<String, String> _titleCache = <String, String>{};

  /// 取书名；查不到回退成 id 前 6 位，保证进度文案不空白。
  Future<String> _bookTitle(String id) async {
    if (id.isEmpty) return '';
    final cached = _titleCache[id];
    if (cached != null) return cached;
    String title = '';
    try {
      final row = await _db.customSelect(
        'SELECT title FROM books WHERE id = ?',
        variables: [Variable.withString(id)],
      ).getSingleOrNull();
      title = row?.data['title'] as String? ?? '';
    } catch (_) {
      // 查不到就用 id
    }
    if (title.isEmpty) {
      title = id.length > 6 ? id.substring(0, 6) : id;
    }
    _titleCache[id] = title;
    return title;
  }

  /// 一条同步 op 涉及的书名（书籍操作直接用 entityId，其它取 payload.bookId）。
  Future<String> _bookTitleOfOp(SyncOpRow op) async {
    if (op.entity == 'book') return _bookTitle(op.entityId);
    try {
      final payload = jsonDecode(op.payload);
      final id = payload is Map ? payload['bookId'] as String? : null;
      if (id != null && id.isNotEmpty) return _bookTitle(id);
    } catch (_) {
      // payload 不是 JSON：没有书名
    }
    return '';
  }

  /// 远端 op 的书名：op 里带标题就用它（本地还没建书时也能显示）。
  Future<String> _titleOfRemoteOp(Map<String, dynamic> op, String entityId) async {
    if (op['entity'] == 'book') {
      final raw = op['payload'];
      if (raw is String) {
        try {
          final payload = jsonDecode(raw);
          if (payload is Map && payload['title'] is String) {
            final title = (payload['title'] as String).trim();
            if (title.isNotEmpty) return title;
          }
        } catch (_) {
          // 坏 payload：退回查库
        }
      }
    }
    return _bookTitle(entityId);
  }

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
