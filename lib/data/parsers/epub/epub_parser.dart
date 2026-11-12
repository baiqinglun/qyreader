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

/// 章内一个排版块（标题或正文段落）。
///
/// 仅作为 `extractChapterBlocks` 的返回类型（测试/工具用）；解析结果本身
/// 用三个平行数组存段落，避免大书产生几十万个对象。
class ParsedBlock {
  const ParsedBlock({
    required this.text,
    this.level = 0,
    this.centered = false,
  });

  /// 块文本（空白已收敛）。
  final String text;

  /// 标题级别：0 = 正文；1..6 = 标题（数字越小级别越高）。
  final int level;

  /// 原书是否显式要求居中。
  final bool centered;
}

/// 解析产出的章节。
class ParsedChapter {
  const ParsedChapter({
    required this.idx,
    required this.title,
    required this.href,
    this.level = 0,
    this.anchor = '',
    this.startOffset = 0,
    this.charCount = 0,
    this.bodyText = '',
    this.paragraphStarts = const <int>[],
    this.paragraphLevels = const <int>[],
    this.paragraphCentered = const <bool>[],
  });

  /// 章序号（0 基）。
  final int idx;

  /// 章标题。
  final String title;

  /// 规范化后的 zip 内 href（不含 fragment）。
  final String href;

  /// 目录层级（0 顶）。
  final int level;

  /// 目录条目指向本文档内的锚点 id（`x.html#p12` → `p12`）；空 = 整篇。
  final String anchor;

  /// 章内起始字符偏移（M1 由分页器回填）。
  final int startOffset;

  /// 章内字符数。
  final int charCount;

  /// 章正文纯文本（段落以 `\n` 分隔；检索与阅读共用）。
  final String bodyText;

  /// 段落起点（相对 [bodyText]，升序；空 = 未提取）。
  final List<int> paragraphStarts;

  /// 段落标题级别（0 = 正文，1..6 = 标题）。
  final List<int> paragraphLevels;

  /// 段落是否原书居中。
  final List<bool> paragraphCentered;

