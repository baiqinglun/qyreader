/// 书籍仓储实现：drift 持久化 + sync_ops 同事务追加。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/hlc.dart';
import '../../core/result.dart';
import '../../domain/entities/book.dart';
import '../../domain/repositories/book_repository.dart';
import '../parsers/epub/epub_parser.dart';

/// 生产实现。写库操作均在事务内完成并追加同步日志。
class BookRepositoryImpl implements BookRepository {
  /// 构造：注入数据库、HLC 时钟、设备 id 与书籍库根目录。
  BookRepositoryImpl({
    required AppDatabase db,
    required HlcClock hlcClock,
    required this.deviceId,
    required Directory libraryDir,
  })  : _db = db,
        _hlcClock = hlcClock,
        _uuid = const Uuid() {
    _booksDir = Directory(p.join(libraryDir.path, 'books'));
    _coversDir = Directory(p.join(libraryDir.path, 'covers'));
  }

  final AppDatabase _db;
  final HlcClock _hlcClock;
  final String deviceId;
  final Uuid _uuid;
  late final Directory _booksDir;
  late final Directory _coversDir;

  @override
  Stream<List<ShelfItem>> watchShelf() =>
      _db.bookDao.watchShelf().map((entries) => entries
          .map((e) => ShelfItem(book: _mapBook(e.book), percent: e.percent))
          .toList());

  @override
  Future<Result<Book>> importFromFile(String sourcePath) async {
    try {
      await _ensureLibraryDirs();
      final source = File(sourcePath);
      if (!await source.exists()) {
        return Result.failure(
          const ImportException('import.missing', '文件不存在'),
        );
      }

      // 1) 流式 SHA-256（不整读内存）
      final sha256Hex = (await sha256.bind(source.openRead()).first).toString();

      // 2) 重复导入检查（内容寻址去重）
      final existing = await _db.bookDao.findBySha256(sha256Hex);
      if (existing != null) {
        return Result.failure(ImportException(
          'import.duplicate',
          '已在书架：${existing.title}',
        ));
      }

      // 3) 魔数嗅探（优先于扩展名）：PK\x03\x04 = zip 容器
      final bytes = await source.readAsBytes();
      if (!_looksLikeZip(bytes)) {
        return Result.failure(
          const ImportException(
            'import.unsupported',
            'M0 仅支持 EPUB，其余格式将在后续里程碑支持',
          ),
        );
      }

      // 4) isolate 解析
      final parsed =
          await parseEpubInIsolate(bytes, p.basename(sourcePath));

      // 5) 落盘：书籍文件 + 封面
      final id = _uuid.v4();
      final now = DateTime.now().millisecondsSinceEpoch;
      final bookPath = p.join(_booksDir.path, '$id.epub');
      await source.copy(bookPath);
      String? coverPath;
      if (parsed.coverBytes != null) {
        coverPath = p.join(
          _coversDir.path,
          '$id${_coverExtension(parsed.coverMediaType)}',
        );
        await File(coverPath).writeAsBytes(parsed.coverBytes!);
      }

      final hlc = _hlcClock.tick();
      final book = Book(
        id: id,
        title: parsed.title,
        author: parsed.author,
        language: parsed.language,
        description: parsed.description,
        format: BookFormat.epub,
        filePath: bookPath,
        fileSha256: sha256Hex,
        fileSize: bytes.length,
        coverPath: coverPath,
        chapterCount: parsed.chapters.length,
        wordCount: parsed.wordCount,
        addedAt: now,
        updatedAt: now,
        hlc: hlc.encode(),
        deviceId: deviceId,
        metaJson: parsed.metaJson,
      );

      // 6) 事务写库：books + chapters + book_fts + sync_ops 原子提交
      await _db.transaction(() async {
        await _db.into(_db.books).insert(_companionOf(book));
        if (parsed.chapters.isNotEmpty) {
          await _db.batch((b) {
            for (final c in parsed.chapters) {
              b.insert(
                _db.chapters,
                ChaptersCompanion.insert(
                  bookId: id,
                  idx: c.idx,
                  href: c.href,
                  title: Value(c.title),
                  level: Value(c.level),
                  startOffset: Value(c.startOffset),
                  charCount: Value(c.charCount),
                ),
              );
            }
          });
        }
        // 全书检索索引（派生数据，不同步）：跳过的 href（单文件多章）只索引一次
        final indexedHrefs = <String>{};
        for (final c in parsed.chapters) {
          if (c.bodyText.isEmpty || !indexedHrefs.add(c.href)) continue;
          await _db.customInsert(
            'INSERT INTO book_fts(book_id, chapter_idx, href, title, body) '
            'VALUES(?, ?, ?, ?, ?)',
            variables: [
              Variable(id),
              Variable(c.idx),
              Variable(c.href),
              Variable(c.title),
              Variable(c.bodyText),
            ],
          );
        }
        await _appendSyncOp(
          entity: 'book',
          entityId: id,
          op: 'upsert',
          payload: jsonEncode(bookToJson(book)),
          hlc: hlc,
          createdAt: now,
        );
      });
      return Result.ok(book);
    } on AppException catch (e) {
      return Result.failure(e);
    } catch (e) {
      return Result.failure(ImportException('import.unknown', '$e'));
    }
  }

