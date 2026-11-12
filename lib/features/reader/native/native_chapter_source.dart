/// 原生文本阅读面的章节文本源。
///
/// 复用 `parseEpub`（与全书检索同一条解析链），拿到每章的纯文本，
/// 供 `NativePaginator` 分页、`NativeReaderView` 渲染。
/// 解析在 isolate 里跑，不阻塞 UI。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Locator;

import '../../../data/parsers/epub/epub_parser.dart';
import '../../../data/parsers/plain_text_parser.dart';
import '../../../core/locator.dart';
import '../../../domain/entities/book.dart';

/// 章内一个排版段落（正文段或标题）。
class NativeParagraph {
  const NativeParagraph({
    required this.text,
    required this.start,
    this.level = 0,
    this.centered = false,
  });

  /// 段落文本（空白已收敛）。
  final String text;

  /// 在章正文里的起始字符偏移（与 [NativeChapter.text] 对齐）。
  final int start;

  /// 标题级别：0 = 正文，1..6 = 标题（数字越小级别越高）。
  final int level;

  /// 原书是否显式居中。
  final bool centered;

  /// 是否标题。
  bool get isHeading => level > 0;
}

/// 一章的正文（原生渲染用）。
///
/// 段落用三个平行数组存（起点/级别/居中），`paragraphs` 惰性生成对象：
/// 一本 770 万字、41 万段的双语诗集，若解析时就为每段建对象，isolate
/// 拷贝足以把真机内存打爆（正文直接出不来）。
class NativeChapter {
  NativeChapter._({
    required this.idx,
    required this.title,
    required this.href,
    required this.text,
    required this.paragraphStarts,
    required this.paragraphLevels,
    required this.paragraphCentered,
  });

  /// 从解析结果构造（紧凑数组）。
  factory NativeChapter.fromCompact({
    required int idx,
    required String title,
    required String href,
    required String text,
    required List<int> paragraphStarts,
    required List<int> paragraphLevels,
    required List<bool> paragraphCentered,
  }) {
    // 旧数据/纯文本：没有段落数组时整章作为一段
    if (paragraphStarts.isEmpty && text.trim().isNotEmpty) {
      return NativeChapter._(
        idx: idx,
        title: title,
        href: href,
        text: text.trim(),
        paragraphStarts: const <int>[0],
        paragraphLevels: const <int>[0],
        paragraphCentered: const <bool>[false],
      );
    }
    return NativeChapter._(
      idx: idx,
      title: title,
      href: href,
      text: text,
      paragraphStarts: paragraphStarts,
      paragraphLevels: paragraphLevels,
      paragraphCentered: paragraphCentered,
    );
  }

  /// 从块对象构造（测试/工具用）。
  factory NativeChapter.fromBlocks({
    required int idx,
    required String title,
    required String href,
    required List<ParsedBlock> blocks,
    required String fallbackText,
  }) {
    final source = blocks.isNotEmpty
        ? blocks
        : <ParsedBlock>[
            if (fallbackText.trim().isNotEmpty)
              ParsedBlock(text: fallbackText.trim()),
          ];
    final starts = <int>[];
    final levels = <int>[];
    final centered = <bool>[];
    final buffer = StringBuffer();
    for (final b in source) {
      final text = b.text.trim();
      if (text.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write(String.fromCharCode(10));
      starts.add(buffer.length);
      levels.add(b.level);
      centered.add(b.centered);
      buffer.write(text);
    }
    return NativeChapter.fromCompact(
      idx: idx,
      title: title,
      href: href,
      text: buffer.toString(),
      paragraphStarts: starts,
      paragraphLevels: levels,
      paragraphCentered: centered,
    );
  }

  /// 章序号（0 基，与解析出的 spine 顺序一致）。
  final int idx;

  /// 章标题。
  final String title;

  /// zip 内 href（目录跳转按它匹配）。
  final String href;

  /// 正文纯文本（段落之间用换行分隔；标注/TTS/进度都用这个坐标系）。
  final String text;

  /// 段落起点（相对 [text]，升序）。
  final List<int> paragraphStarts;

  /// 段落标题级别（0 = 正文，1..6 = 标题）。
  final List<int> paragraphLevels;

  /// 段落是否原书居中。
  final List<bool> paragraphCentered;

  List<NativeParagraph>? _paragraphs;

  /// 分段结构（按需生成；只在当前章排版时用到）。
  List<NativeParagraph> get paragraphs => _paragraphs ??= () {
        final out = <NativeParagraph>[];
        for (var i = 0; i < paragraphStarts.length; i++) {
          final start = paragraphStarts[i];
          final end = i + 1 < paragraphStarts.length
              ? paragraphStarts[i + 1] - 1
              : text.length;
          if (start >= end) continue;
          out.add(NativeParagraph(
            text: text.substring(start, end),
            start: start,
            level: i < paragraphLevels.length ? paragraphLevels[i] : 0,
            centered:
                i < paragraphCentered.length ? paragraphCentered[i] : false,
          ));
        }
        return out;
      }();
}

/// 章节缓存的键：只认「书源文件」，不认会变化的书籍元数据。
///
/// 直接用 `Book` 当 family key 时，`touchOpened` 改 `lastOpenedAt` 会让
/// 每次打开都变成新 key、重新解析一遍（首次慢、第二次也不该重来）。
/// 同一本书（id/路径/内容哈希/大小/格式不变）始终命中同一份解析结果。
@immutable
class NativeChaptersKey {
  const NativeChaptersKey({
    required this.id,
    required this.path,
    required this.sha256,
    required this.size,
    required this.format,
    required this.title,
  });

