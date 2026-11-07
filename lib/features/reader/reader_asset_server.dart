/// 阅读器本地资源服务：把 reader.html 与书籍文件经 127.0.0.1 随机端口
/// 提供给 WebView。
///
/// 动机：Android 上 file:// 页面加载受 allowFileAccess 策略影响、
/// 大文件 base64 经 evaluateJavascript 注入会静默失败。
/// 改为同源 HTTP 后两者都不存在：页面与书籍同源，epub.js 直接 XHR 拉取。
library;

import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 每本打开的书一个实例；阅读器关闭时 [stop]。
class ReaderAssetServer {
  HttpServer? _server;
  String _html = '';
  List<int> _bookBytes = const [];

  /// 是否已启动。
  bool get isRunning => _server != null;

  /// 页面地址（启动后可用）。
  Uri? pageUri;

  /// 启动服务：[html] 为组装后的渲染页，[bookPath] 为书籍文件。
  Future<Uri> start({required String html, required String bookPath}) async {
    await stop();
    _html = html;
    _bookBytes = await File(bookPath).readAsBytes();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = _server!.port;
    _server!.listen(
      _handle,
      onError: (Object e) => debugPrint('reader-server error: $e'),
      cancelOnError: false,
    );
    pageUri = Uri.parse('http://127.0.0.1:$port/reader.html');
    return pageUri!;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      switch (request.uri.path) {
        case '/reader.html':
          request.response.headers.contentType = ContentType(
            'text',
            'html',
            charset: 'utf-8',
          );
          request.response.add(utf8.encode(_html));
        case '/book.epub':
          request.response.headers.contentType = ContentType(
            'application',
            'epub+zip',
          );
          request.response.headers.set('Accept-Ranges', 'bytes');
          request.response.headers.contentLength = _bookBytes.length;
          request.response.add(_bookBytes);
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    } catch (e) {
      debugPrint('reader-server handle error: $e');
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  /// 停止服务。
  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }
}
