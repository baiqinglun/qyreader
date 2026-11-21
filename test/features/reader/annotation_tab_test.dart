/// 标注列表：按章节 / 按颜色分组，按类型（高亮 / 划线）筛选。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/domain/entities/annotation.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/reader/widgets/annotation_tab.dart';

Annotation _ann(String id, String quote, AnnotationType type) => Annotation(
  id: id,
  bookId: 'b1',
  type: type,
  color: AnnotationColor.yellow,
  locatorStart: '{}',
  locatorEnd: '{}',
  quotedText: quote,
  createdAt: 1,
  updatedAt: 1,
);

void main() {
  testWidgets('按类型筛选：全部 / 高亮 / 划线', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: AnnotationTab(
              theme: ReadingTheme.paper,
              chapters: const [
                BookChapter(idx: 0, title: '第一章', href: 'c1.xhtml'),
              ],
              annotations: [
                _ann('a1', '高亮句', AnnotationType.highlight),
                _ann('a2', '划线句', AnnotationType.underline),
              ],
              onGotoAnnotation: (_) {},
              onDelete: (_) {},
              onEditNote: (_) {},
              onExport: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('高亮句'), findsOneWidget);
    expect(find.text('划线句'), findsOneWidget);
    expect(find.text('共 2 条'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('annotation-type-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('划线').last);
    await tester.pumpAndSettle();
    expect(find.text('划线句'), findsOneWidget);
    expect(find.text('高亮句'), findsNothing);
    expect(find.text('共 1/2 条'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('annotation-type-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('高亮').last);
    await tester.pumpAndSettle();
    expect(find.text('高亮句'), findsOneWidget);
    expect(find.text('划线句'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('annotation-type-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部类型').last);
    await tester.pumpAndSettle();
    expect(find.text('高亮句'), findsOneWidget);
    expect(find.text('划线句'), findsOneWidget);
    expect(find.text('共 2 条'), findsOneWidget);
  });

  testWidgets('标注行分享按钮：打开卡片分享面板（模板可切换）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotationTab(
            theme: ReadingTheme.paper,
            chapters: const [
              BookChapter(idx: 0, title: '第一章', href: 'c1.xhtml'),
            ],
            annotations: [_ann('a1', '高亮句', AnnotationType.highlight)],
            onGotoAnnotation: (_) {},
            onDelete: (_) {},
            onEditNote: (_) {},
            onExport: () {},
            bookTitle: '测试的书',
            author: '作者',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('分享卡片'));
    await tester.pumpAndSettle();

    expect(find.text('墨句'), findsOneWidget);
    // 列表行 + 卡片里各出现一次
    expect(find.text('高亮句'), findsNWidgets(2));
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets('未定位标注：自动查询 / 手动定位两个入口', (tester) async {
    Annotation? auto;
    Annotation? manual;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotationTab(
            theme: ReadingTheme.paper,
            chapters: const [
              BookChapter(idx: 0, title: '第一章', href: 'c1.xhtml'),
            ],
            annotations: [_ann('a1', '找不到的原文', AnnotationType.highlight)],
            unlocatedIds: const {'a1'},
            onAutoLocate: (a) => auto = a,
            onManualLocate: (a) => manual = a,
            onGotoAnnotation: (_) {},
            onDelete: (_) {},
            onEditNote: (_) {},
            onExport: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 分组标题 + 行内角标
    expect(find.text('未定位'), findsWidgets);
    expect(find.byIcon(Icons.location_searching), findsNothing);

    // 未定位笔记：长按弹定位面板，不在行尾挤第三个按钮。
    await tester.longPress(find.text('找不到的原文'));
    await tester.pumpAndSettle();
    expect(find.text('自动查询定位'), findsOneWidget);
    expect(find.text('手动定位'), findsOneWidget);
    await tester.tap(find.text('自动查询定位'));
    await tester.pumpAndSettle();
    expect(auto?.id, 'a1');

    await tester.longPress(find.text('找不到的原文'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动定位'));
    await tester.pumpAndSettle();
    expect(manual?.id, 'a1');
  });
}
