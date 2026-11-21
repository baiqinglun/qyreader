/// 书架长按菜单：覆盖导入入口。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/shelf/widgets/book_actions_sheet.dart';

Book _book() => const Book(
  id: 'b1',
  title: '占位书',
  author: '张三',
  format: BookFormat.epub,
  filePath: '/tmp/b1.epub',
  fileSha256: 'abc',
  fileSize: 1024,
  addedAt: 0,
  updatedAt: 0,
  hlc: '0000000000000-00000-aaaaaaaa',
  deviceId: 'aaaaaaaa',
);

void main() {
  testWidgets('书籍长按菜单支持添加和取消收藏', (tester) async {
    BookShelfAction? result;
    var book = _book();
    Future<void> open() async {
      result = await showBookActionsSheet(
        tester.element(find.text('打开')),
        book: book,
      );
    }

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: TextButton(onPressed: open, child: const Text('打开')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('添加到收藏'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('添加到收藏'));
    await tester.pumpAndSettle();
    expect(result, BookShelfAction.favorite);
    book = book.copyWith(isFavorite: true);
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('取消收藏'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('取消收藏'), findsOneWidget);
  });

  testWidgets('长按菜单有「覆盖导入」并返回对应动作', (tester) async {
    BookShelfAction? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showBookActionsSheet(context, book: _book());
                },
                child: const Text('打开菜单'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开菜单'));
    await tester.pumpAndSettle();
    expect(find.text('覆盖导入'), findsOneWidget);
    expect(find.text('分享书籍'), findsOneWidget);
    expect(find.text('用新文件替换正文，保留笔记与进度'), findsNothing);

    await tester.tap(find.text('覆盖导入'));
    await tester.pumpAndSettle();
    expect(result, BookShelfAction.overwriteImport);
  });

  testWidgets('长按菜单有「导出 / 导入阅读数据」并返回对应动作', (tester) async {
    BookShelfAction? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showBookActionsSheet(context, book: _book());
                },
                child: const Text('打开菜单'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开菜单'));
    await tester.pumpAndSettle();
    expect(find.text('导出阅读数据'), findsOneWidget);
    expect(find.text('导入阅读数据'), findsOneWidget);

    await tester.tap(find.text('导出阅读数据'));
    await tester.pumpAndSettle();
    expect(result, BookShelfAction.exportData);

    await tester.tap(find.text('打开菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入阅读数据'));
    await tester.pumpAndSettle();
    expect(result, BookShelfAction.importData);
  });
}
