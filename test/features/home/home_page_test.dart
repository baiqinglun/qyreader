/// 首页四个区块都是卡片，且数据来自书架 + 统计仓储。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/providers.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/domain/entities/reading_stats.dart';
import 'package:qy_reader/domain/repositories/stats_repository.dart';
import 'package:qy_reader/features/home/home_page.dart';
import 'package:qy_reader/features/home/recommendations_card.dart';
import 'package:qy_reader/features/home/home_tabs.dart';
import 'package:qy_reader/features/settings/weread/weread_client.dart';
import 'package:qy_reader/features/home/widgets/cover_thumb.dart';
import 'package:qy_reader/features/shelf/shelf_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

ShelfItem _item(
  String id, {
  required String title,
  String? author,
  int? opened,
  int updated = 0,
  double percent = 0,
  BookReadStatus status = BookReadStatus.unread,
}) => ShelfItem(
  book: Book(
    id: id,
    title: title,
    author: author,
    format: BookFormat.epub,
    filePath: '/tmp/$id.epub',
    fileSha256: id,
    fileSize: 1,
    addedAt: 0,
    updatedAt: updated,
    lastOpenedAt: opened,
    readStatus: status,
    hlc: '0000000000000-00000-aaaaaaaa',
    deviceId: 'aaaaaaaa',
  ),
  percent: percent,
);

class _FakeStatsRepository implements StatsRepository {
  _FakeStatsRepository(this.stats);

  final ReadingStats stats;

  @override
  Future<ReadingStats> overview({int recentDayCount = 14}) async => stats;

  @override
  Future<int> dailyGoalMinutes() async => stats.dailyGoalMinutes;

  @override
  Future<int> bookTotalDurationMs(String bookId) async => 0;

  @override
  Future<List<BookReadingTotal>> bookTotals() async => const [];

  @override
  Future<Map<String, int>> bookDailyDurations(
    String bookId, {
    int days = 14,
  }) async => const {};

  @override
  Future<PeriodReadingStats> periodStats(
    StatsPeriod period,
    DateTime anchor,
  ) async => throw UnimplementedError();

  @override
  Future<void> recordSession({
    required String bookId,
    required int startedAt,
    required int endedAt,
    required int charsRead,
    int? countedDurationMs,
  }) async {}

  @override
  Future<void> setDailyGoalMinutes(int minutes) async {}
}

ReadingStats _stats() => const ReadingStats(
  todayDurationMs: 133000,
  todayChars: 1200,
  totalDurationMs: 500 * 3600000 + 38 * 60000,
  totalChars: 100000,
  totalDays: 30,
  streakDays: 3,
  recentDays: [],
  dailyGoalMinutes: 30,
);

