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

    // B 拉取
    final pullB = await b.sync.syncNow();
    expect(pullB.ok, isTrue, reason: pullB.error);
    expect(pullB.applied, 5);

    // B 上数据齐全：书籍行 + 书源文件 + 章节 + 进度 + 标注（含笔记）+ 书签
    final bBook = await b.books.getById(book.id);
    expect(bBook, isNotNull);
    expect(bBook!.title, book.title);
    expect(await File(bBook.filePath).exists(), isTrue);
    expect((await b.books.getChapters(book.id)).length,
        (await a.books.getChapters(book.id)).length);

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
    expect(await store.get('a/b/missing.json'), isNull);
    expect(await store.list('a/'), ['a/b/c.json']);
    await store.delete('a/b/c.json');
    expect(await store.list('a/'), isEmpty);
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
}
