/// 阅读背景图的同步：背景文件与清单走同一个桶空间。
///
/// 背景图属于「资源」（和字体同级）：自定义阅读主题可以挂一张背景图，
/// 图片存放在 `<应用文档>/QYReader/backgrounds/`。为了让换设备后背景还在：
///
/// - 图片按内容寻址上传到 `spaces/<空间>/backgrounds/bg-<sha256>.<ext>`；
/// - 清单 `spaces/<空间>/backgrounds/manifest.json` 记录 `{sha256, fileName, ext}`；
/// - 拉取时按 sha256 去重：云端有、本机没有的图片下载回背景目录，并出现在
///   「设置 → 资源 → 背景」列表里（可直接给主题用）。
///
/// 语义是「并集」：本机删除背景不会删云端，下次同步会再拉回来；这与字体
/// 同步一致，避免误删别处的资产。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/sync/object_store.dart';
import '../../domain/sync/sync_status.dart';

/// 背景同步结果。
class BackgroundSyncResult {
  /// 构造。
  const BackgroundSyncResult({
    this.uploaded = 0,
    this.downloaded = 0,
    this.bytes = 0,
    this.error,
  });

  /// 本次上传的背景数。
  final int uploaded;

  /// 本次下载的背景数。
  final int downloaded;

  /// 本次传输的字节数。
  final int bytes;

  /// 失败原因（null = 成功）。
  final String? error;
}

/// 一个背景条目（只保留同步需要的字段）。
class SyncBackgroundEntry {
  /// 构造。
  const SyncBackgroundEntry({
    required this.sha256,
    required this.fileName,
    required this.ext,
  });

  /// 文件内容 sha256（跨设备去重的真正身份）。
  final String sha256;

  /// 本机文件名。
  final String fileName;

  /// 扩展名（jpg / jpeg / png / webp）。
  final String ext;

  /// 云端清单条目。
  Map<String, dynamic> toCloudMap() => <String, dynamic>{
    'sha256': sha256,
    'fileName': fileName,
    'ext': ext,
  };
}

/// 背景同步器：上传本机背景、拉取云端缺失背景。
class BackgroundSync {
  /// 构造。[dir] 是背景目录（`<应用文档>/QYReader/backgrounds`）。
  BackgroundSync({
    required ObjectStore store,
    required String spaceId,
    required Directory dir,
  }) : _store = store,
       _spaceId = spaceId,
       _dir = dir;

  final ObjectStore _store;
  final String _spaceId;
  final Directory _dir;

  /// 支持的图片扩展名。
  static const Set<String> imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  String get _prefix => 'spaces/$_spaceId/backgrounds/';
  String get _manifestKey => '${_prefix}manifest.json';

  /// 对齐两边：先传本机背景，再拉云端缺的。
  Future<BackgroundSyncResult> run({
    void Function(SyncProgress progress)? onProgress,
  }) async {
    var uploaded = 0;
    var downloaded = 0;
    var bytes = 0;
    try {
      await _dir.create(recursive: true);
      final local = <SyncBackgroundEntry>[];
      final localShas = <String>{};
      final files = await _listLocalFiles();
      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        final fileName = p.basename(file.path);
        final ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();
        final data = await file.readAsBytes();
        final sha = sha256.convert(data).toString();
        localShas.add(sha);
        local.add(SyncBackgroundEntry(
          sha256: sha,
          fileName: fileName,
          ext: ext,
        ));
        final key = _blobKey(sha, ext);
        if (!await _store.exists(key)) {
          onProgress?.call(SyncProgress(
            '正在上传背景 ${i + 1}/${files.length}',
            uploaded,
            files.length,
          ));
          await _store.put(key, data);
          uploaded++;
          bytes += data.length;
        }
      }

      // 云端有、本机没有：下载回背景目录（名字冲突时加序号）。
      final cloud = await _readCloudEntries();
      final localNames = local.map((e) => e.fileName).toSet();
      final merged = <SyncBackgroundEntry>[...local];
      for (final entry in cloud) {
        if (localShas.contains(entry.sha256)) continue;
        final data = await _store.get(_blobKey(entry.sha256, entry.ext));
        if (data == null) continue;
        final safeName = _uniqueFileName(localNames, entry);
        onProgress?.call(SyncProgress(
          '正在同步背景 ${downloaded + 1}/${cloud.length}',
          downloaded,
          cloud.length,
        ));
        final target = File(p.join(_dir.path, safeName));
        if (!await target.exists()) {
          await target.writeAsBytes(data, flush: true);
        }
        localShas.add(entry.sha256);
        localNames.add(safeName);
        bytes += data.length;
        downloaded++;
        merged.add(SyncBackgroundEntry(
          sha256: entry.sha256,
          fileName: safeName,
          ext: entry.ext,
        ));
      }

      await _store.put(
        _manifestKey,
        Uint8List.fromList(
          utf8.encode(
            jsonEncode(<String, dynamic>{
              'v': 1,
              'updatedAt': DateTime.now().millisecondsSinceEpoch,
              'backgrounds': merged.map((e) => e.toCloudMap()).toList(),
            }),
          ),
        ),
      );
      return BackgroundSyncResult(
        uploaded: uploaded,
        downloaded: downloaded,
        bytes: bytes,
      );
    } catch (e) {
      return BackgroundSyncResult(
        uploaded: uploaded,
        downloaded: downloaded,
        bytes: bytes,
        error: '$e',
      );
    }
  }

  String _blobKey(String sha, String ext) => '${_prefix}bg-$sha.$ext';

  String _uniqueFileName(Set<String> taken, SyncBackgroundEntry entry) {
    final preferred = entry.fileName.isEmpty
        ? 'bg-${entry.sha256.substring(0, 10)}.${entry.ext}'
        : p.basename(entry.fileName);
    if (!taken.contains(preferred)) return preferred;
    final stem = p.basenameWithoutExtension(preferred);
    var n = 2;
    var name = '$stem-$n.${entry.ext}';
    while (taken.contains(name)) {
      n++;
      name = '$stem-$n.${entry.ext}';
    }
    return name;
  }

  Future<List<File>> _listLocalFiles() async {
    if (!await _dir.exists()) return const <File>[];
    final out = <File>[];
    await for (final entity in _dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).replaceFirst('.', '').toLowerCase();
      if (!imageExtensions.contains(ext)) continue;
      out.add(entity);
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  /// 读云端清单；不存在或损坏按空处理。
  Future<List<SyncBackgroundEntry>> _readCloudEntries() async {
    final bytes = await _store.get(_manifestKey);
    if (bytes == null) return const <SyncBackgroundEntry>[];
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return const <SyncBackgroundEntry>[];
    }
    if (decoded is! Map) return const <SyncBackgroundEntry>[];
    final list = decoded['backgrounds'];
    if (list is! List) return const <SyncBackgroundEntry>[];
    final out = <SyncBackgroundEntry>[];
    for (final item in list) {
      if (item is! Map) continue;
      final sha = item['sha256'];
      final ext = item['ext'];
      final fileName = item['fileName'];
      if (sha is! String || sha.length < 16) continue;
      final safeExt = ext is String && ext.isNotEmpty ? ext : 'jpg';
      final name = fileName is String && fileName.isNotEmpty
          ? p.basename(fileName)
          : 'bg-${sha.substring(0, 10)}.$safeExt';
      out.add(SyncBackgroundEntry(
        sha256: sha,
        fileName: name,
        ext: safeExt,
      ));
    }
    return out;
  }
}
