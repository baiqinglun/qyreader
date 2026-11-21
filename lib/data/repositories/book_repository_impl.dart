/// 书籍仓储实现：drift 持久化 + sync_ops 同事务追加。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:kindle_unpack/kindle_unpack.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/hlc.dart';
import '../../core/result.dart';
import '../../domain/entities/book.dart';
import '../../domain/repositories/book_repository.dart';
import '../covers/cover_image.dart';
import '../parsers/epub/epub_parser.dart';
import '../parsers/plain_text_parser.dart';

/// 生产实现。写库操作均在事务内完成并追加同步日志。
class BookRepositoryImpl implements BookRepository {
  /// 构造：注入数据库、HLC 时钟、设备 id 与书籍库根目录。
  BookRepositoryImpl({
    required AppDatabase db,
    required HlcClock hlcClock,
    required this.deviceId,
    required Directory libraryDir,
  }) : _db = db,
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
  Stream<List<ShelfItem>> watchShelf() => _db.bookDao.watchShelf().map(
    (entries) => entries
        .map((e) => ShelfItem(book: _mapBook(e.book), percent: e.percent))
        .toList(),
  );

  @override
  Future<Result<Book>> importFromFile(
    String sourcePath, {
    bool returnExistingOnDuplicate = false,
  }) async {
    try {
      await _ensureLibraryDirs();
      final source = File(sourcePath);
      if (!await source.exists()) {
        return Result.failure(const ImportException('import.missing', '文件不存在'));
      }

      // 1) 流式 SHA-256（不整读内存）
      final sha256Hex = (await sha256.bind(source.openRead()).first).toString();

      // 2) 重复导入检查（内容寻址去重）
      final existing = await _db.bookDao.findBySha256(sha256Hex);
      if (existing != null) {
        if (returnExistingOnDuplicate) {
          return Result.ok(_mapBook(existing));
        }
        return Result.failure(
          ImportException('import.duplicate', '已在书架：${existing.title}'),
        );
      }

      // 3) 格式嗅探 + 解析：EPUB 走 zip 解析；AZW3 先转 EPUB；
      //    TXT/MD 按纯文本切章
      final bytes = await source.readAsBytes();
      final sourceBook = await _parseSourceBytes(sourcePath, bytes);
      final looksZip = sourceBook.looksZip;
      final isMd = sourceBook.isMd;
      final fileTitle = sourceBook.fileTitle;
      final parsed = sourceBook.parsed;
      final storedBytes = sourceBook.storedBytes;
      final storedSha = sha256.convert(storedBytes).toString();

      // AZW3 的原始哈希与转换后的 EPUB 哈希不同：转换后再按存储内容去重。
      if (storedSha != sha256Hex) {
        final convertedExisting = await _db.bookDao.findBySha256(storedSha);
        if (convertedExisting != null) {
          if (returnExistingOnDuplicate) {
            return Result.ok(_mapBook(convertedExisting));
          }
          return Result.failure(
            ImportException(
              'import.duplicate',
              '已在书架：${convertedExisting.title}',
            ),
          );
        }
      }

      // 4) 落盘：书籍文件 + 封面（AZW3 落的是转换后的 EPUB）
      final id = _uuid.v4();
      final now = DateTime.now().millisecondsSinceEpoch;
      final bookPath = p.join(_booksDir.path, '$id${sourceBook.storedExt}');
      await File(bookPath).writeAsBytes(storedBytes);
      String? coverPath;
      final rawCover = parsed?.coverBytes;
      if (rawCover != null) {
        // 封面单独放 covers 目录，入库前压到最长边 512 的 JPEG（省空间又好画）
        coverPath = p.join(_coversDir.path, '$id.jpg');
        await File(coverPath).writeAsBytes(compressCover(rawCover));
      }

      final format = looksZip
          ? BookFormat.epub
          : (isMd ? BookFormat.md : BookFormat.txt);
      final hlc = _hlcClock.tick();
      final book = Book(
        id: id,
        title: looksZip
            ? parsed!.title
            : (fileTitle.isEmpty ? '未命名文档' : fileTitle),
        author: looksZip ? parsed!.author : null,
        language: looksZip ? parsed!.language : null,
        description: looksZip ? parsed!.description : null,
        format: format,
        filePath: bookPath,
        fileSha256: storedSha,
        fileSize: storedBytes.length,
        coverPath: coverPath,
        chapterCount: sourceBook.chapterCount,
        wordCount: sourceBook.wordCount,
        addedAt: now,
        updatedAt: now,
        hlc: hlc.encode(),
        deviceId: deviceId,
        metaJson: looksZip ? parsed!.metaJson : null,
      );

      // 章节行 + 检索索引（两种来源统一成同一份数据）
      final chapterRows = sourceBook.chapterRows;

      // 6) 事务写库：books + chapters + book_fts + sync_ops 原子提交
      await _db.transaction(() async {
        await _db.into(_db.books).insert(_companionOf(book));
        if (chapterRows.isNotEmpty) {
          await _db.batch((b) {
            for (final c in chapterRows) {
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
        for (final c in chapterRows) {
          if (c.body.isEmpty || !indexedHrefs.add(c.href)) continue;
          await _db.customInsert(
            'INSERT INTO book_fts(book_id, chapter_idx, href, title, body) '
            'VALUES(?, ?, ?, ?, ?)',
            variables: [
              Variable(id),
              Variable(c.idx),
              Variable(c.href),
              Variable(c.title),
              Variable(c.body),
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

  /// 用新书源覆盖已有书籍的正文（保留 id / 个人化信息 / 笔记 / 进度）。
  ///
  /// 新文件按「书 id + 内容哈希前 12 位」落盘：事务提交前旧文件始终有效，
  /// 失败不会把原书变成半覆盖状态。书目元数据只补空字段（新文件的书名/
  /// 作者不会冲掉用户已经改过的信息）。
  @override
  Future<Result<Book>> replaceBookContent(
    String bookId,
    String sourcePath,
  ) async {
    try {
      await _ensureLibraryDirs();
      final row = await _db.bookDao.getById(bookId);
      if (row == null) {
        return Result.failure(
          const ImportException('replace.missing', '书籍不存在或已删除'),
        );
      }
      final source = File(sourcePath);
      if (!await source.exists()) {
        return Result.failure(const ImportException('import.missing', '文件不存在'));
      }
      final sha256Hex = (await sha256.bind(source.openRead()).first).toString();
      // 内容没变：不重写章节，也不动阅读进度。
      if (sha256Hex == row.fileSha256) {
        return Result.ok(_mapBook(row));
      }
      final clash = await _db.bookDao.findBySha256(sha256Hex);
      if (clash != null && clash.id != bookId) {
        return Result.failure(
          ImportException(
            'import.duplicate',
            '新文件已在书架《${clash.title}》，请先删除那本再覆盖导入',
          ),
        );
      }

      final bytes = await source.readAsBytes();
      final src = await _parseSourceBytes(sourcePath, bytes);
      final storedBytes = src.storedBytes;
      final storedSha = sha256.convert(storedBytes).toString();
      // AZW3 转 EPUB 后哈希变了：若转换结果与当前书一致，视为内容没变。
      if (storedSha == row.fileSha256) {
        return Result.ok(_mapBook(row));
      }
      if (storedSha != sha256Hex) {
        final convertedClash = await _db.bookDao.findBySha256(storedSha);
        if (convertedClash != null && convertedClash.id != bookId) {
          return Result.failure(
            ImportException(
              'import.duplicate',
              '新文件已在书架《${convertedClash.title}》，请先删除那本再覆盖导入',
            ),
          );
        }
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final hlc = _hlcClock.tick();
      final oldPath = row.filePath;
      final bookPath = p.join(
        _booksDir.path,
        '${bookId}_${storedSha.substring(0, 12)}${src.storedExt}',
      );
      await File(bookPath).writeAsBytes(storedBytes);

      // 封面：本地已有就保留（微信读书/Reeden 导入的封面通常更好）；
      // 本地没有封面时用新文件里的封面补一张。
      var coverPath = row.coverPath;
      final rawCover = src.parsed?.coverBytes;
      if ((coverPath == null || coverPath.isEmpty) && rawCover != null) {
        coverPath = p.join(_coversDir.path, '$bookId.jpg');
        await File(coverPath).writeAsBytes(compressCover(rawCover));
      }

      final local = _mapBook(row);
      final updated = local.copyWith(
        format: src.format,
        filePath: bookPath,
        fileSha256: storedSha,
        fileSize: storedBytes.length,
        coverPath: coverPath,
        chapterCount: src.chapterCount,
        wordCount: src.wordCount,
        author: _fillIfEmpty(local.author, src.parsed?.author),
        language: _fillIfEmpty(local.language, src.parsed?.language),
        description: _fillIfEmpty(local.description, src.parsed?.description),
        metaJson: src.parsed?.metaJson ?? local.metaJson,
        updatedAt: now,
        hlc: hlc.encode(),
      );
      final chapterRows = src.chapterRows;

      await _db.transaction(() async {
        await (_db.update(_db.books)..where((t) => t.id.equals(bookId))).write(
          BooksCompanion(
            format: Value(updated.format.name),
            filePath: Value(updated.filePath),
            fileSha256: Value(updated.fileSha256),
            fileSize: Value(updated.fileSize),
            coverPath: Value(updated.coverPath),
            chapterCount: Value(updated.chapterCount),
            wordCount: Value(updated.wordCount),
            author: Value(updated.author),
            language: Value(updated.language),
            description: Value(updated.description),
            metaJson: Value(updated.metaJson),
            updatedAt: Value(now),
            hlc: Value(hlc.encode()),
          ),
        );
        await (_db.delete(
          _db.chapters,
        )..where((t) => t.bookId.equals(bookId))).go();
        try {
          await _db.customStatement('DELETE FROM book_fts WHERE book_id = ?', [
            bookId,
          ]);
        } catch (_) {
          // 旧库没有 FTS 表时忽略
        }
        if (chapterRows.isNotEmpty) {
          await _db.batch((b) {
            for (final c in chapterRows) {
              b.insert(
                _db.chapters,
                ChaptersCompanion.insert(
                  bookId: bookId,
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
        final indexedHrefs = <String>{};
        for (final c in chapterRows) {
          if (c.body.isEmpty || !indexedHrefs.add(c.href)) continue;
          await _db.customInsert(
            'INSERT INTO book_fts(book_id, chapter_idx, href, title, body) '
            'VALUES(?, ?, ?, ?, ?)',
            variables: [
              Variable(bookId),
              Variable(c.idx),
              Variable(c.href),
              Variable(c.title),
              Variable(c.body),
            ],
          );
        }
        await _appendSyncOp(
          entity: 'book',
          entityId: bookId,
          op: 'upsert',
          payload: jsonEncode(bookToJson(updated)),
          hlc: hlc,
          createdAt: now,
        );
      });

      // 事务成功后再删旧书源，失败时旧文件还在。
      if (oldPath != bookPath) {
        try {
          final old = File(oldPath);
          if (await old.exists()) await old.delete();
        } catch (_) {
          // 旧文件删不掉不影响阅读
        }
      }
      return Result.ok(updated);
    } on AppException catch (e) {
      return Result.failure(e);
    } catch (e) {
      return Result.failure(ImportException('import.unknown', '$e'));
    }
  }

  /// 解析书籍文件（EPUB / AZW3 / MOBI / TXT / Markdown），导入与覆盖导入共用。
  Future<_ParsedSource> _parseSourceBytes(
    String sourcePath,
    Uint8List bytes,
  ) async {
    final ext = p.extension(sourcePath).toLowerCase();
    final looksZip = _looksLikeZip(bytes);
    final isMd = ext == '.md' || ext == '.markdown';
    final isTxt = ext == '.txt';
    final isKindle = ext == '.azw3' || ext == '.mobi';
    if (!looksZip && !isTxt && !isMd && !isKindle) {
      throw const ImportException(
        'import.unsupported',
        '仅支持 EPUB / AZW3 / MOBI / TXT / Markdown 文件',
      );
    }
    if (!looksZip && !isKindle && bytes.contains(0)) {
      throw const ImportException('import.unsupported', '文件不是可读的文本');
    }
    final fileTitle = p.basenameWithoutExtension(sourcePath).trim();
    if (isKindle) {
      // AZW3 / MOBI 都是 Amazon 的 MOBI 容器：先转成 EPUB，再走同一条
      // EPUB 解析链。
      final epubBytes = await _convertKindleToEpub(bytes);
      final parsed = await parseEpubInIsolate(
        epubBytes,
        '$fileTitle.epub',
        withParagraphs: false,
      );
      return _ParsedSource(
        looksZip: true,
        isMd: false,
        fileTitle: fileTitle,
        parsed: parsed,
        plain: const [],
        storedBytes: epubBytes,
        storedExt: '.epub',
      );
    }
    if (looksZip) {
      // 导入只需要纯文本（检索/字数）；段落数组交给阅读器按需解析
      final parsed = await parseEpubInIsolate(
        bytes,
        p.basename(sourcePath),
        withParagraphs: false,
      );
      return _ParsedSource(
        looksZip: true,
        isMd: false,
        fileTitle: fileTitle,
        parsed: parsed,
        plain: const [],
        storedBytes: bytes,
        storedExt: '.epub',
      );
    }
    final plain = splitPlainText(
      utf8.decode(bytes, allowMalformed: true),
      markdown: isMd,
      title: fileTitle,
    );
    if (plain.isEmpty) {
      throw const ImportException('import.empty', '文件里没有可显示的文本');
    }
    return _ParsedSource(
      looksZip: false,
      isMd: isMd,
      fileTitle: fileTitle,
      parsed: null,
      plain: plain,
      storedBytes: bytes,
      storedExt: isMd ? '.md' : '.txt',
    );
  }

  /// AZW3/MOBI → EPUB（DRM 文件直接报错；解析放到 isolate，避免卡 UI）。
  Future<Uint8List> _convertKindleToEpub(Uint8List bytes) async {
    try {
      final pdb = PdbFile.parse(bytes);
      final palm = PalmDocHeader.parse(pdb.records.first.data);
      if (palm.isEncrypted) {
        throw const ImportException(
          'import.kindle_drm',
          'MOBI / AZW3 受 DRM 保护，暂不支持导入',
        );
      }
      return await Isolate.run(
        () => _normalizeZipTimestamps(KindleBook.fromBytes(bytes).toEpub()),
      );
    } on ImportException {
      rethrow;
    } on KindleUnpackException catch (e) {
      throw ImportException('import.kindle', 'MOBI / AZW3 解析失败：${e.message}');
    } catch (e) {
      throw ImportException('import.kindle', 'MOBI / AZW3 解析失败：$e');
    }
  }

  /// ZIP 里每个条目的时间戳默认是「现在」，同一本 AZW3 隔一秒转换会得到
  /// 不同字节，导致重复导入检测失效。把 DOS 时间统一成 1980-01-01 00:00。
  static Uint8List _normalizeZipTimestamps(Uint8List input) {
    final out = Uint8List.fromList(input);
    final view = ByteData.sublistView(out);
    var i = 0;
    while (i + 4 <= out.length) {
      final sig = view.getUint32(i, Endian.little);
      if (sig == 0x04034b50) {
        if (i + 30 > out.length) break;
        view.setUint16(i + 10, 0, Endian.little); // mod time
        view.setUint16(i + 12, 0x21, Endian.little); // mod date: 1980-01-01
        final flags = view.getUint16(i + 6, Endian.little);
        final nameLen = view.getUint16(i + 26, Endian.little);
        final extraLen = view.getUint16(i + 28, Endian.little);
        _zeroZipExtraTimes(out, view, i + 30 + nameLen, extraLen);
        final compSize = view.getUint32(i + 18, Endian.little);
        if ((flags & 0x08) != 0 && compSize == 0) {
          // archive 写出已知大小时不会带 data descriptor；真遇到就只靠
          // 中央目录的时间戳兜底，避免在压缩数据里误判签名。
          i += 30 + nameLen + extraLen;
          continue;
        }
        i += 30 + nameLen + extraLen + compSize;
      } else if (sig == 0x02014b50) {
        if (i + 46 > out.length) break;
        view.setUint16(i + 12, 0, Endian.little);
        view.setUint16(i + 14, 0x21, Endian.little);
        final nameLen = view.getUint16(i + 28, Endian.little);
        final extraLen = view.getUint16(i + 30, Endian.little);
        final commentLen = view.getUint16(i + 32, Endian.little);
        _zeroZipExtraTimes(out, view, i + 46 + nameLen, extraLen);
        i += 46 + nameLen + extraLen + commentLen;
      } else if (sig == 0x06054b50) {
        break;
      } else {
        i++;
      }
    }
    return out;
  }

  /// 0x5455（extended timestamp）额外字段也带 Unix 时间，一并清零。
  static void _zeroZipExtraTimes(
    Uint8List out,
    ByteData view,
    int start,
    int length,
  ) {
    final end = start + length;
    var pos = start;
    while (pos + 4 <= end) {
      final id = view.getUint16(pos, Endian.little);
      final size = view.getUint16(pos + 2, Endian.little);
      final data = pos + 4;
      if (data + size > end) break;
      if (id == 0x5455 && size > 0) {
        final flags = out[data];
        if ((flags & 0x01) != 0 && size >= 5) {
          view.setUint32(data + 1, 0, Endian.little);
        }
        if ((flags & 0x02) != 0 && size >= 9) {
          view.setUint32(data + 5, 0, Endian.little);
        }
        if ((flags & 0x04) != 0 && size >= 13) {
          view.setUint32(data + 9, 0, Endian.little);
        }
      }
      pos = data + size;
    }
  }

  /// 本地为空才用远端值补（覆盖导入不覆盖用户改过的书名/作者/简介）。
  static String? _fillIfEmpty(String? local, String? remote) {
    if (local != null && local.trim().isNotEmpty) return local;
    final r = remote?.trim();
    return r == null || r.isEmpty ? local : r;
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
        .map(
          (c) => BookChapter(
            idx: c.idx,
            title: c.title ?? '第 ${c.idx + 1} 节',
            href: c.href,
            level: c.level,
          ),
        )
        .toList();
  }

  /// 打开书的时间戳在**阅读期间不落库**（书架按 lastOpenedAt 排序，打开
  /// 瞬间落库会让书架流立刻重排 → 转场动画下书架闪动一下；用户口径：
  /// 退出阅读时才重新渲染位置）。打开时只暂存，[flushOpened] 在退出
  /// 阅读器时统一写库 + 写同步日志。
  final Map<String, int> _pendingOpened = {};

  @override
  Future<void> touchOpened(String bookId) async {
    _pendingOpened[bookId] = DateTime.now().millisecondsSinceEpoch;
  }

  @override
  Future<void> flushOpened(String bookId) async {
    final openedAt = _pendingOpened.remove(bookId);
    if (openedAt == null) return;
    final row = await _db.bookDao.getById(bookId);
    if (row == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = _hlcClock.tick();
    final updated = _mapBook(
      row,
    ).copyWith(lastOpenedAt: openedAt, updatedAt: now, hlc: hlc.encode());
    await _db.transaction(() async {
      await (_db.update(_db.books)..where((t) => t.id.equals(bookId))).write(
        BooksCompanion(
          lastOpenedAt: Value(openedAt),
          updatedAt: Value(now),
          hlc: Value(hlc.encode()),
        ),
      );
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

  @override
  Future<void> updateBookMeta(
    String bookId, {
    String? title,
    String? author,
  }) async {
    final row = await _db.bookDao.getById(bookId);
    if (row == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = _hlcClock.tick();
    final t = title?.trim();
    final a = author?.trim();
    // 书名非空才更新（超长截断）；作者空串 = 清除
    final newTitle = t == null || t.isEmpty
        ? row.title
        : (t.length > 120 ? t.substring(0, 120) : t);
    final newAuthor = a == null
        ? row.author
        : a.isEmpty
        ? null
        : (a.length > 60 ? a.substring(0, 60) : a);
    if (newTitle == row.title && newAuthor == row.author) return;
    final updated = _mapBook(row).copyWith(
      title: newTitle,
      author: newAuthor,
      updatedAt: now,
      hlc: hlc.encode(),
    );
    await _db.transaction(() async {
      await (_db.update(_db.books)..where((b) => b.id.equals(bookId))).write(
        BooksCompanion(
          title: Value(newTitle),
          author: Value(newAuthor),
          updatedAt: Value(now),
          hlc: Value(hlc.encode()),
        ),
      );
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

  @override
  Future<void> setPersonalization(
    String bookId, {
    int? rating,
    String? review,
    List<String>? tags,
    String? category,
    BookReadStatus? readStatus,
  }) async {
    final row = await _db.bookDao.getById(bookId);
    if (row == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = _hlcClock.tick();
    final local = _mapBook(row);
    // null = 这个字段不改；显式传 0 / 空串 / 空列表才是清除。
    // 详情页每改一项只传一个字段，不能把其余字段顺手清空。
    final normalizedRating = rating == null
        ? local.rating
        : (rating <= 0 ? null : rating.clamp(1, 5));
    final normalizedReview = review == null
        ? local.review
        : (review.trim().isEmpty ? null : review.trim());
    final normalizedTags = tags == null ? local.tags : _normalizeTags(tags);
    final normalizedCategory = category == null
        ? local.category
        : _normalizeCategory(category);
    final normalizedStatus = readStatus ?? local.readStatus;
    // 手动从不「已读」切到「已读」时记下完成时间；取消已读不改历史时间。
    final finishedAt =
        readStatus == BookReadStatus.finished &&
            local.readStatus != BookReadStatus.finished
        ? now
        : local.finishedAt;
    final updated = local.copyWith(
      rating: normalizedRating,
      review: normalizedReview,
      tags: normalizedTags,
      category: normalizedCategory,
      readStatus: normalizedStatus,
      finishedAt: finishedAt,
      isFinished: normalizedStatus == BookReadStatus.finished,
      updatedAt: now,
      hlc: hlc.encode(),
    );
    await _db.transaction(() async {
      await (_db.update(_db.books)..where((t) => t.id.equals(bookId))).write(
        BooksCompanion(
          rating: Value(normalizedRating),
          review: Value(normalizedReview),
          tags: Value(
            normalizedTags.isEmpty ? null : jsonEncode(normalizedTags),
          ),
          category: Value(normalizedCategory),
          readStatus: Value(normalizedStatus.name),
          finishedAt: Value(finishedAt),
          isFinished: Value(normalizedStatus == BookReadStatus.finished),
          updatedAt: Value(now),
          hlc: Value(hlc.encode()),
        ),
      );
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

  @override
  Future<void> applyReadingState(
    String bookId, {
    BookReadStatus? readStatus,
    int? lastOpenedAt,
    int? finishedAt,
  }) async {
    final row = await _db.bookDao.getById(bookId);
    if (row == null) return;
    final local = _mapBook(row);
    final nextStatus = readStatus ?? local.readStatus;
    final nextOpened = lastOpenedAt ?? local.lastOpenedAt;
    final nextFinishedAt = finishedAt ?? local.finishedAt;
    if (nextStatus == local.readStatus &&
        nextOpened == local.lastOpenedAt &&
        nextFinishedAt == local.finishedAt) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = _hlcClock.tick();
    final finished = nextStatus == BookReadStatus.finished;
    final updated = local.copyWith(
      readStatus: nextStatus,
      lastOpenedAt: nextOpened,
      finishedAt: nextFinishedAt,
      isFinished: finished,
      updatedAt: now,
      hlc: hlc.encode(),
    );
    await _db.transaction(() async {
      await (_db.update(_db.books)..where((b) => b.id.equals(bookId))).write(
        BooksCompanion(
          readStatus: Value(nextStatus.name),
          lastOpenedAt: Value(nextOpened),
          finishedAt: Value(nextFinishedAt),
          isFinished: Value(finished),
          updatedAt: Value(now),
          hlc: Value(hlc.encode()),
        ),
      );
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

  @override
  Future<int> renameTag(String from, String to) async {
    final oldName = _normalizeTagName(from);
    final newName = _normalizeTagName(to);
    if (oldName == null || newName == null || oldName == newName) return 0;
    final rows = await _db.select(_db.books).get();
    var affected = 0;
    await _db.transaction(() async {
      for (final row in rows) {
        if (row.deletedAt != null) continue;
        final tags = _readTags(row.tags);
        if (!tags.contains(oldName)) continue;
        final updatedTags = _normalizeTags([
          for (final tag in tags) tag == oldName ? newName : tag,
        ]);
        await _writeTags(row, updatedTags);
        affected++;
      }
    });
    return affected;
  }

  @override
  Future<int> deleteTag(String tag) async {
    final name = _normalizeTagName(tag);
    if (name == null) return 0;
    final rows = await _db.select(_db.books).get();
    var affected = 0;
    await _db.transaction(() async {
      for (final row in rows) {
        if (row.deletedAt != null) continue;
        final tags = _readTags(row.tags);
        if (!tags.contains(name)) continue;
        final updatedTags = _normalizeTags([
          for (final value in tags)
            if (value != name) value,
        ]);
        await _writeTags(row, updatedTags);
        affected++;
      }
    });
    return affected;
  }

  /// 批量标签操作的落库：改行 + 追加一条 sync_op（与 setPersonalization 同口径）。
  Future<void> _writeTags(BookRow row, List<String> tags) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = _hlcClock.tick();
    final updated = _mapBook(
      row,
    ).copyWith(tags: tags, updatedAt: now, hlc: hlc.encode());
    await (_db.update(_db.books)..where((b) => b.id.equals(row.id))).write(
      BooksCompanion(
        tags: Value(tags.isEmpty ? null : jsonEncode(tags)),
        updatedAt: Value(now),
        hlc: Value(hlc.encode()),
      ),
    );
    await _appendSyncOp(
      entity: 'book',
      entityId: row.id,
      op: 'upsert',
      payload: jsonEncode(bookToJson(updated)),
      hlc: hlc,
      createdAt: now,
    );
  }

  @override
  Future<void> setFavorite(String bookId, bool favorite) async {
    final row = await _db.bookDao.getById(bookId);
    if (row == null || row.isFavorite == favorite) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = _hlcClock.tick();
    final updated = _mapBook(
      row,
    ).copyWith(isFavorite: favorite, updatedAt: now, hlc: hlc.encode());
    await _db.transaction(() async {
      await (_db.update(_db.books)..where((t) => t.id.equals(bookId))).write(
        BooksCompanion(
          isFavorite: Value(favorite),
          updatedAt: Value(now),
          hlc: Value(hlc.encode()),
        ),
      );
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

  @override
  Future<void> setPinned(String bookId, bool pinned) async {
    final row = await _db.bookDao.getById(bookId);
    if (row == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = _hlcClock.tick();
    final pinnedAt = pinned ? now : null;
    final updated = _mapBook(
      row,
    ).copyWith(pinnedAt: pinnedAt, updatedAt: now, hlc: hlc.encode());
    await _db.transaction(() async {
      await (_db.update(_db.books)..where((t) => t.id.equals(bookId))).write(
        BooksCompanion(
          pinnedAt: Value(pinnedAt),
          updatedAt: Value(now),
          hlc: Value(hlc.encode()),
        ),
      );
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

  /// 标签规范化：去空白/去重/限长，最多 12 个。
  /// 分类归一化：去空白、限长 20；空串 → null（未分类）。
  static String? _normalizeCategory(String? category) {
    final v = category?.trim() ?? '';
    if (v.isEmpty) return null;
    return v.length > 20 ? v.substring(0, 20) : v;
  }

  static List<String> _normalizeTags(List<String>? tags) {
    if (tags == null) return const <String>[];
    final seen = <String>{};
    final out = <String>[];
    for (final raw in tags) {
      final clipped = _normalizeTagName(raw);
      if (clipped == null) continue;
      if (seen.add(clipped)) out.add(clipped);
      if (out.length >= 12) break;
    }
    return out;
  }

  /// 单个标签名规范化：去首尾空白、限长 20；空名返回 null。
  static String? _normalizeTagName(String? raw) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty) return null;
    return v.length > 20 ? v.substring(0, 20) : v;
  }

  /// 从数据库列读取标签（JSON 数组；兼容逗号分隔旧数据）。
  static List<String> _readTags(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } catch (_) {
      // 旧的手写分隔格式
    }
    return raw
        .split(RegExp(r'[,，、;；\s]+'))
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }

  @override
  Future<void> deleteBook(
    String bookId, {
    required bool deleteAnnotations,
  }) async {
    final row = await _db.bookDao.getById(bookId);
    if (row == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hlc = _hlcClock.tick();
    await _db.transaction(() async {
      // 关联数据：进度 / 章节 / 会话
      await (_db.delete(
        _db.readingProgress,
      )..where((t) => t.bookId.equals(bookId))).go();
      await (_db.delete(
        _db.readingSessions,
      )..where((t) => t.bookId.equals(bookId))).go();
      await (_db.delete(
        _db.chapters,
      )..where((t) => t.bookId.equals(bookId))).go();
      if (deleteAnnotations) {
        await (_db.delete(
          _db.annotations,
        )..where((t) => t.bookId.equals(bookId))).go();
        await (_db.delete(
          _db.bookmarks,
        )..where((t) => t.bookId.equals(bookId))).go();
      }
      // 书籍行 + 墓碑（同步对端据此删除）
      await (_db.delete(_db.books)..where((t) => t.id.equals(bookId))).go();
      try {
        // 全文索引是派生表；书删了也把索引行清掉，别留孤儿数据。
        await _db.customStatement('DELETE FROM book_fts WHERE book_id = ?', [
          bookId,
        ]);
      } catch (_) {
        // 旧库没有 FTS 表时忽略
      }
      await _appendSyncOp(
        entity: 'book',
        entityId: bookId,
        op: 'delete',
        payload: jsonEncode({
          'id': bookId,
          'deletedAt': now,
          'fileSha256': row.fileSha256,
        }),
        hlc: hlc,
        createdAt: now,
      );
    });
    // 文件在事务外删（失败不影响数据一致性）
    try {
      final file = File(row.filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
    try {
      final cover = row.coverPath;
      if (cover != null && cover.isNotEmpty) {
        final f = File(cover);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
  }

  Future<void> _ensureLibraryDirs() async {
    await _booksDir.create(recursive: true);
    await _coversDir.create(recursive: true);
  }

  Future<void> _appendSyncOp({
    required String entity,
    required String entityId,
    required String op,
    required String payload,
    required Hlc hlc,
    required int createdAt,
  }) => _db
      .into(_db.syncOps)
      .insert(
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
    finishedAt: row.finishedAt,
    isFinished: row.isFinished,
    readStatus: bookReadStatusFromName(row.readStatus),
    isArchived: row.isArchived,
    rating: row.rating,
    review: row.review,
    tags: _readTags(row.tags),
    category: row.category,
    pinnedAt: row.pinnedAt,
    isFavorite: row.isFavorite,
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
    finishedAt: Value(b.finishedAt),
    isFinished: Value(b.isFinished),
    readStatus: Value(b.readStatus.name),
    isArchived: Value(b.isArchived),
    rating: Value(b.rating),
    review: Value(b.review),
    tags: Value(b.tags.isEmpty ? null : jsonEncode(b.tags)),
    category: Value(b.category),
    pinnedAt: Value(b.pinnedAt),
    isFavorite: Value(b.isFavorite),
    deletedAt: Value(b.deletedAt),
    metaJson: Value(b.metaJson),
  );
}

/// 导入/覆盖导入解析出的章节行（EPUB 与 TXT 统一成同一种结构）。
typedef _ChapterRow = ({
  int idx,
  String href,
  String title,
  int level,
  int startOffset,
  int charCount,
  String body,
});

/// 解析结果：只保存导入落库需要的字段，避免把整个解析对象在 UI 层传递。
class _ParsedSource {
  const _ParsedSource({
    required this.looksZip,
    required this.isMd,
    required this.fileTitle,
    required this.parsed,
    required this.plain,
    required this.storedBytes,
    required this.storedExt,
  });

  final bool looksZip;
  final bool isMd;
  final String fileTitle;
  final ParsedEbook? parsed;
  final List<PlainChapter> plain;

  /// 实际落盘的字节（AZW3 是转换后的 EPUB，其余是原文件）。
  final Uint8List storedBytes;

  /// 实际落盘的扩展名（`.epub` / `.txt` / `.md`）。
  final String storedExt;

  BookFormat get format =>
      looksZip ? BookFormat.epub : (isMd ? BookFormat.md : BookFormat.txt);

  int get chapterCount => looksZip ? parsed!.chapters.length : plain.length;

  int get wordCount => looksZip
      ? parsed!.wordCount
      : plain.fold<int>(0, (sum, c) => sum + c.text.length);

  List<_ChapterRow> get chapterRows => looksZip
      ? [
          for (final c in parsed!.chapters)
            (
              idx: c.idx,
              href: c.href,
              title: c.title,
              level: c.level,
              startOffset: c.startOffset,
              charCount: c.charCount > 0 ? c.charCount : c.bodyText.length,
              body: c.bodyText,
            ),
        ]
      : [
          for (final c in plain)
            (
              idx: c.idx,
              href: c.href,
              title: c.title,
              level: 0,
              startOffset: 0,
              charCount: c.text.length,
              body: c.text,
            ),
        ];
}
