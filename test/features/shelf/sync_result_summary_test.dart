/// 同步结果提示文案（书架快捷同步 / 同步面板共用）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/sync/sync_status.dart';
import 'package:qy_reader/features/shelf/widgets/sync_sheet.dart';

void main() {
  test('没有改动时提示已是最新', () {
    expect(syncResultSummary(const SyncResult()), '已是最新，没有需要同步的改动');
  });

  test('有上传 / 合并 / 文件 / 字体时逐项列出', () {
    final summary = syncResultSummary(const SyncResult(
      pushed: 2,
      applied: 3,
      backedUpFiles: 1,
      backedUpBytes: 2048,
      fontsSynced: 1,
    ));
    expect(summary, contains('上传 2 条改动'));
    expect(summary, contains('合并 3 处云端改动'));
    expect(summary, contains('补齐 1 个本地文件（2 KB）'));
    expect(summary, contains('同步 1 个字体'));
  });

  test('失败时给出原因', () {
    expect(
      syncResultSummary(const SyncResult(error: 'no network')),
      '同步失败：no network',
    );
  });
}