  /// 拷贝（正文提取回填用）。
  ParsedChapter copyWith({
    String? bodyText,
    List<int>? paragraphStarts,
    List<int>? paragraphLevels,
    List<bool>? paragraphCentered,
  }) =>
      ParsedChapter(
        idx: idx,
        title: title,
        href: href,
        level: level,
        anchor: anchor,
        startOffset: startOffset,
        charCount: charCount,
        bodyText: bodyText ?? this.bodyText,
        paragraphStarts: paragraphStarts ?? this.paragraphStarts,
        paragraphLevels: paragraphLevels ?? this.paragraphLevels,
        paragraphCentered: paragraphCentered ?? this.paragraphCentered,
      );
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
ParsedEbook parseEpub(
  Uint8List bytes,
  String fileName, {
  /// 是否提取段落结构（阅读器需要；导入/同步只取纯文本时可关掉省内存）。
  bool withParagraphs = true,
}) {
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

  // 5) 章正文：按 href 分组，再用目录锚点把同一份文档切成多章。
  //    单文件 EPUB（calibre / pdftohtml 常见）的多个目录条目用 `#p12`
  //    指向同一份 XHTML：只按 href 取正文会把整本书塞进第一个条目，
  //    后面的章节全部消失（实测《十扇窗》16 个目录条目只剩 4 章）。
  //    这里用目录里的真实锚点（不是按标题猜）定位切分块；一章跨文件时
  //    下一份文档开头（第一个锚点之前）续到上一章，正文不丢也不重复；
  //    锚点一个都对不上时退回「整篇一章」。
  final byHref = <String, List<int>>{};
  for (var i = 0; i < chapters.length; i++) {
    byHref.putIfAbsent(chapters[i].href, () => <int>[]).add(i);
  }

  final blocksByChapter = <int, List<_TextBlock>>{};
  final order = <int>[];
  for (final entry in byHref.entries) {
    final sources = [for (final i in entry.value) chapters[i]];
    final raw = reader.readAsString(entry.key);
    if (raw == null) {
      // 文档读不出来：目录条目原样保留（正文留空）。
      for (final index in entry.value) {
        if (blocksByChapter.containsKey(index)) continue;
        blocksByChapter[index] = <_TextBlock>[];
        order.add(index);
      }
      continue;
    }
    final segments = _splitByAnchors(raw, [for (final c in sources) c.anchor]);
    // 文档开头、第一个锚点之前的内容：属于上一个目录条目（跨文件续章）。
    // 全书第一份文档没有上一章，前置内容（封面 / 版权页）并进第一章。
    if (segments.leading.isNotEmpty) {
      if (order.isNotEmpty) {
        blocksByChapter[order.last]!.addAll(segments.leading);
      } else if (segments.parts.isNotEmpty) {
        segments.parts.first.blocks.insertAll(0, segments.leading);
      }
    }
    for (final part in segments.parts) {
      // `part.source` 是本文档内的条目下标，换成全书目录下标。
      final source = entry.value[part.source];
      final list = blocksByChapter.putIfAbsent(source, () {
        order.add(source);
        return <_TextBlock>[];
      });
      list.addAll(part.blocks);
    }
  }

  final rebuilt = <ParsedChapter>[];
  for (final sourceIndex in order) {
    final source = chapters[sourceIndex];
    final merged = _mergeHardWrappedBlocks(blocksByChapter[sourceIndex]!);
    final data = _layoutOfBlocks(merged, withParagraphs: withParagraphs);
    rebuilt.add(ParsedChapter(
      idx: rebuilt.length,
      title: source.title,
      href: source.href,
      level: source.level,
      anchor: source.anchor,
      startOffset: source.startOffset,
      charCount: source.charCount,
      bodyText: data.text,
      paragraphStarts: data.starts,
      paragraphLevels: data.levels,
      paragraphCentered: data.centered,
    ));
  }
  chapters = rebuilt;

  // 6) 正文字数：spine 文档去标签文本长度求和
  var wordCount = 0;
  for (final idref in spineIdrefs) {
    final item = manifestItems[idref];
    final href = item?.getAttribute('href');
    if (href == null) continue;
    final raw = reader.readAsString(_joinPath(opfDir, _decodeHref(href)));
    if (raw == null) continue;
    wordCount += _extractTextLength(raw);
  }

  final fallbackTitle = _normalizeTitle(
    title == null || title.isEmpty ? _titleFromFileName(fileName) : title,
    author: author,
  );

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
  String fileName, {
  bool withParagraphs = true,
}) =>
    compute(
      (req) => parseEpub(
        req.bytes,
        req.fileName,
        withParagraphs: req.withParagraphs,
      ),
      _ParseRequest(bytes, fileName, withParagraphs),
    );

class _ParseRequest {
  const _ParseRequest(this.bytes, this.fileName, this.withParagraphs);

  final Uint8List bytes;
  final String fileName;
  final bool withParagraphs;
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
            anchor: _fragmentOf(href),
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
          anchor: _fragmentOf(content),
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

/// 提取章正文纯文本：去 script/style，标签替换为空白并收敛空白。
/// 检索索引用；对中文无分词诉求，只需保证字符连续可查。
/// 一章正文的紧凑排版数据（纯文本 + 三个平行数组）。
class _ChapterLayoutData {
  const _ChapterLayoutData(
    this.text,
    this.starts,
    this.levels,
    this.centered,
  );

