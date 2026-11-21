/// 微信读书对比：新增 / 更新 / 一致 / 删除，以及不覆盖本机更靠后的进度。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/settings/weread/weread_compare.dart';
import 'package:qy_reader/features/settings/weread/weread_models.dart';
import 'package:qy_reader/features/settings/weread/weread_sync_state.dart';

void main() {
  Book book(
    String id,
    String title, {
    String? author,
    double percent = 0,
    BookReadStatus status = BookReadStatus.unread,
    int? lastOpenedAt,
    int? finishedAt,
  }) {
    return Book(
      id: id,
      title: title,
      author: author,
      format: BookFormat.epub,
      filePath: '/tmp/$id.epub',
      fileSha256: 'sha-$id',
      fileSize: 1,
      addedAt: 0,
      updatedAt: 0,
      readStatus: status,
      lastOpenedAt: lastOpenedAt,
      finishedAt: finishedAt,
      hlc: '0000000000000-00000-aaaaaaaa',
      deviceId: 'aaaaaaaa',
    );
  }

  ShelfItem shelf(
    String id,
    String title, {
    String? author,
    double percent = 0,
    BookReadStatus status = BookReadStatus.unread,
    int? lastOpenedAt,
    int? finishedAt,
  }) {
    return ShelfItem(
      book: book(
        id,
        title,
        author: author,
        status: status,
        lastOpenedAt: lastOpenedAt,
        finishedAt: finishedAt,
      ),
      percent: percent,
    );
  }

  test('新增 / 更新 / 一致 三态齐全，更新带进度与划线差异', () {
    final diffs = compareWeReadBooks(
      remote: <WeReadBook>[
        const WeReadBook(bookId: 'r1', title: '新书', author: '甲'),
        const WeReadBook(
          bookId: 'r2',
          title: '三体',
          author: '刘慈欣',
          progressPercent: 60,
          noteCount: 3,
          reviewCount: 1,
          readUpdateTime: 2000000000,
        ),
        const WeReadBook(
          bookId: 'r3',
          title: '活着',
          author: '余华',
          progressPercent: 40,
          readUpdateTime: 100,
        ),
      ],
      localShelf: <ShelfItem>[
        shelf(
          'b2',
          '三体',
          author: '刘慈欣',
          percent: 0.2,
          status: BookReadStatus.reading,
          lastOpenedAt: 1000000000000,
        ),
        shelf(
          'b3',
          '活着',
          author: '余华',
          percent: 0.5,
          status: BookReadStatus.reading,
          lastOpenedAt: 2000000000000,
        ),
      ],
      state: WeReadSyncState.empty,
    );

    final byId = <String, WeReadDiff>{
      for (final diff in diffs) diff.remote.bookId: diff,
    };
    expect(byId['r1']!.kind, WeReadDiffKind.added);
    expect(byId['r1']!.local, isNull);

    final updated = byId['r2']!;
    expect(updated.kind, WeReadDiffKind.updated);
    expect(updated.local?.id, 'b2');
    expect(updated.changes.join(), contains('阅读进度 20% → 60%'));
    expect(updated.changes.join(), contains('新增 4 条划线/想法'));
    expect(updated.changes.join(), contains('最近阅读时间更晚'));
    expect(updated.newNoteCount, 4);

    expect(byId['r3']!.kind, WeReadDiffKind.synced);
    expect(byId['r3']!.changes, isEmpty);
  });

  test('上次同步的 link 优先于书名匹配', () {
    final diffs = compareWeReadBooks(
      remote: <WeReadBook>[
        const WeReadBook(bookId: 'r1', title: '三体', author: '刘慈欣'),
      ],
      localShelf: <ShelfItem>[shelf('b1', '完全不同的名字', author: '别人')],
      state: const WeReadSyncState(links: <String, String>{'r1': 'b1'}),
    );

    expect(diffs.single.kind, WeReadDiffKind.synced);
    expect(diffs.single.local?.id, 'b1');
  });

  test('括注、作者后缀与空白不影响书名匹配', () {
    final diffs = compareWeReadBooks(
      remote: <WeReadBook>[
        const WeReadBook(bookId: 'r1', title: '三体（全集）', author: '刘慈欣 著'),
      ],
      localShelf: <ShelfItem>[shelf('b1', '三体', author: '刘慈欣')],
      state: WeReadSyncState.empty,
    );

    expect(diffs.single.kind, WeReadDiffKind.synced);
    expect(diffs.single.local?.id, 'b1');
  });

  test('上次书架有、这次没有的书算删除，本机书仍保留', () {
    final diffs = compareWeReadBooks(
      remote: const <WeReadBook>[],
      localShelf: <ShelfItem>[shelf('b1', '旧书')],
      state: const WeReadSyncState(
        seen: <String>{'gone'},
        links: <String, String>{'gone': 'b1'},
        known: <String, WeReadKnownBook>{
          'gone': WeReadKnownBook(title: '旧书', author: '甲'),
        },
      ),
    );

    expect(diffs.single.kind, WeReadDiffKind.deleted);
    expect(diffs.single.remote.title, '旧书');
    expect(diffs.single.local?.id, 'b1');
  });

  test('本机进度更靠后时不产生更新，也不降级已读完状态', () {
    final diffs = compareWeReadBooks(
      remote: <WeReadBook>[
        const WeReadBook(
          bookId: 'r1',
          title: '书',
          progressPercent: 50,
          readUpdateTime: 100,
        ),
      ],
      localShelf: <ShelfItem>[
        shelf(
          'b1',
          '书',
          percent: 0.8,
          status: BookReadStatus.finished,
          lastOpenedAt: 2000000000000,
        ),
      ],
      state: WeReadSyncState.empty,
    );

    expect(diffs.single.kind, WeReadDiffKind.synced);
    expect(diffs.single.changes, isEmpty);
  });

  test('微信读书更晚但进度更靠前时也算更新（按编辑时间 LWW）', () {
    final remote = const WeReadBook(
      bookId: 'r1',
      title: '书',
      progressPercent: 20,
      readUpdateTime: 1800000000,
    );
    final local = <ShelfItem>[
      shelf(
        'b1',
        '书',
        percent: 0.6,
        status: BookReadStatus.reading,
        lastOpenedAt: 1700000000000,
      ),
    ];

    final diff = compareWeReadBooks(
      remote: <WeReadBook>[remote],
      localShelf: local,
      state: WeReadSyncState.empty,
    ).single;

    expect(diff.kind, WeReadDiffKind.updated);
    expect(diff.changes.join(), contains('微信读书更晚'));
  });

  test('微信读书累计阅读时长未导入时算更新，已导入后不再提示', () {
    final remote = const WeReadBook(
      bookId: 'r1',
      title: '书',
      progressPercent: 10,
      readingSeconds: 3600,
    );
    final local = <ShelfItem>[
      shelf('b1', '书', percent: 0.1, status: BookReadStatus.reading),
    ];

    final before = compareWeReadBooks(
      remote: <WeReadBook>[remote],
      localShelf: local,
      state: WeReadSyncState.empty,
    );
    expect(before.single.kind, WeReadDiffKind.updated);
    expect(before.single.changes.join(), contains('阅读时长 +1.0 小时'));

    final after = compareWeReadBooks(
      remote: <WeReadBook>[remote],
      localShelf: local,
      state: const WeReadSyncState(
        importedReadingSeconds: <String, int>{'r1': 3600},
      ),
    );
    expect(after.single.kind, WeReadDiffKind.synced);
    expect(after.single.changes, isEmpty);
  });

  test('有处理基线时，整本书评/合并想法不会永远显示新增', () {
    final diffs = compareWeReadBooks(
      remote: <WeReadBook>[
        const WeReadBook(
          bookId: 'r1',
          title: '书',
          progressPercent: 10,
          noteCount: 3,
          // 其中 1 条整本书评不计入划线导入；importedCounts 只有 2。
          reviewCount: 2,
        ),
      ],
      localShelf: <ShelfItem>[
        shelf('b1', '书', percent: 0.1, status: BookReadStatus.reading),
      ],
      state: const WeReadSyncState(
        importedCounts: <String, int>{'r1': 2},
        syncedNoteTotals: <String, int>{'r1': 5},
      ),
    );

    expect(diffs.single.newNoteCount, 0);
    expect(diffs.single.kind, WeReadDiffKind.synced);
    expect(diffs.single.changes, isEmpty);
  });

  test('远端笔记总数超过基线才算新增', () {
    final diffs = compareWeReadBooks(
      remote: <WeReadBook>[
        const WeReadBook(
          bookId: 'r1',
          title: '书',
          progressPercent: 10,
          noteCount: 3,
          reviewCount: 2,
        ),
      ],
      localShelf: <ShelfItem>[shelf('b1', '书', percent: 0.1)],
      state: const WeReadSyncState(syncedNoteTotals: <String, int>{'r1': 4}),
    );

    expect(diffs.single.newNoteCount, 1);
    expect(diffs.single.changes.join(), contains('新增 1 条划线/想法'));
  });

  test('微信读书读完时间会带日期提示，已记录后不再提示', () {
    const remote = WeReadBook(
      bookId: 'r1',
      title: '书',
      progressPercent: 100,
      finished: true,
      finishTime: 1700000000,
      readUpdateTime: 1700000000,
    );
    final local = <ShelfItem>[
      shelf('b1', '书', percent: 1, status: BookReadStatus.finished),
    ];

    final first = compareWeReadBooks(
      remote: const <WeReadBook>[remote],
      localShelf: local,
      state: const WeReadSyncState(),
    );
    expect(first.single.changes.join(), contains('读完时间 2023-11'));

    final after = compareWeReadBooks(
      remote: const <WeReadBook>[remote],
      localShelf: <ShelfItem>[
        shelf(
          'b1',
          '书',
          percent: 1,
          status: BookReadStatus.finished,
          lastOpenedAt: 1700000000000,
          finishedAt: 1700000000000,
        ),
      ],
      state: const WeReadSyncState(),
    );
    expect(after.single.changes, isEmpty);
    expect(after.single.kind, WeReadDiffKind.synced);
  });

  test('已导入 / 已跳过的划线从「新增」里扣除', () {
    final diffs = compareWeReadBooks(
      remote: <WeReadBook>[
        const WeReadBook(
          bookId: 'r1',
          title: '书',
          progressPercent: 10,
          noteCount: 4,
          reviewCount: 1,
        ),
      ],
      localShelf: <ShelfItem>[shelf('b1', '书', percent: 0.1)],
      state: const WeReadSyncState(
        importedCounts: <String, int>{'r1': 2},
        skippedCounts: <String, int>{'r1': 1},
      ),
    );

    expect(diffs.single.newNoteCount, 2);
    expect(diffs.single.kind, WeReadDiffKind.updated);
    expect(diffs.single.changes.join(), contains('新增 2 条划线/想法'));
  });
}