  factory NativeChaptersKey.of(Book book) => NativeChaptersKey(
        id: book.id,
        path: book.filePath,
        sha256: book.fileSha256,
        size: book.fileSize,
        format: book.format,
        title: book.title,
      );

  final String id;
  final String path;
  final String sha256;
  final int size;
  final BookFormat format;
  final String title;

  @override
  bool operator ==(Object other) =>
      other is NativeChaptersKey &&
      other.id == id &&
      other.path == path &&
      other.sha256 == sha256 &&
      other.size == size &&
      other.format == format;

  @override
  int get hashCode => Object.hash(id, path, sha256, size, format);
}

/// 单次解析上限：大书（几十 MB）在手机上解析可达数十秒，超时给重试入口，
/// 而不是让「正在打开…」无限转。
const Duration _kNativeParseTimeout = Duration(seconds: 60);

/// 按书源提供章节文本（同一文件只解析一次，之后走缓存）。
final nativeChaptersProvider =
    FutureProvider.family<List<NativeChapter>, NativeChaptersKey>(
        (ref, key) async {
  final file = File(key.path);
  if (!await file.exists()) {
    throw StateError('书籍文件不存在');
  }
  final bytes = await file.readAsBytes();
  if (key.format == BookFormat.pdf) {
    throw StateError('暂不支持 PDF 阅读');
  }
  if (key.format != BookFormat.epub) {
    final plain = await splitPlainTextInIsolate(
      bytes,
      title: key.title,
      markdown: key.format == BookFormat.md,
    ).timeout(_kNativeParseTimeout);
    return [
      for (final c in plain)
        NativeChapter.fromCompact(
          idx: c.idx,
          title: c.title,
          href: c.href,
          text: c.text,
          paragraphStarts: c.paragraphStarts,
          paragraphLevels: c.paragraphLevels,
          paragraphCentered: c.paragraphCentered,
        ),
    ];
  }
  final parsed =
      await parseEpubInIsolate(bytes, key.title).timeout(_kNativeParseTimeout);
  final out = <NativeChapter>[];
  for (final c in parsed.chapters) {
    final chapter = NativeChapter.fromCompact(
      idx: out.length,
      title: c.title.isEmpty ? '第 ${out.length + 1} 章' : c.title,
      href: c.href,
      text: c.bodyText,
      paragraphStarts: c.paragraphStarts,
      paragraphLevels: c.paragraphLevels,
      paragraphCentered: c.paragraphCentered,
    );
    if (chapter.text.trim().isEmpty) continue; // 跳过封面/空占位章节
    out.add(chapter);
  }
  return out;
});


/// 是否是前置页（扉页/版权/书名页/目录等）。
bool isFrontMatterTitle(String title) {
  final t = title.toLowerCase().replaceAll(' ', '');
  const keys = [
    '扉页',
    '版权',
    '书名页',
    '封面',
    '目录',
    '插图',
    'cover',
    'copyright',
    'titlepage',
  ];
  return keys.any(t.contains);
}

/// 新书打开时的起始章：跳过前置页与占位页，落在有正文的章节。
///
/// 很多 EPUB 的第 1 章是「扉页」「版权页」甚至只有「未知」两个字；直接
/// 打开会像"没有内容"。这里跳过标题像前置页的章节，并跳过正文过短
/// （<40 字）的占位章；整本都短（诗集）时退回第一个非前置页。
int firstReadableChapterIndex(List<NativeChapter> chapters) {
  int? firstNonFront;
  for (var i = 0; i < chapters.length; i++) {
    final c = chapters[i];
    if (_looksLikeFrontMatter(c, i)) continue;
    firstNonFront ??= i;
    if (c.text.length >= 40) return i;
  }
  return firstNonFront ?? 0;
}

/// 前置页判定：标题像前置页，或**前几章的正文开头**是版权/目录等标记。
///
/// 有的书章标题是「第 1 章」而不是「版权信息」，但正文开头就是版权页
/// （实测《大学问》第 1 章 4 万字全是版权/CIP）；只按标题判断会漏掉。
bool _looksLikeFrontMatter(NativeChapter c, int index) {
  // 长章节不能整章跳过：单文件 EPUB 里「版权信息」那一章往往把前几章
  // 正文也塞在同一个文件里，跳掉会丢内容。
  if (c.text.length > 5000) return false;
  if (isFrontMatterTitle(c.title)) return true;
  if (index > 2) return false;
  final head = c.text.trimLeft();
  final probe = head.length > 80 ? head.substring(0, 80) : head;
  const markers = [
    '版权信息',
    '图书在版编目',
    'CIP',
    'ISBN',
    '目录',
    '扉页',
    '书名页',
  ];
  return markers.any(probe.contains);
}

/// 标注 / 书签的 locator → 原生章。
///
/// 先看章索引：calibre 这类「一份 XHTML 拆多章」的书，多个 [NativeChapter]
/// 共用同一个 href，只按 href 找会永远落在该文件的第一章——新划线于是画到
/// 别的章、看起来「划线后没有标注色块」（v2.13.2 修）。索引与 href 对得上
/// 才用索引；旧数据（索引是重切章节前的）退回按 href 找第一章，再退索引。
NativeChapter? nativeChapterForLocator(
  List<NativeChapter> chapters,
  Locator loc,
) {
  final idx = loc.chapterIndex;
  final href = loc.href;
  final indexValid = idx != null && idx >= 0 && idx < chapters.length;
  if (indexValid && (href == null || chapters[idx].href == href)) {
    return chapters[idx];
  }
  if (href != null) {
    for (final c in chapters) {
      if (c.href == href) return c;
    }
  }
  return indexValid ? chapters[idx] : null;
}