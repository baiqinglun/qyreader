/// 「添加书签」备注弹窗：可留空、可取消、文本会 trim。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/features/reader/widgets/bookmark_note_dialog.dart';

void main() {
  Future<void> open(WidgetTester tester, List<String?> results) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final result = await showBookmarkNoteDialog(
                    context,
                    theme: ReadingTheme.paper,
                  );
                  results.add(result);
                },
                child: const Text('加书签'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('加书签'));
    await tester.pumpAndSettle();
  }

  testWidgets('可以填写备注并添加', (tester) async {
    final results = <String?>[];
    await open(tester, results);

    expect(find.text('添加书签'), findsOneWidget);
    expect(find.text('备注（可选）'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('bookmark-note-field')),
      '  这一页很重要  ',
    );
    await tester.tap(find.byKey(const ValueKey('bookmark-add')));
    await tester.pumpAndSettle();

    expect(results, ['这一页很重要']);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('不填备注直接添加返回空串', (tester) async {
    final results = <String?>[];
    await open(tester, results);

    await tester.tap(find.byKey(const ValueKey('bookmark-add')));
    await tester.pumpAndSettle();
    expect(results, ['']);
  });

  testWidgets('取消返回 null', (tester) async {
    final results = <String?>[];
    await open(tester, results);

    await tester.tap(find.byKey(const ValueKey('bookmark-cancel')));
    await tester.pumpAndSettle();
    expect(results, [null]);
  });
}
