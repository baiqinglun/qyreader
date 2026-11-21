/// 听书背景音乐（导入音频）的同步：音频文件与清单走同一个桶空间。
///
/// 与字体同步（font_sync.dart）同一套协议：
///
/// - 音频文件按内容寻址上传到 `spaces/<空间>/music/track-<sha256>.<ext>`；
/// - 清单 `spaces/<空间>/music/manifest.json` 记录 `{id, name, sha256, ext}`；
/// - 拉取时按 sha256 去重：云端有、本地没有的音频下载到 `music/` 并追加进
///   本机 manifest（prefs 由 `AudioLibraryController` 读取）。
///
/// 语义是「并集」：本设备删音频不会删别的设备的（音频是小体积个人资产，
/// 宁可留着）。内置曲目打包在 APK 里，不参与同步。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/sync/object_store.dart';
import '../../domain/sync/sync_status.dart';

/// 音频同步结果。
class AudioSyncResult {
  /// 构造。
  const AudioSyncResult({
    this.uploaded = 0,
    this.downloaded = 0,
    this.bytes = 0,
    this.error,
  });

  /// 本次上传的音频数。
  final int uploaded;

  /// 本次下载的音频数。
  final int downloaded;

  /// 本次传输的字节数。
  final int bytes;

  /// 失败原因（null = 成功）。
  final String? error;
}

/// 一个音频条目（只保留同步需要的字段）。
class SyncAudioEntry {
  /// 构造。
  const SyncAudioEntry({
    required this.id,
    required this.name,
    required this.fileName,
    required this.sha256,
    required this.ext,
  });

  /// 本机音频 id（决定文件名；不同设备可能不同）。
  final String id;

  /// 展示名。
  final String name;

  /// 本机 `music/` 下的文件名。
  final String fileName;

  /// 文件内容 sha256（跨设备去重的真正身份）。
  final String sha256;

  /// 扩展名（mp3 / m4a / ...）。
  final String ext;

  /// 云端清单条目。
  Map<String, dynamic> toCloudMap() => <String, dynamic>{
    'id': id,
    'name': name,
    'sha256': sha256,
    'ext': ext,
  };

  /// 本机 manifest 条目（与 `AudioTrack.toMap` 同格式）。
  Map<String, dynamic> toLocalMap() => <String, dynamic>{
    'id': id,
    'name': name,
    'file': fileName,
  };
}

/// 音频同步器：上传本机音频、拉取云端缺失音频。
class AudioSync {
  /// 构造。[dir] 是音频目录（`<应用支持目录>/music`）。
  AudioSync({
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

  /// 本机音频 manifest 的 prefs key（与 `AudioLibraryController` 共用）。
  static const String prefsKey = 'reader.audio';

  String get _prefix => 'spaces/$_spaceId/music/';
  String get _manifestKey => '${_prefix}manifest.json';

  /// 对齐两边：先传本机音频，再拉云端缺的。
  Future<AudioSyncResult> run({
    void Function(SyncProgress progress)? onProgress,
  }) async {
    var uploaded = 0;
    var downloaded = 0;
    var bytes = 0;
    try {
      await _dir.create(recursive: true);
      final local = _readLocalEntries();

      // 1) 本机有、云端没有的音频：上传文件
      final localEntries = <SyncAudioEntry>[];
      final cloudEntries = <String, SyncAudioEntry>{};
      for (final entry in local) {
        final file = File(p.join(_dir.path, entry.fileName));
        if (!await file.exists()) continue;
        final data = await file.readAsBytes();
        final sha = sha256.convert(data).toString();
        final entryWithSha = SyncAudioEntry(
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
            '正在上传音频《${entry.name}》',
            uploaded,
            local.length,
          ));
          await _store.put(key, data);
          uploaded++;
          bytes += data.length;
        }
      }

      // 2) 云端有、本机没有的音频：下载并写进本机 manifest
      final cloud = await _readCloudEntries();
      final merged = <SyncAudioEntry>[...localEntries];
      for (final entry in cloud) {
        if (cloudEntries.containsKey(entry.sha256)) continue;
        final data = await _store.get(_blobKey(entry.sha256, entry.ext));
        if (data == null) continue;
        final id = entry.id.isEmpty ? entry.sha256.substring(0, 10) : entry.id;
        final safeName = _uniqueFileName(merged, id, entry.ext);
        onProgress?.call(SyncProgress(
          '正在同步音频《${entry.name}》',
          downloaded,
          cloud.length,
        ));
        final target = File(p.join(_dir.path, safeName));
        if (!await target.exists()) {
          await target.writeAsBytes(data, flush: true);
        }
        bytes += data.length;
        downloaded++;
        final pulled = SyncAudioEntry(
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
            'tracks': merged.map((e) => e.toLocalMap()).toList(),
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
              'tracks': cloudEntries.values.map((e) => e.toCloudMap()).toList(),
            }),
          ),
        ),
      );
      return AudioSyncResult(
        uploaded: uploaded,
        downloaded: downloaded,
        bytes: bytes,
      );
    } catch (e) {
      return AudioSyncResult(
        uploaded: uploaded,
        downloaded: downloaded,
        bytes: bytes,
        error: '$e',
      );
    }
  }

  String _blobKey(String sha, String ext) => '${_prefix}track-$sha.$ext';

  String _uniqueFileName(List<SyncAudioEntry> existing, String id, String ext) {
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
  List<SyncAudioEntry> _readLocalEntries() {
    final raw = _prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return const <SyncAudioEntry>[];
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const <SyncAudioEntry>[];
    }
    if (decoded is! Map) return const <SyncAudioEntry>[];
    final list = decoded['tracks'];
    if (list is! List) return const <SyncAudioEntry>[];
    final out = <SyncAudioEntry>[];
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
      out.add(SyncAudioEntry(
        id: id,
        name: name,
        fileName: file,
        sha256: '',
        ext: ext.isEmpty ? 'mp3' : ext,
      ));
    }
    return out;
  }

  /// 读云端清单；不存在或损坏按空处理。
  Future<List<SyncAudioEntry>> _readCloudEntries() async {
    final bytes = await _store.get(_manifestKey);
    if (bytes == null) return const <SyncAudioEntry>[];
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return const <SyncAudioEntry>[];
    }
    if (decoded is! Map) return const <SyncAudioEntry>[];
    final list = decoded['tracks'];
    if (list is! List) return const <SyncAudioEntry>[];
    final out = <SyncAudioEntry>[];
    for (final item in list) {
      if (item is! Map) continue;
      final id = item['id'];
      final name = item['name'];
      final sha = item['sha256'];
      final ext = item['ext'];
      if (id is! String || id.isEmpty) continue;
      if (name is! String || name.isEmpty) continue;
      if (sha is! String || sha.length < 16) continue;
      final e = ext is String && ext.isNotEmpty ? ext : 'mp3';
      out.add(SyncAudioEntry(
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
