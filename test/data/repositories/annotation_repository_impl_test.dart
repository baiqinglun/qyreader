/// 标注与书签仓储单测：内存库 + sync_ops 同事务断言。
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qy_reader/core/db/app_database.dart';
import 'package:qy_reader/core/hlc.dart';
import 'package:qy_reader/data/repositories/annotation_repository_impl.dart';
import 'package:qy_reader/domain/entities/annotation.dart';
import 'package:qy_reader/domain/repositories/annotation_repository.dart';

void main() {
  late AppDatabase db;
  late AnnotationRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = AnnotationRepositoryImpl(
      db: db,
      hlcClock: HlcClock(deviceId: 'aaaaaaaa'),
      deviceId: 'aaaaaaaa',
    );
  });

  tearDown(() async => db.close());

  test('addHighlight 落库并同事务追加 sync_ops', () async {
    await repo.addHighlight(
      bookId: 'b1',
      cfiRange: 'epubcfi(/6/4!/4/2,/1:0,/1:20)',
      color: AnnotationColor.yellow,
      quotedText: '山川湖海',
      href: 'OEBPS/ch1.xhtml',
      chapterIndex: 0,
    );

    final rows = await repo.listForBook('b1');
    expect(rows, hasLength(1));
    expect(rows.single.color, AnnotationColor.yellow);
    expect(rows.single.quotedText, '山川湖海');
    expect(rows.single.locatorStart, contains('epubcfi(/6/4'));

    final ops = await db.select(db.syncOps).get();
    expect(ops, hasLength(1));
    expect(ops.single.entity, 'annotation');
    expect(ops.single.op, 'upsert');
  });

  test('setColor / setNote 更新且 sync_ops 追加；setNote 空串清笔记回 highlight', () async {
    final a = await repo.addHighlight(
      bookId: 'b1',
      cfiRange: 'epubcfi(/6/4!/4/2,/1:0,/1:20)',
      color: AnnotationColor.blue,
      quotedText: '日月星辰',
    );

    await repo.setColor(a.id, AnnotationColor.rose);
    await repo.setNote(a.id, '感想');

    var rows = await repo.listForBook('b1');
    expect(rows.single.color, AnnotationColor.rose);
    expect(rows.single.note, '感想');
    expect(rows.single.type, AnnotationType.note);

    await repo.setNote(a.id, '');
    rows = await repo.listForBook('b1');
    expect(rows.single.note, isNull);
    expect(rows.single.type, AnnotationType.highlight);

    final ops = await db.select(db.syncOps).get();
    expect(ops, hasLength(4)); // add + setColor + setNote×2
  });

  test('remove 软删：列表不可见、watch 刷新、sync_ops 记 delete', () async {
    final a = await repo.addHighlight(
      bookId: 'b1',
      cfiRange: 'epubcfi(/6/4!/4/2,/1:0,/1:20)',
      color: AnnotationColor.green,
      quotedText: '湖海',
    );

    final updates = <List<Annotation>>[];
    final gotFirst = Completer<void>();
    final sub = repo.watchForBook('b1').listen((rows) {
      updates.add(rows);
      if (!gotFirst.isCompleted) gotFirst.complete();
    });
    await gotFirst.future;
    await repo.remove(a.id);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    expect(updates.last, isEmpty);
    final dbRow = await db.annotationDao.getById(a.id);
    expect(dbRow.deletedAt, isNotNull);

    final ops = await db.select(db.syncOps).get();
    expect(ops.last.op, 'delete');
  });

  test('书签：新增/删除/列表，sync_ops 同事务', () async {
    final bm = await repo.addBookmark(
      bookId: 'b1',
      locatorJson: '{"v":1,"cfi":"epubcfi(/6/4!/4:0)","href":"OEBPS/ch1.xhtml"}',
    );

    var rows = await repo.listBookmarks('b1');
    expect(rows, hasLength(1));
    expect(rows.single.locator, contains('epubcfi'));

    await repo.removeBookmark(bm.id);
    expect(await repo.listBookmarks('b1'), isEmpty);

    final ops = await db.select(db.syncOps).get();
    expect(ops.map((o) => o.entity), ['bookmark', 'bookmark']);
    expect(ops.last.op, 'delete');
  });
}