Future<void> _pumpHome(
  WidgetTester tester,
  List<ShelfItem> items,
  List<HomeTab> tabs, {
  Size size = const Size(400, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recommendationsProvider.overrideWith((ref) async => null),
        shelfItemsProvider.overrideWith((ref) => Stream.value(items)),
        statsRepositoryProvider.overrideWith(
          (ref) async => _FakeStatsRepository(_stats()),
        ),
      ],
      child: MaterialApp(home: HomePage(onSelectTab: tabs.add)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('切回首页保留上次推荐，手动刷新才重新获取', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var calls = 0;
    late StateSetter update;
    var active = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recommendationsProvider.overrideWith((ref) async {
            calls++;
            return [WeReadRecommendation(title: '推荐书$calls')];
          }),
          shelfItemsProvider.overrideWith((ref) => Stream.value([])),
          statsRepositoryProvider.overrideWith(
            (ref) async => _FakeStatsRepository(_stats()),
          ),
        ],
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return HomePage(active: active);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('推荐书1'), findsOneWidget);
    update(() => active = false);
    await tester.pumpAndSettle();
    update(() => active = true);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('推荐书1'), findsOneWidget);
    await tester.tap(find.byTooltip('刷新推荐'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('推荐书2'), findsOneWidget);
  });

  testWidgets('首页四个区块都是卡片，展示累计 / 继续 / 今日目标 / 年度进度', (tester) async {
    final tabs = <HomeTab>[];
    final thisYear = DateTime.now().year;
    final items = [
      _item(
        'room',
        title: '一间只属于自己的房间',
        author: '弗吉尼亚·伍尔夫',
        opened: 1000,
        percent: 0.0718,
        status: BookReadStatus.reading,
      ),
      _item(
        'finished',
        title: '活着',
        updated: DateTime(thisYear, 10, 1).millisecondsSinceEpoch,
        percent: 1,
        status: BookReadStatus.finished,
      ),
    ];

    await _pumpHome(tester, items, tabs);

    expect(find.byKey(const ValueKey('home-overview-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-continue-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-goal-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-year-card')), findsOneWidget);

    // 圆弧画布必须是正方形，否则宽高不等会画成扁椭圆。
    final arc = find.descendant(
      of: find.byKey(const ValueKey('home-goal-card')),
      matching: find.byType(AspectRatio),
    );
    expect(arc, findsOneWidget);
    expect(tester.widget<AspectRatio>(arc).aspectRatio, 1);
    final arcSize = tester.getSize(arc);
    expect(arcSize.width, closeTo(arcSize.height, 0.5));

    expect(find.text('累计阅读'), findsOneWidget);
    expect(find.textContaining('500 小时 38 分钟'), findsOneWidget);
    expect(find.textContaining('1 本'), findsOneWidget);

    expect(find.text('继续阅读'), findsOneWidget);
    expect(find.text('一间只属于自己的房间'), findsOneWidget);
    expect(find.text('弗吉尼亚·伍尔夫'), findsOneWidget);
    expect(find.text('7.18%'), findsOneWidget);

    expect(find.text('今日目标'), findsOneWidget);
    expect(find.text('2:13'), findsOneWidget);
    expect(find.text('（目标 30 分钟）'), findsOneWidget);
    expect(find.text('开始阅读'), findsOneWidget);

    expect(find.text('今年读完的书'), findsOneWidget);
    expect(find.text('1 / 24'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-overview-card')));
    await tester.pump();
    expect(tabs, [HomeTab.stats]);
  });

  testWidgets('今年读完的书自动换行，默认三行，查看更多进完整页', (tester) async {
    final year = DateTime.now().year;
    final items = <ShelfItem>[
      for (var i = 0; i < 12; i++)
        _item(
          'fin$i',
          title: '读完的书 $i',
          updated: DateTime(year, 10, 1).millisecondsSinceEpoch - i * 1000,
          percent: 1,
          status: BookReadStatus.finished,
        ),
    ];

    await _pumpHome(tester, items, [], size: const Size(400, 1800));

    // 400 宽一行 3 本，默认三行 = 9 本，其余进「查看更多」。
    expect(find.byType(CoverThumb), findsNWidgets(9));
    expect(find.byKey(const ValueKey('home-year-more')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-year-more')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('year-finished-page')), findsOneWidget);
    expect(find.text('12 本'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('year-finished-book-fin0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('year-finished-book-fin11')),
      findsOneWidget,
    );
  });

  testWidgets('今年读完封面行不足整行时也居中（Wrap 撑满宽度）', (tester) async {
    final year = DateTime.now().year;
    final items = <ShelfItem>[
      for (var i = 0; i < 4; i++)
        _item(
          'fin$i',
          title: '读完的书 $i',
          updated: DateTime(year, 10, 1).millisecondsSinceEpoch,
          percent: 1,
          status: BookReadStatus.finished,
        ),
    ];

    await _pumpHome(tester, items, [], size: const Size(400, 1800));

    // 400 宽一行 3 本：第二行只有 1 本，应水平居中而不是贴左。
    final covers = find.byType(CoverThumb);
    expect(covers, findsNWidgets(4));
    final cardLeft = tester
        .getTopLeft(find.byKey(const ValueKey('home-year-card')))
        .dx;
    // 首行 3 本（266 内宽 336）：居中时左边留约 35；贴左时是 16。
    expect(tester.getTopLeft(covers.first).dx - cardLeft, greaterThan(25));
    // 末行单本：居中时左边留约 160；贴左时是 16。
    expect(tester.getTopLeft(covers.at(3)).dx - cardLeft, greaterThan(100));
  });

  testWidgets('空书架：继续阅读 / 年度都显示空态，开始阅读回书架', (tester) async {
    final tabs = <HomeTab>[];
    await _pumpHome(tester, const [], tabs);

    expect(find.text('还没有正在读的书'), findsOneWidget);
    expect(find.text('今年还没有读完的书'), findsOneWidget);
    expect(find.text('0 / 24'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-start-reading')));
    await tester.pump();
    expect(tabs, [HomeTab.shelf]);
    expect(find.text('书架还是空的，先去书架导入一本书吧'), findsOneWidget);
  });

  testWidgets('宽屏：内容限宽 900，开始阅读按钮不超过 420', (tester) async {
    final tabs = <HomeTab>[];
    final thisYear = DateTime.now().year;
    final items = [
      _item(
        'room',
        title: '一间只属于自己的房间',
        author: '弗吉尼亚·伍尔夫',
        opened: 1000,
        percent: 0.0718,
        status: BookReadStatus.reading,
      ),
      _item(
        'finished',
        title: '活着',
        updated: DateTime(thisYear, 10, 1).millisecondsSinceEpoch,
        percent: 1,
        status: BookReadStatus.finished,
      ),
    ];

    await _pumpHome(tester, items, tabs, size: const Size(1400, 1000));

    final scroll = tester.getSize(
      find.byKey(const PageStorageKey('home-scroll')),
    );
    expect(scroll.width, closeTo(900, 0.5), reason: '内容列不应被拉满宽屏');
    final start = tester.getSize(
      find.byKey(const ValueKey('home-start-reading')),
    );
    expect(start.width, lessThanOrEqualTo(420.5));
  });

  test('底栏顺序：首页 / 书架 / 统计 / 设置', () {
    expect(kHomeTabs.map((tab) => tab.label), ['首页', '书架', '统计', '设置']);
    expect(HomeTab.home.index, 0);
    expect(HomeTab.shelf.index, 1);
    expect(HomeTab.stats.index, 2);
    expect(HomeTab.settings.index, 3);
  });
}
