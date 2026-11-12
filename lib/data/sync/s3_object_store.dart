/// S3 兼容对象存储（minio SDK；兼容阿里云 OSS / AWS S3 / R2 / B2 / MinIO）。
///
/// 桶内所有 key 都在构造时给定的前缀下（推荐给应用分配独立前缀/桶）。
/// 凭据由上层从 flutter_secure_storage 读取后注入，本类不落盘。
library;

import 'dart:typed_data';

import 'package:minio/minio.dart';

import '../../domain/sync/object_store.dart';

/// S3 对象存储实现。
class S3ObjectStore implements ObjectStore {
  /// 构造。
  S3ObjectStore({
    required this.endPoint,
    required this.bucket,
    required this.accessKey,
    required this.secretKey,
    this.prefix = '',
    this.region,
    this.useSSL = true,
    this.pathStyle = true,
    int? port,
  }) : _minio = Minio(
          endPoint: endPoint,
          accessKey: accessKey,
          secretKey: secretKey,
          port: port,
          useSSL: useSSL,
          region: region,
          // 阿里云 OSS / Cloudflare R2 只认虚拟主机风格（bucket 拼在域名前），
          // MinIO 默认路径风格；由配置决定。
          pathStyle: pathStyle,
        );

  /// 服务端点（域名或 IP，不含协议）。
  final String endPoint;

  /// 桶名。
  final String bucket;

  /// 访问密钥。
  final String accessKey;

  /// 私钥。
  final String secretKey;

  /// 对象 key 前缀（如 `qyreader/`；空 = 桶根）。
  final String prefix;

  /// 区域（AWS 必填，MinIO 可空）。
  final String? region;

  /// 是否 HTTPS。
  final bool useSSL;

  /// 是否路径风格（`端点/桶/对象`）；false = 虚拟主机风格。
  final bool pathStyle;

  final Minio _minio;

  String _full(String key) => '${prefix.isEmpty ? '' : prefix}$key';

  String _strip(String fullKey) =>
      prefix.isEmpty ? fullKey : fullKey.substring(prefix.length);

  @override
  Future<void> put(String key, List<int> bytes) async {
    final data = Uint8List.fromList(bytes);
    await _minio.putObject(
      bucket,
      _full(key),
      Stream<Uint8List>.value(data),
      size: data.length,
    );
  }

  @override
  Future<List<int>?> get(String key) async {
    try {
      final stream = await _minio.getObject(bucket, _full(key));
      final chunks = <int>[];
      await for (final chunk in stream) {
        chunks.addAll(chunk);
      }
      return chunks;
    } catch (_) {
      // 对象不存在 / 网络错误：同步引擎按「暂无」处理，下次重试
      return null;
    }
  }

  @override
  Future<bool> exists(String key) async {
    try {
      // statObject 只取元数据，不像 getObject 会把整本书读进内存。
      await _minio.statObject(bucket, _full(key));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<String>> list(String prefixFilter) async {
    final result = await _minio.listAllObjects(
      bucket,
      prefix: _full(prefixFilter),
      recursive: true,
    );
    return [
      for (final obj in result.objects)
        if (obj.key != null) _strip(obj.key!),
    ]..sort();
  }

  @override
  Future<List<({String key, int modifiedAtMs})>> listDetailed(
    String prefixFilter,
  ) async {
    final result = await _minio.listAllObjects(
      bucket,
      prefix: _full(prefixFilter),
      recursive: true,
    );
    return [
      for (final obj in result.objects)
        if (obj.key != null)
          (
            key: _strip(obj.key!),
            // 服务端 lastModified；取不到给 0（调用方按「不过滤」处理）。
            modifiedAtMs: obj.lastModified?.millisecondsSinceEpoch ?? 0,
          ),
    ]..sort((a, b) => a.key.compareTo(b.key));
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _minio.removeObject(bucket, _full(key));
    } catch (_) {
      // 删除失败不阻塞同步（对象不可变，下一次列举仍会跳过已应用项）
    }
  }

  /// 连通性自检：桶可访问且可列举（读权限）。
  Future<String?> testConnection() async {
    try {
      final exists = await _minio.bucketExists(bucket);
      if (!exists) return '桶不存在：$bucket';
      // 列举一次验证读权限（1 条即返回）
      await _minio.listObjects(bucket, prefix: prefix, recursive: true)
          .take(1)
          .toList();
      return null;
    } catch (e) {
      return '连接失败：$e';
    }
  }
}
