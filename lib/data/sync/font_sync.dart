/// 自定义阅读字体的同步：字体文件与清单走同一个桶空间。
///
/// 背景（v2.34.0）：字体原本只在本机（应用支持目录 `fonts/` + prefs
/// `reader.fonts`），换设备要重新导入。现在：
///
/// - 字体文件按内容寻址上传到 `spaces/<空间>/fonts/<sha256>.<ext>`；
/// - 清单 `spaces/<空间>/fonts/manifest.json` 记录 `{id, name, sha256, ext}`；
/// - 拉取时按 sha256 去重：云端有、本地没有的字体下载到 `fonts/` 并追加进
///   本机 manifest（prefs 由 `ReaderFontsController` 读取）。
///
/// 语义是「并集」：字体只在两端都不存在时才算真的删掉；本设备删字体不会
/// 把别的设备的删掉（字体是小体积个人资产，宁可留着）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/sync/sync_status.dart';
import '../../domain/sync/object_store.dart';

/// 字体同步结果。
class FontSyncResult {
  /// 构造。
  const FontSyncResult({
    this.uploaded = 0,
    this.downloaded = 0,
    this.bytes = 0,
    this.error,
  });

  /// 本次上传的字体数。
  final int uploaded;

  /// 本次下载的字体数。
  final int downloaded;

  /// 本次传输的字节数。
  final int bytes;

  /// 失败原因（null = 成功）。
  final String? error;
}

/// 一个字体条目（只保留同步需要的字段）。
class SyncFontEntry {
  /// 构造。
  const SyncFontEntry({
    required this.id,
    required this.name,
    required this.fileName,
    required this.sha256,
    required this.ext,
  });

  /// 本机字体 id（决定 family；不同设备可能不同）。
  final String id;

  /// 展示名。
  final String name;

  /// 本机 `fonts/` 下的文件名。
  final String fileName;

  /// 文件内容 sha256（跨设备去重的真正身份）。
  final String sha256;

  /// 扩展名（ttf / otf / ttc）。
  final String ext;

  /// 云端清单条目。
  Map<String, dynamic> toCloudMap() => <String, dynamic>{
    'id': id,
    'name': name,
    'sha256': sha256,
    'ext': ext,
  };

  /// 本机 manifest 条目（与 `ReaderFont.toMap` 同格式）。
  Map<String, dynamic> toLocalMap() => <String, dynamic>{
    'id': id,
    'name': name,
    'file': fileName,
  };
}

/// 字体同步器：上传本机字体、拉取云端缺失字体。
class FontSync {
  /// 构造。[dir] 是字体目录（`<应用支持目录>/fonts`）。
  FontSync({
    required ObjectStore store,
    required String spaceId,
    required SharedPreferences prefs,
    required Directory dir,
  }) : _store = store,
       _spaceId = spaceId,
       _prefs = prefs,
       _dir = dir;

  final ObjectStore _store;
  final String _spaceId;
  final SharedPreferences _prefs;
  final Directory _dir;

  /// 本机字体 manifest 的 prefs key（与 `ReaderFontsController` 共用）。
  static const String prefsKey = 'reader.fonts';

  String get _prefix => 'spaces/$_spaceId/fonts/';
  String get _manifestKey => '${_prefix}manifest.json';

