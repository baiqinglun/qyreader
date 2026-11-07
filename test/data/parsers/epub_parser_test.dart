/// EPUB 解析器单测：测试内动态构造最小 EPUB（zip），不依赖二进制 fixture。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/result.dart';
import 'package:qy_reader/data/parsers/epub/epub_parser.dart';

const String _containerXml = '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

const String _opf = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:1234</dc:identifier>
    <dc:title>测试之书</dc:title>
    <dc:creator>张三</dc:creator>
    <dc:language>zh-CN</dc:language>
    <dc:description>一本用于测试的书</dc:description>
    <meta name="cover" content="cover-img"/>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="cover-img" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>
    <item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>
''';

const String _nav = '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>目录</title></head>
<body>
  <nav epub:type="toc">
    <ol>
      <li><a href="text/ch1.xhtml">第一章 起程</a>
        <ol><li><a href="text/ch2.xhtml">第一节</a></li></ol>
      </li>
    </ol>
  </nav>
</body>
</html>
''';

const String _opfNoTitle = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:1234</dc:identifier>
    <dc:creator>张三</dc:creator>
    <dc:language>zh-CN</dc:language>
  </metadata>
  <manifest>
    <item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>
''';

const String _ch1 = '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>第一章 起程</title></head>
<body><p>山川湖海，日月星辰。</p></body>
</html>
''';

const String _ch2 = '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>第二章 抵达</title></head>
<body><p>轻舟已过万重山。</p></body>
</html>
''';

final Uint8List _fakeJpeg =
    Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x01, 0x02]);

/// 构造最小 EPUB 字节流。
Uint8List buildEpub({
  bool withNav = true,
  bool withCover = true,
  bool withOpf = true,
  bool withTitle = true,
}) {
  final encoder = ZipEncoder();
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml', _containerXml);
  if (withOpf) add('OEBPS/content.opf', withTitle ? _opf : _opfNoTitle);
  if (withNav && withTitle) add('OEBPS/nav.xhtml', _nav);
  add('OEBPS/text/ch1.xhtml', _ch1);
  add('OEBPS/text/ch2.xhtml', _ch2);
  if (withCover && withTitle) {
    archive.addFile(
      ArchiveFile('OEBPS/cover.jpg', _fakeJpeg.length, _fakeJpeg),
    );
  }
  return Uint8List.fromList(encoder.encode(archive));
}

void main() {
  group('parseEpub', () {
    test('解析元数据 / 封面 / nav 目录 / 字数（中文书名）', () {
      final parsed = parseEpub(buildEpub(), '测试之书.epub');

      expect(parsed.title, '测试之书');
      expect(parsed.author, '张三');
      expect(parsed.language, 'zh-CN');
      expect(parsed.description, '一本用于测试的书');

      // 封面：meta name=cover 与 properties=cover-image 均命中同一项
      expect(parsed.coverBytes, isNotNull);
      expect(parsed.coverMediaType, 'image/jpeg');

      // nav 目录：嵌套层级保留
      expect(parsed.chapters, hasLength(2));
      expect(parsed.chapters[0].title, '第一章 起程');
      expect(parsed.chapters[0].href, 'OEBPS/text/ch1.xhtml');
      expect(parsed.chapters[0].level, 0);
      expect(parsed.chapters[1].title, '第一节');
      expect(parsed.chapters[1].href, 'OEBPS/text/ch2.xhtml');
      expect(parsed.chapters[1].level, 1);

      // 字数：两章正文共 8 个中文字符
      expect(parsed.wordCount, greaterThan(0));
    });

    test('无 nav/ncx 时按 spine 兜底分章', () {
      final parsed = parseEpub(buildEpub(withNav: false), 'fallback.epub');
      expect(parsed.chapters, hasLength(2));
      expect(parsed.chapters[0].title, '第一章 起程');
      expect(parsed.chapters[1].title, '第二章 抵达');
    });

    test('书名缺失时用文件名兜底', () {
      final parsed = parseEpub(buildEpub(withTitle: false), '无名之书.epub');
      expect(parsed.title, '无名之书');
    });

    test('container 指向的 OPF 缺失时抛 ParseException', () {
      expect(
        () => parseEpub(buildEpub(withOpf: false), 'bad.epub'),
        throwsA(isA<ParseException>()),
      );
    });

    test('非 zip 输入抛 ParseException', () {
      final garbage = Uint8List.fromList('this is not a zip'.codeUnits);
      expect(
        () => parseEpub(garbage, 'bad.epub'),
        throwsA(isA<ParseException>()),
      );
    });
  });

  test('parseEpubInIsolate 在后台 isolate 完成解析', () async {
    final parsed = await parseEpubInIsolate(buildEpub(), '测试之书.epub');
    expect(parsed.title, '测试之书');
  });
}
