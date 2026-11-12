/// 阅读页活动标记的读写单测（进程被杀后恢复阅读页的依据）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/reader/reader_active_marker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('标记 → 读取 → 清除', () async {
    expect(await activeReaderBook(), isNull);

    await markReaderActive('book-1');
    expect(await activeReaderBook(), 'book-1');

    await clearReaderActive();
    expect(await activeReaderBook(), isNull);
  });

  test('重复标记覆盖旧值', () async {
    await markReaderActive('book-1');
    await markReaderActive('book-2');
    expect(await activeReaderBook(), 'book-2');
  });

  test('清除不存在的标记是安全的', () async {
    await clearReaderActive();
    expect(await activeReaderBook(), isNull);
  });
}
