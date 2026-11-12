/// 纯文本 / Markdown 的章节切分。
///
/// 导入（写目录、建检索索引）与阅读器渲染共用同一套切分算法，保证
/// 目录里的章序号、标题与正文完全对得上。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

/// 一章切分结果（紧凑段落数组，便于跨 isolate 传递）。
class PlainChapter {
  const PlainChapter({
    required this.idx,
    required this.title,
    required this.href,
    required this.text,
    required this.paragraphStarts,
    required this.paragraphLevels,
    required this.paragraphCentered,
  });

  /// 章序号（0 基）。
  final int idx;

  /// 章标题。
  final String title;

  /// 章节定位键（`plain:<idx>`）。
  final String href;

  /// 正文（段落以 `\n` 分隔）。
  final String text;

  /// 段落起点。
  final List<int> paragraphStarts;

  /// 段落标题级别。
  final List<int> paragraphLevels;

  /// 段落是否居中（纯文本恒 false）。
  final List<bool> paragraphCentered;
}

/// 每章目标字符数（无章节标题时按它切分）。
const int _targetChars = 12000;

/// Markdown 标题：`# 标题`（1..6 级）。
final RegExp _mdHeading = RegExp(r'^(#{1,6})\s+(\S.*)$');

/// 中文小说常见章标题：第 1 章 / 第十二回 / 第三卷…
final RegExp _cnHeading =
    RegExp(r'^第[0-9０-９一二三四五六七八九十百千零两]+[章回节卷篇部][^\n]{0,30}$');

/// 章标题行不应带句读（正文句子以「第一章……」开头很常见）。
final RegExp _sentencePunctuation = RegExp('[。！？；，、：]');

/// 切分纯文本 / Markdown。
///
/// - Markdown 的 `#` 标题、TXT 的「第 N 章」行会另起一章，并作为该章标题；
/// - 没有章节标题时按约 1.2 万字在段落边界切分，避免一章几十万字导致
///   首屏排版卡死。
List<PlainChapter> splitPlainText(
  String raw, {
  bool markdown = false,
  String title = '',
}) {
  final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final out = <PlainChapter>[];

  var paragraphs = <String>[];
  var levels = <int>[];
  var chapterTitle = '';
  var chars = 0;

  void flush() {
    if (paragraphs.isEmpty) return;
    final buffer = StringBuffer();
    final starts = <int>[];
    final paraLevels = <int>[];
    for (var i = 0; i < paragraphs.length; i++) {
      if (buffer.isNotEmpty) buffer.write(String.fromCharCode(10));
      starts.add(buffer.length);
      paraLevels.add(levels[i]);
      buffer.write(paragraphs[i]);
    }
    final idx = out.length;
    final fallback = title.isEmpty
        ? '第 ${idx + 1} 部分'
        : (idx == 0 ? title : '第 ${idx + 1} 部分');
    out.add(PlainChapter(
      idx: idx,
      title: chapterTitle.isEmpty ? fallback : chapterTitle,
      href: 'plain:$idx',
      text: buffer.toString(),
      paragraphStarts: starts,
      paragraphLevels: paraLevels,
      paragraphCentered: List<bool>.filled(starts.length, false),
    ));
    paragraphs = <String>[];
    levels = <int>[];
    chapterTitle = '';
    chars = 0;
  }

  for (final rawLine in normalized.split('\n')) {
    final line = rawLine.trimRight();
    if (line.trim().isEmpty) continue;

    var headingText = '';
    var headingLevel = 0;
    final trimmed = line.trim();
    if (markdown) {
      final m = _mdHeading.firstMatch(trimmed);
      if (m != null) {
        headingText = m.group(2)!.trim();
        headingLevel = m.group(1)!.length.clamp(1, 6);
      }
    } else if (rawLine == line &&
        trimmed.length <= 30 &&
        !_sentencePunctuation.hasMatch(trimmed) &&
        _cnHeading.hasMatch(trimmed)) {
      // 只认「顶格 + 短 + 无句读」的行，避免把「第一章……正文」这种
      // 缩进正文首句误判成章标题
      headingText = trimmed;
      headingLevel = 1;
    }

    if (headingText.isNotEmpty) {
      flush();
      chapterTitle = headingText;
      paragraphs.add(headingText);
      levels.add(headingLevel);
      chars += headingText.length;
      continue;
    }

    if (chars >= _targetChars && paragraphs.isNotEmpty) flush();
    paragraphs.add(line.trim());
    levels.add(0);
    chars += line.trim().length;
  }
  flush();
  return out;
}

/// isolate 包装：解码 + 切分。
Future<List<PlainChapter>> splitPlainTextInIsolate(
  Uint8List bytes, {
  required String title,
  required bool markdown,
}) =>
    compute(
      (req) => splitPlainText(
        utf8.decode(req.bytes, allowMalformed: true),
        markdown: req.markdown,
        title: req.title,
      ),
      _PlainRequest(bytes, title, markdown),
    );

class _PlainRequest {
  const _PlainRequest(this.bytes, this.title, this.markdown);

  final Uint8List bytes;
  final String title;
  final bool markdown;
}
