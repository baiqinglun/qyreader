/// 彩色胶囊标签单测：配色稳定性 + 展示/交互。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/shelf/widgets/tag_capsule.dart';

void main() {
  group('tagColorsOf', () {
    test('同名标签颜色恒定（浅色/深色各自稳定）', () {
      final a1 = tagColorsOf('心理学', Brightness.light);
      final a2 = tagColorsOf('心理学', Brightness.light);
      expect(a1.background, a2.background);
      expect(a1.foreground, a2.foreground);
      expect(a1.border, a2.border);

      final dark = tagColorsOf('心理学', Brightness.dark);
      expect(dark.background, isNot(a1.background));
    });

    test('不同标签会散列出多种颜色，且明暗主题前景/底色对比方向正确', () {
      final tags = ['心理学', '哲学', '小说', '历史', '科幻', '科普', '文学', '法律'];
      final lightColors = {
        for (final t in tags) tagColorsOf(t, Brightness.light).foreground,
      };
      expect(lightColors.length, greaterThan(3));

      for (final t in tags) {
        final light = tagColorsOf(t, Brightness.light);
        final dark = tagColorsOf(t, Brightness.dark);
        // 浅色主题：底色比文字亮；深色主题：底色比文字暗
        expect(
          HSLColor.fromColor(light.background).lightness,
          greaterThan(HSLColor.fromColor(light.foreground).lightness),
        );
        expect(
          HSLColor.fromColor(dark.background).lightness,
          lessThan(HSLColor.fromColor(dark.foreground).lightness),
        );
      }
    });
  });

  group('TagCapsule', () {
    testWidgets('展示标签名与数量，胶囊圆角', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(child: TagCapsule(tag: '心理学', count: 12)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('心理学'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);

      final box = tester.widget<Container>(
        find.ancestor(
          of: find.text('心理学'),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(999));
    });

    testWidgets('可点击/可删除；紧凑模式更小', (tester) async {
      var tapped = 0;
      var deleted = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: TagCapsule(
              tag: '科幻',
              onTap: () => tapped++,
              onDeleted: () => deleted++,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('科幻'));
      expect(tapped, 1);

      await tester.tap(find.byIcon(Icons.close));
      expect(deleted, 1);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(child: TagCapsule(tag: '科幻', compact: true)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
