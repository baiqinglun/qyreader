/// Dart → JS 调用封装（桥协议下行方向）。
///
/// 基于 webview_flutter 官方插件（其 Android platform view 实现成熟稳定；
/// flutter_inappwebview Android 在本机实测 platform view 不出像素后替换）。
/// JS → Dart 事件经 console 'QYEVT:' 前缀与 JavaScriptChannel 双通道。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:webview_flutter/webview_flutter.dart';

/// 朗读所需的最小接口（WebView 与原生文本两种实现共用）。
abstract class TtsSurface {
  /// 当前章节的句子列表。
  Future<List<TtsSegment>?> ttsSegments();

  /// 高亮句子；返回 'visible' | 'turning' | 错误码。
  Future<String?> ttsShow(String cfiRange);

  /// 清除高亮。
  Future<void> ttsClear();

  /// 下一章 href；已是最后一章返回 null。
  Future<String?> ttsNextHref();

  /// 跳到章节（WebView 传 href；原生实现里 href 已被编码为 `@章:起:止`）。
  Future<void> gotoChapter(String target);
}

/// 封装 reader.html 暴露的全局函数。
class ReaderBridge implements TtsSurface {
  /// 绑定某个 WebView 实例的控制器。
  ReaderBridge(this._controller);

  final WebViewController _controller;

  /// 载入书籍并渲染：[bookUrl] 为同源书籍地址（file:// 或本地服务），
  /// [locatorJson] 非空时首次 display 直接定位（JS 自主首渲）。
  /// [styleJson] 非空时在首帧前确定边距/主题，避免先满屏再缩进。
  Future<void> loadBook(
    String bookUrl, {
    String? locatorJson,
    String? styleJson,
  }) =>
      _eval('loadBook(${_jsStr(bookUrl)}, '
          '${locatorJson == null ? 'null' : _jsStr(locatorJson)}, '
          '${styleJson == null ? 'null' : _jsStr(styleJson)})');

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

  /// 按页级位置跳转（pos = 章索引 + 章内页比例）。
  ///
  /// 与 [gotoPercent] 不同：pos 是页级口径（应用里的 percent 就是它），
  /// gotoPercent 走的是 epub.js 的字符级 locations 百分比，两者不等价。
  Future<void> gotoPos(double pos) => _eval('gotoPos($pos)');

  /// 下发全书字数（导入时解析得到）：页面用它估算全书页数。
  Future<void> setTotalChars(int chars) => _eval('setTotalChars($chars)');

  /// 取当前阅读位置（Locator JSON）；页面未就绪返回 null。
  ///
  /// 退出阅读时用：最后一条 relocated 可能还没送达 Dart，这里同步问一次
  /// 页面拿真实位置落库。
  Future<String?> currentLocatorJson() => _evalReturning(
        'window.currentLocatorJson ? window.currentLocatorJson() : null',
      );

  /// 前进一页。
  Future<void> nextPage() => _eval('nextPage()');

  /// 后退一页。
  Future<void> prevPage() => _eval('prevPage()');

  /// 与目标位置对齐后前进一页（reserve 池同步用）。
  /// [seq] 原样回传在 syncDone 里，供 Dart 丢弃过期回调。
  Future<void> syncNextMap(Map<String, dynamic> locator, {required int seq}) =>
      _eval('syncNext(${_jsStr(jsonEncode(locator))}, $seq)');

  /// 边距松手后按 WebView 新尺寸重排并回到原 CFI。
  Future<void> flushViewport(String? locatorJson) => _eval(
        'flushViewport(${locatorJson == null ? 'null' : _jsStr(locatorJson)})',
      );

  /// 字号/行距变化后强制重新分页并回到原 CFI。
  Future<void> relayout(String? locatorJson) => _eval(
        'relayout(${locatorJson == null ? 'null' : _jsStr(locatorJson)})',
      );

  /// 重报当前位置（locations 就绪后补 percent）。
  Future<void> reportLocation() => _eval('reportLocation()');

  // ---- M2 标注 ----