  final String text;
  final List<int> starts;
  final List<int> levels;
  final List<bool> centered;
}

/// 把一章 XHTML 拆成「标题 + 正文段落」块序列（测试/工具用）。
///
/// 只认块级元素（p / div / h1..h6 / li / blockquote / td…）：块内若有
/// 嵌套块就继续下钻，否则整块收敛成一段。这样既不会把 <br> 当段落，
/// 也不会把包裹用的 <div> 拆成一段空白。
List<ParsedBlock> extractChapterBlocks(String raw) {
  final blocks = <ParsedBlock>[];
  _forEachBlock(raw, (text, level, centered) {
    blocks.add(ParsedBlock(text: text, level: level, centered: centered));
  });
  final merged = _mergeHardWrappedBlocks(
    [for (final b in blocks) _TextBlock(b.text, b.level, b.centered)],
  );
  return [
    for (final b in merged) ParsedBlock(text: b.text, level: b.level, centered: b.centered),
  ];
}

/// 遍历一章里的所有正文块；块文本已收敛空白。
///
/// [onAnchor] 用来把目录锚点（`id="p12"`，calibre 常写成
/// `<a id="p12"></a>` 放在段首）对到「下一个要发出的块」的下标上：
/// 锚点所在块本身没正文时（锚点独占一段），正好落到后面的正文块。
void _forEachBlock(
  String raw,
  void Function(String text, int level, bool centered) emit, {
  void Function(String anchor, int blockIndex)? onAnchor,
}) {
  var emitted = 0;
  void reportAnchor(XmlElement el) {
    final report = onAnchor;
    if (report == null) return;
    final id = el.getAttribute('id');
    if (id != null && id.isNotEmpty) report(id, emitted);
    if (el.name.local.toLowerCase() == 'a') {
      final name = el.getAttribute('name');
      if (name != null && name.isNotEmpty) report(name, emitted);
    }
  }

  /// 块元素整块吐出来、不再下钻，所以块内的锚点要在这里一次找全。
  void reportAnchorDeep(XmlElement el) {
    if (onAnchor == null) return;
    reportAnchor(el);
    for (final child in el.descendants) {
      if (child is XmlElement) reportAnchor(child);
    }
  }

  void add(String text, int level, bool centered) {
    // 有的（盗版转制）书把标签打散成正文文本，例如一段以
    // `div class="kindle..." aid="11"> 正文...` 开头。带属性的「标签前缀」
    // 不可能是正常段落，剥掉前缀保留后面的正文。
    var cleaned = _stripTagFragment(text);
    // 块内/块尾残留的标签片段（`<div class="...">`、`给父亲</`）一并清掉：
    // 正常正文不会出现「属性="..."」组合或 `</`。
    cleaned = cleaned
        .replaceAll(
          RegExp(r'''/?[A-Za-z][A-Za-z0-9:-]*(\s+[A-Za-z-]+="[^"]*")+\s*/?>'''),
          ' ',
        )
        .replaceAll(RegExp(r'</[A-Za-z0-9]*>?'), '')
        .trim();
    if (cleaned.isEmpty || cleaned == '<' || cleaned == '>' || cleaned == '</') {
      return;
    }
    // 纯 ASCII 且带属性的行 = 拆散的标签残片（正常正文/英文不会出现 ="）
    final cjk = RegExp('[一-鿿]');
    if (!cjk.hasMatch(cleaned) && cleaned.contains('="')) return;
    emitted++;
    emit(cleaned, level, centered);
  }

  try {
    final doc = XmlDocument.parse(_sanitizeXhtml(raw));
    // 剔除 script/style（innerText 会带上其内容，污染检索索引）
    for (final tag in ['script', 'style']) {
      for (final el in doc.findAllElements(tag).toList()) {
        el.parent?.children.remove(el);
      }
    }
    void walk(XmlElement el) {
      for (final node in el.children) {
        if (node is! XmlElement) continue;
        final tag = node.name.local.toLowerCase();
        if (tag == 'script' || tag == 'style') continue;
        if (_blockTags.contains(tag) && !_hasNestedBlock(node)) {
          reportAnchorDeep(node);
          final text = _collapseWhitespace(node.innerText);
          add(text, _headingLevel(node, tag, text), _isCentered(node));
        } else {
          reportAnchor(node);
          walk(node);
        }
      }
    }

    walk(doc.rootElement);
    if (emitted == 0) {
      add(_collapseWhitespace(doc.rootElement.innerText), 0, false);
    }
  } on XmlException {
    // 坏 XML（HTML 风格未闭合标签等）：按块边界切段的保守粗提。
    // 关键：只去掉「像标签」的片段（< 后接字母/斜杠/叹号），正文里的
    // 「2 < 3」这种裸 < 不会把后面一大段文字一起吃掉。
    _fallbackBlocks(_sanitizeXhtml(raw), add);
  }
}

/// 剥掉块首泄漏出来的标签片段（有的书把 `<div class="...">` 打散成正文）。
String _stripTagFragment(String text) {
  var s = text;
  // 形态一：完整标签名开头（div class="..."）
  final named =
      RegExp('^/?[A-Za-z][A-Za-z0-9:-]*([ ][^<>]*)?>').firstMatch(s);
  if (named != null &&
      (named.group(0)!.contains('="') || named.group(0)!.contains("='"))) {
    s = s.substring(named.end).trim();
  }
  // 形态二：只剩属性开头（class="..." aid="11">）
  final gt = s.indexOf('>');
  if (gt > 0 && gt < 160) {
    final head = s.substring(0, gt);
    if (head.contains('="') &&
        RegExp('^[A-Za-z0-9_:/." =,-]*\$').hasMatch(head)) {
      s = s.substring(gt + 1).trim();
    }
  }
  return s;
}

/// 无法按 XML 解析时的兜底：按块级标签换行、保守去标签。
void _fallbackBlocks(
  String raw,
  void Function(String text, int level, bool centered) emit,
) {
  var s = raw;
  for (final tag in ['script', 'style']) {
    s = s.replaceAll(
      RegExp('<$tag.*?</$tag>', caseSensitive: false, dotAll: true),
      ' ',
    );
  }
  // 块级结束标签与 <br> 视作段落边界
  s = s.replaceAll(
    RegExp('</(p|div|section|article|li|blockquote|h[1-6]|tr|td|dd)>',
        caseSensitive: false),
    String.fromCharCode(10),
  );
  s = s.replaceAll(
    RegExp('<br[^>]*>', caseSensitive: false),
    String.fromCharCode(10),
  );
  // 保守去标签：不碰正文里的裸 <
  s = s.replaceAll(RegExp('<[a-zA-Z/!?][^>]*>'), ' ');
  // 有的书 HTML 坏到把标签拆成两行（「<」单独一行 + `div class="...">`），
  // 保守丢弃「像标签碎片」的整行，避免正文里夹着 div 属性串。
  final tagFragment =
      RegExp('^/?[A-Za-z][A-Za-z0-9:-]*([ ]+[^<>]*)?/?>\$');
  final lines = s.split(String.fromCharCode(10));
  for (final line in lines) {
    final text = _collapseWhitespace(line);
    if (text.isEmpty) continue;
    if (text == '<' || text == '>' || text == '</') continue;
    if (tagFragment.hasMatch(text)) continue;
    emit(text, 0, false);
  }
}

/// 常用 HTML 命名实体（XHTML 只认 5 个，其余会让 XmlDocument 解析失败）。
const Map<String, String> _namedEntities = {
  'nbsp': '\u00A0',
  'ldquo': '\u201C',
  'rdquo': '\u201D',
  'lsquo': '\u2018',
  'rsquo': '\u2019',
  'hellip': '\u2026',
  'mdash': '\u2014',
  'ndash': '\u2013',
  'middot': '\u00B7',
  'bull': '\u2022',
  'times': '\u00D7',
  'divide': '\u00F7',
  'copy': '\u00A9',
  'reg': '\u00AE',
  'trade': '\u2122',
  'deg': '\u00B0',
  'plusmn': '\u00B1',
  'laquo': '\u00AB',
  'raquo': '\u00BB',
  'ensp': '\u2002',
  'emsp': '\u2003',
  'thinsp': '\u2009',
  'shy': '\u00AD',
  'zwnj': '\u200C',
  'zwj': '\u200D',
};

/// 宽松清洗：删非法控制字符、把 HTML 命名实体换成字符、裸 & 转义。
///
/// 真实 EPUB 里 `&nbsp;`、`&ldquo;` 非常常见，而 XHTML 解析器只认 XML 的
/// 5 个实体；不清洗就会整章退化成「正则去标签」的粗提（正文里残留标签碎片）。
String _sanitizeXhtml(String raw) {
  final cleaned = StringBuffer();
  for (final rune in raw.runes) {
    // XML 1.0 不允许的控制字符（保留 TAB/LF/CR）
    if (rune < 0x20 && rune != 0x09 && rune != 0x0A && rune != 0x0D) {
      continue;
    }
    cleaned.writeCharCode(rune);
  }
  var s = _selfCloseVoidTags(cleaned.toString());
  if (s.contains('&')) {
    s = s.replaceAllMapped(
      RegExp('&([A-Za-z][A-Za-z0-9]*);'),
      (m) {
        final name = m.group(1)!;
        switch (name) {
          case 'amp':
          case 'lt':
          case 'gt':
          case 'quot':
          case 'apos':
            return m.group(0)!;
        }
        final ch = _namedEntities[name];
        return ch ?? '&amp;$name;';
      },
    );
    // 裸 &（例如书名「AT&T」）会让 XML 解析失败
    s = s.replaceAll(
      RegExp('&(?!(#[0-9]+|#x[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]*);)'),
      '&amp;',
    );
  }
  return s;
}

/// 把 HTML 风格的 void 标签补成自闭合（`<br>` → `<br/>`），
/// 这样未闭合的 `<br>/<img>` 不会让整章 XML 解析失败。
String _selfCloseVoidTags(String input) {
  const voidTags = [
    'br',
    'hr',
    'img',
    'meta',
    'link',
    'input',
    'source',
    'area',
    'base',
    'col',
    'embed',
    'param',
    'track',
    'wbr',
  ];
  var s = input;
  for (final tag in voidTags) {
    s = s.replaceAllMapped(
      RegExp('<$tag([^>]*)>', caseSensitive: false),
      (m) {
        final attrs = (m.group(1) ?? '').trimRight();
        if (attrs.endsWith('/')) return m.group(0)!;
        return '<$tag$attrs/>';
      },
    );
  }
  return s;
}

/// 参与分段的块级标签。
const Set<String> _blockTags = {
  'p',
  'div',
  'section',
  'article',
  'main',
  'header',
  'footer',
  'aside',
  'blockquote',
  'li',
  'dt',
  'dd',
  'td',
  'th',
  'figcaption',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
};

/// 块内是否还有块级子元素（有则说明它只是容器，继续下钻）。
bool _hasNestedBlock(XmlElement el) {
  for (final child in el.descendantElements) {
    if (_blockTags.contains(child.name.local.toLowerCase())) return true;
  }
  return false;
}

/// 判断一个块的标题级别：0 = 正文。
int _headingLevel(XmlElement el, String tag, String text) {
  final byTag = int.tryParse(tag.startsWith('h') ? tag.substring(1) : '');
  if (byTag != null && byTag >= 1 && byTag <= 6) return byTag;
  // 很多 EPUB 用 p/div + class 做标题（class="chapter-title" 等）
  final hint =
      '${el.getAttribute('class') ?? ''} ${el.getAttribute('id') ?? ''}'
          .toLowerCase();
  if (hint.isEmpty || text.length > 60) return 0;
  if (RegExp(r'(^|[\s_-])(chapter|section|heading|title|h[1-6])([\s_-]|$)')
      .hasMatch(hint)) {
    return 1;
  }
  return 0;
}

/// 是否显式居中（内联样式 / align 属性 / center 类名）。
bool _isCentered(XmlElement el) {
  final style = (el.getAttribute('style') ?? '').toLowerCase();
  if (style.contains('text-align:center') ||
      style.contains('text-align: center')) {
    return true;
  }
  if ((el.getAttribute('align') ?? '').toLowerCase() == 'center') return true;
  final hint =
      '${el.getAttribute('class') ?? ''} ${el.getAttribute('id') ?? ''}'
          .toLowerCase();
  return hint.contains('center');
}

/// 收敛空白：连续空白合一，去首尾。
String _collapseWhitespace(String s) =>
    s.replaceAll(RegExp(r'\s+'), ' ').trim();

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

/// href 里的锚点 id（`x.html#p12` → `p12`）；没有锚点返回空串。
String _fragmentOf(String href) {
  final hash = href.indexOf('#');
  if (hash < 0 || hash + 1 >= href.length) return '';
  return _decodeHref(href.substring(hash + 1));
}

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

/// 书名清洗：下载站/calibre 元数据的 dc:title 常带推广语与丛书信息，
/// 看起来就像「还是用的文件名」。保守清洗两条（不动正文语义）：
///
/// - 【…】推广段（内容 ≥8 字，如「【女性创造力的绝美样本。中英双语…】」）
///   几乎必然是营销文本，整段去掉；短段保留（「【日】」作者国籍标注）。
/// - 文件名式作者后缀「 - 作者」「_作者」（仅当与解析出的作者相同时去掉）。
///
/// 清洗后为空则回退原文；剩余的丛书括注等脏数据交给详情页手动编辑。
String _normalizeTitle(String raw, {String? author}) {
  var t = raw.trim();
  final stripped = t.replaceAll(RegExp(r'【[^】]{8,}】'), ' ');
  if (stripped.trim().isNotEmpty) t = stripped;
  if (author != null && author.isNotEmpty) {
    t = t.replaceAll(
      RegExp('[-_—]\\s*${RegExp.escape(author)}\\s*\$'),
      '',
    );
  }
  t = t
      .replaceFirst(RegExp(r'^[-_—·]\s*'), '')
      .trim()
      .replaceAll(RegExp(r'\s{2,}'), ' ');
  return t.isEmpty ? raw.trim() : t;
}


/// 正文块（分段前的中间形态，供单文件按锚点切分）。
class _TextBlock {
  const _TextBlock(this.text, this.level, this.centered);