  /// 对齐两边：先传本机字体，再拉云端缺的。
  Future<FontSyncResult> run({
    void Function(SyncProgress progress)? onProgress,
  }) async {
    var uploaded = 0;
    var downloaded = 0;
    var bytes = 0;
    try {
      await _dir.create(recursive: true);
      final local = _readLocalEntries();

      // 1) 本机有、云端没有的字体：上传文件
      final localEntries = <SyncFontEntry>[];
      final cloudEntries = <String, SyncFontEntry>{};
      for (final entry in local) {
        final file = File(p.join(_dir.path, entry.fileName));
        if (!await file.exists()) continue;
        final data = await file.readAsBytes();
        final sha = sha256.convert(data).toString();
        final entryWithSha = SyncFontEntry(
          id: entry.id,
          name: entry.name,
          fileName: entry.fileName,
          sha256: sha,
          ext: entry.ext,
        );
        localEntries.add(entryWithSha);
        cloudEntries[sha] = entryWithSha;
        final key = _blobKey(sha, entry.ext);
        if (!await _store.exists(key)) {
          onProgress?.call(SyncProgress(
            '正在上传字体《${entry.name}》',
            uploaded,
            local.length,
          ));
          await _store.put(key, data);
          uploaded++;
          bytes += data.length;
        }
      }

      // 2) 云端有、本机没有的字体：下载并写进本机 manifest
      final cloud = await _readCloudEntries();
      final merged = <SyncFontEntry>[...localEntries];
      for (final entry in cloud) {
        if (cloudEntries.containsKey(entry.sha256)) continue;
        final data = await _store.get(_blobKey(entry.sha256, entry.ext));
        if (data == null) continue;
        final id = entry.id.isEmpty ? entry.sha256.substring(0, 10) : entry.id;
        final safeName = _uniqueFileName(merged, id, entry.ext);
        onProgress?.call(SyncProgress(
          '正在同步字体《${entry.name}》',
          downloaded,
          cloud.length,
        ));
        final target = File(p.join(_dir.path, safeName));
        if (!await target.exists()) {
          await target.writeAsBytes(data, flush: true);
        }
        bytes += data.length;
        downloaded++;
        final pulled = SyncFontEntry(
          id: safeName.substring(0, safeName.lastIndexOf('.')),
          name: entry.name,
          fileName: safeName,
          sha256: entry.sha256,
          ext: entry.ext,
        );
        merged.add(pulled);
        cloudEntries[entry.sha256] = pulled;
      }

      // 3) 写回两边清单
      if (merged.length != local.length) {
        await _prefs.setString(
          prefsKey,
          jsonEncode(<String, dynamic>{
            'v': 1,
            'fonts': merged.map((e) => e.toLocalMap()).toList(),
          }),
        );
      }
      // 云端清单每次都重写（几 KB，保证并集完整）；失败也不影响本次同步
      await _store.put(
        _manifestKey,
        Uint8List.fromList(
          utf8.encode(
            jsonEncode(<String, dynamic>{
              'v': 1,
              'updatedAt': DateTime.now().millisecondsSinceEpoch,
              'fonts': cloudEntries.values.map((e) => e.toCloudMap()).toList(),
            }),
          ),
        ),
      );
      return FontSyncResult(
        uploaded: uploaded,
        downloaded: downloaded,
        bytes: bytes,
      );
    } catch (e) {
      return FontSyncResult(
        uploaded: uploaded,
        downloaded: downloaded,
        bytes: bytes,
        error: '$e',
      );
    }
  }

  String _blobKey(String sha, String ext) => '${_prefix}font-$sha.$ext';

  String _uniqueFileName(List<SyncFontEntry> existing, String id, String ext) {
    final taken = existing.map((e) => e.fileName).toSet();
    var name = '$id.$ext';
    var n = 2;
    while (taken.contains(name)) {
      name = '$id-$n.$ext';
      n++;
    }
    return name;
  }

  /// 读本机 manifest（prefs）；坏条目跳过。
  List<SyncFontEntry> _readLocalEntries() {
    final raw = _prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return const <SyncFontEntry>[];
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const <SyncFontEntry>[];
    }
    if (decoded is! Map) return const <SyncFontEntry>[];
    final list = decoded['fonts'];
    if (list is! List) return const <SyncFontEntry>[];
    final out = <SyncFontEntry>[];
    for (final item in list) {
      if (item is! Map) continue;
      final id = item['id'];
      final name = item['name'];
      final file = item['file'];
      if (id is! String || id.isEmpty) continue;
      if (name is! String || name.isEmpty) continue;
      if (file is! String || file.isEmpty) continue;
      if (file.contains('/') || file.contains('\\') || file.contains('..')) {
        continue;
      }
      final ext = p.extension(file).replaceFirst('.', '').toLowerCase();
      out.add(SyncFontEntry(
        id: id,
        name: name,
        fileName: file,
        sha256: '',
        ext: ext.isEmpty ? 'ttf' : ext,
      ));
    }
    return out;
  }

  /// 读云端清单；不存在或损坏按空处理。
  Future<List<SyncFontEntry>> _readCloudEntries() async {
    final bytes = await _store.get(_manifestKey);
    if (bytes == null) return const <SyncFontEntry>[];
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return const <SyncFontEntry>[];
    }
    if (decoded is! Map) return const <SyncFontEntry>[];
    final list = decoded['fonts'];
    if (list is! List) return const <SyncFontEntry>[];
    final out = <SyncFontEntry>[];
    for (final item in list) {
      if (item is! Map) continue;
      final id = item['id'];
      final name = item['name'];
      final sha = item['sha256'];
      final ext = item['ext'];
      if (id is! String || id.isEmpty) continue;
      if (name is! String || name.isEmpty) continue;
      if (sha is! String || sha.length < 16) continue;
      final e = ext is String && ext.isNotEmpty ? ext : 'ttf';
      out.add(SyncFontEntry(
        id: id,
        name: name,
        fileName: '$id.$e',
        sha256: sha,
        ext: e,
      ));
    }
    return out;
  }
}
