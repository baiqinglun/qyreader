/// 分片导出/应用往返：只包含这一本书的行。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/db/app_database.dart';
import 'package:qy_reader/data/sync/book_shard.dart';

BooksCompanion _book(String id) => BooksCompanion.insert(
      id: id,
      title: '书$id',
      format: 'epub',
      filePath: '/tmp/$id.epub',
      fileSha256: 'sha-$id',
      fileSize: 1,
      chapterCount: const Value(1),
      wordCount: const Value(1),
      addedAt: 1,
      updatedAt: 1,
      hlc: '1',
      deviceId: 'dev',
    );

void main() {
  test('导出的分片只带这本书，应用回来数据一致', () async {
    final source = AppDatabase(NativeDatabase.memory());
    final target = AppDatabase(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(target.close);

    await source.into(source.books).insert(_book('a'));
    await source.into(source.books).insert(_book('b'));
    await source.into(source.annotations).insert(
          AnnotationsCompanion.insert(
            id: 'ann-a',
            bookId: 'a',
            type: 'highlight',
            color: 'yellow',
            locatorStart: '{}',
            locatorEnd: '{}',
            createdAt: 2,
            updatedAt: 2,
            hlc: '2',
            deviceId: 'dev',
          ),
        );

    final shard = await BookShard.export(source, 'a');
    final rows = (shard['books'] as List).cast<Map<String, dynamic>>();
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'a');
    expect((shard['annotations'] as List), hasLength(1));

    await BookShard.apply(target, BookShard.decode(BookShard.encode(shard))!);
    final books = await target.customSelect('SELECT id FROM books').get();
    expect(books.map((r) => r.data['id']), ['a']);
    final anns = await target.customSelect('SELECT id FROM annotations').get();
    expect(anns.map((r) => r.data['id']), ['ann-a']);
  });

  test('坏分片解码返回 null', () {
    expect(BookShard.decode([1, 2, 3]), isNull);
  });
}
