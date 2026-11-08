/// 标注（划线/笔记）DAO。
library;

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'annotation_dao.g.dart';

/// 标注相关查询（墓碑行一律过滤，同步合并在数据层实现做）。
@DriftAccessor(tables: [Annotations])
class AnnotationDao extends DatabaseAccessor<AppDatabase>
    with _$AnnotationDaoMixin {
  /// 构造。
  AnnotationDao(super.db);

  /// 监听某本书的标注（按创建时间倒序，列表/导出用）。
  Stream<List<AnnotationRow>> watchForBook(String bookId) =>
      (select(annotations)
            ..where((r) => r.bookId.equals(bookId))
            ..where((r) => r.deletedAt.isNull())
            ..orderBy([
              (r) => OrderingTerm.desc(r.createdAt),
            ]))
          .watch();

  /// 查询某本书的标注。
  Future<List<AnnotationRow>> listForBook(String bookId) =>
      (select(annotations)
            ..where((r) => r.bookId.equals(bookId))
            ..where((r) => r.deletedAt.isNull())
            ..orderBy([
              (r) => OrderingTerm.desc(r.createdAt),
            ]))
          .get();

  /// 按 id 查询。
  Future<AnnotationRow> getById(String id) =>
      (select(annotations)..where((r) => r.id.equals(id))).getSingle();

  /// 覆盖写入（主键冲突即整行更新）。仅用于新增路径；
  /// 局部/可空字段更新走 [writeById]（insertOnConflictUpdate 的冲突更新
  /// 会把 null 值列标记 absent 不写入，无法清空可空字段）。
  Future<void> upsert(AnnotationRow row) =>
      into(annotations).insertOnConflictUpdate(row);

  /// 按 id 全列更新（companion 显式携带 null，用于清空可空字段/软删）。
  Future<void> writeById(String id, AnnotationsCompanion c) =>
      (update(annotations)..where((r) => r.id.equals(id))).write(c);
}

/// 书签 DAO。
@DriftAccessor(tables: [Bookmarks])
class BookmarkDao extends DatabaseAccessor<AppDatabase>
    with _$BookmarkDaoMixin {
  /// 构造。
  BookmarkDao(super.db);

  /// 监听某本书的书签（新在前）。
  Stream<List<BookmarkRow>> watchForBook(String bookId) =>
      (select(bookmarks)
            ..where((r) => r.bookId.equals(bookId))
            ..where((r) => r.deletedAt.isNull())
            ..orderBy([
              (r) => OrderingTerm.desc(r.createdAt),
            ]))
          .watch();

  /// 查询某本书的书签。
  Future<List<BookmarkRow>> listForBook(String bookId) =>
      (select(bookmarks)
            ..where((r) => r.bookId.equals(bookId))
            ..where((r) => r.deletedAt.isNull())
            ..orderBy([
              (r) => OrderingTerm.desc(r.createdAt),
            ]))
          .get();

  /// 按 id 查询。
  Future<BookmarkRow> getById(String id) =>
      (select(bookmarks)..where((r) => r.id.equals(id))).getSingle();

  /// 覆盖写入（新增路径用）。
  Future<void> upsert(BookmarkRow row) =>
      into(bookmarks).insertOnConflictUpdate(row);

  /// 按 id 全列更新（软删用）。
  Future<void> writeById(String id, BookmarksCompanion c) =>
      (update(bookmarks)..where((r) => r.id.equals(id))).write(c);
}
