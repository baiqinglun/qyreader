/// TXT / Markdown 导入单测：格式、章节、检索索引。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/db/app_database.dart';
import 'package:qy_reader/core/hlc.dart';
import 'package:qy_reader/data/repositories/book_repository_impl.dart';
import 'package:qy_reader/domain/entities/book.dart';

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late BookRepositoryImpl repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('qy_reader_plain');
    repo = BookRepositoryImpl(
      db: db,
      hlcClock: HlcClock(deviceId: 'testdev1'),
      deviceId: 'testdev1',
      libraryDir: tempDir,
    );
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  Future<Book> importText(String name, String content) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsString(content);
    final result = await repo.importFromFile(file.path);
    return result.when(
      ok: (b) => b,
      failure: (e) => throw StateError('导入失败: ${e.message}'),
    );
  }

  test('TXT：按章切分写库 + 检索索引', () async {
    final book = await importText('我的小说.txt', '''
第一章 起程
　　第一章正文内容，用来测试导入后的章节与索引。

第二章 抵达
　　第二章正文内容。
''');
    expect(book.format, BookFormat.txt);
    expect(book.title, '我的小说');
    expect(book.chapterCount, 2);
    expect(book.wordCount, greaterThan(0));
    expect(book.filePath.endsWith('.txt'), isTrue);

    final chapters = await repo.getChapters(book.id);
    expect(chapters.map((c) => c.title), ['第一章 起程', '第二章 抵达']);

    final rows = await db
        .customSelect('SELECT book_id, chapter_idx, href, title FROM book_fts')
        .get();
    expect(rows.length, 2,
        reason: rows.map((r) => r.data.toString()).join(' | '));
  });

  test('Markdown：按 # 标题切章', () async {
    final book = await importText('笔记.md', '''
# 第一篇

正文一。

## 小节

正文二。
''');
    expect(book.format, BookFormat.md);
    final chapters = await repo.getChapters(book.id);
    expect(chapters.map((c) => c.title), ['第一篇', '小节']);
    expect(chapters[1].level, 0); // 章级别由正文标题段落承载
  });

  test('PDF（或其他格式）拒绝导入', () async {
    final file = File('${tempDir.path}/x.pdf');
    await file.writeAsBytes('%PDF-1.4 fake'.codeUnits);
    final result = await repo.importFromFile(file.path);
    result.when(
      ok: (_) => fail('不该导入成功'),
      failure: (e) => expect(e.message, contains('EPUB / TXT / Markdown')),
    );

    final bin = File('${tempDir.path}/x.bin');
    await bin.writeAsBytes([0, 1, 2, 3, 4, 0, 5]);
    final r2 = await repo.importFromFile(bin.path);
    r2.when(
      ok: (_) => fail('不该导入成功'),
      failure: (e) => expect(e.code, 'import.unsupported'),
    );
  });
}
