/// 书架/书籍查询 DAO。
library;

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'book_dao.g.dart';

/// 书架条目：书籍行 + 当前进度行（可能为 null，尚未读过）。
class ShelfEntry {
  /// 构造。
  ShelfEntry(this.book, this.progress);

  /// 书籍行。
  final BookRow book;

  /// 当前进度行。
  final ReadingProgressRow? progress;

  /// 展示用百分比 0..1。
  double get percent => progress?.percent ?? 0;
}

/// 书籍相关查询。
@DriftAccessor(tables: [Books, ReadingProgress])
class BookDao extends DatabaseAccessor<AppDatabase> with _$BookDaoMixin {
  /// 构造。
  BookDao(super.db);

  /// 监听书架（未删除书籍 + 进度联查），按最近打开降序、未打开按入库时间降序。
  Stream<List<ShelfEntry>> watchShelf() {
    final query = select(books).join([
      leftOuterJoin(readingProgress, readingProgress.bookId.equalsExp(books.id)),
    ]);
    return query.watch().map((rows) {
      final entries = rows
          .map((row) => ShelfEntry(
                row.readTable(books),
                row.readTableOrNull(readingProgress),
              ))
          .where((entry) => entry.book.deletedAt == null)
          .toList()
        ..sort((a, b) {
          final aOpened = a.book.lastOpenedAt ?? 0;
          final bOpened = b.book.lastOpenedAt ?? 0;
          if (aOpened != bOpened) return bOpened - aOpened;
          return b.book.addedAt - a.book.addedAt;
        });
      return entries;
    });
  }

  /// 按内容哈希查书（导入去重）。
  Future<BookRow?> findBySha256(String sha256) =>
      (select(books)..where((b) => b.fileSha256.equals(sha256)))
          .getSingleOrNull();

  /// 按 id 查书。
  Future<BookRow?> getById(String id) =>
      (select(books)..where((b) => b.id.equals(id))).getSingleOrNull();

  /// 更新最近打开时间。
  Future<void> touchOpened(String id, int at) =>
      (update(books)..where((b) => b.id.equals(id)))
          .write(BooksCompanion(lastOpenedAt: Value(at)));
}
