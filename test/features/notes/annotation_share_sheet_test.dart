/// 卡片式分享面板：三种模板渲染与切换、动作按钮。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/notes/annotation_share_sheet.dart';

AnnotationCardData _data() => const AnnotationCardData(
  quote: '本应根据手册迅速应变，却受到疾病管理本部阻挠。',
  note: '规则与人情的冲突写得真好。',
  bookTitle: '测试的书',
  author: '测试作者',
  createdAt: 1700000000000,
  colorToken: 'yellow',
  kindLabel: '高亮',
);

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: AnnotationShareSheet(data: _data()))),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('默认「墨句」模板：引文与书名渲染，模板切换可用', (tester) async {
    await _pump(tester);

    expect(find.text('墨句'), findsOneWidget); // 选中胶囊
    expect(find.text('本应根据手册迅速应变，却受到疾病管理本部阻挠。'), findsOneWidget);
    expect(find.textContaining('《测试的书》'), findsOneWidget);

    // 切「便签」：引文仍在，想法出现
    await tester.tap(find.text('便签'));
    await tester.pumpAndSettle();
    expect(find.text('本应根据手册迅速应变，却受到疾病管理本部阻挠。'), findsOneWidget);
    expect(find.text('规则与人情的冲突写得真好。'), findsOneWidget);

    // 切「简约」
    await tester.tap(find.text('简约'));
    await tester.pumpAndSettle();
    expect(find.text('本应根据手册迅速应变，却受到疾病管理本部阻挠。'), findsOneWidget);
  });

  testWidgets('无想法的划线：不渲染想法区，动作按钮齐全', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotationShareSheet(
            data: const AnnotationCardData(
              quote: '一句没有想法的划线。',
              bookTitle: '另一本书',
              createdAt: 1700000000000,
              colorToken: 'blue',
              kindLabel: '划线',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('一句没有想法的划线。'), findsOneWidget);
    expect(find.text('规则与人情的冲突写得真好。'), findsNothing);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);
  });
}
