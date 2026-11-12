/// 阅读器启动前的书源恢复：本地文件在时不应触碰同步库。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/reader/reader_boot.dart';

Book _book(String path) => Book(
      id: 'b1',
      title: '测试书',
      format: BookFormat.epub,
      filePath: path,
      fileSha256: 'sha1',
      fileSize: 1,
      addedAt: 0,
      updatedAt: 0,
      hlc: '0000000000000-00000-aaaaaaaa',
      deviceId: 'aaaaaaaa',
    );

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('qy_reader_boot');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('本地书源存在：直接启动，不初始化同步仓储', () async {
    final file = File('${tempDir.path}/book.epub')
      ..writeAsBytesSync(const [1, 2, 3]);
    var restored = false;

    final triggered = await restoreBookFileIfNeeded(
      loadBook: () async => _book(file.path),
      restoreFromCloud: () async {
        restored = true;
      },
    );

    expect(triggered, isFalse);
    expect(restored, isFalse);
  });

  test('本地书源缺失：调用云端恢复', () async {
    var restored = 0;

    final triggered = await restoreBookFileIfNeeded(
      loadBook: () async => _book('${tempDir.path}/missing.epub'),
      restoreFromCloud: () async {
        restored++;
      },
    );

    expect(triggered, isTrue);
    expect(restored, 1);
  });

  test('云端恢复卡住：超时抛错，让调用方继续启动', () async {
    final pending = Completer<void>();

    await expectLater(
      restoreBookFileIfNeeded(
        loadBook: () async => null,
        restoreFromCloud: () => pending.future,
        syncTimeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
}
