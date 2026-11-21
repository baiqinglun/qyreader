/// 路由覆盖感知：HomeShell 式的 RouteAware 依赖 GoRouter 把 observers
/// 传给 Navigator——盖住的路由 pop 后 didPopNext 必须触发
/// （首页/统计页「从阅读器回来就刷新」依赖它）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:qy_reader/app/router.dart';

class _AwareShell extends StatefulWidget {
  const _AwareShell({required this.onPopNext});

  final VoidCallback onPopNext;

  @override
  State<_AwareShell> createState() => _AwareShellState();
}

class _AwareShellState extends State<_AwareShell> with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() => widget.onPopNext();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('主框架'));
}

class _PageAwareShell extends StatefulWidget {
  const _PageAwareShell({required this.onPopNext});
  final VoidCallback onPopNext;
  @override
  State<_PageAwareShell> createState() => _PageAwareShellState();
}

class _PageAwareShellState extends State<_PageAwareShell> with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) pageRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    pageRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() => widget.onPopNext();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
      child: const Text('打开详情'),
    ),
  );
}

void main() {
  testWidgets('关闭弹窗不刷新首页，从页面返回仍刷新', (tester) async {
    var count = 0;
    final router = GoRouter(
      observers: [routeObserver, pageRouteObserver],
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => _PageAwareShell(onPopNext: () => count++),
        ),
        GoRoute(
          path: '/reader',
          builder: (_, __) => const Scaffold(body: Text('阅读页')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(count, 0);
    unawaited(router.push('/reader'));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(count, 1);
  });

  testWidgets('GoRouter observers：盖住的路由 pop 后 didPopNext 触发', (tester) async {
    var popNextCount = 0;
    final router = GoRouter(
      observers: [routeObserver],
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => _AwareShell(onPopNext: () => popNextCount++),
        ),
        GoRoute(
          path: '/reader',
          builder: (_, __) => const Scaffold(body: Text('阅读页')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('主框架'), findsOneWidget);
    expect(popNextCount, 0);

    // 盖住主框架（模拟进阅读器），再返回。
    // 注意：router.push 返回的 Future 要等路由被 pop 才完成，不能先 await。
    unawaited(router.push('/reader'));
    await tester.pumpAndSettle();
    expect(find.text('阅读页'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('主框架'), findsOneWidget);
    expect(popNextCount, 1, reason: '回到主框架必须触发 didPopNext（刷新依赖它）');
  });
}
