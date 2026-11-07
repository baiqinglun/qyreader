/// 阅读进度 DAO。
library;

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'progress_dao.g.dart';

/// 进度相关查询。
@DriftAccessor(tables: [ReadingProgress])
class ProgressDao extends DatabaseAccessor<AppDatabase>
    with _$ProgressDaoMixin {
  /// 构造。
  ProgressDao(super.db);

  /// 监听某本书的进度。
  Stream<ReadingProgressRow?> watchForBook(String bookId) =>
      (select(readingProgress)..where((r) => r.bookId.equals(bookId)))
          .watchSingleOrNull();

  /// 查询某本书的进度。
  Future<ReadingProgressRow?> getForBook(String bookId) =>
      (select(readingProgress)..where((r) => r.bookId.equals(bookId)))
          .getSingleOrNull();

  /// 覆盖写入进度（主键冲突即整行更新；furthest 的 max 合并在上层做）。
  Future<void> upsert(ReadingProgressRow row) =>
      into(readingProgress).insertOnConflictUpdate(row);
}
