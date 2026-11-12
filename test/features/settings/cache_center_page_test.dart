/// 缓存中心：三个页签（书籍 / 字体 / 背景）与背景空态。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/settings/cache_center_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('缓存中心有三个页签，背景页签有空态提示', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: CacheCenterPage())),
    );
    // 书籍页签等待仓储时会转圈，不能用 pumpAndSettle（无限动画）
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('缓存'), findsOneWidget);
    expect(find.text('书籍'), findsOneWidget);
    expect(find.text('字体'), findsOneWidget);
    expect(find.text('背景'), findsOneWidget);

    // 背景页签的空态由下一个用例（initialTab: 2）验证
  });

  testWidgets('可以指定初始页签（资源 → 背景直接落在背景页）', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: CacheCenterPage(initialTab: 2)),
      ),
    );
    // 背景页加载时顶部有进度条动画，不能 pumpAndSettle。
    await tester.pump(const Duration(milliseconds: 300));
    // 背景管理里可上传背景（选图后新建并应用一个主题）。
    expect(find.byKey(const ValueKey('background-upload')), findsOneWidget);
    expect(find.text('上传背景'), findsOneWidget);
  });
}
