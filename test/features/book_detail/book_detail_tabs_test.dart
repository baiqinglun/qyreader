/// 编辑信息页：顶部页签（基础信息 / 标签分类 / 目录 / 书评 / 笔记）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/shelf/widgets/batch_actions.dart';

void main() {
  testWidgets('批量删除：取消 / 删除书籍 / 删除全部（危险二次确认）', (tester) async {
    BatchDeleteMode? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showBatchDeleteDialog(context, count: 2);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('删除 2 本书'), findsOneWidget);
    expect(find.text('删除书籍'), findsOneWidget);
    expect(find.text('删除全部'), findsOneWidget);
    await tester.tap(find.text('删除全部'));
    await tester.pumpAndSettle();

    // 删除全部是危险操作：必须再确认一次。
    expect(find.text('危险操作'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.text('继续删除'));
    await tester.pumpAndSettle();
    expect(result, BatchDeleteMode.all);
  });
}
