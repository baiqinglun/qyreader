/// 标注编辑弹窗：居中最中弹窗、改色、写想法、删除。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/domain/entities/annotation.dart';
import 'package:qy_reader/features/reader/widgets/annotation_dialog.dart';

Annotation _annotation({String? note}) => Annotation(
      id: 'a1',
      bookId: 'b1',
      type: AnnotationType.highlight,
      color: AnnotationColor.yellow,
      locatorStart: '{}',
      locatorEnd: '{}',
      quotedText: '这是一段被划线的原文。',
      note: note,
      createdAt: 1,
      updatedAt: 1,
    );

void main() {
  Future<AnnotationEditResult?> Function() openDialog(WidgetTester tester) {
    AnnotationEditResult? result;
    return () async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showAnnotationEditDialog(
                    context,
                    annotation: _annotation(note: '旧想法'),
                    theme: ReadingTheme.paper,
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      return result;
    };
  }

  testWidgets('中间弹窗：显示原文、颜色、长想法输入框和删除', (tester) async {
    final open = openDialog(tester);
    await open();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('编辑标注'), findsOneWidget);
    expect(find.text('这是一段被划线的原文。'), findsOneWidget);
    expect(find.text('颜色'), findsOneWidget);
    expect(find.text('想法'), findsOneWidget);
    expect(find.text('删除标注'), findsOneWidget);

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('annotation-note-field')),
    );
    expect(field.minLines, 4);
    expect(field.maxLines, 8);
    expect(field.controller!.text, '旧想法');

    await tester.enterText(
      find.byKey(const ValueKey('annotation-note-field')),
      '新的想法',
    );
    await tester.tap(find.byKey(const ValueKey('annotation-color-blue')));
    await tester.tap(find.byKey(const ValueKey('annotation-save')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('保存返回选中的颜色与想法', (tester) async {
    AnnotationEditResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showAnnotationEditDialog(
                  context,
                  annotation: _annotation(note: '旧想法'),
                  theme: ReadingTheme.white,
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('annotation-note-field')),
      '新的想法',
    );
    await tester.tap(find.byKey(const ValueKey('annotation-color-rose')));
    await tester.tap(find.byKey(const ValueKey('annotation-save')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.color, AnnotationColor.rose);
    expect(result!.note, '新的想法');
    expect(result!.delete, isFalse);
  });

  testWidgets('删除返回 delete 标记', (tester) async {
    AnnotationEditResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showAnnotationEditDialog(
                  context,
                  annotation: _annotation(),
                  theme: ReadingTheme.paper,
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('annotation-delete')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.delete, isTrue);
  });
}
