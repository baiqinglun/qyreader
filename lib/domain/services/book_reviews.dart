/// 书评的多条存取：`books.review` 单字段里编解码多条书评。
///
/// 单条书评保持纯文本（与旧数据兼容）；多条时存 JSON 数组。
/// 解析容错：坏 JSON / 非字符串元素按单条原文处理。
library;

import 'dart:convert';

/// 解出这本书的所有书评（旧单条纯文本 → 一条）。
List<String> decodeBookReviews(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return const <String>[];
  if (text.startsWith('[')) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        final out = <String>[];
        for (final item in decoded) {
          if (item is String) {
            final t = item.trim();
            if (t.isNotEmpty) out.add(t);
          }
        }
        if (out.isNotEmpty) return out;
      }
    } catch (_) {
      // 坏 JSON 按单条原文处理
    }
  }
  return [text];
}

/// 编码回 `books.review` 字段；单条存纯文本，多条存 JSON 数组。
String encodeBookReviews(List<String> reviews) {
  final clean = [
    for (final r in reviews)
      if (r.trim().isNotEmpty) r.trim(),
  ];
  if (clean.isEmpty) return '';
  if (clean.length == 1) return clean.first;
  return jsonEncode(clean);
}
