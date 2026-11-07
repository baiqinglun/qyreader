/// EPUB 2/3 解析器。
///
/// 在 isolate 中运行：容器解析 → OPF 元数据 → 封面 → spine →
/// nav/ncx 目录 → 正文字数统计。不整本解压到磁盘，按需读 zip 条目。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:xml/xml.dart';

import '../../../core/result.dart';

/// 解析产出的章节。
class ParsedChapter {
  const ParsedChapter({
    required this.idx,
    required this.title,
    required this.href,
    this.level = 0,
    this.startOffset = 0,
    this.charCount = 0,
  });

  /// 章序号（0 基）。
  final int idx;

  /// 章标题。
  final String title;

  /// 规范化后的 zip 内 href（不含 fragment）。
  final String href;

  /// 目录层级（0 顶）。
  final int level;

  /// 章内起始字符偏移（M1 由分页器回填）。
  final int startOffset;

  /// 章内字符数。
  final int charCount;
}

/// 解析产出：元数据 + 章节 + 封面字节。
class ParsedEbook {
  const ParsedEbook({
    required this.title,
    required this.chapters,
    required this.wordCount,
    this.author,
    this.language,
    this.description,
    this.coverBytes,
    this.coverMediaType,
    this.metaJson,
  });

  /// 书名（可能由文件名兜底）。
  final String title;

  /// 作者。
  final String? author;

  /// 语言。
  final String? language;

  /// 简介。
  final String? description;

  /// 封面图原始字节。
  final Uint8List? coverBytes;

  /// 封面 MIME 类型。
  final String? coverMediaType;

  /// 章节列表（目录顺序）。
  final List<ParsedChapter> chapters;

  /// 全文近似字数。
  final int wordCount;

  /// OPF 其余元数据 JSON。
  final String? metaJson;
}

/// EPUB 解析入口。纯函数，可在 isolate 或测试中直接调用。
ParsedEbook parseEpub(Uint8List bytes, String fileName) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw ParseException('parse.epub.zip', '无法解压 EPUB：$e');
  }

  _EntryReader reader = _EntryReader(archive);

  // 1) container.xml → OPF 路径
  final containerRaw = reader.readAsString('META-INF/container.xml');
  if (containerRaw == null) {
    throw ParseException('parse.epub.container', '缺少 META-INF/container.xml');
  }
  final opfPath = _findOpfPath(containerRaw);
  if (opfPath == null) {
    throw ParseException('parse.epub.rootfile', 'container.xml 中无 rootfile');
  }

  // 2) OPF：元数据 / manifest / spine
  final opfRaw = reader.readAsString(opfPath);
  if (opfRaw == null) {
    throw ParseException('parse.epub.opf', 'OPF 文件不存在: $opfPath');
  }
  XmlDocument opf;
  try {
    opf = XmlDocument.parse(opfRaw);
  } catch (e) {
    throw ParseException('parse.epub.opf.xml', 'OPF 不是合法 XML：$e');
  }
  final opfDir = _parentDir(opfPath);

  final title = opf.findAllElements('dc:title').firstOrNull?.innerText.trim();
  final author =
      opf.findAllElements('dc:creator').firstOrNull?.innerText.trim();
  final language =
      opf.findAllElements('dc:language').firstOrNull?.innerText.trim();
  final description =
      opf.findAllElements('dc:description').firstOrNull?.innerText.trim();

  // manifest: id → item
  final manifestItems = <String, XmlNode>{};
  for (final item in opf.findAllElements('item')) {
    final id = item.getAttribute('id');
    if (id != null) manifestItems[id] = item;
  }

  // spine: 文档顺序 idref
  final spineIdrefs = <String>[];
  String? ncxId;
  for (final spine in opf.findAllElements('spine')) {
    ncxId = spine.getAttribute('toc');
    for (final ref in spine.findElements('itemref')) {
      final idref = ref.getAttribute('idref');
      if (idref != null) spineIdrefs.add(idref);
    }
  }

  // 3) 封面：meta name="cover" 或 properties 含 cover-image
  final cover = _extractCover(reader, opf, manifestItems, opfDir);

  // 4) 目录：EPUB3 nav 优先，退回 EPUB2 ncx，最后按 spine 兜底
  var chapters = _parseNav(reader, manifestItems, opfDir);
  if (chapters.isEmpty) {
    chapters = _parseNcx(reader, manifestItems, ncxId, opfDir);
  }
  if (chapters.isEmpty) {
    chapters = _chaptersFromSpine(reader, manifestItems, spineIdrefs, opfDir);
  }

  // 5) 正文字数：spine 文档去标签文本长度求和
  var wordCount = 0;
  for (final idref in spineIdrefs) {
    final item = manifestItems[idref];
    final href = item?.getAttribute('href');
    if (href == null) continue;
    final raw = reader.readAsString(_joinPath(opfDir, _decodeHref(href)));
    if (raw == null) continue;
    wordCount += _extractTextLength(raw);
  }

  final fallbackTitle =
      title == null || title.isEmpty ? _titleFromFileName(fileName) : title;

  return ParsedEbook(
    title: fallbackTitle,
    author: author == null || author.isEmpty ? null : author,
    language: language == null || language.isEmpty ? null : language,
    description: description == null || description.isEmpty
        ? null
        : description,
    coverBytes: cover.$1,
    coverMediaType: cover.$2,
    chapters: chapters,
    wordCount: wordCount,
    metaJson: null,
  );
}