  final String text;
  final int level;
  final bool centered;
}

/// 一份 XHTML 按目录锚点切出来的一章。
class _ChapterPart {
  const _ChapterPart(this.source, this.blocks);

  /// 对应的目录条目下标（标题 / 层级 / href 从这里取）。
  final int source;

  /// 本章的正文块（未合并扫描行，合并放到全书拼好之后）。
  final List<_TextBlock> blocks;
}

/// 一份 XHTML 按锚点切出来的结果。
class _FileSegments {
  const _FileSegments(this.leading, this.parts);

  /// 第一个锚点之前的内容：属于上一个目录条目（跨文件续章）。
  final List<_TextBlock> leading;

  /// 各锚点起的章节段。
  final List<_ChapterPart> parts;
}

/// 按目录锚点把一份 XHTML 的块序列切成多章。
///
/// [anchors] 与目录条目一一对应（空串 = 该条目没有锚点）。能定位到的
/// 锚点作为章节起点，同一块上的重复锚点只认第一个；一个都定位不到时
/// 整篇作一章（`source` 取 0，保持旧行为）。
_FileSegments _splitByAnchors(String raw, List<String> anchors) {
  final blocks = <_TextBlock>[];
  final blockOfAnchor = <String, int>{};
  _forEachBlock(
    raw,
    (text, level, centered) => blocks.add(_TextBlock(text, level, centered)),
    onAnchor: (anchor, blockIndex) =>
        blockOfAnchor.putIfAbsent(anchor, () => blockIndex),
  );
  if (blocks.isEmpty) return const _FileSegments(<_TextBlock>[], <_ChapterPart>[]);

  final hits = <({int source, int block})>[];
  for (var i = 0; i < anchors.length; i++) {
    final anchor = anchors[i];
    if (anchor.isEmpty) continue;
    final block = blockOfAnchor[anchor];
    if (block == null) continue;
    hits.add((source: i, block: block));
  }
  if (hits.isEmpty) {
    return _FileSegments(const <_TextBlock>[], [
      _ChapterPart(0, blocks),
    ]);
  }

  // 目录顺序一般就是文档顺序；真乱了也按块位置排，切出来仍然连续。
  hits.sort((a, b) => a.block.compareTo(b.block));
  final starts = <({int source, int block})>[];
  for (final hit in hits) {
    if (starts.isNotEmpty && starts.last.block == hit.block) continue;
    starts.add(hit);
  }
  final leading = blocks.sublist(0, starts.first.block);
  final parts = <_ChapterPart>[];
  for (var i = 0; i < starts.length; i++) {
    final from = starts[i].block;
    final to = i + 1 < starts.length ? starts[i + 1].block : blocks.length;
    if (to <= from) continue;
    parts.add(_ChapterPart(starts[i].source, blocks.sublist(from, to)));
  }
  return _FileSegments(leading, parts);
}

/// 句末标点：以这些字符收尾的块视为「段落完整」。
///
/// 注意**不含**逗号/顿号/破折号——印刷行在逗号后断行很常见，那仍是
/// 段中行，要继续合并。
const String _sentenceEnders =
    '。！？；：…”’』」）】〕〉》»…!?.;:)';

/// 印刷行的最小列宽：扫描重排版书的正文行通常 29~32 字一行，
/// 诗歌/标题/页码远短于此（实测海子的诗最长无标点诗行 21 字——
/// 阈值取 20 会把《亚洲铜》的诗行并成一段）。达到该长度且不以
/// 句末标点收尾的块，才认为它是被硬拆的段中行。
const int _hardWrapMinChars = 25;

/// 把「一行一个 <p>」的扫描重排版书合并回逻辑段落。
///
/// 大量手工转制的 EPUB（Calibre 抓排版书）把每个印刷行拆成独立的
/// `<p>`，直接排版会让每个印刷行都拿到首行缩进、被当段末行做对齐
/// 补偿——整页出现句中缩进和大字距，排出来没法看（实测《十扇窗》）。
///
/// 启发式（保守，三条同时满足才合并）：
/// 1. 两侧都是正文块（非标题、非居中）；
/// 2. 前块最后一行达到印刷行宽（[_hardWrapMinChars]）；
/// 3. 前块不以句末标点收尾（[_sentenceEnders]）。
///
/// 诗句（短）、标题、页码行、居中块一律不动。拼接时前块以 ASCII
/// 字母数字结尾且后块以 ASCII 字母数字开头才补一个空格（英文书），
/// 中文边界直接相连。
List<_TextBlock> _mergeHardWrappedBlocks(List<_TextBlock> blocks) {
  if (blocks.length < 2) return blocks;
  final out = <_TextBlock>[];
  var i = 0;
  while (i < blocks.length) {
    final first = blocks[i];
    var text = first.text;
    var lastLineLen = text.length;
    var lastChar = text.isEmpty ? '' : text.substring(text.length - 1);
    while (i + 1 < blocks.length &&
        first.level == 0 &&
        !first.centered &&
        blocks[i + 1].level == 0 &&
        !blocks[i + 1].centered &&
        lastLineLen >= _hardWrapMinChars &&
        !_sentenceEnders.contains(lastChar)) {
      i++;
      final next = blocks[i];
      final joinsAscii = lastChar.isNotEmpty &&
          RegExp('[A-Za-z0-9]').hasMatch(lastChar) &&
          next.text.isNotEmpty &&
          RegExp('[A-Za-z0-9]').hasMatch(next.text.substring(0, 1));
      text += (joinsAscii ? ' ' : '') + next.text;
      lastLineLen = next.text.length;
      lastChar = next.text.isEmpty ? '' : next.text.substring(next.text.length - 1);
    }
    out.add(_TextBlock(text, first.level, first.centered));
    i++;
  }
  return out;
}

_ChapterLayoutData _layoutOfBlocks(
  List<_TextBlock> blocks, {
  required bool withParagraphs,
}) {
  final buffer = StringBuffer();
  final starts = <int>[];
  final levels = <int>[];
  final centered = <bool>[];
  for (final b in blocks) {
    if (buffer.isNotEmpty) buffer.write(String.fromCharCode(10));
    if (withParagraphs) {
      starts.add(buffer.length);
      levels.add(b.level);
      centered.add(b.centered);
    }
    buffer.write(b.text);
  }
  return _ChapterLayoutData(buffer.toString(), starts, levels, centered);
}
