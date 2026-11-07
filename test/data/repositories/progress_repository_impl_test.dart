/// ProgressRepositoryImpl 单测：内存 SQLite，验证 furthest max 合并。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/db/app_database.dart';
import 'package:qy_reader/core/hlc.dart';
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
}
