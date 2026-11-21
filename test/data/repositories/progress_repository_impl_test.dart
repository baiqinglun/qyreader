/// ProgressRepositoryImpl 单测：内存 SQLite，验证 furthest max 合并。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/db/app_database.dart';
import 'package:qy_reader/core/hlc.dart';
import 'package:qy_reader/core/locator.dart';
import 'package:qy_reader/data/repositories/progress_repository_impl.dart';

void main() {
  late AppDatabase db;
  late ProgressRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ProgressRepositoryImpl(
      db: db,
      hlcClock: HlcClock(deviceId: 'testdev1'),
      deviceId: 'testdev1',
    );
  });

  tearDown(() async => db.close());

  test('首次保存：当前与最远一致', () async {
    await repo.saveProgress(
      bookId: 'b1',
      locator: '{"v":1,"percent":0.2}',
      percent: 0.2,
    );
    final progress = await repo.getProgress('b1');
    expect(progress!.percent, 0.2);
    expect(progress.furthestPercent, 0.2);
  });

  test('前进：furthest 跟随前进并记录新 locator', () async {
    await repo.saveProgress(bookId: 'b1', locator: '{"p":1}', percent: 0.2);
    await repo.saveProgress(bookId: 'b1', locator: '{"p":2}', percent: 0.5);
    final progress = await repo.getProgress('b1');
    expect(progress!.percent, 0.5);
    expect(progress.furthestPercent, 0.5);
    expect(progress.furthestLocator, '{"p":2}');
  });

  test('回退：当前进度回退，furthest 永不回退', () async {
    await repo.saveProgress(bookId: 'b1', locator: '{"p":1}', percent: 0.8);
    await repo.saveProgress(bookId: 'b1', locator: '{"p":2}', percent: 0.3);
    final progress = await repo.getProgress('b1');
    expect(progress!.percent, 0.3);
    expect(progress.furthestPercent, 0.8);
    // 最远 locator 保留在 0.8 时的位置
    expect(progress.furthestLocator, '{"p":1}');
  });

  test('每次保存同事务追加一条 progress sync_op', () async {
    await repo.saveProgress(bookId: 'b1', locator: '{"p":1}', percent: 0.2);
    await repo.saveProgress(bookId: 'b1', locator: '{"p":2}', percent: 0.3);
    final ops = await db.select(db.syncOps).get();
    expect(ops, hasLength(2));
    expect(ops.every((op) => op.entity == 'progress'), isTrue);
    expect(ops.last.payload, contains('"furthestPercent"'));
  });

  test('未读过的书返回 null', () async {
    expect(await repo.getProgress('nope'), isNull);
  });

  group('外部百分比进度（微信读书）', () {
    test('按章节字数换算章索引与章内偏移', () {
      final position = ProgressRepositoryImpl.positionForPercent(
        const <({int charCount, String href})>[
          (charCount: 100, href: 'c0'),
          (charCount: 100, href: 'c1'),
          (charCount: 100, href: 'c2'),
        ],
        0.5,
      );
      expect(position, isNotNull);
      expect(position!.chapterIndex, 1);
      expect(position.offset, 50);
      expect(position.href, 'c1');

      final later = ProgressRepositoryImpl.positionForPercent(
        const <({int charCount, String href})>[
          (charCount: 100, href: 'c0'),
          (charCount: 100, href: 'c1'),
          (charCount: 100, href: 'c2'),
        ],
        0.75,
      );
      expect(later!.chapterIndex, 2);
      expect(later.offset, 25);
    });

    test('章节字数全为 0 时按章节数落到大致章节', () {
      final position = ProgressRepositoryImpl.positionForPercent(
        const <({int charCount, String href})>[
          (charCount: 0, href: 'c0'),
          (charCount: 0, href: 'c1'),
          (charCount: 0, href: 'c2'),
        ],
        0.6,
      );
      expect(position, isNotNull);
      expect(position!.chapterIndex, 1);
      expect(position.offset, 0);
      expect(position.href, 'c1');
    });

    test('saveExternalProgress 写 locator + percent，并追加 sync_op', () async {
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              id: 'b1',
              title: '书',
              format: 'epub',
              filePath: '/tmp/b1.epub',
              fileSha256: 'sha',
              fileSize: 1,
              addedAt: 0,
              updatedAt: 0,
              hlc: '0000000000000-00000-testdev1',
              deviceId: 'testdev1',
            ),
          );
      await db.batch((batch) {
        batch.insert(
          db.chapters,
          ChaptersCompanion.insert(
            bookId: 'b1',
            idx: 0,
            href: 'c0.xhtml',
            charCount: const Value(100),
          ),
        );
        batch.insert(
          db.chapters,
          ChaptersCompanion.insert(
            bookId: 'b1',
            idx: 1,
            href: 'c1.xhtml',
            charCount: const Value(100),
          ),
        );
      });

      await repo.saveExternalProgress(bookId: 'b1', percent: 0.5);
      final progress = await repo.getProgress('b1');
      expect(progress, isNotNull);
      expect(progress!.percent, 0.5);
      final locator = locatorFromJson(progress.locator);
      expect(locator, isNotNull);
      expect(locator!.chapterIndex, 1);
      expect(locator.offset, 0);
      expect(locator.href, 'c1.xhtml');
      expect(locator.percent, 0.5);
      expect(await db.select(db.syncOps).get(), hasLength(1));
    });

    test('没有章节时退化为只有 percent 的 locator', () async {
      await repo.saveExternalProgress(bookId: 'no-chapters', percent: 0.3);
      final progress = await repo.getProgress('no-chapters');
      expect(progress!.percent, 0.3);
      final locator = locatorFromJson(progress.locator);
      expect(locator!.percent, 0.3);
      expect(locator.chapterIndex, isNull);
    });
  });
}
