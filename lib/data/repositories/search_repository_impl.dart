/// 全书检索仓储实现：FTS5 trigram + 短查询 LIKE 降级 + 索引缺失懒重建。
library;

import 'dart:io';

import 'package:drift/drift.dart';

import '../../core/db/app_database.dart';
import '../../data/parsers/epub/epub_parser.dart';
import '../../domain/repositories/book_repository.dart';
import '../../domain/repositories/search_repository.dart';

/// 生产实现。book_fts 为派生数据，不参与同步。
class SearchRepositoryImpl implements SearchRepository {
  /// 构造：注入数据库与书籍仓储（懒重建时取书源文件）。
  SearchRepositoryImpl({required AppDatabase db, required BookRepository books})
      : _db = db,
        _books = books;

  final AppDatabase _db;
  final BookRepository _books;

  @override
  Future<void> indexBook(
    String bookId,
    List<(int, String, String, String)> chapters,
  ) async {
    await _db.transaction(() async {
      await _db.customStatement(
        'DELETE FROM book_fts WHERE book_id = ?',
        [bookId],
      );
      for (final (idx, href, title, body) in chapters) {
        if (body.isEmpty) continue;
        await _db.customInsert(
          'INSERT INTO book_fts(book_id, chapter_idx, href, title, body) '
          'VALUES(?, ?, ?, ?, ?)',
          variables: [
            Variable(bookId),
            Variable(idx),
            Variable(href),
            Variable(title),
            Variable(body),
          ],
        );
      }
    });
  }

  @override
  Future<bool> hasIndex(String bookId) async {
    final rows = await _db.customSelect(
      'SELECT COUNT(*) AS n FROM book_fts WHERE book_id = ?',
      variables: [Variable(bookId)],
    ).get();
    return (rows.first.data['n'] as int? ?? 0) > 0;
  }

  @override
  Future<List<BookSearchHit>> search({
    required String bookId,
    required String query,
    int limit = 50,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    await _ensureIndexed(bookId);

    final hits = <BookSearchHit>[];
    // FTS5 trigram 只能命中 >=3 字查询；更短的查询降级 LIKE 扫描
    //（书内检索数据量小，可接受）。
    if (q.runes.length >= 3) {
      // SQLite 里双引号是标识符，字符串字面量必须单引号
      const snippetArg = '\u3010';
      const snippetEnd = '\u3011';
      final rows = await _db.customSelect(
        'SELECT chapter_idx, href, title, '
        "snippet(book_fts, 4, '$snippetArg', '$snippetEnd', '…', 12) AS snip "
        'FROM book_fts WHERE book_fts MATCH ? AND book_id = ? '
        'ORDER BY rank LIMIT ?',
        variables: [Variable(q), Variable(bookId), Variable(limit)],
      ).get();
      for (final row in rows) {
        hits.add(BookSearchHit(
          chapterIdx: row.data['chapter_idx'] as int,
          href: row.data['href'] as String,
          chapterTitle: (row.data['title'] as String?) ?? '',
          snippet: (row.data['snip'] as String?) ?? '',
        ));
      }
      return hits;
    }

    // LIKE 降级：手工截取命中上下文
    final rows = await _db.customSelect(
      'SELECT chapter_idx, href, title, body FROM book_fts '
      'WHERE book_id = ? ORDER BY chapter_idx',
      variables: [Variable(bookId)],
    ).get();
    for (final row in rows) {
      final body = row.data['body'] as String? ?? '';
      final lowerBody = body.toLowerCase();
      final lowerQ = q.toLowerCase();
      final idx = lowerBody.indexOf(lowerQ);
      if (idx < 0) continue;
      final start = (idx - 20).clamp(0, body.length);
      final end = (idx + q.length + 20).clamp(0, body.length);
      final snip = body.substring(start, end);
      hits.add(BookSearchHit(
        chapterIdx: row.data['chapter_idx'] as int,
        href: row.data['href'] as String,
        chapterTitle: (row.data['title'] as String?) ?? '',
        snippet: snip.replaceRange(
          idx - start,
          idx - start + q.length,
          '\u3010${body.substring(idx, idx + q.length)}\u3011',
        ),
      ));
      if (hits.length >= limit) break;
    }
    return hits;
  }

  /// 索引缺失时从书源文件懒重建（旧版本导入的书没有 FTS 行）。
  /// 懒重建走 isolate，避免大书阻塞 UI。
  Future<void> _ensureIndexed(String bookId) async {
    if (await hasIndex(bookId)) return;
    final book = await _books.getById(bookId);
    if (book == null) return;
    final bytes = await File(book.filePath).readAsBytes();
    final parsed = await parseEpubInIsolate(bytes, book.title);
    await indexBook(
      bookId,
      [
        for (final c in parsed.chapters)
          (c.idx, c.href, c.title, c.bodyText),
      ],
    );
  }
}
