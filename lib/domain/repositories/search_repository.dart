/// 全书检索仓储接口（领域层）。
///
/// 索引为派生数据（可由书籍文件重建），不参与同步。
library;

/// 一条检索命中。
class BookSearchHit {
  const BookSearchHit({
    required this.chapterIdx,
    required this.href,
    required this.chapterTitle,
    required this.snippet,
  });

  /// 章序号。
  final int chapterIdx;

  /// 章 href（跳转用）。
  final String href;

  /// 章标题。
  final String chapterTitle;

  /// 命中上下文片段。
  final String snippet;
}

/// 全书检索。
abstract interface class SearchRepository {
  /// 重建某本书的检索索引（导入时与索引缺失兜底共用）。
  Future<void> indexBook(
    String bookId,

    /// (章序号, 章 href, 章标题, 章正文)。
    List<(int, String, String, String)> chapters,
  );

  /// 某本书是否已有索引。
  Future<bool> hasIndex(String bookId);

  /// 全书检索。
  ///
  /// FTS5 trigram 对 <3 字查询无命中，短查询自动降级 LIKE 扫描。
  Future<List<BookSearchHit>> search({
    required String bookId,
    required String query,
    int limit,
  });
}
