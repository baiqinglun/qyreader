/// 音频同步：本机音频上传、另一台设备拉取，按 sha256 去重（并集语义）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/data/sync/audio_sync.dart';
import 'package:qy_reader/data/sync/local_object_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    root = await Directory.systemTemp.createTemp('qy-audiosync-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Uint8List fakeAudio() => Uint8List.fromList(<int>[
    0x49, 0x44, 0x33, 0x04, 0x00, 0x00, // "ID3" 头
    ...List<int>.filled(200, 0x11),
  ]);

  Future<void> seedDeviceA(LocalObjectStore store) async {
    final dirA = Directory('${root.path}/a/music')..createSync(recursive: true);
    final prefsA = await SharedPreferences.getInstance();
    File('${dirA.path}/tid1.mp3').writeAsBytesSync(fakeAudio());
    await prefsA.setString(
      AudioSync.prefsKey,
      jsonEncode(<String, dynamic>{
        'v': 1,
        'tracks': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'tid1', 'name': '海浪', 'file': 'tid1.mp3'},
        ],
      }),
    );
    final a = AudioSync(store: store, spaceId: 's1', prefs: prefsA, dir: dirA);
    final push = await a.run();
    expect(push.error, isNull);
    expect(push.uploaded, 1);
    expect(await store.exists('spaces/s1/music/manifest.json'), isTrue);
  }

  test('本机音频上传后，另一台设备同步能拉到文件与清单', () async {
    final store = LocalObjectStore(Directory('${root.path}/bucket'));
    await seedDeviceA(store);

    // 另一台设备：全新 prefs + 空音频目录
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefsB = await SharedPreferences.getInstance();
    final dirB = Directory('${root.path}/b/music');
    final b = AudioSync(store: store, spaceId: 's1', prefs: prefsB, dir: dirB);
    final pull = await b.run();
    expect(pull.error, isNull);
    expect(pull.downloaded, 1);

    final manifest =
        jsonDecode(prefsB.getString(AudioSync.prefsKey)!) as Map<String, dynamic>;
    final tracks = (manifest['tracks'] as List).cast<Map<String, dynamic>>();
    expect(tracks, hasLength(1));
    expect(tracks.single['name'], '海浪');
    final file = File('${dirB.path}/${tracks.single['file']}');
    expect(await file.exists(), isTrue);
    expect(await file.readAsBytes(), fakeAudio());
  });

  test('同一音频按 sha256 去重：第二次同步不再重复上传/下载', () async {
    final store = LocalObjectStore(Directory('${root.path}/bucket'));
    await seedDeviceA(store);

    // 设备 A 二次同步：什么都不传
    final prefsA = await SharedPreferences.getInstance();
    final dirA = Directory('${root.path}/a/music');
    final again = await AudioSync(
      store: store,
      spaceId: 's1',
      prefs: prefsA,
      dir: dirA,
    ).run();
    expect(again.uploaded, 0);
    expect(again.downloaded, 0);

    // 设备 B 二次同步：不再重复下载，目录里只有一份文件
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefsB = await SharedPreferences.getInstance();
    final dirB = Directory('${root.path}/b/music');
    final b = AudioSync(store: store, spaceId: 's1', prefs: prefsB, dir: dirB);
    expect((await b.run()).downloaded, 1);
    expect((await b.run()).downloaded, 0);
    final files = dirB
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.mp3'))
        .toList();
    expect(files, hasLength(1));
  });
}
