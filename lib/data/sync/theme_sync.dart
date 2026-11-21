/// 阅读主题同步：自定义主题清单整体同步（最后写入者优先）。
///
/// 主题不是书籍数据，不进 `sync_ops`：整个自定义主题列表 + 更新时间放在
/// `spaces/<空间>/themes.json`（`{updatedAt, themes}`）。同一份清单按
/// `updatedAt` 取新；本机已有主题但还没有时间戳（旧版本升级上来）时，
/// 与云端按 id 取并集，本机同名主题优先，避免第一次同步丢掉本机主题。
///
/// 主题里的背景图只存**文件名**（不存绝对路径），下载时还原到本机的
/// `<应用文档>/QYReader/backgrounds/`；图片文件本身由 `BackgroundSync`
/// 负责传输，所以主题同步必须排在背景同步之后。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/sync/object_store.dart';

/// 主题同步结果。
class ThemeSyncResult {
  /// 构造。
  const ThemeSyncResult({this.uploaded = 0, this.downloaded = 0, this.error});

  /// 本次上传的主题数。
  final int uploaded;

  /// 本次拉取到的主题数。
  final int downloaded;

  /// 失败原因（null = 成功）。
  final String? error;
}

/// 主题同步器：上传 / 拉取自定义阅读主题清单。
class ThemeSync {
  /// 构造。[backgroundsDir] 是本机背景目录（`QYReader/backgrounds`）。
  ThemeSync({
    required ObjectStore store,
    required String spaceId,
    required SharedPreferences prefs,
    required Directory backgroundsDir,
  }) : _store = store,
       _spaceId = spaceId,
       _prefs = prefs,
       _backgroundsDir = backgroundsDir;

  final ObjectStore _store;
  final String _spaceId;
  final SharedPreferences _prefs;
  final Directory _backgroundsDir;

  /// 自定义主题在 prefs 里的 key（`ReaderThemesController` 共用）。
  static const String themesKey = 'reader.customThemes';

  /// 本机主题最后一次改动的时间（LWW 用；与云端清单的 `updatedAt` 比较）。
  static const String updatedAtKey = 'reader.themesSyncAt';

  String get _manifestKey => 'spaces/$_spaceId/themes.json';

  /// 执行一次主题同步。
  Future<ThemeSyncResult> run() async {
    try {
      final local = _decodeThemes(_prefs.getString(themesKey) ?? '[]');
      final localAt = _prefs.getInt(updatedAtKey) ?? 0;
      final remote = await _readRemote();

      // 旧版本没有时间戳：与云端并集后整体上传，不丢本机已有主题。
      if (localAt == 0 && local.isNotEmpty) {
        final merged = _merge(local, remote.themes);
        final now = DateTime.now().millisecondsSinceEpoch;
        await _writeLocal(merged, now);
        await _writeRemote(merged, now);
        return ThemeSyncResult(
          uploaded: merged.length,
          downloaded: remote.themes.length,
        );
      }
      if (remote.updatedAt > localAt) {
        await _writeLocal(remote.themes, remote.updatedAt);
        return ThemeSyncResult(downloaded: remote.themes.length);
      }
      if (localAt > remote.updatedAt) {
        await _writeRemote(local, localAt);
        return ThemeSyncResult(uploaded: local.length);
      }
      return const ThemeSyncResult();
    } catch (e) {
      return ThemeSyncResult(error: '$e');
    }
  }

  Future<({int updatedAt, List<Map<String, dynamic>> themes})>
  _readRemote() async {
    final bytes = await _store.get(_manifestKey);
    if (bytes == null) {
      return (updatedAt: 0, themes: const <Map<String, dynamic>>[]);
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        return (updatedAt: 0, themes: const <Map<String, dynamic>>[]);
      }
      final updatedAt = (decoded['updatedAt'] as num?)?.toInt() ?? 0;
      return (updatedAt: updatedAt, themes: _decodeList(decoded['themes']));
    } catch (_) {
      return (updatedAt: 0, themes: const <Map<String, dynamic>>[]);
    }
  }

  Future<void> _writeLocal(
    List<Map<String, dynamic>> themes,
    int updatedAt,
  ) async {
    final localized = [
      for (final theme in themes) _withBackground(theme, _localPath),
    ];
    await _prefs.setString(themesKey, jsonEncode(localized));
    await _prefs.setInt(updatedAtKey, updatedAt);
  }

  Future<void> _writeRemote(
    List<Map<String, dynamic>> themes,
    int updatedAt,
  ) async {
    final portable = [
      for (final theme in themes) _withBackground(theme, _fileName),
    ];
    await _store.put(
      _manifestKey,
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'updatedAt': updatedAt,
          'themes': portable,
        }),
      ),
    );
  }

  /// 本机列表与远端按 id 取并集；本机同名主题覆盖远端。
  List<Map<String, dynamic>> _merge(
    List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> remote,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final theme in remote) {
      byId[theme['id'] as String] = theme;
    }
    for (final theme in local) {
      byId[theme['id'] as String] = theme;
    }
    return byId.values.toList();
  }

  List<Map<String, dynamic>> _decodeThemes(String raw) {
    try {
      return _decodeList(jsonDecode(raw));
    } catch (_) {
      return const [];
    }
  }

  /// 只接受自定义主题（内置主题不需要同步）。
  List<Map<String, dynamic>> _decodeList(dynamic raw) {
    if (raw is! List) return const [];
    final themes = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final theme = Map<String, dynamic>.from(item);
      final id = theme['id'];
      if (id is String && id.startsWith('custom:')) themes.add(theme);
    }
    return themes;
  }

  /// 复制主题，把背景图路径（含快照里的）按 [map] 转换。
  Map<String, dynamic> _withBackground(
    Map<String, dynamic> theme,
    String Function(String path) map,
  ) {
    final copy = Map<String, dynamic>.from(theme);
    final image = copy['backgroundImage'];
    if (image is String && image.trim().isNotEmpty) {
      copy['backgroundImage'] = map(image);
    }
    final snapshot = copy['snapshot'];
    if (snapshot is Map) {
      final settings = Map<String, dynamic>.from(snapshot);
      final image = settings['backgroundImage'];
      if (image is String && image.trim().isNotEmpty) {
        settings['backgroundImage'] = map(image);
      }
      copy['snapshot'] = settings;
    }
    return copy;
  }

  String _fileName(String path) => p.basename(path);

  String _localPath(String name) =>
      p.join(_backgroundsDir.path, p.basename(name));
}
