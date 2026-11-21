/// 微信读书扫码登录：二维码、轮询、OTP、拿到官方 Key 与退出。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/settings/weread/weread_credentials.dart';
import 'package:qy_reader/features/settings/weread/weread_login.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('扫码确认后拿到官方 API Key，并保存账号昵称', () async {
    final http = _FakeHttp(<WeReadHttpResult>[
      const WeReadHttpResult(statusCode: 200, body: '<html></html>'),
      const WeReadHttpResult(
        statusCode: 200,
        body: '{"uid":"u123"}',
        cookies: <String>['wr_qt=q1'],
      ),
      const WeReadHttpResult(
        statusCode: 200,
        body:
            '{"succeed":true,"webLoginVid":"vid1",'
            '"accessToken":"tok1","refreshToken":"rt1"}',
      ),
      const WeReadHttpResult(
        statusCode: 200,
        body: '{"name":"阿读"}',
        cookies: <String>['wr_vid=vid1'],
      ),
      const WeReadHttpResult(statusCode: 200, body: '{"apikey":"wrk-test"}'),
    ]);
    final credentials = _FakeCredentials();
    final service = WeReadQrLoginService(
      credentials: credentials,
      request: http.call,
    );

    final session = await service.start();
    expect(session.qrUrl, contains('/web/confirm?uid=u123'));
    expect(http.urls.first, endsWith('/r/weread-skills'));
    expect(http.headers.first['Cookie'], startsWith('wr_fp='));

    final poll = await session.poll();
    expect(poll.step, WeReadLoginStep.success);
    expect(poll.accountName, '阿读');
    expect(credentials.key, 'wrk-test');
    expect(await service.accountName(), '阿读');
    expect(await service.accountVid(), 'vid1');

    final keyRequestIndex = http.urls.indexWhere(
      (url) => url.contains('/api/skills/apikeyGet'),
    );
    expect(http.headers[keyRequestIndex]['X-Vid'], 'vid1');
    expect(http.headers[keyRequestIndex]['X-Skey'], 'tok1');
  });

  test('需要验证码时用 4 位 OTP 再确认', () async {
    final http = _FakeHttp(<WeReadHttpResult>[
      const WeReadHttpResult(statusCode: 200, body: ''),
      const WeReadHttpResult(statusCode: 200, body: '{"uid":"u9"}'),
      const WeReadHttpResult(
        statusCode: 200,
        body: '{"logicCode":"NEED_OTP"}',
      ),
      const WeReadHttpResult(
        statusCode: 200,
        body:
            '{"succeed":true,"webLoginVid":"vid9",'
            '"accessToken":"tok9","refreshToken":""}',
      ),
      const WeReadHttpResult(statusCode: 200, body: '{"name":"九号"}'),
      const WeReadHttpResult(statusCode: 200, body: '{"apikey":"wrk-nine"}'),
    ]);
    final credentials = _FakeCredentials();
    final service = WeReadQrLoginService(
      credentials: credentials,
      request: http.call,
    );

    final session = await service.start();
    final first = await session.poll();
    expect(first.step, WeReadLoginStep.needOtp);

    final second = await session.poll(otp: '1234');
    expect(second.step, WeReadLoginStep.success);
    expect(credentials.key, 'wrk-nine');
    expect(
      http.urls.any((url) => url.contains('/api/auth/getLoginInfo')),
      isTrue,
    );
    expect(
      http.urls.lastWhere((url) => url.contains('/api/auth/getLoginInfo')),
      contains('otp=1234'),
    );
  });

  test('登录状态接口长轮询超时后继续等，不会当成登录失败', () async {
    final http = _FakeHttp(<Object>[
      const WeReadHttpResult(statusCode: 200, body: ''),
      const WeReadHttpResult(statusCode: 200, body: '{"uid":"u2"}'),
      const WeReadLoginException('连接微信读书超时', retryable: true),
      const WeReadHttpResult(
        statusCode: 200,
        body:
            '{"succeed":true,"webLoginVid":"vid2",'
            '"accessToken":"tok2","refreshToken":""}',
      ),
      const WeReadHttpResult(statusCode: 200, body: '{"name":"乙"}'),
      const WeReadHttpResult(statusCode: 200, body: '{"apikey":"wrk-two"}'),
    ]);
    final credentials = _FakeCredentials();
    final service = WeReadQrLoginService(
      credentials: credentials,
      request: http.call,
    );

    final session = await service.start();
    final waiting = await session.poll();
    expect(waiting.step, WeReadLoginStep.waiting);

    final success = await session.poll();
    expect(success.step, WeReadLoginStep.success);
    expect(credentials.key, 'wrk-two');
  });

  test('扫码成功但 Key 为空时提示开启微信读书 Skill', () async {
    final http = _FakeHttp(<WeReadHttpResult>[
      const WeReadHttpResult(statusCode: 200, body: ''),
      const WeReadHttpResult(statusCode: 200, body: '{"uid":"u1"}'),
      const WeReadHttpResult(
        statusCode: 200,
        body:
            '{"succeed":true,"webLoginVid":"vid1",'
            '"accessToken":"tok1","refreshToken":""}',
      ),
      const WeReadHttpResult(statusCode: 200, body: '{"name":"甲"}'),
      const WeReadHttpResult(statusCode: 200, body: '{}'),
      const WeReadHttpResult(statusCode: 200, body: '{}'),
      const WeReadHttpResult(statusCode: 200, body: '{}'),
    ]);
    final credentials = _FakeCredentials();
    final service = WeReadQrLoginService(
      credentials: credentials,
      request: http.call,
    );

    final session = await service.start();
    await expectLater(
      session.poll(),
      throwsA(
        isA<WeReadLoginException>().having(
          (error) => error.message,
          'message',
          contains('微信读书 Skill'),
        ),
      ),
    );
    expect(credentials.key, isNull);
  });

  test('退出登录清掉 Key、账号与缓存状态', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'weread.accountName': '阿读',
      'weread.accountVid': 'vid1',
      'weread.lastSnapshot': '{}',
      'weread.syncState': '{}',
    });
    final credentials = _FakeCredentials()..key = 'wrk-old';
    final service = WeReadQrLoginService(
      credentials: credentials,
      request: (method, url, headers) async =>
          const WeReadHttpResult(statusCode: 200, body: '{}'),
    );

    await service.logout();

    expect(credentials.key, isNull);
    expect(await service.accountName(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('weread.lastSnapshot'), isNull);
    expect(prefs.getString('weread.syncState'), isNull);
  });
}

class _FakeCredentials extends WeReadCredentials {
  String? key;

  @override
  Future<String?> read() async => key;

  @override
  Future<void> save(String apiKey) async {
    key = apiKey;
  }

  @override
  Future<void> clear() async {
    key = null;
  }
}

class _FakeHttp {
  _FakeHttp(this.responses);

  final List<Object> responses;
  final List<String> urls = <String>[];
  final List<Map<String, String>> headers = <Map<String, String>>[];

  Future<WeReadHttpResult> call(
    String method,
    Uri url,
    Map<String, String> requestHeaders,
  ) async {
    urls.add(url.toString());
    headers.add(requestHeaders);
    if (responses.isEmpty) {
      throw StateError('unexpected request: $url');
    }
    final next = responses.removeAt(0);
    if (next is WeReadLoginException) throw next;
    return next as WeReadHttpResult;
  }
}
