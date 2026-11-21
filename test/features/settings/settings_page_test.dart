/// 设置页分组：外观 / 资源 / 管理 / 数据 / 关于。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/settings/appearance_provider.dart';
import 'package:qy_reader/features/settings/settings_page.dart';
import 'package:qy_reader/features/shelf/shelf_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<void> pumpSettings(WidgetTester tester) async {
    // 高一点的窗口：设置页五组一次全渲染，不用滚动断言。
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 书架为空：设置页只用到分类数，避免测试里打开数据库。
          shelfItemsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('设置页分成外观 / 资源 / 管理 / 数据 / 实验性功能 / 关于六组', (tester) async {
    await pumpSettings(tester);

    for (final section in ['外观', '资源', '管理', '数据', '实验性功能', '关于']) {
      expect(find.text(section), findsOneWidget, reason: '缺少「$section」分组');
    }

    // 外观：亮暗模式 + 主题色
    expect(find.text('显示模式'), findsOneWidget);
    expect(find.text('主题色'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-theme-mode')), findsOneWidget);

    // 资源：字体 / 背景 / 听书音频
    expect(find.text('字体'), findsOneWidget);
    expect(find.text('背景'), findsOneWidget);
    expect(find.text('听书音频'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-audio')), findsOneWidget);

    // 管理：我的阅读 / 笔记回顾 / 标签 / 分类 / 作者管理 / 重复书籍整理
    expect(find.text('我的阅读'), findsOneWidget);
    expect(find.text('笔记回顾'), findsOneWidget);
    expect(find.text('标签'), findsOneWidget);
    expect(find.text('分类'), findsOneWidget);
    expect(find.text('作者管理'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-authors')), findsOneWidget);
    expect(find.text('重复书籍整理'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-duplicate-books')),
      findsOneWidget,
    );

    // 数据：同步 / 缓存 / 导出阅读数据
    expect(find.text('同步'), findsOneWidget);
    expect(find.text('缓存'), findsOneWidget);
    expect(find.text('导出阅读数据'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-export-reading-data')),
      findsOneWidget,
    );

    // 实验性功能：微信读书
    expect(find.text('微信读书'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-weread')), findsOneWidget);

    // 关于：关于 + 开源协议
    expect(find.text('关于 QYReader'), findsOneWidget);
    expect(find.text('开源协议'), findsOneWidget);
  });

  testWidgets('已移除：阅读主题 / 书架设置 / 每日目标 / 临时文件 / 数据存储', (tester) async {
    await pumpSettings(tester);

    expect(find.text('阅读主题'), findsNothing);
    expect(find.text('书架设置'), findsNothing);
    expect(find.text('每日阅读目标'), findsNothing);
    expect(find.text('临时文件与图片'), findsNothing);
    expect(find.text('数据存储'), findsNothing);
  });

  testWidgets('显示模式是单个切换开关，点亮即切到暗色', (tester) async {
    await pumpSettings(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );

    expect(find.byKey(const ValueKey('settings-theme-mode')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-theme-mode')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(appThemeModeControllerProvider).name, 'dark');
  });
}
