/// 小米 MiMo 云端语音合成客户端（mimo.mi.com 开放平台）。
///
/// 协议是 OpenAI 兼容的 `chat/completions`：
/// - 待合成的文本放在 **`role: assistant`** 的 content（不是 user）；
/// - `role: user` 消息可选，放风格/语速指令；
/// - `audio: {format: 'wav', voice: '<音色ID>'}`；非流式响应里音频是
///   `choices[0].message.audio.data` 的 base64 WAV（24kHz 单声道）。
///
/// 模型 ID 默认 `mimo-v2.5-tts`（官方文档示例值；小米曾提示 V2.5 聊天系列
/// 下线、建议核对 V2.6——如果接口报「模型不存在」，改 [kMimoTtsModel] 即可，
/// 客户端对模型名不做硬编码校验）。API Key 存 flutter_secure_storage
/// （照 `SyncBackendStore` 的规矩，不进明文 prefs）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// MiMo 开放平台 base URL（OpenAI 兼容入口）。
const String kMimoTtsBaseUrl = 'https://api.xiaomimimo.com/v1';

/// 语音合成模型 ID（官方 speech-synthesis 文档示例值）。
const String kMimoTtsModel = 'mimo-v2.5-tts';

/// secure storage 里的 API Key。
const String kMimoTtsApiKeySecureKey = 'tts.mimo.apiKey';

/// MiMo 请求/响应异常（消息可直接展示）。
class MimoTtsException implements Exception {
  /// 构造。
  const MimoTtsException(this.message);

  /// 用户可读原因。
  final String message;

  @override
  String toString() => message;
}

/// MiMo API Key 凭据（flutter_secure_storage）。
class MimoTtsCredentials {
  /// 构造。[secure] 供测试注入。
  MimoTtsCredentials({FlutterSecureStorage? secure})
    : _secure = secure ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;

  /// 读取 API Key（未配置返回 null）。
  Future<String?> read() async {
    try {
      final value = await _secure.read(key: kMimoTtsApiKeySecureKey);
      return (value == null || value.isEmpty) ? null : value;
    } catch (_) {
      return null;
    }
  }

  /// 保存 API Key。
  Future<void> save(String apiKey) =>
      _secure.write(key: kMimoTtsApiKeySecureKey, value: apiKey);

  /// 清除 API Key。
  Future<void> clear() async {
    try {
      await _secure.delete(key: kMimoTtsApiKeySecureKey);
    } catch (_) {}
  }
}

/// 发送 POST 并解析 JSON 响应（测试可注入替身）。
typedef MimoPostFn =
    Future<Map<String, dynamic>> Function(
      Uri url,
      Map<String, String> headers,
      Map<String, dynamic> body,
    );

/// MiMo 语音合成客户端：一句话 → 一段 WAV 字节。
class MimoTtsClient {
  /// 构造。[post] 供测试注入（默认走 dart:io HttpClient）。
  MimoTtsClient({
    required String apiKey,
    this.baseUrl = kMimoTtsBaseUrl,
    this.model = kMimoTtsModel,
    MimoPostFn? post,
  }) : _apiKey = apiKey,
       _post = post ?? _postJson;

  final String _apiKey;
  final String baseUrl;
  final String model;
  final MimoPostFn _post;

  /// 合成 [text]（应为单句/短段），返回 WAV 字节。
  ///
  /// [voice] 是 MiMo 音色 ID（如 `冰糖`、`mimo_default`）。倍速不在合成侧
  /// 控制（指令不可靠），由 `MimoVoicePlayer` 的播放器变速即时实现。
  Future<Uint8List> synthesize(String text, {required String voice}) async {
    final messages = <Map<String, dynamic>>[
      // 待合成文本必须放 assistant 角色（MiMo TTS 协议约定）
      <String, dynamic>{'role': 'assistant', 'content': text},
    ];
    final Uri url;
    try {
      url = Uri.parse('$baseUrl/chat/completions');
    } catch (e) {
      throw MimoTtsException('服务地址无效：$e');
    }
    final Map<String, dynamic> map;
    try {
      map = await _post(
        url,
        <String, String>{
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        <String, dynamic>{
          'model': model,
          'messages': messages,
          'audio': <String, dynamic>{'format': 'wav', 'voice': voice},
        },
      );
    } on MimoTtsException {
      rethrow;
    } catch (e) {
      throw MimoTtsException('网络请求失败：$e');
    }
    return extractMimoAudio(map);
  }

  /// 从 chat.completions 响应里解出音频（base64 → WAV 字节）。
  static Uint8List extractMimoAudio(Map<String, dynamic> map) {
    final choices = map['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const MimoTtsException('响应缺少 choices');
    }
    final first = choices.first;
    if (first is! Map) throw const MimoTtsException('响应 choices 格式异常');
    final message = first['message'];
    if (message is! Map) throw const MimoTtsException('响应缺少 message');
    final audio = message['audio'];
    if (audio is! Map) throw const MimoTtsException('响应缺少音频数据');
    final data = audio['data'];
    if (data is! String || data.isEmpty) {
      throw const MimoTtsException('响应音频数据为空');
    }
    try {
      return base64Decode(data);
    } catch (_) {
      throw const MimoTtsException('音频数据解码失败');
    }
  }

  /// 从错误响应里提取可读信息（OpenAI 风格 error.message 优先）。
  static String describeErrorBody(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
        if (decoded['message'] is String) return decoded['message'] as String;
      }
    } catch (_) {}
    final trimmed = raw.trim();
    return trimmed.isEmpty
        ? '（无响应体）'
        : trimmed.substring(0, trimmed.length.clamp(0, 200));
  }

  /// 默认传输：dart:io HttpClient（不加 http 依赖）。
  static Future<Map<String, dynamic>> _postJson(
    Uri url,
    Map<String, String> headers,
    Map<String, dynamic> body,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client
          .postUrl(url)
          .timeout(const Duration(seconds: 20));
      headers.forEach(request.headers.set);
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(
        const Duration(seconds: 90),
      );
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw MimoTtsException(
          'HTTP ${response.statusCode}：${describeErrorBody(text)}',
        );
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const MimoTtsException('响应不是 JSON 对象');
      }
      return decoded;
    } on MimoTtsException {
      rethrow;
    } on TimeoutException {
      throw const MimoTtsException('请求超时，请检查网络后重试');
    }
  }
}

/// MiMo 合成结果是否为 WAV（调试断言用；非流式格式恒为 wav）。
@visibleForTesting
bool looksLikeWav(Uint8List bytes) =>
    bytes.length > 12 &&
    bytes[0] == 0x52 &&
    bytes[1] == 0x49 &&
    bytes[2] == 0x46 &&
    bytes[3] == 0x46; // "RIFF"
