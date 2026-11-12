/// 同步后端配置：类型（本地桶 / S3）、S3 参数与凭据。
///
/// 非敏感参数存 shared_preferences；accessKey/secretKey 存
/// flutter_secure_storage（禁止明文入库）。
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 同步后端类型。
enum SyncBackendType {
  /// 阿里云 OSS（S3 兼容接口，虚拟主机风格）。
  s3('阿里云 OSS');

  const SyncBackendType(this.label);

  /// 展示名。
  final String label;
}

/// 同步后端配置（不含密钥）。
class SyncBackendConfig {
  const SyncBackendConfig({
    this.type = SyncBackendType.s3,
    this.endPoint = '',
    this.bucket = '',
    this.prefix = 'qyreader/',
    this.region,
    this.useSSL = true,
    this.port,
    this.pathStyle = true,
  });

  /// 后端类型。
  final SyncBackendType type;

  /// S3 端点（不含协议）。
  final String endPoint;

  /// 桶名。
  final String bucket;

  /// 对象前缀。
  final String prefix;

  /// 区域（AWS 必填）。
  final String? region;

  /// 是否 HTTPS。
  final bool useSSL;

  /// 端口（null = 按协议默认）。
  final int? port;

  /// 路径风格：true = `端点/桶/对象`（MinIO），
  /// false = `桶.端点/对象`（阿里云 OSS / R2 这类只支持虚拟主机风格的服务）。
  final bool pathStyle;

  /// 是否已填齐 S3 必填项。
  bool get s3Complete =>
      endPoint.trim().isNotEmpty && bucket.trim().isNotEmpty;

  /// 序列化。
  Map<String, dynamic> toMap() => <String, dynamic>{
        'type': type.name,
        'endPoint': endPoint,
        'bucket': bucket,
        'prefix': prefix,
        if (region != null) 'region': region,
        'useSSL': useSSL,
        if (port != null) 'port': port,
        'pathStyle': pathStyle,
      };

  /// 反序列化。
  static SyncBackendConfig fromMap(Map<String, dynamic> json) =>
      SyncBackendConfig(
        type: SyncBackendType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => SyncBackendType.s3,
        ),
        endPoint: json['endPoint'] as String? ?? '',
        bucket: json['bucket'] as String? ?? '',
        prefix: json['prefix'] as String? ?? 'qyreader/',
        region: json['region'] as String?,
        useSSL: json['useSSL'] as bool? ?? true,
        port: (json['port'] as num?)?.toInt(),
        // 旧配置没有这个字段：当年只有 MinIO 风格（路径风格）
        pathStyle: json['pathStyle'] as bool? ?? true,
      );
}

/// 同步凭据（仅内存 + secure storage）。
class SyncCredentials {
  const SyncCredentials({this.accessKey = '', this.secretKey = ''});

  /// 访问密钥。
  final String accessKey;

  /// 私钥。
  final String secretKey;

  /// 是否已配置。
  bool get configured => accessKey.isNotEmpty && secretKey.isNotEmpty;
}

/// 同步后端配置存储。
class SyncBackendStore {
  /// 构造。
  SyncBackendStore({
    FlutterSecureStorage? secure,
  }) : _secure = secure ?? const FlutterSecureStorage();

  static const String _kConfigKey = 'sync.backend';
  static const String _kAccessKey = 'sync.s3.accessKey';
  static const String _kSecretKey = 'sync.s3.secretKey';

  final FlutterSecureStorage _secure;

  /// 读取配置（缺省为本地桶）。
  Future<SyncBackendConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kConfigKey);
    if (raw == null) return const SyncBackendConfig();
    try {
      return SyncBackendConfig.fromMap(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const SyncBackendConfig();
    }
  }

  /// 保存配置。
  Future<void> saveConfig(SyncBackendConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kConfigKey, jsonEncode(config.toMap()));
  }

  /// 读取凭据（secure storage）。
  Future<SyncCredentials> loadCredentials() async {
    try {
      return SyncCredentials(
        accessKey: await _secure.read(key: _kAccessKey) ?? '',
        secretKey: await _secure.read(key: _kSecretKey) ?? '',
      );
    } catch (_) {
      // 设备不支持安全存储（如部分模拟器缺 keystore）：视为未配置
      return const SyncCredentials();
    }
  }

  /// 保存凭据（secure storage）。
  Future<void> saveCredentials(SyncCredentials credentials) async {
    await _secure.write(key: _kAccessKey, value: credentials.accessKey);
    await _secure.write(key: _kSecretKey, value: credentials.secretKey);
  }
}
