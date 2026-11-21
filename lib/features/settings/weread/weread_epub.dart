/// 为「微信读书有、本机没有」的书生成最小 EPUB 占位书源。
///
/// 只包含书封、书名、作者与简介等元数据；正文只有书名页，供书架占位与
/// 后续替换正式书源。生成的是合法 EPUB 3（mimetype 首项且不压缩）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 生成一本「只有书名」的 EPUB。
Uint8List buildWeReadEpub({
  required String bookId,
  required String title,
  String? author,
  String? description,
  String? category,
  String? publisher,
  String? publishTime,
  Uint8List? coverBytes,
}) {
  final safeTitle = title.trim().isEmpty ? '未命名书籍' : title.trim();
  final archive = Archive();

  // mimetype 必须是 zip 的第一项且 store（不压缩），否则阅读器拒绝。
  final mimetype = ArchiveFile.bytes(
    'mimetype',
    utf8.encode('application/epub+zip'),
  )..compression = CompressionType.none;
  archive.addFile(mimetype);

  archive.addFile(ArchiveFile.string('META-INF/container.xml', _containerXml));

  final cover = _coverType(coverBytes);
  final coverId = cover == null ? null : 'cover-image';
  archive.addFile(
    ArchiveFile.string(
      'OEBPS/content.opf',
      _contentOpf(
        bookId: bookId,
        title: safeTitle,
        author: author,
        description: description,
        category: category,
        publisher: publisher,
        publishTime: publishTime,
        cover: cover,
      ),
    ),
  );
  archive.addFile(ArchiveFile.string('OEBPS/nav.xhtml', _navXhtml(safeTitle)));
  archive.addFile(
    ArchiveFile.string('OEBPS/chapter1.xhtml', _chapterXhtml(safeTitle)),
  );
  archive.addFile(ArchiveFile.string('OEBPS/style.css', _styleCss));
  if (cover != null && coverBytes != null && coverId != null) {
    archive.addFile(ArchiveFile.bytes('OEBPS/cover.${cover.ext}', coverBytes));
  }

  return ZipEncoder().encodeBytes(archive);
}

const String _containerXml =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/></rootfiles></container>';

String _contentOpf({
  required String bookId,
  required String title,
  String? author,
  String? description,
  String? category,
  String? publisher,
  String? publishTime,
  ({String ext, String mediaType})? cover,
}) {
  final modified = DateTime.now().toUtc().toIso8601String().replaceAll(
    RegExp(r'\.\d+Z$'),
    'Z',
  );
  final creator = (author ?? '').trim();
  final intro = (description ?? '').trim();
  final subject = (category ?? '').trim();
  final publisherName = (publisher ?? '').trim();
  final date = (publishTime ?? '').trim();
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="bookid">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="bookid">urn:weread:${_xml(bookId)}</dc:identifier>'
      '<dc:title>${_xml(title)}</dc:title>'
      '${creator.isEmpty ? '' : '<dc:creator>${_xml(creator)}</dc:creator>'}'
      '${intro.isEmpty ? '' : '<dc:description>${_xml(intro)}</dc:description>'}'
      '<dc:language>zh-CN</dc:language>'
      '${subject.isEmpty ? '' : '<dc:subject>${_xml(subject)}</dc:subject>'}'
      '${publisherName.isEmpty ? '' : '<dc:publisher>${_xml(publisherName)}</dc:publisher>'}'
      '${date.isEmpty ? '' : '<dc:date>${_xml(date)}</dc:date>'}'
      '<meta property="dcterms:modified">$modified</meta>'
      '${cover == null ? '' : '<meta name="cover" content="cover-image"/>'}'
      '</metadata>'
      '<manifest>'
      '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
      'properties="nav"/>'
      '<item id="chapter1" href="chapter1.xhtml" '
      'media-type="application/xhtml+xml"/>'
      '<item id="style" href="style.css" media-type="text/css"/>'
      '${cover == null ? '' : '<item id="cover-image" href="cover.${cover.ext}" '
                'media-type="${cover.mediaType}" properties="cover-image"/>'}'
      '</manifest>'
      '<spine><itemref idref="chapter1"/></spine>'
      '</package>';
}

String _navXhtml(String title) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:epub="http://www.idpf.org/2007/ops" lang="zh-CN">'
    '<head><title>目录</title></head><body>'
    '<nav epub:type="toc" id="toc"><h1>目录</h1>'
    '<ol><li><a href="chapter1.xhtml">${_xml(title)}</a></li></ol>'
    '</nav></body></html>';

String _chapterXhtml(String title) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:epub="http://www.idpf.org/2007/ops" lang="zh-CN">'
    '<head><title>${_xml(title)}</title>'
    '<link rel="stylesheet" type="text/css" href="style.css"/></head>'
    '<body><section epub:type="titlepage"><h1>${_xml(title)}</h1></section>'
    '</body></html>';

const String _styleCss =
    'html, body { margin: 0; padding: 0; }\n'
    'body { min-height: 100vh; }\n'
    'section { padding: 34vh 1.4em 0; }\n'
    'h1 { text-align: center; font-size: 2em; line-height: 1.45; '
    'font-weight: 600; }\n';

({String ext, String mediaType})? _coverType(Uint8List? bytes) {
  if (bytes == null || bytes.length < 12) return null;
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return (ext: 'jpg', mediaType: 'image/jpeg');
  }
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return (ext: 'png', mediaType: 'image/png');
  }
  if (bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38) {
    return (ext: 'gif', mediaType: 'image/gif');
  }
  if (bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return (ext: 'webp', mediaType: 'image/webp');
  }
  return null;
}

String _xml(String input) => input
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
