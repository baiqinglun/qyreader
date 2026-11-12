/// 标签选择器（编辑书籍时从标签库直接勾选）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/shelf/widgets/tag_capsule.dart';
import 'package:qy_reader/features/tags/tag_library.dart';
import 'package:qy_reader/features/tags/tag_picker_sheet.dart';

void main() {
  testWidgets('已选标签高亮，点未选标签回调并切换选中态', (tester) async {
    final toggled = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TagPickerSheet(
          tags: const [
            TagSummary(name: '科幻', count: 2),
            TagSummary(name: '历史', count: 1),
          ],
          selected: const {'科幻'},
          onToggle: toggled.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TagCapsule>(find.widgetWithText(TagCapsule, '科幻')).selected,
      isTrue,
    );
    expect(
      tester.widget<TagCapsule>(find.widgetWithText(TagCapsule, '历史')).selected,
      isFalse,
    );

    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    expect(toggled, ['历史']);
    expect(
      tester.widget<TagCapsule>(find.widgetWithText(TagCapsule, '历史')).selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索标签', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TagPickerSheet(
          tags: const [
            TagSummary(name: '科幻', count: 2),
            TagSummary(name: '历史', count: 1),
          ],
          selected: const {},
          onToggle: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '科幻');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TagCapsule, '科幻'), findsOneWidget);
    expect(find.widgetWithText(TagCapsule, '历史'), findsNothing);

    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pumpAndSettle();
    expect(find.textContaining('没有找到'), findsOneWidget);
  });

  testWidgets('最多选 12 个标签', (tester) async {
    final toggled = <String>[];
    final tags = [
      for (var i = 0; i < 13; i++) TagSummary(name: 'T$i', count: 1),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TagPickerSheet(
          tags: tags,
          selected: {for (var i = 0; i < 12; i++) 'T$i'},
          onToggle: toggled.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('T12'));
    await tester.pumpAndSettle();
    expect(toggled, isEmpty);
    expect(find.text('每本书最多 12 个标签'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
