/// 导入结果弹窗：计数、关闭、清空记录。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/shelf/import_history.dart';
import 'package:qy_reader/features/shelf/widgets/import_result_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

ImportRecord _record(String name, ImportRecordStatus status) => ImportRecord(
  fileName: name,
  title: name,
  status: status,
  message: status == ImportRecordStatus.success ? '已加入书架' : '原因',
  at: 1760000000000,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      kImportHistoryPrefsKey: encodeImportRecords([
        _record('a.epub', ImportRecordStatus.success),
        _record('b.epub', ImportRecordStatus.duplicate),
        _record('c.txt', ImportRecordStatus.failure),
      ]),
    });
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    List<ImportRecord> batch = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showImportResultDialog(context, batch: batch),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('回看全部记录：显示成功 / 重复 / 失败计数', (tester) async {
    await pumpDialog(tester);

    expect(find.text('导入记录'), findsOneWidget);
    expect(find.text('共 3 条记录'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('import-summary-success')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('import-summary-duplicate')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('import-summary-failure')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(find.text('a.epub'), findsOneWidget);
    expect(find.text('c.txt'), findsOneWidget);
  });

  testWidgets('刚导入完：标题是「导入完成」，统计本次文件', (tester) async {
    final batch = [
      _record('d.epub', ImportRecordStatus.success),
      _record('e.epub', ImportRecordStatus.failure),
    ];
    // 生产环境里 ImportController 先写历史再弹窗，这里模拟同样的 5 条。
    SharedPreferences.setMockInitialValues({
      kImportHistoryPrefsKey: encodeImportRecords([
        ...batch,
        _record('a.epub', ImportRecordStatus.success),
        _record('b.epub', ImportRecordStatus.duplicate),
        _record('c.txt', ImportRecordStatus.failure),
      ]),
    });
    await pumpDialog(tester, batch: batch);

    expect(find.text('导入完成'), findsOneWidget);
    expect(find.text('本次导入 2 个文件 · 累计 5 条记录'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('import-summary-success')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('关闭后可以再打开，记录还在；清空后记录消失', (tester) async {
    await pumpDialog(tester);
    expect(find.text('a.epub'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-result-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('import-result-dialog')), findsNothing);

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('a.epub'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-history-clear')));
    await tester.pumpAndSettle();
    expect(find.text('清空导入记录？'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('import-history-clear-confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有导入记录'), findsOneWidget);
    expect(find.text('a.epub'), findsNothing);
  });
}
