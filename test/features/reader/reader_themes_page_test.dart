/// 阅读主题列表页：内置/自定义分组、点选应用。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/features/reader/reader_settings.dart';
import 'package:qy_reader/features/settings/reader_themes_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('默认主题和我的主题分组，点纯白立即应用', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ReaderThemesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('阅读主题'), findsOneWidget);
    expect(find.text('默认主题'), findsOneWidget);
    expect(find.text('新建主题'), findsOneWidget);
    expect(find.text('纯白'), findsOneWidget);

    await tester.tap(find.text('纯白'));
    await tester.pumpAndSettle();

    expect(container.read(readingSettingsControllerProvider).theme, ReadingTheme.white);
    expect(find.textContaining('已应用'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('我的主题'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('我的主题'), findsOneWidget);
  });
}
