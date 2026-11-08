/// 全书检索仓储单测：trigram 中文检索、snippet、短查询 LIKE 降级、懒重建。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qy_reader/core/db/app_database.dart';
import 'package:qy_reader/data/repositories/search_repository_impl.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/domain/repositories/book_repository.dart';
import 'package:qy_reader/domain/repositories/search_repository.dart';

/// 恒返回 null 书籍的 BookRepository 桩（懒重建不触发路径）。
class _NullBooks implements BookRepository {
  @override
  Future<Book?> getById(String bookId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late SearchRepository repo;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    db = AppDatabase(NativeDatabase.memory());
    repo = SearchRepositoryImpl(db: db, books: _NullBooks());
  });

  tearDown(() async => db.close());

  Future<void> seed() => repo.indexBook('b1', [
        (0, 'OEBPS/ch1.xhtml', '第一章', '山川湖海，日月星辰。天地玄黄，宇宙洪荒。'),
        (1, 'OEBPS/ch2.xhtml', '第二章', '寒来暑往，秋收冬藏。闰余成岁，律吕调阳。'),
      ]);

  test('indexBook + 中文长查询命中并带章节信息', () async {
    await seed();
    expect(await repo.hasIndex('b1'), isTrue);

    final hits = await repo.search(bookId: 'b1', query: '山川湖海');
    expect(hits, hasLength(1));
    expect(hits.single.chapterIdx, 0);
    expect(hits.single.href, 'OEBPS/ch1.xhtml');
    expect(hits.single.snippet, contains('山川湖海'));
  });

  test('重复 indexBook 覆盖旧索引', () async {
    await seed();
    await repo.indexBook('b1', [
      (0, 'OEBPS/x.xhtml', '新章', '新的正文内容。'),
    ]);
    final hits = await repo.search(bookId: 'b1', query: '山川湖海');
    expect(hits, isEmpty);
    expect(await repo.search(bookId: 'b1', query: '新的正文'), hasLength(1));
  });

  test('三字以上查询走 FTS snippet 路径不抛 SQL 异常', () async {
    await seed();
    // 回归：snippet() 的字符串参数曾用双引号（SQLite 视为标识符）报错
    final hits = await repo.search(bookId: 'b1', query: '日月星辰');
    expect(hits, hasLength(1));
    expect(hits.single.snippet, contains('【日月星辰】'));
  });

  test('两字短查询降级 LIKE 路径仍可命中', () async {
    await seed();
    final hits = await repo.search(bookId: 'b1', query: '寒来');
    expect(hits, hasLength(1));
    expect(hits.single.chapterIdx, 1);
    expect(hits.single.snippet, contains('【寒来】'));
  });

  test('未命中返回空；空查询返回空', () async {
    await seed();
    expect(await repo.search(bookId: 'b1', query: '不存在的词组'), isEmpty);
    expect(await repo.search(bookId: 'b1', query: '  '), isEmpty);
  });

  test('hasIndex=false 时不崩（懒重建由上层触发，桩返回 null 直接跳过）', () async {
    expect(await repo.hasIndex('nope'), isFalse);
    expect(await repo.search(bookId: 'nope', query: '山川湖海'), isEmpty);
  });
}
