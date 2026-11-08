/// 本地目录对象存储：用文件系统模拟 S3 桶（M4 打底，接口不变）。
///
/// key 直接映射为相对路径；key 中的非法片段做最小转义，杜绝路径穿越。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/sync/object_store.dart';

/// 本地目录对象存储。
class LocalObjectStore implements ObjectStore {
  /// 构造：根目录即「桶」。
  LocalObjectStore(this.rootDir);

  /// 桶根目录。
  final Directory rootDir;

  @override
  Future<void> put(String key, List<int> bytes) async {
    final file = _fileOf(key);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<List<int>?> get(String key) async {
    final file = _fileOf(key);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<List<String>> list(String prefix) async {
    if (!await rootDir.exists()) return const [];
    final result = <String>[];
    await for (final entity in rootDir.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = p
          .relative(entity.path, from: rootDir.path)
          .replaceAll(r'\', '/');
      if (!rel.startsWith(prefix)) continue;
      result.add(_unescapeKey(rel));
    }
    result.sort();
    return result;
  }

  @override
  Future<void> delete(String key) async {
    final file = _fileOf(key);
    if (await file.exists()) await file.delete();
  }

  File _fileOf(String key) => File(p.join(rootDir.path, _escapeKey(key)));

  /// key → 安全相对路径：`.`/`..` 段整段百分号转义，杜绝路径穿越。
  String _escapeKey(String key) => key
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .map((segment) {
        if (segment == '.' || segment == '..') {
          return segment.replaceAll('.', '%2E');
        }
        return segment.replaceAll('%', '%25');
      })
      .join(Platform.pathSeparator);

  String _unescapeKey(String rel) => rel;
}
