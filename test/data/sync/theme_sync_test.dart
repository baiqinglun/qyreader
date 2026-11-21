/// 阅读主题同步：清单上传 / 拉取、背景路径可移植、删除传播。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qy_reader/data/sync/local_object_store.dart';
import 'package:qy_reader/data/sync/theme_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;
  late LocalObjectStore store;
  late Directory backgrounds;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    root = await Directory.systemTemp.createTemp('theme_sync_test');
    store = LocalObjectStore(Directory(p.join(root.path, 'bucket')));
    backgrounds = Directory(p.join(root.path, 'backgrounds'));
    await backgrounds.create(recursive: true);
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  Future<ThemeSyncResult> run(SharedPreferences prefs, Directory backgrounds) {
    return ThemeSync(
      store: store,
      spaceId: 'space1',
      prefs: prefs,
      backgroundsDir: backgrounds,
    ).run();
  }

  Map<String, dynamic> theme({
    String id = 'custom:1',
    String name = '我的主题',
    String image = '',
  }) {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'background': 'paper',
      'backgroundImage': image,
      if (image.isNotEmpty)
        'snapshot': <String, dynamic>{'backgroundImage': image, 'fontSize': 20},
    };
  }

  test('上传主题时背景只存文件名，另一设备还原成本机路径', () async {
    final image = File(p.join(backgrounds.path, 'bg.png'));
    await image.writeAsBytes(<int>[1, 2, 3]);
    final local = await prefs();
    await local.setString(
      ThemeSync.themesKey,
      jsonEncode([theme(image: image.path)]),
    );
    await local.setInt(ThemeSync.updatedAtKey, 1000);

    final up = await run(local, backgrounds);
    expect(up.error, isNull);
    expect(up.uploaded, 1);

    final raw = await store.get('spaces/space1/themes.json');
    final manifest = jsonDecode(utf8.decode(raw!)) as Map<String, dynamic>;
    expect(manifest['updatedAt'], 1000);
    final cloudTheme = (manifest['themes'] as List).single as Map;
    expect(cloudTheme['backgroundImage'], 'bg.png');
    expect((cloudTheme['snapshot'] as Map)['backgroundImage'], 'bg.png');

    // 模拟另一台设备：本机 prefs 为空、背景目录不同。
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final otherDir = Directory(p.join(root.path, 'other-backgrounds'));
    await otherDir.create(recursive: true);
    final other = await prefs();
    final down = await run(other, otherDir);
    expect(down.error, isNull);
    expect(down.downloaded, 1);

    final saved =
        jsonDecode(other.getString(ThemeSync.themesKey)!) as List<dynamic>;
    final savedTheme = saved.single as Map<String, dynamic>;
    expect(savedTheme['backgroundImage'], p.join(otherDir.path, 'bg.png'));
    expect(
      (savedTheme['snapshot'] as Map)['backgroundImage'],
      p.join(otherDir.path, 'bg.png'),
    );
  });

  test('删除主题也会同步：本机清单更新后上传空列表', () async {
    // 云端已有旧主题。
    await store.put(
      'spaces/space1/themes.json',
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'updatedAt': 1000,
          'themes': [theme()],
        }),
      ),
    );
    // 本机删光并更新时间戳。
    final local = await prefs();
    await local.setString(ThemeSync.themesKey, '[]');
    await local.setInt(ThemeSync.updatedAtKey, 2000);

    final up = await run(local, backgrounds);
    expect(up.error, isNull);
    expect(up.uploaded, 0);

    final raw = await store.get('spaces/space1/themes.json');
    final manifest = jsonDecode(utf8.decode(raw!)) as Map<String, dynamic>;
    expect(manifest['updatedAt'], 2000);
    expect(manifest['themes'], isEmpty);

    // 另一台设备还停在旧清单：拉取后清空。
    SharedPreferences.setMockInitialValues(<String, Object>{
      ThemeSync.themesKey: jsonEncode([theme()]),
      ThemeSync.updatedAtKey: 1000,
    });
    final other = await prefs();
    final down = await run(other, backgrounds);
    expect(down.error, isNull);
    expect(other.getString(ThemeSync.themesKey), '[]');
  });

  test('旧版本没有时间戳：与云端按 id 并集，不丢本机主题', () async {
    await store.put(
      'spaces/space1/themes.json',
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'updatedAt': 500,
          'themes': [theme(id: 'custom:remote', name: '云端主题')],
        }),
      ),
    );
    final local = await prefs();
    await local.setString(
      ThemeSync.themesKey,
      jsonEncode([theme(id: 'custom:local', name: '本机主题')]),
    );

    final result = await run(local, backgrounds);
    expect(result.error, isNull);
    expect(result.uploaded, 2);

    final saved = jsonDecode(local.getString(ThemeSync.themesKey)!) as List;
    final ids = {for (final t in saved) (t as Map)['id']};
    expect(ids, containsAll(<String>['custom:local', 'custom:remote']));
    expect(local.getInt(ThemeSync.updatedAtKey), greaterThan(500));
  });
}
