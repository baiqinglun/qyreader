/// reader.html 资源组装：把 jszip/epub 内联进页面，避免相对路径与 file 域限制。
///
/// 渲染页以 file:// 方式加载（data-URI 在部分平台实现上不可靠），
/// 组装结果落盘到应用支持目录。
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 组装完成的 HTML 缓存。
String? _cachedHtml;

/// 返回可注入 WebView 的完整 HTML（脚本内联）。
Future<String> loadReaderHtml() async {
  final cached = _cachedHtml;
  if (cached != null) return cached;

  final html = await rootBundle.loadString('assets/reader/reader.html');
  final jszip = await rootBundle.loadString('assets/reader/jszip.min.js');
  final epub = await rootBundle.loadString('assets/reader/epub.min.js');

  // 压缩库内容里不应出现闭合 script 标签；出现则内联会被截断，直接报错暴露。
  for (final js in <String>[jszip, epub]) {
    if (js.toLowerCase().contains('</script')) {
      throw StateError('assets/reader 内联脚本包含 </script>，无法内联');
    }
  }

  final inlined = html
      .replaceAll(
        '<script src="jszip.min.js"></script>',
        '<script>\n$jszip\n</script>',
      )
      .replaceAll(
        '<script src="epub.min.js"></script>',
        '<script>\n$epub\n</script>',
      );
  _cachedHtml = inlined;
  return inlined;
}

/// 把组装好的 HTML 落盘，返回 file:// URL（各平台 WebView 均可靠）。
Future<Uri> ensureReaderHtmlFile() async {
  final html = await loadReaderHtml();
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, 'reader.html'));
  // 内容变化（升级后旧文件残留）才重写
  var needsWrite = true;
  if (await file.exists()) {
    try {
      needsWrite = await file.length() != html.length;
    } catch (_) {
      needsWrite = true;
    }
  }
  if (needsWrite) await file.writeAsString(html, flush: true);
  return Uri.file(file.path);
}
