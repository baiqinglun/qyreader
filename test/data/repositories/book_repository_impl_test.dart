/// BookRepositoryImpl 单测：内存 SQLite + 临时目录，不联网。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/db/app_database.dart';
import 'package:qy_reader/core/hlc.dart';
import 'package:qy_reader/data/repositories/book_repository_impl.dart';

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
    test('书架流可见新书，touchOpened 更新最近打开并追加 sync_op', () async {
      await repo.importFromFile(epubFile.path);

      final first = await repo.watchShelf().first;
      expect(first, hasLength(1));
      expect(first.single.percent, 0);

      final before = await db.select(db.syncOps).get();
      await repo.touchOpened(first.single.book.id);
      final after = await db.select(db.syncOps).get();

      final row = await db.select(db.books).getSingle();
      expect(row.lastOpenedAt, isNotNull);
      expect(after.length, before.length + 1);
    });
  });
}
