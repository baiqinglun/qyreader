/// 书籍信息页每日阅读时长：竖排逐日展示有记录的前 14 天，超过给「显示更多」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/book_detail/book_detail_page.dart';

void main() {
  String keyOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  testWidgets('有阅读记录的前 14 天 + 显示更多 / 收起', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final start = DateTime(2026, 11, 1);
    final daily = <String, int>{
      for (var i = 0; i < 20; i++)
        keyOf(start.subtract(Duration(days: i))): 10 * 60 * 1000,
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _Host(dailyMs: daily)),
      ),
    );
    await tester.pumpAndSettle();

    // 只展示最近 14 个有记录的日子，竖排逐行；不再补 0 值空柱。
    expect(find.text('阅读时间'), findsOneWidget);
    expect(find.textContaining('共 20 天'), findsOneWidget);
    expect(
      find.byKey(ValueKey('book-daily-row-${keyOf(start)}')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('book-daily-row-2026-10-19')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('book-daily-row-2026-10-18')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('book-daily-show-more')), findsOneWidget);
    expect(find.text('显示更多（还有 6 天）'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('book-daily-show-more')));
    await tester.pumpAndSettle();

    expect(find.text('更早的阅读记录'), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);
    // 第 14 天之后的更早记录出现在列表里。
    expect(
      find.byKey(
        ValueKey(
          'book-daily-more-${keyOf(start.subtract(const Duration(days: 19)))}',
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('收起'));
    await tester.pumpAndSettle();
    expect(find.text('更早的阅读记录'), findsNothing);
  });

  testWidgets('不超过 14 个阅读日时不显示「显示更多」', (tester) async {
    final start = DateTime(2026, 11, 1);
    final daily = <String, int>{
      for (var i = 0; i < 5; i++)
        keyOf(start.subtract(Duration(days: i))): 5 * 60 * 1000,
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: _Host(dailyMs: daily)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('阅读时间'), findsOneWidget);
    expect(
      find.byKey(ValueKey('book-daily-row-${keyOf(start)}')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('book-daily-show-more')), findsNothing);
  });

  testWidgets('没有阅读记录时显示空提示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BookDailyBars(
            dailyMs: <String, int>{},
            muted: Colors.grey,
            fg: Colors.black,
            showAll: false,
            onToggleShowAll: _noop,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有阅读记录'), findsOneWidget);
    expect(find.byKey(const ValueKey('book-daily-show-more')), findsNothing);
  });
}

void _noop() {}

class _Host extends StatefulWidget {
  const _Host({required this.dailyMs});

  final Map<String, int> dailyMs;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    return BookDailyBars(
      dailyMs: widget.dailyMs,
      muted: Colors.grey,
      fg: Colors.black,
      showAll: _showAll,
      onToggleShowAll: () => setState(() => _showAll = !_showAll),
    );
  }
}
