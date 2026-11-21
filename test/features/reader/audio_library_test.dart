/// 音频库：导入 / 删除 / manifest 解析 / 内置曲目清单。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qy_reader/data/sync/audio_sync.dart' show AudioSync;
import 'package:qy_reader/features/reader/tts/audio_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 把应用支持目录指到临时目录（path_provider Windows 走 FFI，无通道可 mock）。
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationSupportPath() async =>
      Directory('${root.path}/support').path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    root = await Directory.systemTemp.createTemp('qy-audiolib-');
    PathProviderPlatform.instance = _FakePathProvider(root);
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// 当前控制器（容器内读取，keepAlive）。
  AudioLibraryController controller() =>
      container.read(audioLibraryControllerProvider.notifier);

  List<AudioTrack> state() => container.read(audioLibraryControllerProvider);

  test('内置曲目清单齐全且标记为内置', () {
    expect(kBuiltinAudioTracks, hasLength(3));
    expect(kBuiltinAudioTracks.map((t) => t.id), contains('builtin-rain'));
    for (final t in kBuiltinAudioTracks) {
      expect(t.isBuiltin, isTrue);
      expect(t.asset, startsWith('assets/music/'));
      expect(t.assetSourceKey(), startsWith('music/'));
    }
    // allAudioTracks：内置在前，导入在后
    final merged = allAudioTracks([
      const AudioTrack.imported(id: 'x1', name: '我的音乐', fileName: 'x1.mp3'),
    ]);
    expect(merged.first.isBuiltin, isTrue);
    expect(merged.last.id, 'x1');
  });

  test('导入音频：复制进 music/ 目录并写 manifest', () async {
    final src = File('${root.path}/source.mp3')
      ..writeAsBytesSync(List<int>.filled(64, 3));
    final track = await controller().importFromFile(src.path);

    expect(track.name, 'source');
    expect(track.isBuiltin, isFalse);
    expect(state(), hasLength(1));

    final dir = await audioLibraryDir();
    final saved = File('${dir.path}/${track.fileName}');
    expect(await saved.exists(), isTrue);
    expect(await saved.length(), 64);

    // manifest 落了 prefs（AudioSync 用同一个 key 读取）
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AudioSync.prefsKey), isNotNull);
  });

  test('不支持扩展名 / 超大文件被拒绝', () async {
    final bad = File('${root.path}/song.txt')..writeAsBytesSync([1, 2, 3]);
    expect(
      () => controller().importFromFile(bad.path),
      throwsA(isA<AudioImportException>()),
    );
    expect(state(), isEmpty);
  });

  test('删除导入音频：文件与 manifest 一起消失', () async {
    final src = File('${root.path}/song.mp3')
      ..writeAsBytesSync(List<int>.filled(32, 5));
    final track = await controller().importFromFile(src.path);
    expect(state(), hasLength(1));

    await controller().deleteTrack(track.id);
    expect(state(), isEmpty);
    final dir = await audioLibraryDir();
    expect(File('${dir.path}/${track.fileName}').existsSync(), isFalse);
  });

  test('manifest 解析：坏条目跳过、路径穿越拒绝', () {
    final tracks = parseAudioManifest(
      '{"v":1,"tracks":['
      '{"id":"a1","name":"好音频","file":"a1.mp3"},'
      '{"id":"","name":"无id","file":"b.mp3"},'
      '{"id":"a2","name":"穿越","file":"../a2.mp3"},'
      '"junk"'
      ']}',
    );
    expect(tracks, hasLength(1));
    expect(tracks.single.id, 'a1');

    expect(parseAudioManifest('not json'), isEmpty);
    expect(parseAudioManifest('{"tracks":null}'), isEmpty);
  });
}
