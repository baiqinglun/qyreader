/// 书架批量操作弹层：标签解析、分组新建、删除选项。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/shelf/widgets/batch_actions.dart';

void main() {
  testWidgets('批量加标签：已有标签 + 逗号分隔的新标签', (tester) async {
    List<String>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showBatchTagSheet(
                  context,
                  count: 2,
                  knownTags: const ['心理学', '哲学'],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('batch-tag-known-心理学')));
    await tester.enterText(
      find.byKey(const ValueKey('batch-tag-input')),
      '科幻，历史 心理学',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('batch-tag-apply')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result, containsAll(['心理学', '科幻', '历史']));
    expect(result!.where((t) => t == '心理学').length, 1);
  });

  testWidgets('批量分组：选已有或新建', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showBatchShelfSheet(
                  context,
                  count: 2,
                  shelves: const ['小说'],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('batch-shelf-小说')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('batch-shelf-input')),
      '历史',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('batch-shelf-create')));
    await tester.pumpAndSettle();

    expect(result, '历史');
  });

  testWidgets('批量删除：取消 / 删除书籍 / 删除全部（二次危险确认）', (tester) async {
    BatchDeleteMode? result;
    Future<void> openDialog() async {
      final button = find.text('open');
      if (button.evaluate().isEmpty) {
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showBatchDeleteDialog(context, count: 3);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    await openDialog();
    expect(find.text('删除 3 本书'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('删除书籍'), findsOneWidget);
    expect(find.text('删除全部'), findsOneWidget);

    // 「删除书籍」保留笔记，直接返回。
    await tester.tap(find.byKey(const ValueKey('batch-delete-book-only')));
    await tester.pumpAndSettle();
    expect(result, BatchDeleteMode.bookOnly);

    // 「删除全部」先弹危险确认，取消则什么都不发生。
    result = null;
    await openDialog();
    await tester.tap(find.byKey(const ValueKey('batch-delete-all')));
    await tester.pumpAndSettle();
    expect(find.text('危险操作'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);

    // 继续删除才真正返回「删除全部」。
    await openDialog();
    await tester.tap(find.byKey(const ValueKey('batch-delete-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('danger-delete-confirm')));
    await tester.pumpAndSettle();
    expect(result, BatchDeleteMode.all);
  });
}
