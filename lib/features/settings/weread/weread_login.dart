/// 微信读书扫码登录。
///
/// 流程照微信读书网页版：`/r/weread-skills` 页面登录后即可取官方 API Key。
/// 这里直接调网页登录接口拿 `uid`，把 `https://weread.qq.com/web/confirm?uid=…`
/// 渲染成二维码，用户用微信扫码确认后换取 `wr_vid` / `wr_skey`，再取回
/// 官方 `wrk-` Key 存进安全存储。后续同步仍然走官方 Agent API，不需要把
/// 账号 Cookie 暴露给业务层。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'weread_credentials.dart';
import 'weread_sync_state.dart';

/// 微信读书网页版根地址。
const String kWeReadWebBaseUrl = 'https://weread.qq.com';

/// 官方 Skills 页面（登录后取 API Key 的入口）。
const String kWeReadSkillsPath = '/r/weread-skills';

const String _kLoginUidPath = '/api/auth/getLoginUid';
const String _kLoginInfoPath = '/api/auth/getLoginInfo';
const String _kUserInfoPath = '/api/userInfo';
const String _kApiKeyPath = '/api/skills/apikeyGet';

const String _kUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

const String _kFingerprintKey = 'weread.deviceFingerprint';
const String _kAccountNameKey = 'weread.accountName';
const String _kAccountVidKey = 'weread.accountVid';

/// 扫码登录失败（message 可直接展示给用户）。
class WeReadLoginException implements Exception {
  /// 构造。
  const WeReadLoginException(this.message, {this.retryable = false});

  /// 用户可读原因。
  final String message;

  /// 是否是可继续等待的网络问题（超时/断网），长轮询里不该当登录失败。
  final bool retryable;

  @override
  String toString() => message;
}

/// 一次扫码登录所处的阶段。
enum WeReadLoginStep {
  /// 等待扫码 / 手机上确认。
  waiting,

  /// 微信里要求输入手机上的 4 位验证码。
  needOtp,

  /// 登录成功，官方 API Key 已写入安全存储。
  success,

  /// 二维码或验证码过期。
  expired,

  /// 登录失败。
  failed,
}

/// 一次轮询的结果。
class WeReadLoginPoll {
  /// 构造。
  const WeReadLoginPoll({
    required this.step,
    this.message = '',
    this.accountName,
  });

  /// 当前阶段。
  final WeReadLoginStep step;

  /// 可展示的状态文案。
  final String message;

  /// 登录成功后的账号昵称。
  final String? accountName;
}

/// 扫码登录会话（页面持有的二维码 + 轮询状态）。
abstract interface class WeReadLoginSession {
  /// 二维码内容（`https://weread.qq.com/web/confirm?uid=…`）。
  String get qrUrl;

  /// 问一次登录状态；[otp] 为手机上的 4 位验证码。
  Future<WeReadLoginPoll> poll({String otp = ''});

  /// 关闭会话，停止后续轮询。
  void cancel();
}

/// 页面依赖的扫码登录能力（测试可覆盖）。
abstract interface class WeReadLoginApi {
  /// 打开一次扫码登录会话。
  Future<WeReadLoginSession> start();

  /// 已登录账号的昵称；没登录返回 null。
  Future<String?> accountName();

  /// 退出登录：清 Key、账号信息与缓存快照。
  Future<void> logout();
}

/// HTTP 回包（测试注入用）。
class WeReadHttpResult {
  /// 构造。
  const WeReadHttpResult({
    required this.statusCode,
    required this.body,
    this.cookies = const <String>[],
  });

  /// HTTP 状态码。
  final int statusCode;

  /// 响应体。
  final String body;

  /// `Set-Cookie` 的 `name=value` 列表。
  final List<String> cookies;
}

/// 可注入的 HTTP 请求函数。
typedef WeReadHttpRequest =
    Future<WeReadHttpResult> Function(
      String method,
      Uri url,
      Map<String, String> headers,
    );

/// 扫码登录实现。
class WeReadQrLoginService implements WeReadLoginApi {
  /// 构造。
  WeReadQrLoginService({
    WeReadCredentials? credentials,
    WeReadHttpRequest? request,
    WeReadSyncStore store = const WeReadSyncStore(),
  }) : _credentials = credentials ?? WeReadCredentials(),
       _request = request ?? _defaultRequest,
       _store = store;

