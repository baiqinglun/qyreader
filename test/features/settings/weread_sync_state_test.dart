/// 微信读书同步状态：prefs 往返、损坏数据兜底。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/settings/weread/weread_models.dart';
import 'package:qy_reader/features/settings/weread/weread_sync_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('状态往返：link / seen / known / 导入计数 / 跳过计数', () async {
    const store = WeReadSyncStore();
    const state = WeReadSyncState(
      links: <String, String>{'r1': 'b1'},
      seen: <String>{'r1', 'r2'},
      known: <String, WeReadKnownBook>{
        'r1': WeReadKnownBook(title: '三体', author: '刘慈欣', cover: 'c'),
      },
      importedMarks: <String>{'m1', 'm2'},
      importedCounts: <String, int>{'r1': 2},
      syncedNoteTotals: <String, int>{'r1': 4},
      skippedCounts: <String, int>{'r1': 1},
      importedReadingSeconds: <String, int>{'r1': 3600},
      lastSyncAt: 1700000000000,
    );

    await store.save(state);
    final loaded = await store.load();

    expect(loaded.links, state.links);
    expect(loaded.seen, state.seen);
    expect(loaded.known['r1']!.title, '三体');
    expect(loaded.known['r1']!.cover, 'c');
    expect(loaded.importedMarks, state.importedMarks);
    expect(loaded.importedCounts['r1'], 2);
    expect(loaded.syncedNoteTotals['r1'], 4);
    expect(loaded.skippedCounts['r1'], 1);
    expect(loaded.importedReadingSeconds['r1'], 3600);
    expect(loaded.lastSyncAt, 1700000000000);
  });

  test('损坏 JSON 回退空状态，不让页面崩', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      WeReadSyncStore.prefsKey: '{oops',
    });
    const store = WeReadSyncStore();
    final loaded = await store.load();
    expect(loaded.links, isEmpty);
    expect(loaded.seen, isEmpty);
  });

  test('上次抓取快照往返：书名/进度/时长/笔记计数都保留', () async {
    const store = WeReadSyncStore();
    final snapshot = WeReadSnapshot(
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      albumCount: 2,
      hasMp: true,
      progressFailures: 1,
      books: <WeReadBook>[
        const WeReadBook(
          bookId: 'r1',
          title: '三体',
          author: '刘慈欣',
          progressPercent: 66,
          readingSeconds: 3600,
          noteCount: 3,
          reviewCount: 2,
          finished: true,
        ),
      ],
    );
    await store.saveSnapshot(snapshot);
    final loaded = await store.loadSnapshot();

    expect(loaded, isNotNull);
    expect(loaded!.books, hasLength(1));
    expect(loaded.books.single.title, '三体');
    expect(loaded.books.single.progressPercent, 66);
    expect(loaded.books.single.readingSeconds, 3600);
    expect(loaded.books.single.totalNotes, 5);
    expect(loaded.books.single.finished, isTrue);
    expect(loaded.albumCount, 2);
    expect(loaded.hasMp, isTrue);
    expect(loaded.progressFailures, 1);
    expect(loaded.fetchedAt.millisecondsSinceEpoch, 1700000000000);
  });

  test('清空状态', () async {
    const store = WeReadSyncStore();
    await store.save(const WeReadSyncState(seen: <String>{'r1'}));
    await store.clear();
    final loaded = await store.load();
    expect(loaded.seen, isEmpty);
  });
}
