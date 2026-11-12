/// 同步引擎单测：两个独立库共享一个本地桶，验证推送/拉取/合并/幂等。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qy_reader/core/db/app_database.dart';
import 'package:qy_reader/core/hlc.dart';
import 'package:qy_reader/data/repositories/annotation_repository_impl.dart';
import 'package:qy_reader/data/repositories/book_repository_impl.dart';
import 'package:qy_reader/data/repositories/progress_repository_impl.dart';
import 'package:qy_reader/data/repositories/sync_repository_impl.dart';
import 'package:qy_reader/data/sync/local_object_store.dart';
import 'package:qy_reader/domain/entities/annotation.dart';
import 'package:qy_reader/domain/entities/book.dart';

import '../../data/parsers/epub_parser_test.dart' show buildEpub;

/// 单台设备的测试夹具（库 + 仓储）。
class _Device {
  _Device(this.deviceId, this.db, this.libraryDir, this.store);

  final String deviceId;
  final AppDatabase db;
  final Directory libraryDir;
  final LocalObjectStore store;

  late final HlcClock clock = HlcClock(deviceId: deviceId);
  late final BookRepositoryImpl books = BookRepositoryImpl(
    db: db,
    hlcClock: clock,
    deviceId: deviceId,
    libraryDir: libraryDir,
  );
  late final ProgressRepositoryImpl progress = ProgressRepositoryImpl(
    db: db,
    hlcClock: clock,
    deviceId: deviceId,
  );
  late final AnnotationRepositoryImpl annotations =
      AnnotationRepositoryImpl(
    db: db,
    hlcClock: clock,
    deviceId: deviceId,
  );
  late final SyncRepositoryImpl sync = SyncRepositoryImpl(
    db: db,
    store: store,
    spaceId: 'test-space',
    deviceId: deviceId,
    libraryDir: libraryDir,
    hlcClock: clock,
  );

  Future<Book> importBook(String sourcePath) async {
    final r = await books.importFromFile(sourcePath);
    return r.when(
      ok: (b) => b,
      failure: (e) => throw StateError('导入失败: $e'),
    );
  }
}