/// isolate 包装：主线程调用，解析在后台 isolate 完成。
Future<ParsedEbook> parseEpubInIsolate(
  Uint8List bytes,
  String fileName,
) =>
    compute(
      (req) => parseEpub(req.bytes, req.fileName),
      _ParseRequest(bytes, fileName),
    );

class _ParseRequest {
  const _ParseRequest(this.bytes, this.fileName);

  final Uint8List bytes;
  final String fileName;
}

/// zip 条目按需读取器。
class _EntryReader {
  _EntryReader(this._archive);

  final Archive _archive;
  final Map<String, ArchiveFile> _cache = {};

  /// 按路径读文本（utf8，容错解码）；不存在返回 null。
  String? readAsString(String path) {
    final bytes = readAsBytes(path);
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 按路径读字节；不存在返回 null。
  Uint8List? readAsBytes(String path) {
    final normalized = _normalizeZipPath(path);
    final cached = _cache[normalized];
    if (cached != null) return Uint8List.fromList(cached.content);
    final file = _findEntry(normalized);
    if (file == null) return null;
    _cache[normalized] = file;
    return Uint8List.fromList(file.content);
  }

  ArchiveFile? _findEntry(String path) {
    for (final file in _archive.files) {
      if (file.isFile && _normalizeZipPath(file.name) == path) return file;
    }
    return null;
  }

  /// zip 内路径大小写与 ./ 前缀宽松匹配。
  static String _normalizeZipPath(String path) {
    var p = path.replaceAll('\\', '/');
    while (p.startsWith('./')) {
      p = p.substring(2);
    }
    return p;
  }
}

String? _findOpfPath(String containerXml) {
  try {
    final doc = XmlDocument.parse(containerXml);
    for (final rootfile in doc.findAllElements('rootfile')) {
      final path = rootfile.getAttribute('full-path');
      if (path != null && path.isNotEmpty) return path;
    }
  } on XmlException {
    return null;
  }
  return null;
}

/// 返回 (封面字节, MIME)；找不到封面返回 (null, null)。
(Uint8List?, String?) _extractCover(
  _EntryReader reader,
  XmlDocument opf,
  Map<String, XmlNode> manifestItems,
  String opfDir,
) {
  // EPUB2 优先：meta name="cover" content={manifest id}
  String? coverId;
  for (final meta in opf.findAllElements('meta')) {
    if (meta.getAttribute('name') == 'cover') {
      coverId = meta.getAttribute('content');
    }
  }
  XmlNode? item;
  if (coverId != null) item = manifestItems[coverId];
  // EPUB3：properties 含 cover-image
  if (item == null) {
    for (final it in manifestItems.values) {
      final props = (it.getAttribute('properties') ?? '').split(RegExp(r'\s+'));
      if (props.contains('cover-image')) {
        item = it;
        break;
      }
    }
  }
  final href = item?.getAttribute('href');
  if (href == null || href.isEmpty) return (null, null);
  final bytes = reader.readAsBytes(_joinPath(opfDir, _decodeHref(href)));
  return (bytes, item?.getAttribute('media-type'));
}

/// EPUB3 nav.xhtml 目录。
List<ParsedChapter> _parseNav(
  _EntryReader reader,
  Map<String, XmlNode> manifestItems,
  String opfDir,
) {
  XmlNode? navItem;
  for (final it in manifestItems.values) {
    final props = (it.getAttribute('properties') ?? '').split(RegExp(r'\s+'));
    if (props.contains('nav')) {
      navItem = it;
      break;
    }
  }
  if (navItem == null) return const [];
  final navHref = navItem.getAttribute('href');
  if (navHref == null) return const [];
  final navPath = _joinPath(opfDir, _decodeHref(navHref));
  final raw = reader.readAsString(navPath);
  if (raw == null) return const [];

  XmlDocument doc;
  try {
    doc = XmlDocument.parse(raw);
  } on XmlException {
    return const [];
  }
  final baseDir = _parentDir(navPath);
  final result = <ParsedChapter>[];

  void walk(XmlElement ol, int level) {
    for (final li in ol.findElements('li')) {
      final a = li.findElements('a').firstOrNull;
      if (a == null) {
        // 无链接条目：继续看嵌套 ol（卷名无正文的情况）
        final nested = li.findElements('ol').firstOrNull;
        if (nested != null) walk(nested, level);
        continue;
      }
      final title = a.innerText.trim();
      final href = a.getAttribute('href');
      if (title.isNotEmpty && href != null) {
        result.add(
          ParsedChapter(
            idx: result.length,
            title: title,
            href: _joinPath(baseDir, _decodeHref(_stripFragment(href))),
            level: level,
          ),
        );
      }
      final nested = li.findElements('ol').firstOrNull;
      if (nested != null) walk(nested, level + 1);
    }
  }

  // 优先 epub:type="toc" 的 nav，退回第一个 nav
  final navs = doc.findAllElements('nav').toList();
  XmlElement? tocNav;
  for (final n in navs) {
    final type = n.getAttribute('type',
            namespace: 'http://www.idpf.org/2007/ops') ??
        n.getAttribute('epub:type');
    if (type == 'toc') {
      tocNav = n;
      break;
    }
  }
  tocNav ??= navs.firstOrNull;
  if (tocNav == null) return const [];
  for (final ol in tocNav.findElements('ol')) {
    walk(ol, 0);
  }
  return result;
}

/// EPUB2 toc.ncx 目录。
List<ParsedChapter> _parseNcx(
  _EntryReader reader,
  Map<String, XmlNode> manifestItems,
  String? ncxId,
  String opfDir,
) {
  XmlNode? ncxItem = ncxId == null ? null : manifestItems[ncxId];
  if (ncxItem == null) {
    for (final it in manifestItems.values) {
      if (it.getAttribute('media-type') == 'application/x-dtbncx+xml') {
        ncxItem = it;
        break;
      }
    }
  }
  final href = ncxItem?.getAttribute('href');
  if (href == null || href.isEmpty) return const [];
  final ncxPath = _joinPath(opfDir, _decodeHref(href));
  final raw = reader.readAsString(ncxPath);
  if (raw == null) return const [];

  XmlDocument doc;
  try {
    doc = XmlDocument.parse(raw);
  } on XmlException {
    return const [];
  }
  final baseDir = _parentDir(ncxPath);
  final result = <ParsedChapter>[];

  void walk(XmlElement navPoint, int level) {
    final label = navPoint.findElements('navLabel').firstOrNull?.innerText ??
        navPoint.findElements('text').firstOrNull?.innerText ??
        '';
    final content =
        navPoint.findElements('content').firstOrNull?.getAttribute('src');
    if (label.trim().isNotEmpty && content != null) {
      result.add(
        ParsedChapter(
          idx: result.length,
          title: label.trim(),
          href: _joinPath(baseDir, _decodeHref(_stripFragment(content))),
          level: level,
        ),
      );
    }
    for (final child in navPoint.findElements('navPoint')) {
      walk(child, level + 1);
    }
  }

  for (final np in doc.findAllElements('navPoint')) {
    // 只从顶层 navPoint 开始（父级在 navMap 直接子层）
    if (np.parentElement?.name.local == 'navPoint') continue;
    walk(np, 0);
  }
  return result;
}

/// 无目录时按 spine 兜底：每章一个条目，标题取文档 title/h1，取不到用序号。
List<ParsedChapter> _chaptersFromSpine(
  _EntryReader reader,
  Map<String, XmlNode> manifestItems,
  List<String> spineIdrefs,
  String opfDir,
) {
  final result = <ParsedChapter>[];
  for (final idref in spineIdrefs) {
    final item = manifestItems[idref];
    final href = item?.getAttribute('href');
    if (href == null) continue;
    final path = _joinPath(opfDir, _decodeHref(href));
    String title = '';
    final raw = reader.readAsString(path);
    if (raw != null) {
      try {
        final doc = XmlDocument.parse(raw);
        title = doc.findAllElements('title').firstOrNull?.innerText.trim() ??
            doc.findAllElements('h1').firstOrNull?.innerText.trim() ??
            '';
      } on XmlException {
        // 标题解析失败按空处理
      }
    }
    result.add(
      ParsedChapter(
        idx: result.length,
        title: title.isEmpty ? '第 ${result.length + 1} 节' : title,
        href: path,
      ),
    );
  }
  return result;
}

/// 提取 HTML/XHTML 文本的近似长度（去标签）。
int _extractTextLength(String raw) {
  try {
    final doc = XmlDocument.parse(raw);
    return doc.rootElement.innerText.length;
  } on XmlException {
    // 非 XML 的 HTML：粗略去标签
    final noScript = raw.replaceAll(RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), '');
    return noScript.replaceAll(RegExp(r'<[^>]+>'), '').length;
  }
}

String _decodeHref(String href) {
  try {
    return Uri.decodeComponent(href);
  } on ArgumentError {
    return href;
  }
}

String _stripFragment(String href) =>
    href.contains('#') ? href.substring(0, href.indexOf('#')) : href;

/// 以 OPF 所在目录为基准合并相对路径，处理 `..` 与 `./`。
String _joinPath(String baseDir, String href) {
  final parts = <String>[];
  if (baseDir.isNotEmpty) parts.addAll(baseDir.split('/'));
  for (final seg in href.split('/')) {
    if (seg == '.' || seg.isEmpty) continue;
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(seg);
  }
  return parts.join('/');
}

String _parentDir(String path) {
  final idx = path.lastIndexOf('/');
  return idx <= 0 ? '' : path.substring(0, idx);
}

String _titleFromFileName(String fileName) {
  var name = fileName;
  final slash = name.lastIndexOf('/');
  if (slash >= 0) name = name.substring(slash + 1);
  if (name.toLowerCase().endsWith('.epub')) {
    name = name.substring(0, name.length - 5);
  }
  return name.isEmpty ? '未命名书籍' : name;
}