  @override
  Future<Book?> getById(String bookId) async {
    final row = await _db.bookDao.getById(bookId);
    return row == null ? null : _mapBook(row);
  }

  @override
  Future<List<BookChapter>> getChapters(String bookId) async {
    final rows = await _db.bookDao.getChapters(bookId);
    return rows
        .map((c) => BookChapter(
              idx: c.idx,
              title: c.title ?? '第 ${c.idx + 1} 节',
              href: c.href,
              level: c.level,
            ))
        .toList();
  }

  @override
  Future<void> touchOpened(String bookId) async {
    final row = await _db.bookDao.getById(bookId);
    if (row == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = _hlcClock.tick();
    final updated = _mapBook(row).copyWith(
      lastOpenedAt: now,
      updatedAt: now,
      hlc: hlc.encode(),
    );
    await _db.transaction(() async {
      await (_db.update(_db.books)..where((t) => t.id.equals(bookId)))
          .write(BooksCompanion(
        lastOpenedAt: Value(now),
        updatedAt: Value(now),
        hlc: Value(hlc.encode()),
      ));
      await _appendSyncOp(
        entity: 'book',
        entityId: bookId,
        op: 'upsert',
        payload: jsonEncode(bookToJson(updated)),
        hlc: hlc,
        createdAt: now,
      );
    });
  }

  Future<void> _ensureLibraryDirs() async {
    await _booksDir.create(recursive: true);
    await _coversDir.create(recursive: true);
  }

  Future<void> _appendSyncOp({    required String entity,
    required String entityId,
    required String op,
    required String payload,
    required Hlc hlc,
    required int createdAt,
  }) =>
      _db.into(_db.syncOps).insert(
            SyncOpsCompanion.insert(
              opId: _uuid.v4(),
              entity: entity,
              entityId: entityId,
              op: op,
              payload: payload,
              hlc: hlc.encode(),
              createdAt: createdAt,
            ),
          );

  /// 流式哈希已提前算好，这里只做容器嗅探。
  bool _looksLikeZip(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
      (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08);

  String _coverExtension(String? mediaType) {
    switch (mediaType) {
      case 'image/jpeg':
      case 'image/jpg':
        return '.jpg';
      case 'image/png':
        return '.png';
      case 'image/webp':
        return '.webp';
      case 'image/gif':
        return '.gif';
      default:
        return '.dat';
    }
  }

  Book _mapBook(BookRow row) => Book(
        id: row.id,
        title: row.title,
        author: row.author,
        series: row.series,
        seriesIndex: row.seriesIndex,
        language: row.language,
        description: row.description,
        format: BookFormat.values.firstWhere(
          (f) => f.name == row.format,
          orElse: () => BookFormat.epub,
        ),
        filePath: row.filePath,
        fileSha256: row.fileSha256,
        fileSize: row.fileSize,
        coverPath: row.coverPath,
        chapterCount: row.chapterCount,
        wordCount: row.wordCount,
        addedAt: row.addedAt,
        updatedAt: row.updatedAt,
        lastOpenedAt: row.lastOpenedAt,
        isFinished: row.isFinished,
        isArchived: row.isArchived,
        deletedAt: row.deletedAt,
        metaJson: row.metaJson,
        hlc: row.hlc,
        deviceId: row.deviceId,
      );

  BooksCompanion _companionOf(Book b) => BooksCompanion.insert(
        id: b.id,
        title: b.title,
        format: b.format.name,
        filePath: b.filePath,
        fileSha256: b.fileSha256,
        fileSize: b.fileSize,
        addedAt: b.addedAt,
        updatedAt: b.updatedAt,
        hlc: b.hlc,
        deviceId: b.deviceId,
        author: Value(b.author),
        series: Value(b.series),
        seriesIndex: Value(b.seriesIndex),
        language: Value(b.language),
        description: Value(b.description),
        coverPath: Value(b.coverPath),
        chapterCount: Value(b.chapterCount),
        wordCount: Value(b.wordCount),
        lastOpenedAt: Value(b.lastOpenedAt),
        isFinished: Value(b.isFinished),
        isArchived: Value(b.isArchived),
        deletedAt: Value(b.deletedAt),
        metaJson: Value(b.metaJson),
      );
}
