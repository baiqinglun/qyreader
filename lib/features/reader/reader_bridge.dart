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

  /// 载入书籍（base64）并渲染；[locatorJson] 非空时首次 display 直接定位
  /// （JS 自主首渲，规避桥时序问题）。大文件一次性注入，M1 接受。
  Future<void> loadBook(String base64, {String? locatorJson}) => _eval(
        'loadBook(${_jsStr(base64)}, ${locatorJson == null ? 'null' : _jsStr(locatorJson)})',
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

  /// 与目标位置对齐后前进一页（reserve 池同步用）。
  Future<void> syncNextMap(Map<String, dynamic> locator) =>
      _eval('syncNext(${_jsStr(jsonEncode(locator))})');

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
