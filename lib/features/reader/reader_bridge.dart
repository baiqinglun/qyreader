/// Dart → JS 调用封装（桥协议下行方向）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 封装 reader.html 暴露的全局函数。
class ReaderBridge {
  /// 绑定某个 WebView 实例的控制器。
  ReaderBridge(this._controller);

  final InAppWebViewController _controller;

  /// 载入书籍并渲染：[bookUrl] 为本地资源服务地址（同源，epub.js 自行
  /// 拉取），[locatorJson] 非空时首次 display 直接定位（JS 自主首渲）。
  Future<void> loadBook(String bookUrl, {String? locatorJson}) => _eval(
    'loadBook(${_jsStr(bookUrl)}, ${locatorJson == null ? 'null' : _jsStr(locatorJson)})',
  );

  /// 注入排版样式（含主题色）。
  Future<void> applyStyle(String styleJson) =>
      _eval('applyStyle(${_jsStr(styleJson)})');

  /// 定位到 Locator Map（CFI 失败自动降级 percent/href，见 reader.html）。
  Future<void> gotoLocatorMap(Map<String, dynamic> locator) =>
      _eval('gotoLocator(${_jsStr(jsonEncode(locator))})');

  /// 从头开始显示。
  Future<void> gotoStart() => _eval('gotoLocator({})');

  /// 定位到文档路径（目录跳转）。
  Future<void> gotoHref(String href) => _eval('gotoHref(${_jsStr(href)})');

  /// 按全书百分比跳转（进度条 scrub）。
  Future<void> gotoPercent(double percent) => _eval('gotoPercent($percent)');

  /// 前进一页。
  Future<void> nextPage() => _eval('nextPage()');

  /// 后退一页。
  Future<void> prevPage() => _eval('prevPage()');

  /// 重报当前位置（locations 就绪后补 percent）。
  Future<void> reportLocation() => _eval('reportLocation()');

  /// 与目标位置对齐后前进一页（reserve 池同步用）。
  Future<void> syncNextMap(Map<String, dynamic> locator) =>
      _eval('syncNext(${_jsStr(jsonEncode(locator))})');

  /// 通道探针：经 console 注入一条 bridgeReady 事件验证下行解析。
  Future<bool> probeChannel() async {
    try {
      await _controller.evaluateJavascript(
        source:
            r"console.log('QYEVT:' + JSON.stringify({type: 'bridgeReady'})); return true;",
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 拉取页面内部诊断（__diagDump）：错误文本与桥/书状态。
  Future<String?> dumpDiag() async {
    try {
      return await _controller.evaluateJavascript(
        source: r'window.__diagDump ? window.__diagDump() : null',
      );
    } catch (_) {
      return null;
    }
  }

  /// 截取当前页（后翻覆盖层用）；平台不支持时返回 null。
  Future<Uint8List?> screenshot() async {
    try {
      return await _controller.takeScreenshot();
    } catch (_) {
      return null;
    }
  }

  /// JSON 字符串字面量即合法 JS 字符串字面量（转义规则一致）。
  String _jsStr(String s) => jsonEncode(s);

  Future<void> _eval(String source) async {
    try {
      await _controller.evaluateJavascript(source: source);
    } catch (_) {
      // WebView 已销毁/平台不支持时静默丢弃；翻页锁由 relocated 超时兜底解除。
    }
  }
}
