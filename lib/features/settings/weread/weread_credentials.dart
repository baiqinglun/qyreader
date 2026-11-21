/// 微信读书 API Key 的本地安全存储。
///
/// 照 MiMo / 同步凭据的规矩：Key 只进 flutter_secure_storage，不进明文
/// prefs、不写日志。格式一般是 `wrk-` 开头。
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'weread_client.dart' show kWeReadApiKeySecureKey;

/// 微信读书 API Key 凭据。
class WeReadCredentials {
  /// 构造。[secure] 供测试注入。
  WeReadCredentials({FlutterSecureStorage? secure})
    : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;

  /// 读取 API Key（未配置返回 null）。
  Future<String?> read() async {
    try {
      final value = await _secure.read(key: kWeReadApiKeySecureKey);
      return (value == null || value.trim().isEmpty) ? null : value.trim();
    } catch (_) {
      return null;
    }
  }

  /// 保存 API Key。
  Future<void> save(String apiKey) =>
      _secure.write(key: kWeReadApiKeySecureKey, value: apiKey.trim());

  /// 清除 API Key。
  Future<void> clear() async {
    try {
      await _secure.delete(key: kWeReadApiKeySecureKey);
    } catch (_) {}
  }
}
