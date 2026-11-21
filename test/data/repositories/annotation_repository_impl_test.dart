/// 标注与书签仓储单测：内存库 + sync_ops 同事务断言。
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qy_reader/core/db/app_database.dart';
import 'package:qy_reader/core/hlc.dart';
import 'package:qy_reader/core/locator.dart';
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

  test('watchAll / watchAllBookmarks 返回全库未删除笔记', () async {
    final a1 = await repo.addHighlight(
      bookId: 'b1',
      cfiRange: 'epubcfi(/6/4!/4/2,/1:0,/1:20)',
      color: AnnotationColor.yellow,
      quotedText: '山川湖海',
    );
    await repo.addHighlight(
      bookId: 'b2',
      cfiRange: 'epubcfi(/6/4!/4/2,/1:0,/1:20)',
      color: AnnotationColor.blue,
      quotedText: '日月星辰',
    );
    await repo.addBookmark(bookId: 'b1', locatorJson: '{}', label: '这里');
    await repo.remove(a1.id);

    final all = await repo.watchAll().first;
    expect(all, hasLength(1));
    expect(all.single.bookId, 'b2');
    final marks = await repo.watchAllBookmarks().first;
    expect(marks, hasLength(1));
    expect(marks.single.label, '这里');
  });

  test('addHighlight 可创建下划线类型', () async {
    final a = await repo.addHighlight(
      bookId: 'b1',
      cfiRange: '',
      color: AnnotationColor.blue,
      quotedText: '下划线',
      chapterIndex: 0,
      offset: 1,
      offsetEnd: 3,
      type: AnnotationType.underline,
    );
    expect(a.type, AnnotationType.underline);
    final rows = await repo.listForBook('b1');
    expect(rows.single.type, AnnotationType.underline);
    final op = await db.select(db.syncOps).getSingle();
    expect(op.payload, contains('"type":"underline"'));
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

  test('setAnchor 同时更新起点/终点（覆盖导入匹配笔记用）', () async {
    final a = await repo.addHighlight(
      bookId: 'b1',
      cfiRange: 'epubcfi(/6/4!/4/2,/1:0,/1:20)',
      color: AnnotationColor.yellow,
      quotedText: '山川湖海',
      chapterIndex: 0,
    );
    final anchor = locatorToJson(
      const Locator(
        href: 'c1.xhtml',
        chapterIndex: 1,
        offset: 3,
        offsetEnd: 12,
      ),
    );

    await repo.setAnchor(a.id, anchor, locatorEnd: anchor);

    final row = (await repo.listForBook('b1')).single;
    expect(row.locatorStart, anchor);
    expect(row.locatorEnd, anchor);
    expect(row.chapterIndex, 1);
    expect(row.href, 'c1.xhtml');
    final op = (await db.select(db.syncOps).get()).last;
    expect(op.payload, contains('"locatorEnd"'));
    expect(op.payload, contains('c1.xhtml'));
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

  test('书签：新增/删除/列表，备注随 sync_ops 落库', () async {
    final bm = await repo.addBookmark(
      bookId: 'b1',
      locatorJson:
          '{"v":1,"cfi":"epubcfi(/6/4!/4:0)","href":"OEBPS/ch1.xhtml"}',
      label: '这一页很重要',
    );

    var rows = await repo.listBookmarks('b1');
    expect(rows, hasLength(1));
    expect(rows.single.locator, contains('epubcfi'));
    expect(rows.single.label, '这一页很重要');

    final ops = await db.select(db.syncOps).get();
    expect(ops.single.entity, 'bookmark');
    expect(ops.single.op, 'upsert');
    expect(ops.single.payload, contains('这一页很重要'));

    await repo.removeBookmark(bm.id);
    expect(await repo.listBookmarks('b1'), isEmpty);

    final allOps = await db.select(db.syncOps).get();
    expect(allOps.map((o) => o.entity), ['bookmark', 'bookmark']);
    expect(allOps.last.op, 'delete');
  });
}
