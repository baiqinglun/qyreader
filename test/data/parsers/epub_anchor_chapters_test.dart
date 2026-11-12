/// 单文件 EPUB 按目录锚点切章：calibre / pdftohtml 常见形态。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/data/parsers/epub/epub_parser.dart';

const String _container = '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

const String _opf = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:anchor</dc:identifier>
    <dc:title>锚点之书</dc:title>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="ch1" href="text/all.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="text/cont.xhtml" media-type="application/xhtml+xml"/>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>
''';

/// NCX：[anchors] 为每个目录条目的 src（含 #锚点）。
String _ncx(List<String> anchors) {
  final points = StringBuffer();
  for (var i = 0; i < anchors.length; i++) {
    points.write('''
    <navPoint id="n${i + 1}" playOrder="${i + 1}">
      <navLabel><text>第${i + 1}章 标题</text></navLabel>
      <content src="${anchors[i]}"/>
    </navPoint>''');
  }
  return '''<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>$points
  </navMap>
</ncx>
''';
}

/// 一份「一行一个 <p>，段首挂 <a id>」的正文文档。
const String _allXhtml = '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>x</title></head>
<body>
<p><a id="p1"></a>第一章 甲</p>
<p>甲一</p>
<p>甲二</p>
<p><a id="p2"></a>第二章 乙</p>
<p>乙一</p>
<p>乙二</p>
</body>
</html>
''';

/// 第二份文档开头是上一章的续文（跨文件续章）。
const String _contXhtml = '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>x</title></head>
<body>
<p>乙三续文</p>
<p><a id="p3"></a>第三章 丙</p>
<p>丙一</p>
</body>
</html>
''';

Uint8List _build({required String ncx, String? cont = _contXhtml}) {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml', _container);
  add('OEBPS/content.opf', _opf);
  add('OEBPS/toc.ncx', ncx);
  add('OEBPS/text/all.xhtml', _allXhtml);
  if (cont != null) add('OEBPS/text/cont.xhtml', cont);
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('同一文档的多个目录条目按 #锚点 切成多章，跨文件续文归上一章', () {
    final parsed = parseEpub(
      _build(ncx: _ncx([
        'text/all.xhtml#p1',
        'text/all.xhtml#p2',
        'text/cont.xhtml#p3',
      ])),
      '锚点之书.epub',
    );

    expect(parsed.chapters, hasLength(3));
    expect(
      parsed.chapters.map((c) => c.title),
      ['第1章 标题', '第2章 标题', '第3章 标题'],
    );

    // 第一章：锚点 p1 起，到第二章锚点前；第二章标题块不算进第一章。
    expect(parsed.chapters[0].bodyText, contains('甲一'));
    expect(parsed.chapters[0].bodyText, contains('甲二'));
    expect(parsed.chapters[0].bodyText, isNot(contains('乙一')));

    // 第二章：本文件的乙一/乙二 + 下一份文档开头的续文。
    expect(parsed.chapters[1].bodyText, contains('乙一'));
    expect(parsed.chapters[1].bodyText, contains('乙二'));
    expect(parsed.chapters[1].bodyText, contains('乙三续文'));
    expect(parsed.chapters[1].bodyText, isNot(contains('丙一')));

    // 第三章：锚点 p3 起。
    expect(parsed.chapters[2].bodyText, contains('丙一'));

    // 全书正文不丢：三章拼起来覆盖所有段落。
    final all = parsed.chapters.map((c) => c.bodyText).join('\n');
    for (final text in ['第一章 甲', '甲一', '甲二', '第二章 乙', '乙一', '乙二', '乙三续文', '第三章 丙', '丙一']) {
      expect(all, contains(text), reason: '不应丢掉「$text」');
    }
    // 也不重复：每个正文段只在某一章里出现一次。
    expect('甲一'.allMatches(all).length, 1);
    expect('乙三续文'.allMatches(all).length, 1);
  });

  test('锚点全都对不上时退回整篇一章（内容不丢）', () {
    final parsed = parseEpub(
      _build(ncx: _ncx([
        'text/all.xhtml#missing1',
        'text/all.xhtml#missing2',
      ])),
      '坏目录.epub',
    );
    expect(parsed.chapters, hasLength(1));
    expect(parsed.chapters[0].title, '第1章 标题');
    expect(parsed.chapters[0].bodyText, contains('甲一'));
    expect(parsed.chapters[0].bodyText, contains('第二章 乙'));
    expect(parsed.chapters[0].bodyText, contains('乙二'));
  });

  test('目录条目没有锚点：一份文档仍作一章（旧行为）', () {
    final parsed = parseEpub(
      _build(ncx: _ncx(['text/all.xhtml', 'text/cont.xhtml'])),
      '无锚点.epub',
    );
    expect(parsed.chapters, hasLength(2));
    expect(parsed.chapters[0].bodyText, contains('甲一'));
    expect(parsed.chapters[0].bodyText, contains('乙二'));
    expect(parsed.chapters[1].bodyText, contains('丙一'));
  });
}
