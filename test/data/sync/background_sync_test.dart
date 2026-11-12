/// 背景同步：本机背景上传、另一台设备拉取，按 sha256 去重。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/data/sync/background_sync.dart';
import 'package:qy_reader/data/sync/local_object_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('qy-bgsync-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Uint8List fakeImage(int seed) =>
      Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, seed, ...List<int>.filled(64, seed)]);

  test('本机背景上传后，另一台设备同步能拉到文件与清单', () async {
    final store = LocalObjectStore(Directory('${root.path}/bucket'));
    final dirA = Directory('${root.path}/a/QYReader/backgrounds')
      ..createSync(recursive: true);
    File('${dirA.path}/bg-1.jpg').writeAsBytesSync(fakeImage(1));

    final a = BackgroundSync(store: store, spaceId: 's1', dir: dirA);
    final push = await a.run();
    expect(push.error, isNull);
    expect(push.uploaded, 1);
    expect(await store.exists('spaces/s1/backgrounds/manifest.json'), isTrue);

    // 另一台设备：空背景目录
    final dirB = Directory('${root.path}/b/QYReader/backgrounds');
    final b = BackgroundSync(store: store, spaceId: 's1', dir: dirB);
    final pull = await b.run();
    expect(pull.error, isNull);
    expect(pull.downloaded, 1);
    final names = dirB.listSync().whereType<File>().map((f) => f.path).toList();
    expect(names, hasLength(1));
    expect(File(names.single).readAsBytesSync(), fakeImage(1));
  });

  test('同一张背景第二次同步不重复上传', () async {
    final store = LocalObjectStore(Directory('${root.path}/bucket'));
    final dir = Directory('${root.path}/a/backgrounds')..createSync(recursive: true);
    File('${dir.path}/one.png').writeAsBytesSync(fakeImage(2));
    final sync = BackgroundSync(store: store, spaceId: 's1', dir: dir);

    final first = await sync.run();
    expect(first.uploaded, 1);
    final second = await sync.run();
    expect(second.uploaded, 0);
    expect(second.downloaded, 0);
  });
}
