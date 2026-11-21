/// 全局听书控制条覆盖层：朗读中在所有页面底部显示、点信息区进听书页；
/// 阅读页/听书页声明盖住（suppress）时隐藏；空闲时收缩。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qy_reader/app/router.dart' show routerProvider;
import 'package:qy_reader/features/home/widgets/global_tts_bar.dart';
import 'package:qy_reader/features/reader/tts/tts_playback.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePlayingTts extends TtsPlayback {
  @override
  TtsPlaybackState build() => const TtsPlaybackState(
    status: TtsPlaybackStatus.playing,
    bookId: 'b1',
    bookTitle: '测试的书',
    index: 1,
    total: 9,
    currentText: '正在朗读的句子',
  );
}

class _FakeIdleTts extends TtsPlayback {
  @override
  TtsPlaybackState build() => const TtsPlaybackState();
}

Widget _host(GoRouter router, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [routerProvider.overrideWithValue(router), ...overrides],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => TtsBarOverlay(child: child),
      ),
    );

GoRouter makeRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const Scaffold(body: SizedBox()),
    ),
    GoRoute(
      path: '/other',
      builder: (_, __) => const Scaffold(body: SizedBox()),
    ),
    GoRoute(
      path: '/reader/:bookId/tts',
      builder: (_, __) => const Scaffold(
        body: SizedBox(key: ValueKey('tts-route')),
      ),
    ),
  ],
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TtsBarOverlay.resetForTest();
  });

  tearDown(TtsBarOverlay.resetForTest);

  testWidgets('主框架路由：覆盖层不显示（HomeShell 自己的条负责）', (tester) async {
    final router = makeRouter();
    await tester.pumpWidget(
      _host(
        router,
        overrides: [ttsPlaybackProvider.overrideWith(_FakePlayingTts.new)],
      ),
    );
    await tester.pumpAndSettle();

    // 栈顶 '/' 是主框架：覆盖层让位，HomeShell 里的 'home-tts-bar' 负责
    expect(find.byKey(const ValueKey('overlay-tts-bar')), findsNothing);
  });

  testWidgets('非主框架路由：覆盖层显示控制条，点信息区进听书页', (tester) async {
    final router = makeRouter();
    await tester.pumpWidget(
      _host(
        router,
        overrides: [ttsPlaybackProvider.overrideWith(_FakePlayingTts.new)],
      ),
    );
    await tester.pumpAndSettle();
    unawaited(router.push('/other'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('overlay-tts-bar')), findsOneWidget);
    expect(find.text('正在朗读的句子'), findsOneWidget);

    await tester.tap(find.text('正在朗读的句子'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tts-route')), findsOneWidget);
  });

  testWidgets('阅读页/听书页声明盖住时：控制条隐藏', (tester) async {
    final router = makeRouter();
    await tester.pumpWidget(
      _host(
        router,
        overrides: [ttsPlaybackProvider.overrideWith(_FakePlayingTts.new)],
      ),
    );
    // 阅读页/听书页挂载时声明盖住
    TtsBarOverlay.suppress();
    unawaited(router.push('/other'));
    await tester.pumpAndSettle();

    // 声明盖住 → 非主框架路由上也不显示
    expect(find.byKey(const ValueKey('overlay-tts-bar')), findsNothing);

    // 归还后重新显示（栈顶 '/other' 非主框架）
    TtsBarOverlay.unsuppress();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('overlay-tts-bar')), findsOneWidget);
  });

  testWidgets('空闲：控制条收缩（不渲染条本体）', (tester) async {
    final router = makeRouter();
    await tester.pumpWidget(
      _host(
        router,
        overrides: [ttsPlaybackProvider.overrideWith(_FakeIdleTts.new)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('overlay-tts-bar')), findsNothing);
    expect(find.text('正在朗读的句子'), findsNothing);
  });
}
