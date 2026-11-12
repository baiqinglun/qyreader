/// 字体同步：本机字体上传、另一台设备拉取，按 sha256 去重。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/data/sync/font_sync.dart';
import 'package:qy_reader/data/sync/local_object_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    root = await Directory.systemTemp.createTemp('qy-fontsync-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Uint8List fakeFont() =>
      Uint8List.fromList(<int>[0x00, 0x01, 0x00, 0x00, ...List<int>.filled(120, 7)]);

  test('本机字体上传后，另一台设备同步能拉到文件与清单', () async {
    final store = LocalObjectStore(Directory('${root.path}/bucket'));
    final dirA = Directory('${root.path}/a/fonts')..createSync(recursive: true);
    final prefsA = await SharedPreferences.getInstance();
    final bytes = fakeFont();
    File('${dirA.path}/fid1.ttf').writeAsBytesSync(bytes);
    await prefsA.setString(
      FontSync.prefsKey,
      jsonEncode(<String, dynamic>{
        'v': 1,
        'fonts': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'fid1', 'name': '测试字体', 'file': 'fid1.ttf'},
        ],
      }),
    );

    final a = FontSync(
      store: store,
      spaceId: 's1',
      prefs: prefsA,
      dir: dirA,
    );
    final push = await a.run();
    expect(push.error, isNull);
    expect(push.uploaded, 1);
    expect(await store.exists('spaces/s1/fonts/manifest.json'), isTrue);

    // 另一台设备：全新 prefs + 空字体目录
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefsB = await SharedPreferences.getInstance();
    final dirB = Directory('${root.path}/b/fonts');
    final b = FontSync(
      store: store,
      spaceId: 's1',
      prefs: prefsB,
      dir: dirB,
    );
    final pull = await b.run();
    expect(pull.error, isNull);
    expect(pull.downloaded, 1);

    final manifest =
        jsonDecode(prefsB.getString(FontSync.prefsKey)!) as Map<String, dynamic>;
    final fonts = (manifest['fonts'] as List).cast<Map<String, dynamic>>();
    expect(fonts, hasLength(1));
    expect(fonts.single['name'], '测试字体');
    final file = File('${dirB.path}/${fonts.single['file']}');
    expect(await file.exists(), isTrue);
    expect(await file.readAsBytes(), bytes);
  });

  test('同一字体按 sha256 去重：第二次同步不再重复下载/上传', () async {
    final store = LocalObjectStore(Directory('${root.path}/bucket'));
    final dirA = Directory('${root.path}/a/fonts')..createSync(recursive: true);
    final prefsA = await SharedPreferences.getInstance();
    File('${dirA.path}/fid1.ttf').writeAsBytesSync(fakeFont());
    await prefsA.setString(
      FontSync.prefsKey,
      jsonEncode(<String, dynamic>{
        'v': 1,
        'fonts': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'fid1', 'name': '测试字体', 'file': 'fid1.ttf'},
        ],
      }),
    );
    final a = FontSync(store: store, spaceId: 's1', prefs: prefsA, dir: dirA);
    expect((await a.run()).uploaded, 1);
    final again = await a.run();
    expect(again.uploaded, 0);
    expect(again.downloaded, 0);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefsB = await SharedPreferences.getInstance();
    final dirB = Directory('${root.path}/b/fonts');
    final b = FontSync(store: store, spaceId: 's1', prefs: prefsB, dir: dirB);
    expect((await b.run()).downloaded, 1);
    final second = await b.run();
    expect(second.downloaded, 0);
    // 字体目录里只有一份文件，没有重复导入
    final files = dirB
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.ttf'))
        .toList();
    expect(files, hasLength(1));
  });
}
