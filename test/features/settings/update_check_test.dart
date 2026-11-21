import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/settings/update_check.dart';

void main() {
  test('解析版本和多个下载链接', () {
    final result = UpdateManifest.parse(
      jsonEncode({
        'versionName': '3.0.0',
        'versionCode': 225,
        'notes': '更新说明',
        'updates': [
          {'apkUrl': 'https://example.com/app.apk'},
          {'apkUrl': 'https://example.com/share', 'password': '49vg'},
        ],
      }),
    );
    expect(result.versionCode, 225);
    expect(result.notes, '更新说明');
    expect(result.links.first.isApk, isTrue);
    expect(result.links.last.password, '49vg');
  });
  test('拒绝错误版本和不安全链接', () {
    expect(
      () => UpdateManifest.parse('{"versionCode":23}'),
      throwsFormatException,
    );
    expect(
      () => UpdateManifest.parse(
        jsonEncode({
          'versionName': '3',
          'versionCode': 225,
          'updates': [
            {'apkUrl': 'http://example.com/a.apk'},
          ],
        }),
      ),
      throwsFormatException,
    );
  });
  test('清单请求成功与 404 错误', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      if (request.uri.path == '/missing') {
        request.response.statusCode = 404;
      } else {
        request.response.write(
          jsonEncode({
            'versionName': '3',
            'versionCode': 225,
            'apkUrl': 'https://example.com/a.apk',
          }),
        );
      }
      request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final uri = Uri.parse('http://127.0.0.1:${server.port}');
    expect((await fetchUpdateManifest(url: uri)).versionCode, 225);
    await expectLater(
      fetchUpdateManifest(url: uri.replace(path: '/missing')),
      throwsA(isA<HttpException>()),
    );
  });
}
