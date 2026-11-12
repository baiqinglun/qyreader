/// 书架/书籍查询 DAO。
library;

import 'package:drift/drift.dart';

import '../../locator.dart';
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
  ///
  /// 优先用 Locator.pos（页级位置）：percent 受 locations 分块量化，
  /// 短书/短章里连续多页都会是 0，书架会误显示“未读”。
  double get percent {
    final raw = progress?.locator;
    if (raw != null) {
      final pos = locatorFromJson(raw)?.pos;
      if (pos != null && pos > 0) return pos.clamp(0.0, 1.0);
    }
    return progress?.percent ?? 0;
  }
}

/// 书籍相关查询。
@DriftAccessor(tables: [Books, ReadingProgress, Chapters])
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
          // 置顶优先（最近置顶在前），再按最近打开，最后按入库时间
          final aPin = a.book.pinnedAt ?? 0;
          final bPin = b.book.pinnedAt ?? 0;
          if (aPin != bPin) return bPin - aPin;
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

  /// 查询章节目录（idx 升序）。
  Future<List<ChapterRow>> getChapters(String bookId) =>
      (select(chapters)..where((c) => c.bookId.equals(bookId)))
          .get()
          .then((rows) => rows..sort((a, b) => a.idx - b.idx));

  /// 更新最近打开时间。
  Future<void> touchOpened(String id, int at) =>
      (update(books)..where((b) => b.id.equals(id)))
          .write(BooksCompanion(lastOpenedAt: Value(at)));
}