void main() {
  late Directory tempRoot;
  late Directory bucketDir;
  late _Device a;
  late _Device b;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('qy_sync_test');
    bucketDir = Directory('${tempRoot.path}/bucket');
    await bucketDir.create(recursive: true);
    // 两台设备共享同一个「桶」目录（模拟同一 S3 空间）
    a = _Device(
      'deviceA1',
      AppDatabase(NativeDatabase.memory()),
      Directory('${tempRoot.path}/libA'),
      LocalObjectStore(bucketDir),
    );
    b = _Device(
      'deviceB2',
      AppDatabase(NativeDatabase.memory()),
      Directory('${tempRoot.path}/libB'),
      LocalObjectStore(bucketDir),
    );
    await a.libraryDir.create(recursive: true);
    await b.libraryDir.create(recursive: true);
  });

  tearDown(() async {
    await a.db.close();
    await b.db.close();
    await tempRoot.delete(recursive: true);
  });

  Future<String> writeEpub(String name) async {
    final f = File('${tempRoot.path}/$name');
    await f.writeAsBytes(buildEpub());
    return f.path;
  }

  test('书籍 + 进度 + 标注 + 书签全链路同步到另一台设备', () async {
    final src = await writeEpub('book.epub');
    final book = await a.importBook(src);
    await a.progress.saveProgress(
      bookId: book.id,
      locator: '{"v":1,"cfi":"epubcfi(/6/2!/4/2/1:0)","percent":0.2}',
      percent: 0.2,
    );
    final ann = await a.annotations.addHighlight(
      bookId: book.id,
      cfiRange: 'epubcfi(/6/2!/4/2,/1:0,/1:20)',
      color: AnnotationColor.green,
      quotedText: '山川湖海',
    );
    await a.annotations.setNote(ann.id, '好句');
    await a.annotations.addBookmark(
      bookId: book.id,
      locatorJson: '{"v":1,"cfi":"epubcfi(/6/2!/4:0)"}',
    );

    // A 推送
    final pushA = await a.sync.syncNow();
    expect(pushA.ok, isTrue, reason: pushA.error);
    // book + progress + annotation(add) + annotation(setNote) + bookmark
    expect(pushA.pushed, 5);
    // 书源文件已进桶
    final blobs = await bucketDir
        .list(recursive: true)
        .where((e) => e.path.endsWith('.epub'))
        .toList();
    expect(blobs, hasLength(1));
    // 封面也会进桶（按书 id），不依赖书源文件的 sha256
    expect(
      await a.store.get('spaces/test-space/covers/${book.id}.jpg'),
      isNotNull,
    );

    // B 拉取
    final pullB = await b.sync.syncNow();
    expect(pullB.ok, isTrue, reason: pullB.error);
    expect(pullB.applied, 5);

    // B 上数据齐全：书籍行 + 封面 + 章节（元数据随分片），但**书源文件按需下载**
    // —— 同步不把书源文件一口气拉下来（v2.30.0）。
    final bBook = await b.books.getById(book.id);
    expect(bBook, isNotNull);
    expect(bBook!.title, book.title);
    expect(await File(bBook.filePath).exists(), isFalse);
    expect(bBook.coverPath, isNotNull);
    expect(await File(bBook.coverPath!).exists(), isTrue);
    expect((await b.books.getChapters(book.id)).length,
        (await a.books.getChapters(book.id)).length);

    // 首次打开（按需）才下载书源文件
    expect(await b.sync.ensureBookFileLocal(book.id), isTrue);
    final withFile = await b.books.getById(book.id);
    expect(await File(withFile!.filePath).exists(), isTrue);

    final bProgress = await b.progress.getProgress(book.id);
    expect(bProgress!.percent, closeTo(0.2, 1e-9));

    final bAnns = await b.annotations.listForBook(book.id);
    expect(bAnns, hasLength(1));
    expect(bAnns.single.quotedText, '山川湖海');
    expect(bAnns.single.note, '好句');
    expect(bAnns.single.color, AnnotationColor.green);

    expect(await b.annotations.listBookmarks(book.id), hasLength(1));
  });

  test('幂等：重复同步不再产生新增/重复数据', () async {
    final src = await writeEpub('book.epub');
    final book = await a.importBook(src);
    await a.sync.syncNow();
    await b.sync.syncNow();

    // 双端再同步两轮
    final again1 = await b.sync.syncNow();
    final again2 = await a.sync.syncNow();
    expect(again1.applied, 0);
    expect(again1.skipped, greaterThanOrEqualTo(1));
    expect(again2.applied, 0);

    expect(await b.books.getById(book.id), isNotNull);
    final all = await a.db.select(a.db.books).get();
    expect(all, hasLength(1));
  });

  test('本地有书源与封面、云端缺失时同步会补齐上传', () async {
    final src = await writeEpub('backup.epub');
    final book = await a.importBook(src);
    expect(await a.sync.syncNow().then((r) => r.ok), isTrue);

    final bookKey = 'spaces/test-space/books/${book.fileSha256}.epub';
    final coverKey = 'spaces/test-space/covers/${book.id}.jpg';
    expect(await a.store.get(bookKey), isNotNull);
    expect(await a.store.get(coverKey), isNotNull);

    // 模拟云端备份文件丢失（本地书与封面仍在）
    await a.store.delete(bookKey);
    await a.store.delete(coverKey);

    // 没有新的 sync_ops：全靠本地文件补齐扫描发现缺失。
    final second = await a.sync.syncNow();
    expect(second.ok, isTrue, reason: second.error);
    expect(second.backedUpFiles, 2);
    expect(second.backedUpBytes, greaterThan(0));
    expect(await a.store.get(bookKey), isNotNull);
    expect(await a.store.get(coverKey), isNotNull);

    // 云端已齐全：重复同步不再上传
    final third = await a.sync.syncNow();
    expect(third.backedUpFiles, 0);
  });

  test('本地封面文件丢失时，同步会从云端补回', () async {
    final src = await writeEpub('cover.epub');
    final book = await a.importBook(src);
    await a.sync.syncNow();
    await b.sync.syncNow();

    final before = await b.books.getById(book.id);
    expect(before!.coverPath, isNotNull);
    final cover = File(before.coverPath!);
    expect(await cover.exists(), isTrue);
    await cover.delete();

    final result = await b.sync.syncNow();
    expect(result.ok, isTrue, reason: result.error);
    final after = await b.books.getById(book.id);
    expect(after!.coverPath, isNotNull);
    expect(await File(after.coverPath!).exists(), isTrue);
  });

  test('进度冲突：当前进度 LWW，最远进度取 max 永不回退', () async {
    final src = await writeEpub('book.epub');
    final book = await a.importBook(src);
    await a.sync.syncNow();
    await b.sync.syncNow();

    // A 读到 0.8（最远 0.8）
    await a.progress.saveProgress(
      bookId: book.id,
      locator: '{"v":1,"cfi":"epubcfi(/6/2!/4/2,/1:800)"}',
      percent: 0.8,
    );
    await a.sync.syncNow();

    // B 只读到 0.3（更晚的 HLC）
    await b.progress.saveProgress(
      bookId: book.id,
      locator: '{"v":1,"cfi":"epubcfi(/6/2!/4/2,/1:300)"}',
      percent: 0.3,
    );
    await b.sync.syncNow(); // B 拉 A（0.8 更早？A 先写，HLC 更早）

    // A 拉 B：当前进度应变为 B 的 0.3（LWW），但最远仍 0.8
    await a.sync.syncNow();
    final merged = await a.progress.getProgress(book.id);
    expect(merged!.percent, closeTo(0.3, 1e-9));
    expect(merged.furthestPercent, closeTo(0.8, 1e-9));
  });

  test('标注删除墓碑传播：另一设备删除后本设备列表不再显示', () async {
    final src = await writeEpub('book.epub');
    final book = await a.importBook(src);
    final ann = await a.annotations.addHighlight(
      bookId: book.id,
      cfiRange: 'epubcfi(/6/2!/4/2,/1:0,/1:20)',
      color: AnnotationColor.blue,
      quotedText: '日月星辰',
    );
    await a.sync.syncNow();
    await b.sync.syncNow();
    expect(await b.annotations.listForBook(book.id), hasLength(1));

    // B 侧删除并同步
    await b.annotations.remove(ann.id);
    await b.sync.syncNow();
    // A 拉取墓碑
    await a.sync.syncNow();

    expect(await a.annotations.listForBook(book.id), isEmpty);
    final row = await a.db.annotationDao.getById(ann.id);
    expect(row.deletedAt, isNotNull);
  });

  test('标注 LWW：后写覆盖先写（同一条 id 笔记更新）', () async {
    final src = await writeEpub('book.epub');
    final book = await a.importBook(src);
    final ann = await a.annotations.addHighlight(
      bookId: book.id,
      cfiRange: 'epubcfi(/6/2!/4/2,/1:0,/1:20)',
      color: AnnotationColor.yellow,
      quotedText: '天地玄黄',
    );
    await a.sync.syncNow();
    await b.sync.syncNow();

    // B 更新笔记（HLC 更晚），A 也更新颜色（更晚）
    await b.annotations.setNote(ann.id, 'B 的笔记');
    await b.sync.syncNow();
    await a.annotations.setColor(ann.id, AnnotationColor.rose);
    await a.sync.syncNow(); // A 先拉到 B 的笔记（更早），再被自己的 setColor 影响

    // B 拉 A 的最新
    await b.sync.syncNow();
    final onB = (await b.annotations.listForBook(book.id)).single;
    // 颜色以 A 的最新为准；笔记保留 B 的（A 的更新未携带 note 变更语义，
    // 实际以整行 LWW 为准，这里断言最终状态稳定不丢）
    expect(onB.color, AnnotationColor.rose);
  });

  test('status 反映待上传数与上次同步时间', () async {
    final src = await writeEpub('book.epub');
    await a.importBook(src);
    final before = await a.sync.status();
    expect(before.pendingOps, greaterThan(0));
    expect(before.lastSyncAt, isNull);

    await a.sync.syncNow();
    final after = await a.sync.status();
    expect(after.pendingOps, 0);
    expect(after.lastSyncAt, isNotNull);
    expect(after.deviceId, 'deviceA1');
    expect(after.spaceId, 'test-space');
  });

  test('本地存储：put/get/list/delete 与路径安全', () async {
    final store = LocalObjectStore(Directory('${tempRoot.path}/store'));
    await store.put('a/b/c.json', [1, 2, 3]);
    expect(await store.get('a/b/c.json'), [1, 2, 3]);
    expect(await store.exists('a/b/c.json'), isTrue);
    expect(await store.get('a/b/missing.json'), isNull);
    expect(await store.exists('a/b/missing.json'), isFalse);
    expect(await store.list('a/'), ['a/b/c.json']);
    await store.delete('a/b/c.json');
    expect(await store.list('a/'), isEmpty);
    expect(await store.exists('a/b/c.json'), isFalse);
    // 路径穿越被隔离在桶内（'..' 段转义成 %2E%2E，不会写到桶外）
    await store.put('../escape.txt', [9]);
    expect(
      Directory('${tempRoot.path}/escape.txt').existsSync(),
      isFalse,
    );
    expect(await store.list(''), contains('%2E%2E/escape.txt'));
    // 转义后的对象仍可按原 key 读回
    expect(await store.get('../escape.txt'), [9]);
  });

  test('Book JSON 往返一致（payload 契约）', () async {
    final src = await writeEpub('book.epub');
    final book = await a.importBook(src);
    final back = bookFromJson(bookToJson(book));
    expect(back.id, book.id);
    expect(back.title, book.title);
    expect(back.fileSha256, book.fileSha256);
  });

  group('书源缓存（清除本地 → 阅读时从同步库拉回）', () {
    test('上传 / 备份查询 / 拉回', () async {
      final src = await writeEpub('book.epub');
      final book = await a.importBook(src);

      // 导入只写 sync_ops，还没推送：备份尚不在桶里
      expect(await a.sync.isBookBackedUp(book.id), isFalse);

      // 清缓存前的「确保备份」：立即上传
      expect(await a.sync.uploadBookBlobNow(book.id), isTrue);
      expect(await a.sync.isBookBackedUp(book.id), isTrue);

      // 删除本地文件 → ensure 拉回 → 文件恢复且可重复调用
      final f = File(book.filePath);
      expect(await f.exists(), isTrue);
      await f.delete();
      expect(await a.sync.ensureBookFileLocal(book.id), isTrue);
      expect(await f.exists(), isTrue);
      expect(await a.sync.ensureBookFileLocal(book.id), isTrue);
    });

    test('未备份且本地缺失：ensure 返回 false 不抛异常', () async {
      final src = await writeEpub('book.epub');
      final book = await a.importBook(src);
      await File(book.filePath).delete();
      expect(await a.sync.isBookBackedUp(book.id), isFalse);
      expect(await a.sync.ensureBookFileLocal(book.id), isFalse);
    });

    test('新设备同步只拉书籍元数据，书源文件按需下载（v2.30.0）', () async {
      final src = await writeEpub('book.epub');
      final book = await a.importBook(src);
      await a.sync.syncNow();
      await b.sync.syncNow();

      // 同步后：书在架子上、有目录，但书源文件没落地
      final pulled = await b.books.getById(book.id);
      expect(pulled, isNotNull);
      expect(await File(pulled!.filePath).exists(), isFalse);
      expect(await b.books.getChapters(book.id), isNotEmpty);

      // 首次打开才下载，并落到本机计划路径
      expect(await b.sync.ensureBookFileLocal(book.id), isTrue);
      final withFile = await b.books.getById(book.id);
      expect(withFile!.filePath, pulled.filePath);
      expect(await File(withFile.filePath).exists(), isTrue);
      expect(await File(withFile.filePath).length(),
          (await File(book.filePath).length()));
    });

    test('清除缓存只删本地书源：封面、数据库、云端都保留', () async {
      final src = await writeEpub('cache.epub');
      final book = await a.importBook(src);
      await a.sync.syncNow();

      final file = File(book.filePath);
      final cover = File(book.coverPath!);
      final bookKey = 'spaces/test-space/books/${book.fileSha256}.epub';
      final coverKey = 'spaces/test-space/covers/${book.id}.jpg';
      expect(await file.exists(), isTrue);
      expect(await cover.exists(), isTrue);

      expect(await a.sync.clearLocalBookCache(book.id), isTrue);
      // 书源没了，封面还在
      expect(await file.exists(), isFalse);
      expect(await cover.exists(), isTrue);
      // 数据库记录和云端对象都保留
      expect(await a.books.getById(book.id), isNotNull);
      expect(await a.store.exists(bookKey), isTrue);
      expect(await a.store.exists(coverKey), isTrue);
      // 下次打开自动拉回
      expect(await a.sync.ensureBookFileLocal(book.id), isTrue);
      expect(await file.exists(), isTrue);
    });

    test('没有云端备份时不清除本地文件', () async {
      final src = await writeEpub('nobackup.epub');
      final book = await a.importBook(src);
      // 本地文件先丢了：无法上传备份，清除必须失败且不抛异常。
      await File(book.filePath).delete();
      expect(await a.sync.clearLocalBookCache(book.id), isFalse);
    });

    test('删除书籍时云端书源、封面与分片一起删除', () async {
      final src = await writeEpub('delete.epub');
      final book = await a.importBook(src);
      await a.sync.syncNow();

      final bookKey = 'spaces/test-space/books/${book.fileSha256}.epub';
      final coverKey = 'spaces/test-space/covers/${book.id}.jpg';
      final shardKey = 'shards/${book.id}.json';
      expect(await a.store.exists(bookKey), isTrue);
      expect(await a.store.exists(coverKey), isTrue);
      expect(await a.store.exists(shardKey), isTrue);

      await a.books.deleteBook(book.id, deleteAnnotations: true);
      // 本地文件已删；云端等下次同步推送墓碑时清理
      expect(await a.store.exists(bookKey), isTrue);
      await a.sync.syncNow();
      expect(await a.store.exists(bookKey), isFalse);
      expect(await a.store.exists(coverKey), isFalse);
      expect(await a.store.exists(shardKey), isFalse);

      // 不会因为「补齐本地文件」或空分片被重新传回来
      await a.sync.syncNow();
      expect(await a.store.exists(bookKey), isFalse);
      expect(await a.store.exists(coverKey), isFalse);
      expect(await a.store.exists(shardKey), isFalse);
    });

    test('删除墓碑传播：另一台设备同步后也移除书籍', () async {
      final src = await writeEpub('tombstone.epub');
      final book = await a.importBook(src);
      await a.sync.syncNow();
      await b.sync.syncNow();
      expect(await b.books.getById(book.id), isNotNull);

      await a.books.deleteBook(book.id, deleteAnnotations: true);
      await a.sync.syncNow();

      final pulled = await b.sync.syncNow();
      expect(pulled.ok, isTrue, reason: pulled.error);
      expect(await b.books.getById(book.id), isNull);
    });
  });

  test('增量拉取：水位线之前的旧 op 不再重复下载', () async {
    final src = await writeEpub('incremental.epub');
    final book = await a.importBook(src);
    await a.sync.syncNow();

    // 把桶里 ops 的文件时间拨回 2 小时前：模拟「这批 op 是很久以前同步的」。
    final opsDir = Directory('${bucketDir.path}/spaces/test-space/ops');
    expect(opsDir.existsSync(), isTrue);
    final oldTime = DateTime.now().subtract(const Duration(hours: 2));
    await for (final entity in opsDir.list()) {
      if (entity is File) await entity.setLastModified(oldTime);
    }

    // B 首次同步：水位线为 0，全量拉取并应用。
    final first = await b.sync.syncNow();
    expect(first.ok, isTrue, reason: first.error);
    expect(first.applied, greaterThanOrEqualTo(1));

    // A 再产生一条新 op（书评），文件时间是「现在」。
    await a.books.setPersonalization(book.id, review: '新书评');
    await a.sync.syncNow();

    // B 再次同步：旧的 op 因水位线被过滤，只拉新的那条。
    final second = await b.sync.syncNow();
    expect(second.ok, isTrue, reason: second.error);
    expect(second.applied, 1);
    final pulled = await b.books.getById(book.id);
    expect(pulled!.review, '新书评');
  });

  test('同步进度会报出正在同步的书名（不是只报阶段）', () async {
    final src = await writeEpub('progress.epub');
    final book = await a.importBook(src);
    final labels = <String>[];
    await a.sync.syncNow(onProgress: (p) => labels.add(p.label));
    await b.sync.syncNow(onProgress: (p) => labels.add(p.label));

    expect(labels, isNotEmpty);
    // 至少一条带书名：上传 / 下载 / 备份任一步都要能看出是哪本书。
    expect(labels.any((l) => l.contains(book.title)), isTrue);
    expect(labels.any((l) => l.startsWith('正在')), isTrue);
  });

  test('分片增量：上次同步之后没改过的书不再下载分片', () async {
    final s1 = await writeEpub('shard-a.epub');
    final book1 = await a.importBook(s1);
    // 第二本书内容不同（去掉封面）：否则 sha256 相同会被判重复。
    final s2 = File('${tempRoot.path}/shard-b.epub');
    await s2.writeAsBytes(buildEpub(withCover: false));
    await a.importBook(s2.path);
    await a.sync.syncNow();
    await b.sync.syncNow(); // B 首次全量拉一遍

    // 把云端分片时间拨到 1 小时前：B 的水位线仍在「现在」，这些旧分片应被跳过。
    final shardDir = Directory('${bucketDir.path}/shards');
    final past = DateTime.now().subtract(const Duration(hours: 1));
    await for (final e in shardDir.list()) {
      if (e is File) await e.setLastModified(past);
    }
    b.store.readKeys.clear();
    final idle = await b.sync.syncNow();
    expect(idle.ok, isTrue, reason: idle.error);
    expect(
      b.store.readKeys.where((k) => k.startsWith('shards/')),
      isEmpty,
    );

    // A 只读了 book1：同步后 B 只该拉这一本书的分片。
    await a.progress.saveProgress(
      bookId: book1.id,
      locator: '{"v":1,"cfi":"epubcfi(/6/2!/4/2/1:0)","percent":0.3}',
      percent: 0.3,
    );
    await a.sync.syncNow();
    b.store.readKeys.clear();
    final pulled = await b.sync.syncNow();
    expect(pulled.ok, isTrue, reason: pulled.error);
    final shardReads =
        b.store.readKeys.where((k) => k.startsWith('shards/')).toList();
    expect(shardReads, hasLength(1));
    expect(shardReads.single, contains(book1.id));
    expect(pulled.applied, greaterThanOrEqualTo(1));
  });
}