  /// 批量注入划线（bookReady 后对双池各调一次；单条新增用 [addHighlight]）。
  Future<void> applyHighlights(String itemsJson) =>
      _eval('__qyApplyHighlights && __qyApplyHighlights($itemsJson)');

  /// 新增一条划线。
  Future<void> addHighlight({
    required String id,
    required String cfiRange,
    required String colorToken,
  }) =>
      _eval('__qyAddHighlight && __qyAddHighlight('
          '${_jsStr(id)}, ${_jsStr(cfiRange)}, ${_jsStr(colorToken)})');

  /// 移除一条划线（按选区 CFI，epub.js 的注销键）。
  Future<void> removeHighlight(String cfiRange) =>
      _eval('__qyRemoveHighlight && __qyRemoveHighlight(${_jsStr(cfiRange)})');

  /// 清除 iframe 内当前文本选区（标注菜单关闭时调用）。
  Future<void> clearSelection() =>
      _eval('__qyClearSelection && __qyClearSelection()');

  // ---- M3 TTS ----

  /// 当前章节的句子列表（JSON：[{cfi, text}]）；失败返回 null。
  @override
  Future<List<TtsSegment>?> ttsSegments() async {
    final raw = await _evalReturning(
      'window.__qyTtsSegments ? window.__qyTtsSegments() : null',
    );
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return null;
      return [
        for (final item in list)
          if (item is Map<String, dynamic>)
            if (item['cfi'] is String && item['text'] is String)
              TtsSegment(
                cfi: item['cfi'] as String,
                text: item['text'] as String,
              ),
      ];
    } catch (_) {
      return null;
    }
  }

  /// 高亮第 cfi 句；返回 'visible' | 'turning' | 错误码。
  @override
  Future<String?> ttsShow(String cfiRange) => _evalReturning(
        'window.__qyTtsShow ? window.__qyTtsShow(${_jsStr(cfiRange)}) : null',
      );

  /// 清除 TTS 跟读高亮。
  @override
  Future<void> ttsClear() => _eval('__qyTtsClear && __qyTtsClear()');

  @override
  Future<void> gotoChapter(String target) => gotoHref(target);

  /// 下一章 href；已是最后一章返回 null。
  @override
  Future<String?> ttsNextHref() => _evalReturning(
        'window.__qyTtsNextHref ? window.__qyTtsNextHref() : null',
      );

  /// 求值并取回字符串结果（页面未就绪/已销毁返回 null）。
  Future<String?> _evalReturning(String source) async {
    try {
      final result =
          await _controller.runJavaScriptReturningResult(source);
      final text = result.toString();
      // Android 返回 JSON 编码字面量（带引号），null 返回 "null"
      if (text == 'null' || text.isEmpty) return null;
      if (text.startsWith('"') && text.endsWith('"')) {
        return jsonDecode(text) as String;
      }
      return text;
    } catch (_) {
      return null;
    }
  }

  /// 截取 WebView 当前画面。
  ///
  /// webview_flutter 不提供内部截图 API（flutter_inappwebview 才有），
  /// 返回 null；后翻页覆盖动画在无截图时自动降级为直接切换。
  /// TODO(M2): 用页面内 canvas（html2canvas 思路）实现内容截图。
  Future<Uint8List?> screenshot() async => null;

  /// 拉取页面内部诊断（__diagDump）：错误文本与桥/书状态。
  Future<String?> dumpDiag() async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        'window.__diagDump ? window.__diagDump() : null',
      );
      return result.toString();
    } catch (_) {
      return null;
    }
  }

  /// JSON 字符串字面量即合法 JS 字符串字面量（转义规则一致）。
  String _jsStr(String s) => jsonEncode(s);

  Future<void> _eval(String source) async {
    try {
      await _controller.runJavaScript(source);
    } catch (_) {
      // WebView 已销毁/页面未就绪时静默丢弃；事件由重试与看门狗兜底。
    }
  }
}


/// TTS 句子片段。
class TtsSegment {
  const TtsSegment({required this.cfi, required this.text});

  /// 句子范围 CFI（epub.js 可直接定位）。
  final String cfi;

  /// 句子文本。
  final String text;
}
