/// 微信读书页：Key 配置、对比列表、筛选与单本同步。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/settings/weread/weread_compare.dart';
import 'package:qy_reader/features/settings/weread/weread_login.dart';
import 'package:qy_reader/features/settings/weread/weread_models.dart';
import 'package:qy_reader/features/settings/weread/weread_page.dart';
import 'package:qy_reader/features/settings/weread/weread_sync_service.dart';
import 'package:qy_reader/features/settings/weread/weread_sync_state.dart';

Book localBook(String id, String title) {
  return Book(
    id: id,
    title: title,
    author: '作者',
    format: BookFormat.epub,
    filePath: '/tmp/$id.epub',
    fileSha256: 'sha-$id',
    fileSize: 1,
    addedAt: 0,
    updatedAt: 0,
    hlc: '0000000000000-00000-aaaaaaaa',
    deviceId: 'aaaaaaaa',
  );
}

void main() {
  final updatedBook = localBook('b2', '三体');
  final result = WeReadFetchResult(
    snapshot: WeReadSnapshot(
      books: <WeReadBook>[
        const WeReadBook(bookId: 'r1', title: '新书', author: '甲', noteCount: 1),
        const WeReadBook(
          bookId: 'r2',
          title: '三体',
          author: '刘慈欣',
          progressPercent: 60,
          noteCount: 2,
          readUpdateTime: 2000000000,
        ),
        const WeReadBook(
          bookId: 'r3',
          title: '活着',
          author: '余华',
          progressPercent: 40,
        ),
      ],
      fetchedAt: DateTime(2026, 11, 17, 10, 30),
    ),
    diffs: <WeReadDiff>[
      const WeReadDiff(
        kind: WeReadDiffKind.added,
        remote: WeReadBook(
          bookId: 'r1',
          title: '新书',
          author: '甲',
          noteCount: 1,
        ),
        changes: <String>['本地书架没有这本书'],
      ),
      WeReadDiff(
        kind: WeReadDiffKind.updated,
        remote: const WeReadBook(
          bookId: 'r2',
          title: '三体',
          author: '刘慈欣',
          progressPercent: 60,
          noteCount: 2,
          readUpdateTime: 2000000000,
        ),
        local: updatedBook,
        localPercent: 0.2,
        newNoteCount: 2,
        changes: const <String>['阅读进度 20% → 60%', '新增 2 条划线/想法'],
      ),
      WeReadDiff(
        kind: WeReadDiffKind.synced,
        remote: const WeReadBook(
          bookId: 'r3',
          title: '活着',
          author: '余华',
          progressPercent: 40,
        ),
        local: localBook('b3', '活着'),
        localPercent: 0.4,
      ),
    ],
    state: const WeReadSyncState(
      importedCounts: <String, int>{'r2': 2},
      lastSyncAt: 1700000000000,
    ),
  );

  Future<void> pumpPage(
    WidgetTester tester,
    _FakeWeReadApi api, {
    Size size = const Size(900, 1800),
    _FakeLogin? login,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          wereadSyncApiProvider.overrideWithValue(api),
          wereadLoginProvider.overrideWithValue(login ?? _FakeLogin()),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const WeReadPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('未登录时显示引导，右上角可打开扫码登录弹窗', (tester) async {
    final api = _FakeWeReadApi(configured: false)..result = result;
    final login = _FakeLogin();
    await pumpPage(tester, api, login: login);

    expect(find.text('同步微信读书的阅读信息'), findsOneWidget);
    expect(find.text('扫码登录'), findsWidgets);
    expect(api.fetchCalls, 0);

    await tester.tap(find.byKey(const ValueKey('weread-login-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byKey(const ValueKey('weread-login-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('weread-qr-image')), findsOneWidget);
    expect(login.startCalls, 1);

    await tester.tap(find.byKey(const ValueKey('weread-login-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('weread-login-dialog')), findsNothing);
  });

  testWidgets('已扫码登录时显示账号，可退出登录', (tester) async {
    final api = _FakeWeReadApi(configured: true)
      ..result = result
      ..cachedResult = result;
    final login = _FakeLogin()..name = '测试用户';
    await pumpPage(tester, api, login: login);

    await tester.tap(find.byKey(const ValueKey('weread-login-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('weread-account-dialog')), findsOneWidget);
    expect(find.text('测试用户'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('weread-logout')));
    await tester.pumpAndSettle();

    expect(login.logoutCalls, 1);
    expect(find.text('已退出微信读书'), findsOneWidget);
    expect(find.text('同步微信读书的阅读信息'), findsOneWidget);
  });

  testWidgets('有上次抓取结果时先展示缓存，进入页面不自动联网', (tester) async {
    final api = _FakeWeReadApi(configured: true)
      ..result = result
      ..cachedResult = result;
    await pumpPage(tester, api);

    expect(api.fetchCalls, 0);
    expect(find.text('对比结果'), findsOneWidget);
    expect(find.text('三体'), findsOneWidget);
  });

  testWidgets('已配置 Key 且无缓存时自动拉取并展示新增 / 更新 / 一致', (tester) async {
    final api = _FakeWeReadApi(configured: true)..result = result;
    await pumpPage(tester, api);

    expect(api.fetchCalls, 1);
    expect(find.text('对比结果'), findsOneWidget);
    expect(find.text('新书'), findsOneWidget);
    expect(find.text('三体'), findsOneWidget);
    expect(find.text('活着'), findsOneWidget);
    expect(find.text('新增 1'), findsWidgets);
    expect(find.text('更新 1'), findsWidgets);
    expect(find.text('全部同步（1）'), findsOneWidget);
  });

  testWidgets('手机窄屏下汇总卡与书卡不溢出', (tester) async {
    final api = _FakeWeReadApi(configured: true)..result = result;
    await pumpPage(tester, api, size: const Size(360, 800));

    expect(find.text('对比结果'), findsOneWidget);
    expect(find.byKey(const ValueKey('weread-sync-all')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('筛选「更新」只留下有差异的书', (tester) async {
    final api = _FakeWeReadApi(configured: true)..result = result;
    await pumpPage(tester, api);

    await tester.tap(find.byKey(const ValueKey('weread-filter-updated')));
    await tester.pumpAndSettle();

    expect(find.text('三体'), findsOneWidget);
    expect(find.text('新书'), findsNothing);
    expect(find.text('活着'), findsNothing);
  });

  testWidgets('新增的书可以导入占位 EPUB，导入后变成本机已一致', (tester) async {
    final api = _FakeWeReadApi(configured: true)..result = result;
    await pumpPage(tester, api);

    expect(find.byKey(const ValueKey('weread-import-all')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('weread-import-r1')));
    await tester.pumpAndSettle();

    expect(api.imported, contains('r1'));
    expect(find.byKey(const ValueKey('weread-import-r1')), findsNothing);
    expect(find.textContaining('已导入《新书》'), findsWidgets);
    expect(find.text('已一致'), findsNWidgets(2));
  });

  testWidgets('没有本地书籍也能查看划线/想法', (tester) async {
    final api = _FakeWeReadApi(configured: true)
      ..result = result
      ..cachedResult = result
      ..notes = const <WeReadNote>[
        WeReadNote(
          id: 'n1',
          bookId: 'r1',
          quote: '给岁月以文明',
          thought: '很喜欢这句',
          chapterName: '第一章',
          createdAt: 1700000000,
        ),
      ];
    await pumpPage(tester, api);

    await tester.tap(find.byKey(const ValueKey('weread-notes-r1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('weread-notes-sheet')), findsOneWidget);
    expect(find.text('给岁月以文明'), findsOneWidget);
    expect(find.text('很喜欢这句'), findsOneWidget);
    expect(find.text('第一章'), findsOneWidget);
  });

  testWidgets('可重试的失败保持「更新」，不会假装已一致', (tester) async {
    final api = _FakeWeReadApi(configured: true)..result = result;
    api.applyResult = const WeReadApplyResult(
      message: '章节解析失败，划线未导入，可稍后重试',
      retryable: true,
    );
    await pumpPage(tester, api);

    await tester.tap(find.byKey(const ValueKey('weread-sync-r2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('weread-sync-r2')), findsOneWidget);
    expect(find.text('章节解析失败，划线未导入，可稍后重试'), findsWidgets);
  });

  testWidgets('点单本「同步」调用 apply，并把状态改成已一致', (tester) async {
    final api = _FakeWeReadApi(configured: true)..result = result;
    await pumpPage(tester, api);

    await tester.tap(find.byKey(const ValueKey('weread-sync-r2')));
    await tester.pumpAndSettle();

    expect(api.applied, contains('r2'));
    expect(find.text('已一致'), findsWidgets);
    expect(find.text('已一致'), findsNWidgets(2));
  });
}

class _FakeWeReadApi implements WeReadSyncApi {
  _FakeWeReadApi({required this.configured});

  bool configured;
  String? savedKey;
  WeReadFetchResult? result;
  WeReadFetchResult? cachedResult;
  List<WeReadNote> notes = const <WeReadNote>[];
  int fetchCalls = 0;
  final List<String> applied = <String>[];
  final List<String> imported = <String>[];

  @override
  Future<bool> hasKey() async => configured;

  @override
  Future<void> saveKey(String apiKey) async {
    savedKey = apiKey;
    configured = true;
  }

  @override
  Future<void> clearKey() async {
    configured = false;
  }

  @override
  Future<WeReadFetchResult?> loadCached() async => cachedResult;

  @override
  Future<List<WeReadNote>> notesFor(String bookId) async => notes;

  @override
  Future<WeReadFetchResult> fetch({
    void Function(String message)? onProgress,
  }) async {
    fetchCalls++;
    onProgress?.call('测试进度');
    return result!;
  }

  WeReadApplyResult applyResult = const WeReadApplyResult(message: '阅读进度已更新');

  @override
  Future<WeReadApplyResult> apply(WeReadDiff diff) async {
    applied.add(diff.remote.bookId);
    return applyResult;
  }

  @override
  Future<WeReadApplyResult> importAdded(WeReadDiff diff) async {
    imported.add(diff.remote.bookId);
    return WeReadApplyResult(
      message: '已导入《${diff.remote.title}》',
      importedBook: localBook(
        'imported-${diff.remote.bookId}',
        diff.remote.title,
      ),
    );
  }

  @override
  Future<void> ignore(WeReadDiff diff) async {}
}

class _FakeLogin implements WeReadLoginApi {
  String? name;
  int startCalls = 0;
  int logoutCalls = 0;

  @override
  Future<WeReadLoginSession> start() async {
    startCalls++;
    return _FakeLoginSession();
  }

  @override
  Future<String?> accountName() async => name;

  @override
  Future<void> logout() async {
    logoutCalls++;
    name = null;
  }
}

class _FakeLoginSession implements WeReadLoginSession {
  bool cancelled = false;

  @override
  String get qrUrl => 'https://weread.qq.com/web/confirm?uid=test';

  @override
  Future<WeReadLoginPoll> poll({String otp = ''}) async {
    return const WeReadLoginPoll(
      step: WeReadLoginStep.waiting,
      message: '等待微信扫码…',
    );
  }

  @override
  void cancel() => cancelled = true;
}
