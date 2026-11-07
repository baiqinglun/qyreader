/// reader.html 资源组装：把 jszip/epub 内联进页面，避免相对路径与 file 域限制。
library;

import 'package:flutter/services.dart' show rootBundle;

/// 组装完成的一次性缓存。
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
