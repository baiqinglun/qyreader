/// 书籍个人化信息（评分/书评/标签/置顶）仓储测试。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/db/app_database.dart';
import 'package:qy_reader/core/hlc.dart';
import 'package:qy_reader/data/repositories/book_repository_impl.dart';
import 'package:qy_reader/domain/entities/book.dart';

import '../parsers/epub_parser_test.dart' show buildEpub;

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late BookRepositoryImpl repo;
  late File epubFile;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('qy_reader_personalize');
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

  Future<Book> importBook() async {
    final result = await repo.importFromFile(epubFile.path);
    return result.when(
      ok: (b) => b,
      failure: (e) => throw StateError('导入失败: $e'),
    );
  }

  test('评分/书评/标签：写库 + 同步日志；清除时写回 NULL', () async {
    final book = await importBook();

    await repo.setPersonalization(
      book.id,
      rating: 5,
      review: '  值得一读  ',
      tags: const ['科幻', ' 科幻 ', '经典', ''],
    );

    var row = (await db.select(db.books).get()).single;
    expect(row.rating, 5);
    expect(row.review, '值得一读');
    expect(jsonDecode(row.tags!), ['科幻', '经典']);

    var ops = await db.select(db.syncOps).get();
    expect(ops, hasLength(2)); // 导入 + 个人化
    final payload = jsonDecode(ops.last.payload) as Map<String, dynamic>;
    expect(payload['rating'], 5);
    expect(payload['review'], '值得一读');
    expect(payload['tags'], ['科幻', '经典']);

    await repo.setPersonalization(
      book.id,
      rating: 0,
      review: '   ',
      tags: const [],
    );
    row = (await db.select(db.books).get()).single;
    expect(row.rating, isNull);
    expect(row.review, isNull);
    expect(row.tags, isNull);
    expect(await db.select(db.syncOps).get(), hasLength(3));
  });

  test('只更新一个字段时其他字段保持（null = 不改）', () async {
    final book = await importBook();
    await repo.setPersonalization(
      book.id,
      rating: 4,
      review: '值得一读',
      tags: const ['科幻', '经典'],
      category: '小说',
    );

    // 改评分不能把书评/标签/分类清掉（详情页每改一项只传一个字段）
    await repo.setPersonalization(book.id, rating: 5);
    var row = (await db.select(db.books).get()).single;
    expect(row.rating, 5);
    expect(row.review, '值得一读');
    expect(jsonDecode(row.tags!), ['科幻', '经典']);
    expect(row.category, '小说');

    // 改标签同样只动标签
    await repo.setPersonalization(book.id, tags: const ['科幻']);
    row = (await db.select(db.books).get()).single;
    expect(row.rating, 5);
    expect(row.review, '值得一读');
    expect(jsonDecode(row.tags!), ['科幻']);
    expect(row.category, '小说');

    // 移动书架（只传分类）不能清掉评分/书评/标签
    await repo.setPersonalization(book.id, category: '历史');
    row = (await db.select(db.books).get()).single;
    expect(row.rating, 5);
    expect(row.review, '值得一读');
    expect(jsonDecode(row.tags!), ['科幻']);
    expect(row.category, '历史');

    // 显式空串 / 0 / 空列表才是清除
    await repo.setPersonalization(
      book.id,
      rating: 0,
      review: '  ',
      tags: const [],
      category: '',
    );
    row = (await db.select(db.books).get()).single;
    expect(row.rating, isNull);
    expect(row.review, isNull);
    expect(row.tags, isNull);
    expect(row.category, isNull);
  });

  test('分类：写库 + 同步 payload；清空写回 NULL；超长截断', () async {
    final book = await importBook();

    await repo.setPersonalization(
      book.id,
      category: '  小说  ',
    );
    var row = (await db.select(db.books).get()).single;
    expect(row.category, '小说');
    var ops = await db.select(db.syncOps).get();
    var payload = jsonDecode(ops.last.payload) as Map<String, dynamic>;
    expect(payload['category'], '小说');

    await repo.setPersonalization(
      book.id,
      category: '这是一个明显超过二十个字的超长分类名称用来测试截断逻辑',
    );
    row = (await db.select(db.books).get()).single;
    expect(row.category, hasLength(20));

    await repo.setPersonalization(book.id, category: '   ');
    row = (await db.select(db.books).get()).single;
    expect(row.category, isNull);
    ops = await db.select(db.syncOps).get();
    payload = jsonDecode(ops.last.payload) as Map<String, dynamic>;
    expect(payload.containsKey('category'), isFalse);
  });

  test('置顶写入 pinnedAt，并参与书架排序', () async {
    final book = await importBook();
    await repo.setPinned(book.id, true);
    final row = (await db.select(db.books).get()).single;
    expect(row.pinnedAt, isNotNull);

    final now = DateTime.now().millisecondsSinceEpoch;
    // 手动插入一本已置顶但最近打开更早的书，验证置顶优先
    await db.into(db.books).insert(BooksCompanion.insert(
          id: 'b2',
          title: '置顶书',
          format: 'epub',
          filePath: '/tmp/b2.epub',
          fileSha256: 'sha2',
          fileSize: 1,
          addedAt: now,
          updatedAt: now,
          lastOpenedAt: Value(now - 100000),
          pinnedAt: Value(now + 1000),
          hlc: '1-test',
          deviceId: 'testdev1',
        ));

    final shelf = await repo.watchShelf().first;
    expect(shelf.first.book.id, 'b2');
    expect(shelf.first.book.pinnedAt, now + 1000);

    await repo.setPinned(book.id, false);
    expect((await db.select(db.books).get())
        .firstWhere((r) => r.id == book.id)
        .pinnedAt, isNull);
  });

  test('批量重命名/删除标签：更新所有书、合并去重并追加同步日志', () async {
    final book = await importBook();
    await repo.setPersonalization(book.id, tags: const ['科幻', '经典']);
    final now = DateTime.now().millisecondsSinceEpoch;
    Future<void> insertBook(String id, List<String> tags) async {
      await db.into(db.books).insert(BooksCompanion.insert(
            id: id,
            title: id,
            format: 'epub',
            filePath: '/tmp/$id.epub',
            fileSha256: 'sha-$id',
            fileSize: 1,
            addedAt: now,
            updatedAt: now,
            tags: Value(jsonEncode(tags)),
            hlc: '1-test',
            deviceId: 'testdev1',
          ));
    }

    await insertBook('b2', ['科幻', '待读']);
    await insertBook('b3', ['历史']);
    final beforeOps = (await db.select(db.syncOps).get()).length;

    // 科幻 → SciFi：两本书受影响；历史那本不动。
    expect(await repo.renameTag('科幻', 'SciFi'), 2);
    final rows = await db.select(db.books).get();
    List<String> tagsOf(String id) =>
        (jsonDecode(rows.firstWhere((r) => r.id == id).tags!) as List<dynamic>)
            .cast<String>();
    expect(tagsOf(book.id), ['SciFi', '经典']);
    expect(tagsOf('b2'), ['SciFi', '待读']);
    expect(tagsOf('b3'), ['历史']);
    expect(await db.select(db.syncOps).get(), hasLength(beforeOps + 2));

    // 合并：SciFi → 经典 后同一本书内不重复。
    expect(await repo.renameTag('SciFi', '经典'), 2);
    final merged = await db.select(db.books).get();
    expect(
      jsonDecode(merged.firstWhere((r) => r.id == book.id).tags!),
      ['经典'],
    );
    expect(
      jsonDecode(merged.firstWhere((r) => r.id == 'b2').tags!),
      ['经典', '待读'],
    );

    // 删除经典：从两本书移除；第三次删除 0 本。
    expect(await repo.deleteTag('经典'), 2);
    final cleaned = await db.select(db.books).get();
    expect(cleaned.firstWhere((r) => r.id == book.id).tags, isNull);
    expect(jsonDecode(cleaned.firstWhere((r) => r.id == 'b2').tags!), ['待读']);
    expect(await repo.deleteTag('经典'), 0);
  });

  test('编辑书名/作者：写库 + 同步日志；空串清除作者', () async {
    final book = await importBook();
    expect(book.title, '测试之书');

    await repo.updateBookMeta(book.id, title: '  新书名  ', author: '  李四  ');
    var row = (await db.select(db.books).get()).single;
    expect(row.title, '新书名');
    expect(row.author, '李四');

    // 空串清除作者；书名空串不动
    await repo.updateBookMeta(book.id, title: '   ', author: '');
    row = (await db.select(db.books).get()).single;
    expect(row.title, '新书名');
    expect(row.author, isNull);
  });
}
