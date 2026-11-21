/// 重复书籍检测：强匹配 / 疑似匹配 / 作者开关 / 文件重复。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/settings/duplicate_books.dart';

Book _book(
  String id,
  String title, {
  String? author,
  String? category,
  int fileSize = 1000,
  int wordCount = 100,
  int addedAt = 1,
  String? sha,
}) {
  return Book(
    id: id,
    title: title,
    author: author,
    category: category,
    format: BookFormat.epub,
    filePath: '/books/$id.epub',
    fileSha256: sha ?? 'sha-$id',
    fileSize: fileSize,
    chapterCount: 1,
    wordCount: wordCount,
    addedAt: addedAt,
    updatedAt: addedAt,
    hlc: 'hlc',
    deviceId: 'dev',
  );
}

void main() {
  test('强匹配：忽略大小写、空白和扩展名', () {
    final groups = findDuplicateBookGroups([
      _book('1', 'The Hobbit'),
      _book('2', '  the   hobbit.epub '),
    ]);
    expect(groups, hasLength(1));
    expect(groups.single.strong, isTrue);
    expect(groups.single.books, hasLength(2));
  });

  test('疑似匹配：忽略括号、卷号、版本词与标点', () {
    final groups = findDuplicateBookGroups([
      _book('1', '血腥的盛唐'),
      _book('2', '血腥的盛唐（全7册）'),
      _book('3', '《血腥的盛唐》 第2版'),
    ]);
    expect(groups, hasLength(1));
    expect(groups.single.strong, isFalse);
    expect(groups.single.books, hasLength(3));
    expect(groups.single.displayTitle, '血腥的盛唐');
  });

  test('连续标点和书名号不影响疑似匹配', () {
    final groups = findDuplicateBookGroups([
      _book('1', '我们为什么要睡觉？'),
      _book('2', '我们为什么要睡觉?'),
    ]);
    expect(groups, hasLength(1));
    expect(groups.single.strong, isFalse);
  });

  test('同组内既有完全同名又有版本差异时，归为疑似匹配一组', () {
    final groups = findDuplicateBookGroups([
      _book('1', '喜鹊谋杀案'),
      _book('2', '喜鹊谋杀案'),
      _book('3', '喜鹊谋杀案（美国亚马逊年度好书）'),
    ]);
    expect(groups, hasLength(1));
    expect(groups.single.strong, isFalse);
    expect(groups.single.books, hasLength(3));
  });

  test('匹配作者开关：同名不同作者默认合并，开启后分开', () {
    final books = [
      _book('1', '同名书', author: '张三'),
      _book('2', '同名书', author: '李四'),
    ];
    expect(findDuplicateBookGroups(books), hasLength(1));
    expect(findDuplicateBookGroups(books, matchAuthor: true), isEmpty);
  });

  test('匹配作者：忽略作者空白与「著」后缀', () {
    final groups = findDuplicateBookGroups([
      _book('1', '同名书', author: '张三 著'),
      _book('2', '同名书', author: '张三'),
    ], matchAuthor: true);
    expect(groups, hasLength(1));
  });

  test('匹配作者：缺作者的书不参与分组', () {
    final groups = findDuplicateBookGroups([
      _book('1', '同名书'),
      _book('2', '同名书'),
    ], matchAuthor: true);
    expect(groups, isEmpty);
  });

  test('匹配范围过滤强 / 疑似', () {
    final groups = findDuplicateBookGroups([
      _book('1', '完全同名'),
      _book('2', '完全同名'),
      _book('3', '另一本'),
      _book('4', '另一本（全2册）'),
    ]);
    expect(
      filterDuplicateGroups(groups, DuplicateMatchScope.all),
      hasLength(2),
    );
    expect(
      filterDuplicateGroups(groups, DuplicateMatchScope.strong),
      hasLength(1),
    );
    expect(
      filterDuplicateGroups(groups, DuplicateMatchScope.suspected),
      hasLength(1),
    );
  });

  test('文件重复：相同 SHA-256 归为一组', () {
    final groups = findDuplicateFileGroups([
      _book('1', '第一本', sha: 'abc'),
      _book('2', '第二本', sha: 'abc'),
      _book('3', '第三本', sha: 'def'),
    ]);
    expect(groups, hasLength(1));
    expect(groups.single.strong, isTrue);
    expect(groups.single.type, DuplicateDetectType.file);
    expect(groups.single.books.map((b) => b.id), ['1', '2']);
  });

  test('保留建议：字数最多优先，其次文件最大', () {
    final group = findDuplicateBookGroups([
      _book('1', '测试书', wordCount: 100, fileSize: 9999),
      _book('2', '测试书', wordCount: 300, fileSize: 100),
      _book('3', '测试书', wordCount: 400, fileSize: 200),
    ]).single;
    expect(group.keepCandidate.id, '3');
    expect(group.mostWordsId, '3');
    expect(group.largestFileId, '1');
  });

  test('单个字 / 空标题不参与分组', () {
    expect(
      findDuplicateBookGroups([_book('1', '书'), _book('2', '书')]),
      isEmpty,
    );
    expect(findDuplicateBookGroups([_book('1', ''), _book('2', '')]), isEmpty);
  });
}
