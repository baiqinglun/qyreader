/// 阅读状态自动切换：打开 → 在读，进度 100% → 已读。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/reader/reader_controller.dart';

void main() {
  test('打开书（无进度）视为在读', () {
    expect(readStatusForProgress(null), BookReadStatus.reading);
    expect(readStatusForProgress(0), BookReadStatus.reading);
    expect(readStatusForProgress(0.5), BookReadStatus.reading);
  });

  test('进度到 100% 视为已读（允许浮点误差）', () {
    expect(readStatusForProgress(0.998), BookReadStatus.reading);
    expect(readStatusForProgress(kReadFinishedThreshold), BookReadStatus.finished);
    expect(readStatusForProgress(1.0), BookReadStatus.finished);
  });
}
