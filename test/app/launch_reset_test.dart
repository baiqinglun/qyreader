/// 启动归位：正在阅读时切回前台保持阅读页；不在阅读页时回书架。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qy_reader/app/launch_reset.dart';
import 'package:qy_reader/features/reader/reader_active_marker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('阅读中切回前台不掉书；不在阅读页才回书架', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Text('书架')),
        GoRoute(path: '/reader/:id', builder: (_, __) => const Text('阅读器')),
      ],
    );
    addTearDown(router.dispose);
    LaunchReset.bind(router);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('书架'), findsOneWidget);

    router.go('/reader/abc');
    await tester.pumpAndSettle();
    expect(find.text('阅读器'), findsOneWidget);

    // 模拟原生端收到「点桌面图标」的 onNewIntent；阅读页仍在活动标记里，
    // 这次不应该把书合上。
    await markReaderActive('abc');
    await _sendReset();
    await tester.pumpAndSettle();
    expect(find.text('阅读器'), findsOneWidget);
    expect(find.text('书架'), findsNothing);

    // 主动退出阅读器后标记被清掉：再点图标才回书架。
    await clearReaderActive();
    router.go('/');
    await tester.pumpAndSettle();
    await _sendReset();
    await tester.pumpAndSettle();
    expect(find.text('书架'), findsOneWidget);
  });
}

Future<void> _sendReset() async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    'qyreader/launch',
    const StandardMethodCodec().encodeMethodCall(
      const MethodCall('resetToShelf'),
    ),
    (_) {},
  );
}