  final WeReadCredentials _credentials;
  final WeReadHttpRequest _request;
  final WeReadSyncStore _store;

  @override
  Future<WeReadLoginSession> start() async {
    final prefs = await SharedPreferences.getInstance();
    final fingerprint = await _fingerprint(prefs);
    final cookies = <String, String>{'wr_fp': fingerprint};
    final pageHeaders = <String, String>{
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Referer': '$kWeReadWebBaseUrl/',
      'Cookie': _cookieHeader(cookies),
    };
    final page = await _request(
      'GET',
      Uri.parse('$kWeReadWebBaseUrl$kWeReadSkillsPath'),
      pageHeaders,
    );
    _mergeCookies(cookies, page.cookies);
    if (page.statusCode < 200 || page.statusCode >= 300) {
      throw WeReadLoginException('打不开微信读书登录页（HTTP ${page.statusCode}）');
    }

    final headers = <String, String>{
      'Accept': 'application/json, text/plain, */*',
      'Referer': '$kWeReadWebBaseUrl$kWeReadSkillsPath',
    };
    if (cookies.isNotEmpty) headers['Cookie'] = _cookieHeader(cookies);
    final uidResult = await _request(
      'GET',
      Uri.parse('$kWeReadWebBaseUrl$_kLoginUidPath'),
      headers,
    );
    _mergeCookies(cookies, uidResult.cookies);
    final uidJson = _decode(uidResult, '获取登录二维码');
    final uid = _stringOf(uidJson['uid']);
    if (uid == null || uid.isEmpty) {
      throw const WeReadLoginException('微信读书没有返回登录二维码，请稍后重试');
    }

    return _HttpWeReadLoginSession(
      service: this,
      uid: uid,
      cookies: cookies,
      startedAt: DateTime.now(),
      qrUrl:
          '$kWeReadWebBaseUrl/web/confirm?uid=${Uri.encodeQueryComponent(uid)}',
    );
  }

