/// 作者分组纯逻辑：按作者归组、排序与搜索过滤。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/settings/author_groups.dart';

ShelfItem _item(String id, String title, {String? author}) {
  return ShelfItem(
    book: Book(
      id: id,
      title: title,
      author: author,
      format: BookFormat.epub,
      filePath: '/books/$id.epub',
      fileSha256: 'sha-$id',
      fileSize: 1000,
      chapterCount: 1,
      wordCount: 100,
      addedAt: DateTime(2026, 1, 1).millisecondsSinceEpoch,
      updatedAt: DateTime(2026, 1, 1).millisecondsSinceEpoch,
      hlc: 'hlc',
      deviceId: 'dev',
    ),
  );
}

void main() {
  test('按作者归组：同名（含空白差异）合并，null 作者进未知组', () {
    final groups = groupBooksByAuthor([
      _item('1', '三体', author: ' 刘慈欣 '),
      _item('2', '球状闪电', author: '刘慈欣'),
      _item('3', '嫌疑人X的献身', author: '东野圭吾'),
      _item('4', '无名之书'),
      _item('5', '又一本书', author: '   '),
    ]);

    expect(groups.length, 3);
    expect(groups.map((g) => g.key).toList(), ['', '刘慈欣', '东野圭吾']);
    expect(groups[0].isUnknown, isTrue);
    expect(groups[0].displayName, '未知作者');
    expect(groups[0].books.length, 2);
    expect(groups[1].books.length, 2);
    expect(groups[2].books.length, 1);
  });

  test('排序：未知作者最前，其余按书数降序，同数按名字排', () {
    final groups = groupBooksByAuthor([
      _item('1', 'a1', author: '乙'),
      _item('2', 'a2', author: '乙'),
      _item('3', 'a3', author: '乙'),
      _item('4', 'b1', author: '甲'),
      _item('5', 'b2', author: '甲'),
      _item('6', 'c1', author: '丙'),
      _item('7', 'u1'),
    ]);

    expect(groups.map((g) => g.displayName).toList(), [
      '未知作者',
      '乙',
      '甲',
      '丙',
    ]);
  });

  test('空书架返回空列表', () {
    expect(groupBooksByAuthor(const []), isEmpty);
  });

  test('搜索过滤：作者名命中保留整组', () {
    final groups = groupBooksByAuthor([
      _item('1', '三体', author: '刘慈欣'),
      _item('2', '嫌疑人X的献身', author: '东野圭吾'),
    ]);

    final matched = filterAuthorGroups(groups, '东野');
    expect(matched.length, 1);
    expect(matched[0].key, '东野圭吾');
    expect(matched[0].books.length, 1);
  });

  test('搜索过滤：书名命中也能带出该作者整组', () {
    final groups = groupBooksByAuthor([
      _item('1', '三体', author: '刘慈欣'),
      _item('2', '球状闪电', author: '刘慈欣'),
      _item('3', '嫌疑人X的献身', author: '东野圭吾'),
    ]);

    final matched = filterAuthorGroups(groups, '球状');
    expect(matched.length, 1);
    expect(matched[0].books.length, 2);
  });

  test('搜索过滤：关键字去空白、忽略大小写；无命中返回空', () {
    final groups = groupBooksByAuthor([
      _item('1', 'The Trilogy', author: 'Author A'),
    ]);

    expect(filterAuthorGroups(groups, '  author a ').length, 1);
    expect(filterAuthorGroups(groups, 'the '), hasLength(1));
    expect(filterAuthorGroups(groups, '不存在的作者'), isEmpty);
  });
}
