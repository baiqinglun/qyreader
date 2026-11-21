/// 层级分类：建树 / 计数 / 折叠展平 / 子树改名与删除的纯函数回归。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/settings/category_tree.dart';

ShelfItem _item(String id, String category) => ShelfItem(
  book: Book(
    id: id,
    title: '书$id',
    format: BookFormat.epub,
    filePath: '/tmp/$id.epub',
    fileSha256: id,
    fileSize: 1,
    addedAt: 0,
    updatedAt: 0,
    category: category,
    hlc: '0000000000000-00000-aaaaaaaa',
    deviceId: 'aaaaaaaa',
  ),
  percent: 0,
);

void main() {
  test('建树：层级嵌套、计数含后代、子分类按名称排序', () {
    final tree = buildCategoryTree(items: [
      _item('b1', '小说'),
      _item('b2', '小说/科幻'),
      _item('b3', '小说/科幻'),
      _item('b4', '小说/中国文学'),
      _item('b5', '文学'),
    ]);

    expect(tree, hasLength(2)); // 小说 / 文学
    final fiction = tree.first;
    expect(fiction.path, '小说');
    expect(fiction.name, '小说');
    expect(fiction.directCount, 1); // 直接挂在小说
    expect(fiction.totalCount, 4); // 1 + 科幻2 + 中国文学1
    expect(fiction.hasChildren, isTrue);

    // 子分类按名称排序：中国文学(U+4E2D) < 科幻(U+79E1)
    expect(fiction.children.map((c) => c.name).toList(), ['中国文学', '科幻']);
    expect(fiction.children[1].path, '小说/科幻');
    expect(fiction.children[1].directCount, 2);
    expect(fiction.children[1].totalCount, 2);
    expect(fiction.children[1].depth, 1);

    expect(tree.last.path, '文学');
    expect(tree.last.totalCount, 1);
    expect(tree.last.hasChildren, isFalse);
  });

  test('空分类（extraPaths）也能建树，计数为 0', () {
    final tree = buildCategoryTree(
      items: [_item('b1', '小说')],
      extraPaths: const ['沟通表达', '小说/短篇'],
    );
    expect(tree.map((n) => n.name), contains('沟通表达'));
    final empty = tree.firstWhere((n) => n.name == '沟通表达');
    expect(empty.totalCount, 0);
    // 小说多了个空子分类
    final fiction = tree.first;
    expect(fiction.totalCount, 1);
    expect(fiction.children.map((c) => c.name), contains('短篇'));
  });

  test('categoryUnderPath / renameCategoryPath', () {
    expect(categoryUnderPath('小说/科幻', '小说'), isTrue);
    expect(categoryUnderPath('小说', '小说'), isTrue);
    expect(categoryUnderPath('文学', '小说'), isFalse);
    // 前缀不能是半截字：'小说家' 不在 '小说' 子树内
    expect(categoryUnderPath('小说家', '小说'), isFalse);

    expect(
      renameCategoryPath('小说/科幻', '小说', 'Story'),
      'Story/科幻',
    );
    expect(renameCategoryPath('文学', '小说', 'Story'), '文学');
  });

  test('flattenCategoryTree：折叠隐藏子级，搜索只留匹配节点', () {
    final tree = buildCategoryTree(items: [
      _item('b1', '小说'),
      _item('b2', '小说/科幻'),
      _item('b3', '文学'),
    ]);

    // 全部展开
    final all = flattenCategoryTree(tree, {}, null);
    expect(all.map((n) => n.name).toList(), ['小说', '科幻', '文学']);

    // 折叠小说：科幻隐藏
    final collapsed = flattenCategoryTree(tree, {'小说'}, null);
    expect(collapsed.map((n) => n.name).toList(), ['小说', '文学']);

    // 搜索：只留匹配（路径包含）
    final searched = flattenCategoryTree(tree, {}, '科幻');
    expect(searched.map((n) => n.name).toList(), ['科幻']);
  });
}
