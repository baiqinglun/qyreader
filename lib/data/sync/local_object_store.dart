/// 本地目录对象存储：**仅供测试**（应用里只有阿里云 OSS 后端）。
///
/// 生产代码不要引用它；单测用它验证同步引擎的读写/列举语义。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/sync/object_store.dart';

/// 用一个本地目录模拟桶。
class LocalObjectStore implements ObjectStore {
  /// 构造。
  LocalObjectStore(this.rootDir);

  /// 桶根目录。
  final Directory rootDir;

  /// 被读取过的 key（测试用：断言增量同步没有重复下载）。
  final List<String> readKeys = <String>[];

  /// .. 段转义成 %2E%2E，避免写到桶目录外面。
  String _escape(String key) => key.replaceAll('..', '%2E%2E');

  File _file(String key) =>
      File(p.join(rootDir.path, _escape(key).replaceAll('/', p.separator)));

  @override
  Future<void> put(String key, List<int> bytes) async {
    final file = _file(key);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<List<int>?> get(String key) async {
    readKeys.add(key);
    final file = _file(key);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<bool> exists(String key) => _file(key).exists();

  @override
  Future<List<String>> list(String prefix) async {
    if (!await rootDir.exists()) return const [];
    final out = <String>[];
    await for (final entity in rootDir.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: rootDir.path);
      final key = rel.replaceAll(p.separator, '/');
      if (key.startsWith(prefix)) out.add(key);
    }
    out.sort();
    return out;
  }

  @override
  Future<List<({String key, int modifiedAtMs})>> listDetailed(
    String prefix,
  ) async {
    if (!await rootDir.exists()) return const [];
    final out = <({String key, int modifiedAtMs})>[];
    await for (final entity in rootDir.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: rootDir.path);
      final key = rel.replaceAll(p.separator, '/');
      if (!key.startsWith(prefix)) continue;
      final stat = await entity.stat();
      out.add((key: key, modifiedAtMs: stat.modified.millisecondsSinceEpoch));
    }
    out.sort((a, b) => a.key.compareTo(b.key));
    return out;
  }

  @override
  Future<void> delete(String key) async {
    final file = _file(key);
    if (await file.exists()) await file.delete();
  }
}
