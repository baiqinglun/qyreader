import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/home/recommendations_card.dart';
import 'package:qy_reader/features/settings/weread/weread_client.dart';

void main() {
  testWidgets('刷新推荐时显示加载状态', (tester) async {
    var calls = 0;
    final pending = Completer<List<WeReadRecommendation>?>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recommendationsProvider.overrideWith((ref) {
            calls++;
            return calls == 1
                ? Future.value([const WeReadRecommendation(title: '三体')])
                : pending.future;
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: RecommendationsCard())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新推荐'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    pending.complete([const WeReadRecommendation(title: '新书')]);
    await tester.pumpAndSettle();
    expect(find.text('新书'), findsOneWidget);
  });
  testWidgets('推荐详情显示真实元数据并展示四个页签', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recommendationsProvider.overrideWith(
            (ref) async => [
              const WeReadRecommendation(
                title: '三体',
                intro: '科幻简介',
                metadata: {
                  'readingCount': 1200,
                  'finishCount': 100,
                  'wordCount': 300000,
                  'category': '科幻',
                  'newRating': 90,
                  'newRatingDetail': {'title': '神作'},
                },
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: RecommendationsCard())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('三体'));
    await tester.pumpAndSettle();
    expect(find.text('神作'), findsOneWidget);
    expect(find.text('1200 人'), findsOneWidget);
    expect(find.text('100 人'), findsOneWidget);
    expect(find.text('30.0万 字'), findsOneWidget);
    expect(find.text('科幻'), findsOneWidget);
    expect(find.text('热门书评'), findsOneWidget);
    expect(find.text('科幻简介'), findsOneWidget);
    expect(find.text('目录'), findsOneWidget);
    expect(find.byType(Tab), findsNWidgets(4));
  });

  testWidgets('推荐卡显示书籍并可查看理由', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recommendationsProvider.overrideWith(
            (ref) async => [
              const WeReadRecommendation(
                title: '三体',
                author: '刘慈欣',
                reason: '喜欢科幻',
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: RecommendationsCard())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('书籍推荐'), findsOneWidget);
    await tester.tap(find.text('三体'));
    await tester.pumpAndSettle();
    expect(find.textContaining('喜欢科幻'), findsOneWidget);
  });
}
