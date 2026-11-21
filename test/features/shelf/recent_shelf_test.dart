/// 竖排书架组件单测：布局不溢出 + 交互回调。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/widgets/pressable_scale.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/shelf/widgets/recent_shelf.dart';

Book _book(String id, String title) => Book(
  id: id,
  title: title,
  format: BookFormat.epub,
  filePath: '/tmp/$id.epub',
  fileSha256: id,
  fileSize: 1,
  addedAt: 0,
  updatedAt: 0,
  lastOpenedAt: 1,
  hlc: '0000000000000-00000-aaaaaaaa',
  deviceId: 'aaaaaaaa',
);

ShelfItem _item(String id, String title) =>
    ShelfItem(book: _book(id, title), percent: 0.35);

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SafeArea(child: child)),
);

void main() {
  testWidgets('中英文/超长书名都能立起来，不溢出', (tester) async {
    final items = [
      _item('a', '最重要的事，只有一件'),
      _item('b', 'A Very Long English Book Title That Should Rotate'),
      _item('c', '一个特别特别特别特别特别特别长的中文书名用来测试截断'),
      _item('d', '海子诗选'),
    ];
    await tester.pumpWidget(
      _host(
        RecentShelf(
          items: items,
          onOpen: (_) {},
          onManage: (_) {},
          onHide: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('最近在读'), findsOneWidget);
    expect(find.text('4 本'), findsOneWidget);
    expect(find.byType(PressableScale), findsWidgets);
  });

  testWidgets('点书脊打开对应书籍，长按进入管理', (tester) async {
    Book? opened;
    Book? managed;
    final items = [_item('a', '第一本'), _item('b', '第二本')];
    await tester.pumpWidget(
      _host(
        RecentShelf(
          items: items,
          onOpen: (book) => opened = book,
          onManage: (book) => managed = book,
          onHide: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PressableScale).last);
    expect(opened?.id, 'b');

    await tester.longPress(find.byType(PressableScale).first);
    expect(managed?.id, 'a');
  });

  testWidgets('书少时整排居中，不会贴着左边', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final items = [_item('a', '第一本'), _item('b', '第二本')];
    await tester.pumpWidget(
      _host(
        RecentShelf(
          items: items,
          onOpen: (_) {},
          onManage: (_) {},
          onHide: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final spines = find.byType(PressableScale);
    expect(spines, findsNWidgets(2));
    final left = tester.getRect(spines.first).left;
    final right = tester.getRect(spines.last).right;
    expect((left + right) / 2, closeTo(195, 1));
    expect(left, greaterThan(20), reason: '居中后左侧应留出空白');
    expect(right, lessThan(370), reason: '居中后右侧应留出空白');
  });

  testWidgets('收起按钮与恢复入口都回调', (tester) async {
    var hidden = 0;
    await tester.pumpWidget(
      _host(
        RecentShelf(
          items: [for (var i = 0; i < 6; i++) _item('b$i', '书$i')],
          onOpen: (_) {},
          onManage: (_) {},
          onHide: () => hidden++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('隐藏最近在读'));
    expect(hidden, 1);

    var shown = 0;
    await tester.pumpWidget(
      _host(CollapsedRecentShelf(count: 6, onShow: () => shown++)),
    );
    await tester.pumpAndSettle();
    expect(find.text('最近在读 · 6 本'), findsOneWidget);
    await tester.tap(find.text('最近在读 · 6 本'));
    expect(shown, 1);
  });
}
