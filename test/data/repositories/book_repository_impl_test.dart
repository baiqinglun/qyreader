/// BookRepositoryImpl 单测：内存 SQLite + 临时目录，不联网。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/db/app_database.dart';
import 'package:qy_reader/core/hlc.dart';
import 'package:qy_reader/data/repositories/book_repository_impl.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/shelf/shelf_controller.dart';

import '../parsers/epub_parser_test.dart' show buildEpub;

/// 最小 PDB（记录 0 的 PalmDOC 头 encryption=2），只用于 DRM 拒绝分支。
Uint8List _encryptedKindlePdb() {
  final bytes = Uint8List(102);
  final view = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, ascii.encode('test'));
  bytes.setRange(60, 64, ascii.encode('BOOK'));
  bytes.setRange(64, 68, ascii.encode('MOBI'));
  view.setUint16(76, 1); // record count
  view.setUint32(78, 86); // record 0 offset
  view.setUint16(86, 1); // PalmDOC compression = none
  view.setUint32(90, 0); // text length
  view.setUint16(94, 0); // text record count
  view.setUint16(96, 4096); // max record size
  view.setUint16(98, 2); // encryption = mobipocket
  return bytes;
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late BookRepositoryImpl repo;
  late File epubFile;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('qy_reader_test');
    repo = BookRepositoryImpl(
      db: db,
      hlcClock: HlcClock(deviceId: 'testdev1'),
      deviceId: 'testdev1',
      libraryDir: tempDir,
    );
    epubFile = File('${tempDir.path}/fixture.epub');
    await epubFile.writeAsBytes(buildEpub());
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('v6 书库升级后保留书籍并默认未收藏', () async {
    final path = '${tempDir.path}/migration.sqlite';
    final oldDb = AppDatabase(NativeDatabase(File(path)));
    final oldRepo = BookRepositoryImpl(
      db: oldDb,
      hlcClock: HlcClock(deviceId: 'testdev1'),
      deviceId: 'testdev1',
      libraryDir: tempDir,
    );
    final result = await oldRepo.importFromFile(epubFile.path);
    final book = result.when(
      ok: (b) => b,
      failure: (e) => throw StateError('$e'),
    );
    await oldDb.customStatement('ALTER TABLE books DROP COLUMN is_favorite');
    await oldDb.customStatement('PRAGMA user_version = 6');
    await oldDb.close();
    final upgraded = AppDatabase(NativeDatabase(File(path)));
    final row = await upgraded.bookDao.getById(book.id);
    expect(row?.title, book.title);
    expect(row?.isFavorite, isFalse);
    await upgraded.close();
  });

  test('收藏写入书籍并生成同步操作，取消收藏可往返', () async {
    final result = await repo.importFromFile(epubFile.path);
    final book = result.when(
      ok: (b) => b,
      failure: (e) => throw StateError('$e'),
    );
    await repo.setFavorite(book.id, true);
    final favorite = (await repo.getById(book.id))!;
    expect(favorite.isFavorite, isTrue);
    expect(bookFromJson(bookToJson(favorite)).isFavorite, isTrue);
    final ops = await db.select(db.syncOps).get();
    expect(jsonDecode(ops.last.payload)['isFavorite'], isTrue);
    await repo.setFavorite(book.id, false);
    expect((await repo.getById(book.id))!.isFavorite, isFalse);
  });

  group('importFromFile', () {
    test('导入成功：写 books/chapters 且同事务追加 sync_ops', () async {
      final result = await repo.importFromFile(epubFile.path);

      final book = result.when(
        ok: (b) => b,
        failure: (e) => throw StateError('导入失败: $e'),
      );
      expect(book.title, '测试之书');
      // 导入默认未读（打开后才变在读）。
      expect(book.readStatus, BookReadStatus.unread);
      expect(book.fileSha256, hasLength(64));
      expect(book.hlc, contains('-testdev1'));

      final rows = await db.select(db.books).get();
      expect(rows, hasLength(1));
      expect(rows.single.title, '测试之书');

      final chapters = await db.select(db.chapters).get();
      expect(chapters, hasLength(2));

      final ops = await db.select(db.syncOps).get();
      expect(ops, hasLength(1));
      expect(ops.single.entity, 'book');
      expect(ops.single.op, 'upsert');
      // payload 是可反解的书籍快照 JSON
      final payload = jsonDecode(ops.single.payload) as Map<String, dynamic>;
      expect(payload['title'], '测试之书');
      expect(payload['deviceId'], 'testdev1');
    });

    test('同一文件导入两次：第二次返回 import.duplicate，不产生第二本', () async {
      await repo.importFromFile(epubFile.path);
      final second = await repo.importFromFile(epubFile.path);

      final error = second.when(
        ok: (_) => throw StateError('重复导入应当失败'),
        failure: (e) => e,
      );
      expect(error.code, 'import.duplicate');
      final rows = await db.select(db.books).get();
      expect(rows, hasLength(1));
    });

    test('不存在的文件返回 import.missing', () async {
      final result = await repo.importFromFile('${tempDir.path}/no_such.epub');
      result.when(
        ok: (_) => throw StateError('应当失败'),
        failure: (e) => expect(e.code, 'import.missing'),
      );
    });
  });

  group('Kindle 导入（MOBI / AZW3）', () {
    test('MOBI 先转 EPUB 落盘，章节与元数据可用', () async {
      final source = File('test/fixtures/pg1342.mobi');
      expect(await source.exists(), isTrue);

      final book = await repo
          .importFromFile(source.path)
          .then(
            (r) => r.when(ok: (b) => b, failure: (e) => throw StateError('$e')),
          );

      expect(book.title.trim(), isNotEmpty);
      expect(book.author, isNotNull);
      expect(book.format, BookFormat.epub);
      expect(book.filePath, endsWith('.epub'));
      expect(book.fileSha256, hasLength(64));
      final stored = File(book.filePath);
      expect(await stored.exists(), isTrue);
      final storedBytes = await stored.readAsBytes();
      expect(storedBytes.take(2), [0x50, 0x4B]); // ZIP（EPUB）头
      expect(book.fileSize, storedBytes.length);
      expect(await db.select(db.chapters).get(), isNotEmpty);

      // 原文件哈希与转换后 EPUB 哈希不同；ZIP 时间戳已归一化，隔一秒
      // 再转也要按转换内容去重。
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final again = await repo.importFromFile(source.path);
      again.when(
        ok: (_) => throw StateError('同一 MOBI 不应导入两次'),
        failure: (e) => expect(e.code, 'import.duplicate'),
      );
    });

    test('AZW3 扩展名走同一条转换链', () async {
      final fixture = File('test/fixtures/pg1342.mobi');
      final source = File('${tempDir.path}/book.azw3');
      await source.writeAsBytes(await fixture.readAsBytes());

      final book = await repo
          .importFromFile(source.path)
          .then(
            (r) => r.when(ok: (b) => b, failure: (e) => throw StateError('$e')),
          );

      expect(book.title.trim(), isNotEmpty);
      expect(book.format, BookFormat.epub);
      expect(book.filePath, endsWith('.epub'));
      expect(await db.select(db.chapters).get(), isNotEmpty);
    });

    test('DRM 加密的 MOBI/AZW3 拒绝导入', () async {
      final file = File('${tempDir.path}/drm.mobi');
      await file.writeAsBytes(_encryptedKindlePdb());

      final result = await repo.importFromFile(file.path);
      result.when(
        ok: (_) => throw StateError('DRM 文件不应导入成功'),
        failure: (e) => expect(e.code, 'import.kindle_drm'),
      );
      expect(await db.select(db.books).get(), isEmpty);
    });
  });

  group('replaceBookContent', () {
    test('保留 id / 书名 / 个人化信息，替换书源、章节与哈希', () async {
      final book = await repo
          .importFromFile(epubFile.path)
          .then(
            (r) => r.when(ok: (b) => b, failure: (e) => throw StateError('$e')),
          );
      await repo.setPersonalization(
        book.id,
        rating: 4,
        review: '一本好书',
        category: '小说',
      );
      final oldPath = book.filePath;
      final oldSha = book.fileSha256;
      final opsBefore = (await db.select(db.syncOps).get()).length;

      final replacement = File('${tempDir.path}/replacement.txt');
      await replacement.writeAsString(
        '第一章 新的开始\n新书的第一段文字。\n\n'
        '第二章 继续\n新书的第二段文字。',
      );

      final updated = await repo
          .replaceBookContent(book.id, replacement.path)
          .then(
            (r) => r.when(ok: (b) => b, failure: (e) => throw StateError('$e')),
          );

      expect(updated.id, book.id);
      expect(updated.title, '测试之书'); // 新文件名不覆盖已有书名
      expect(updated.author, '张三');
      expect(updated.rating, 4);
      expect(updated.review, '一本好书');
      expect(updated.category, '小说');
      expect(updated.fileSha256, isNot(oldSha));
      expect(updated.filePath, isNot(oldPath));
      expect(updated.chapterCount, 2);
      expect(await File(updated.filePath).exists(), isTrue);
      expect(await File(oldPath).exists(), isFalse);

      final chapters = await db.select(db.chapters).get();
      expect(chapters, hasLength(2));
      expect(chapters.every((c) => c.bookId == book.id), isTrue);
      expect(chapters.map((c) => c.href), containsAll(['plain:0', 'plain:1']));

      final ops = await db.select(db.syncOps).get();
      expect(ops.length, opsBefore + 1); // 覆盖导入追加一条 book upsert
      final payload = jsonDecode(ops.last.payload) as Map<String, dynamic>;
      expect(payload['id'], book.id);
      expect(payload['fileSha256'], updated.fileSha256);
    });

    test('内容已在书架另一本书上时拒绝覆盖', () async {
      final first = await repo
          .importFromFile(epubFile.path)
          .then(
            (r) => r.when(ok: (b) => b, failure: (e) => throw StateError('$e')),
          );
      final txt = File('${tempDir.path}/another.txt');
      await txt.writeAsString('第一章\n只有这一章。');
      await repo.importFromFile(txt.path);

      final result = await repo.replaceBookContent(first.id, txt.path);
      final error = result.when(
        ok: (_) => throw StateError('重复内容不应覆盖成功'),
        failure: (e) => e,
      );
      expect(error.code, 'import.duplicate');
      expect((await repo.getById(first.id))!.fileSha256, first.fileSha256);
    });

    test('书不存在返回 replace.missing', () async {
      final result = await repo.replaceBookContent(
        'no-such-book',
        epubFile.path,
      );
      result.when(
        ok: (_) => throw StateError('应当失败'),
        failure: (e) => expect(e.code, 'replace.missing'),
      );
    });

    test('相同文件不重写章节与同步日志', () async {
      final book = await repo
          .importFromFile(epubFile.path)
          .then(
            (r) => r.when(ok: (b) => b, failure: (e) => throw StateError('$e')),
          );
      final opsBefore = (await db.select(db.syncOps).get()).length;
      final again = await repo
          .replaceBookContent(book.id, epubFile.path)
          .then(
            (r) => r.when(ok: (b) => b, failure: (e) => throw StateError('$e')),
          );
      expect(again.filePath, book.filePath);
      expect((await db.select(db.syncOps).get()).length, opsBefore);
    });
  });

  group('watchShelf / touchOpened', () {
    test('touchOpened 只暂存，flushOpened 落库并追加 sync_op', () async {
      // 书架按 lastOpenedAt 排序：打开瞬间落库会让书架流立刻重排（转场
      // 下闪动）。打开只暂存，退出阅读器 flushOpened 才写库 + 同步日志。
      await repo.importFromFile(epubFile.path);

      final first = await repo.watchShelf().first;
      expect(first, hasLength(1));
      final bookId = first.single.book.id;

      await repo.touchOpened(bookId);

      // 暂存期：库不变、无 sync_op
      final mid = await db.select(db.books).getSingle();
      expect(mid.lastOpenedAt, isNull);
      final opsMid = await db.select(db.syncOps).get();

      await repo.flushOpened(bookId);

      final row = await db.select(db.books).getSingle();
      expect(row.lastOpenedAt, isNotNull);
      final opsAfter = await db.select(db.syncOps).get();
      expect(opsAfter.length, opsMid.length + 1);

      // 幂等：重复 flush 是空操作
      final again = await db.select(db.syncOps).get();
      await repo.flushOpened(bookId);
      expect((await db.select(db.syncOps).get()).length, again.length);
    });
  });

  test('阅读状态落库并进同步日志（默认未读）', () async {
    final book = await repo
        .importFromFile(epubFile.path)
        .then(
          (r) => r.when(ok: (b) => b, failure: (e) => throw StateError('$e')),
        );
    expect(book.readStatus, BookReadStatus.unread);

    await repo.setPersonalization(book.id, readStatus: BookReadStatus.reading);
    expect((await repo.getById(book.id))!.readStatus, BookReadStatus.reading);

    await repo.setPersonalization(book.id, readStatus: BookReadStatus.finished);
    final finished = await repo.getById(book.id);
    expect(finished!.readStatus, BookReadStatus.finished);
    expect(finished.finishedAt, isNotNull);

    await repo.setPersonalization(book.id, readStatus: BookReadStatus.dropped);
    final updated = await repo.getById(book.id);
    expect(updated!.readStatus, BookReadStatus.dropped);
    // 取消已读不抹掉历史读完时间。
    expect(updated.finishedAt, finished.finishedAt);

    // 只改别的字段时阅读状态保持不变。
    await repo.setPersonalization(book.id, rating: 4);
    expect((await repo.getById(book.id))!.readStatus, BookReadStatus.dropped);

    final ops = await db.select(db.syncOps).get();
    final last = jsonDecode(ops.last.payload) as Map<String, dynamic>;
    expect(last['readStatus'], 'dropped');
  });

  test('外部阅读状态与最近阅读时间一起落库并进同步日志', () async {
    final book = await repo
        .importFromFile(epubFile.path)
        .then(
          (r) => r.when(ok: (b) => b, failure: (e) => throw StateError('$e')),
        );
    final opsBefore = (await db.select(db.syncOps).get()).length;

    await repo.applyReadingState(
      book.id,
      readStatus: BookReadStatus.finished,
      lastOpenedAt: 1700000000000,
      finishedAt: 1690000000000,
    );

    final updated = await repo.getById(book.id);
    expect(updated!.readStatus, BookReadStatus.finished);
    expect(updated.lastOpenedAt, 1700000000000);
    expect(updated.finishedAt, 1690000000000);
    final ops = await db.select(db.syncOps).get();
    expect(ops.length, opsBefore + 1);
    final payload = jsonDecode(ops.last.payload) as Map<String, dynamic>;
    expect(payload['readStatus'], 'finished');
    expect(payload['lastOpenedAt'], 1700000000000);
    expect(payload['finishedAt'], 1690000000000);

    // 参数为 null 的字段不变。
    await repo.applyReadingState(book.id, lastOpenedAt: 1800000000000);
    final again = await repo.getById(book.id);
    expect(again!.readStatus, BookReadStatus.finished);
    expect(again.lastOpenedAt, 1800000000000);
    expect(again.finishedAt, 1690000000000);
  });

  test('touchOpened 只在 flushOpened 时落库（最近在读依赖它）', () async {
    final book = await repo
        .importFromFile(epubFile.path)
        .then(
          (r) => r.when(ok: (b) => b, failure: (e) => throw StateError('$e')),
        );
    expect(book.lastOpenedAt, isNull);

    await repo.touchOpened(book.id);
    // 打开期间不落库：书架不该在转场时重排
    expect((await repo.getById(book.id))!.lastOpenedAt, isNull);

    await repo.flushOpened(book.id);
    final flushed = (await repo.getById(book.id))!.lastOpenedAt;
    expect(flushed, isNotNull);
    expect(flushed! > 0, isTrue);

    // 重复 flush（退出 + 切后台都会调）不能把时间冲掉 / 报错
    await repo.flushOpened(book.id);
    expect((await repo.getById(book.id))!.lastOpenedAt, flushed);

    // 落库后书架「最近在读」才包含这本书
    final shelf = await repo.watchShelf().first;
    final recent = recentlyReadItems(shelf);
    expect(recent.map((e) => e.book.id), contains(book.id));
  });
}