  @override
  Future<String?> accountName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_kAccountNameKey);
    return (name == null || name.trim().isEmpty) ? null : name.trim();
  }

  /// 已登录账号的 vid（用于判断是否换了账号）。
  Future<String?> accountVid() async {
    final prefs = await SharedPreferences.getInstance();
    final vid = prefs.getString(_kAccountVidKey);
    return (vid == null || vid.trim().isEmpty) ? null : vid.trim();
  }

  @override
  Future<void> logout() async {
    await _credentials.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccountNameKey);
    await prefs.remove(_kAccountVidKey);
    try {
      await _store.clear();
      await _store.clearSnapshot();
    } catch (_) {}
  }

  Future<WeReadLoginPoll> _poll(
    _HttpWeReadLoginSession session,
    String otp,
  ) async {
    if (DateTime.now().difference(session.startedAt) >
        const Duration(minutes: 5)) {
      return const WeReadLoginPoll(
        step: WeReadLoginStep.expired,
        message: '二维码已过期，请刷新',
      );
    }
    final headers = <String, String>{
      'Accept': 'application/json, text/plain, */*',
      'Referer': '$kWeReadWebBaseUrl$kWeReadSkillsPath',
    };
    if (session.cookies.isNotEmpty) {
      headers['Cookie'] = _cookieHeader(session.cookies);
    }
    final uri = Uri.parse('$kWeReadWebBaseUrl$_kLoginInfoPath').replace(
      queryParameters: <String, String>{'uid': session.uid, 'otp': otp},
    );
    final WeReadHttpResult result;
    try {
      result = await _request(
        'GET',
        uri,
        headers,
      ).timeout(const Duration(seconds: 9));
    } on TimeoutException {
      // getLoginInfo 是长轮询，等不到人扫码时本来就会挂住；超时后继续轮询。
      return const WeReadLoginPoll(
        step: WeReadLoginStep.waiting,
        message: '等待微信扫码…',
      );
    } on WeReadLoginException catch (error) {
      if (!error.retryable) rethrow;
      return const WeReadLoginPoll(
        step: WeReadLoginStep.waiting,
        message: '等待微信扫码…',
      );
    } on SocketException {
      return const WeReadLoginPoll(
        step: WeReadLoginStep.waiting,
        message: '网络连接中断，正在重试…',
      );
    }
    _mergeCookies(session.cookies, result.cookies);
    final json = _decode(result, '读取扫码状态');
    if (json['succeed'] == true) {
      return _complete(session, json);
    }
    final code = _stringOf(json['logicCode'])?.toUpperCase() ?? '';
    switch (code) {
      case 'NEED_OTP':
        return const WeReadLoginPoll(
          step: WeReadLoginStep.needOtp,
          message: '请输入手机微信上显示的 4 位验证码',
        );
      case 'LOGIN_TIMEOUT':
        return const WeReadLoginPoll(
          step: WeReadLoginStep.expired,
          message: '二维码已过期，请刷新',
        );
      case 'OTP_EXPIRED':
        return const WeReadLoginPoll(
          step: WeReadLoginStep.expired,
          message: '验证码已过期，请刷新二维码重新登录',
        );
      case 'OTP_NOT_MATCH':
        return const WeReadLoginPoll(
          step: WeReadLoginStep.needOtp,
          message: '验证码不对，请重新输入',
        );
      case '':
        return const WeReadLoginPoll(
          step: WeReadLoginStep.waiting,
          message: '等待微信扫码…',
        );
      default:
        return WeReadLoginPoll(
          step: WeReadLoginStep.failed,
          message: '微信读书登录失败（$code）',
        );
    }
  }

  /// 扫码确认后：换 Cookie → 取账号昵称 → 取官方 API Key → 落库。
  Future<WeReadLoginPoll> _complete(
    _HttpWeReadLoginSession session,
    Map<String, dynamic> json,
  ) async {
    if (session.done) {
      return const WeReadLoginPoll(
        step: WeReadLoginStep.success,
        message: '已经登录',
      );
    }
    final vid = _stringOf(json['webLoginVid']) ?? '';
    final token = _stringOf(json['accessToken']) ?? '';
    if (vid.isEmpty || token.isEmpty) {
      throw const WeReadLoginException('扫码成功，但微信读书没有返回账号凭据');
    }
    session.cookies['wr_vid'] = vid;
    session.cookies['wr_skey'] = token;
    session.cookies['wr_ql'] = '0';
    final refresh = _stringOf(json['refreshToken']);
    if (refresh != null && refresh.isNotEmpty) {
      session.cookies['wr_rt'] = Uri.encodeComponent(refresh);
    }

    final authHeaders = <String, String>{
      'Accept': 'application/json, text/plain, */*',
      'Referer': '$kWeReadWebBaseUrl$kWeReadSkillsPath',
      'Cookie': _cookieHeader(session.cookies),
      'X-Vid': vid,
      'X-Skey': token,
    };
    final userUri = Uri.parse(
      '$kWeReadWebBaseUrl$_kUserInfoPath',
    ).replace(queryParameters: <String, String>{'userVid': vid});
    var name = '';
    try {
      final user = await _request(
        'GET',
        userUri,
        authHeaders,
      ).timeout(const Duration(seconds: 15));
      _mergeCookies(session.cookies, user.cookies);
      final userJson = _decode(user, '读取账号信息');
      name = _stringOf(userJson['name']) ?? _stringOf(userJson['nick']) ?? '';
    } catch (_) {
      // 昵称拿不到不影响登录，后面只显示「已登录」。
    }

    String apiKey = '';
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final keyResult = await _request(
          'GET',
          Uri.parse('$kWeReadWebBaseUrl$_kApiKeyPath?only_show=1'),
          authHeaders,
        ).timeout(const Duration(seconds: 15));
        _mergeCookies(session.cookies, keyResult.cookies);
        final keyJson = _decode(keyResult, '获取官方 API Key');
        apiKey = _stringOf(keyJson['apikey']) ?? _nestedApiKey(keyJson);
        if (apiKey.isNotEmpty) break;
      } catch (error) {
        lastError = error;
      }
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    if (apiKey.isEmpty) {
      throw WeReadLoginException(
        '扫码成功，但没有拿到官方 API Key'
        '${lastError == null ? '' : '：$lastError'}。'
        '请确认微信读书账号已开启「微信读书 Skill」后重试。',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final oldVid = prefs.getString(_kAccountVidKey);
    if (oldVid == null || oldVid != vid) {
      // 换账号时旧账号的增量水位/已导入标记会串，先清掉。
      try {
        await _store.clear();
        await _store.clearSnapshot();
      } catch (_) {}
    }
    await _credentials.save(apiKey);
    if (name.isNotEmpty) {
      await prefs.setString(_kAccountNameKey, name);
    } else {
      await prefs.remove(_kAccountNameKey);
    }
    await prefs.setString(_kAccountVidKey, vid);
    session.done = true;
    return WeReadLoginPoll(
      step: WeReadLoginStep.success,
      message: '登录成功',
      accountName: name,
    );
  }

  Future<String> _fingerprint(SharedPreferences prefs) async {
    final saved = prefs.getString(_kFingerprintKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final value = Random.secure().nextInt(0x100000000).toString();
    await prefs.setString(_kFingerprintKey, value);
    return value;
  }
}

class _HttpWeReadLoginSession implements WeReadLoginSession {
  _HttpWeReadLoginSession({
    required this.service,
    required this.uid,
    required this.cookies,
    required this.startedAt,
    required this.qrUrl,
  });

  final WeReadQrLoginService service;
  final String uid;
  final DateTime startedAt;
  final Map<String, String> cookies;

  @override
  final String qrUrl;

  bool done = false;
  bool cancelled = false;

  @override
  Future<WeReadLoginPoll> poll({String otp = ''}) async {
    if (cancelled) {
      return const WeReadLoginPoll(
        step: WeReadLoginStep.failed,
        message: '登录已取消',
      );
    }
    if (done) {
      return const WeReadLoginPoll(
        step: WeReadLoginStep.success,
        message: '已经登录',
      );
    }
    return service._poll(this, otp.trim());
  }

  @override
  void cancel() {
    cancelled = true;
  }
}

Map<String, dynamic> _decode(WeReadHttpResult result, String action) {
  if (result.statusCode < 200 || result.statusCode >= 300) {
    throw WeReadLoginException('$action失败（HTTP ${result.statusCode}）');
  }
  try {
    final decoded = jsonDecode(result.body);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {}
  throw WeReadLoginException('$action失败：微信读书返回了无法识别的内容');
}

String _cookieHeader(Map<String, String> cookies) {
  return <String>[
    for (final entry in cookies.entries)
      if (entry.value.isNotEmpty) '${entry.key}=${entry.value}',
  ].join('; ');
}

void _mergeCookies(Map<String, String> cookies, List<String> raw) {
  for (final item in raw) {
    final pair = item.split(';').first.trim();
    final index = pair.indexOf('=');
    if (index <= 0) continue;
    final name = pair.substring(0, index).trim();
    final value = pair.substring(index + 1).trim();
    if (name.isEmpty) continue;
    cookies[name] = value;
  }
}

String? _stringOf(Object? raw) {
  if (raw is String) return raw;
  if (raw is num) return '$raw';
  return null;
}

String _nestedApiKey(Map<String, dynamic> json) {
  final data = json['data'];
  if (data is Map) {
    return _stringOf(data['apikey']) ?? _stringOf(data['apiKey']) ?? '';
  }
  return _stringOf(json['apiKey']) ?? '';
}

/// 默认传输：dart:io HttpClient（不新增 http 依赖）。
Future<WeReadHttpResult> _defaultRequest(
  String method,
  Uri url,
  Map<String, String> headers,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client
        .openUrl(method, url)
        .timeout(const Duration(seconds: 20));
    request.followRedirects = true;
    request.maxRedirects = 5;
    request.headers.set(HttpHeaders.userAgentHeader, _kUserAgent);
    request.headers.set(HttpHeaders.acceptLanguageHeader, 'zh-CN,zh;q=0.9');
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 8));
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 8));
    return WeReadHttpResult(
      statusCode: response.statusCode,
      body: body,
      cookies: <String>[
        for (final cookie in response.cookies) '${cookie.name}=${cookie.value}',
      ],
    );
  } on WeReadLoginException {
    rethrow;
  } on TimeoutException {
    throw const WeReadLoginException('连接微信读书超时，请检查网络后重试', retryable: true);
  } on SocketException catch (error) {
    throw WeReadLoginException('连接微信读书失败：${error.message}', retryable: true);
  } finally {
    client.close(force: true);
  }
}

/// 页面使用的 provider；测试可覆盖。
final wereadLoginProvider = Provider<WeReadLoginApi>(
  (ref) => WeReadQrLoginService(),
);
