/// 书架排序：书名 / 导入时间 / 最近阅读，升降序与置顶优先。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/shelf/shelf_controller.dart';
import 'package:qy_reader/features/shelf/shelf_prefs.dart';

ShelfItem _item(
  String id, {
  String? title,
  int added = 0,
  int? opened,
  int? pinned,
}) =>
    ShelfItem(
      book: Book(
        id: id,
        title: title ?? id,
        format: BookFormat.epub,
        filePath: '/tmp/$id.epub',
        fileSha256: id,
        fileSize: 1,
        addedAt: added,
        updatedAt: 0,
        lastOpenedAt: opened,
        pinnedAt: pinned,
        hlc: '0000000000000-00000-aaaaaaaa',
        deviceId: 'aaaaaaaa',
      ),
    );

List<String> _ids(List<ShelfItem> items) => [for (final i in items) i.book.id];

void main() {
  final items = [
    _item('b', title: 'Beta', added: 20, opened: 200),
    _item('a', title: 'alpha', added: 10, opened: 100),
    _item('c', title: 'Gamma', added: 30),
  ];

  test('书名升序 / 降序（忽略大小写）', () {
    expect(
      _ids(sortShelfItems(items,
          field: ShelfSortField.title, ascending: true)),
      ['a', 'b', 'c'],
    );
    expect(
      _ids(sortShelfItems(items,
          field: ShelfSortField.title, ascending: false)),
      ['c', 'b', 'a'],
    );
  });

  test('导入时间升序 / 降序', () {
    expect(
      _ids(sortShelfItems(items,
          field: ShelfSortField.added, ascending: true)),
      ['a', 'b', 'c'],
    );
    expect(
      _ids(sortShelfItems(items,
          field: ShelfSortField.added, ascending: false)),
      ['c', 'b', 'a'],
    );
  });

  test('最近阅读降序，没读过的排最后', () {
    expect(
      _ids(sortShelfItems(items,
          field: ShelfSortField.lastOpened, ascending: false)),
      ['b', 'a', 'c'],
    );
  });

  test('置顶始终在最前，不参与升序 / 降序', () {
    final pinned = [
      ...items,
      _item('p', title: 'zzz', added: 1, opened: 1, pinned: 999),
    ];
    for (final ascending in [true, false]) {
      final sorted = sortShelfItems(
        pinned,
        field: ShelfSortField.title,
        ascending: ascending,
      );
      expect(_ids(sorted).first, 'p');
    }
  });
}
