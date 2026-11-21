/// 导入记录：计数、序列化、持久化与清空。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/shelf/import_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

ImportRecord _record(String name, ImportRecordStatus status, {int at = 1}) =>
    ImportRecord(
      fileName: name,
      title: name,
      status: status,
      message: status == ImportRecordStatus.success ? '已加入书架' : '原因',
      at: at,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('统计成功 / 重复 / 失败', () {
    final summary = importRecordSummary([
      _record('a.epub', ImportRecordStatus.success),
      _record('b.epub', ImportRecordStatus.success),
      _record('c.epub', ImportRecordStatus.duplicate),
      _record('d.txt', ImportRecordStatus.failure),
    ]);
    expect(summary.success, 2);
    expect(summary.duplicate, 1);
    expect(summary.failure, 1);
    expect(summary.total, 4);
  });

  test('编码 / 解码往返，损坏输入回退空列表', () {
    final records = [
      _record('a.epub', ImportRecordStatus.success, at: 10),
      _record('b.epub', ImportRecordStatus.duplicate, at: 20),
    ];
    final decoded = decodeImportRecords(encodeImportRecords(records));
    expect(decoded.map((r) => r.fileName), ['b.epub', 'a.epub']);
    expect(decoded.first.status, ImportRecordStatus.duplicate);
    expect(decodeImportRecords('not json'), isEmpty);
    expect(decodeImportRecords('{"a":1}'), isEmpty);
  });

  test('记录写入 prefs，重启后仍在；清空后不再恢复', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(importHistoryControllerProvider.future);
    await container.read(importHistoryControllerProvider.notifier).addAll([
      _record('a.epub', ImportRecordStatus.success),
      _record('b.epub', ImportRecordStatus.failure),
    ]);

    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    final restoredRecords = await restored.read(
      importHistoryControllerProvider.future,
    );
    expect(restoredRecords, hasLength(2));
    expect(restoredRecords.first.fileName, 'a.epub');

    await restored.read(importHistoryControllerProvider.notifier).clear();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kImportHistoryPrefsKey), isNull);

    final afterClear = ProviderContainer();
    addTearDown(afterClear.dispose);
    expect(
      await afterClear.read(importHistoryControllerProvider.future),
      isEmpty,
    );
  });

  test('最多保留 200 条', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(importHistoryControllerProvider.future);
    await container.read(importHistoryControllerProvider.notifier).addAll([
      for (var i = 0; i < 205; i++)
        _record('$i.epub', ImportRecordStatus.success, at: i),
    ]);
    final records = await container.read(
      importHistoryControllerProvider.future,
    );
    expect(records, hasLength(kImportHistoryMax));
  });
}
