/// 书架筛选：最低星级 + 标签（任一）+ 阅读状态（任一）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/shelf/shelf_filter.dart';

Book _book({
  int? rating,
  List<String> tags = const [],
  BookReadStatus readStatus = BookReadStatus.unread,
}) =>
    Book(
      id: 'b',
      title: '书',
      format: BookFormat.epub,
      filePath: '/tmp/b.epub',
      fileSha256: 'b',
      fileSize: 1,
      addedAt: 0,
      updatedAt: 0,
      rating: rating,
      tags: tags,
      readStatus: readStatus,
      hlc: '0000000000000-00000-aaaaaaaa',
      deviceId: 'aaaaaaaa',
    );

void main() {
  test('未设置条件时不筛选', () {
    const filter = ShelfFilter();
    expect(filter.active, isFalse);
    expect(filter.matches(_book()), isTrue);
  });

  test('最低星级', () {
    const filter = ShelfFilter(minRating: 4);
    expect(filter.active, isTrue);
    expect(filter.matches(_book(rating: 3)), isFalse);
    expect(filter.matches(_book(rating: 4)), isTrue);
    expect(filter.matches(_book(rating: 5)), isTrue);
    expect(filter.matches(_book()), isFalse);
  });

  test('标签命中任意一个', () {
    const filter = ShelfFilter(tags: {'心理学', '哲学'});
    expect(filter.matches(_book(tags: ['心理学'])), isTrue);
    expect(filter.matches(_book(tags: ['哲学', '小说'])), isTrue);
    expect(filter.matches(_book(tags: ['小说'])), isFalse);
    expect(filter.matches(_book()), isFalse);
  });

  test('阅读状态命中任意一个', () {
    const filter = ShelfFilter(
      statuses: {BookReadStatus.reading, BookReadStatus.finished},
    );
    expect(filter.active, isTrue);
    expect(
      filter.matches(_book(readStatus: BookReadStatus.reading)),
      isTrue,
    );
    expect(
      filter.matches(_book(readStatus: BookReadStatus.finished)),
      isTrue,
    );
    expect(
      filter.matches(_book(readStatus: BookReadStatus.unread)),
      isFalse,
    );
    expect(
      filter.matches(_book(readStatus: BookReadStatus.dropped)),
      isFalse,
    );
  });

  test('星级、标签和阅读状态同时生效', () {
    const filter = ShelfFilter(
      minRating: 4,
      tags: {'心理学'},
      statuses: {BookReadStatus.finished},
    );
    expect(
      filter.matches(
        _book(
          rating: 4,
          tags: ['心理学'],
          readStatus: BookReadStatus.finished,
        ),
      ),
      isTrue,
    );
    expect(
      filter.matches(
        _book(
          rating: 4,
          tags: ['心理学'],
          readStatus: BookReadStatus.reading,
        ),
      ),
      isFalse,
    );
  });
}
