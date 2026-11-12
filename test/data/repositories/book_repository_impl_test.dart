/// BookRepositoryImpl 单测：内存 SQLite + 临时目录，不联网。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/db/app_database.dart';
import 'package:qy_reader/core/hlc.dart';
import 'package:qy_reader/data/repositories/book_repository_impl.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/shelf/shelf_controller.dart';

import '../parsers/epub_parser_test.dart' show buildEpub;

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
      final result =
          await repo.importFromFile('${tempDir.path}/no_such.epub');
      result.when(
        ok: (_) => throw StateError('应当失败'),
        failure: (e) => expect(e.code, 'import.missing'),
      );
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
    final book = await repo.importFromFile(epubFile.path).then(
          (r) => r.when(ok: (b) => b, failure: (e) => throw StateError('$e')),
        );
    expect(book.readStatus, BookReadStatus.unread);

    await repo.setPersonalization(book.id, readStatus: BookReadStatus.reading);
    expect((await repo.getById(book.id))!.readStatus, BookReadStatus.reading);

    await repo.setPersonalization(book.id, readStatus: BookReadStatus.dropped);
    final updated = await repo.getById(book.id);
    expect(updated!.readStatus, BookReadStatus.dropped);

    // 只改别的字段时阅读状态保持不变。
    await repo.setPersonalization(book.id, rating: 4);
    expect((await repo.getById(book.id))!.readStatus, BookReadStatus.dropped);

    final ops = await db.select(db.syncOps).get();
    final last = jsonDecode(ops.last.payload) as Map<String, dynamic>;
    expect(last['readStatus'], 'dropped');
  });

  test('touchOpened 只在 flushOpened 时落库（最近在读依赖它）', () async {
    final book = await repo.importFromFile(epubFile.path).then(
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