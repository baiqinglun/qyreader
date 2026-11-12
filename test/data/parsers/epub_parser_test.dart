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
  String? opfContent,
}) {
  final encoder = ZipEncoder();
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml', _containerXml);
  if (withOpf) {
    add('OEBPS/content.opf', opfContent ?? (withTitle ? _opf : _opfNoTitle));
  }
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

    test('紧凑段落数组与正文对齐；关掉段落提取时只留正文', () {
      final parsed = parseEpub(buildEpub(), '测试之书.epub');
      final ch = parsed.chapters.first;
      expect(ch.paragraphStarts, isNotEmpty);
      expect(ch.paragraphStarts.first, 0);
      expect(ch.paragraphLevels.length, ch.paragraphStarts.length);
      for (var i = 0; i < ch.paragraphStarts.length; i++) {
        final end = i + 1 < ch.paragraphStarts.length
            ? ch.paragraphStarts[i + 1] - 1
            : ch.bodyText.length;
        expect(end, greaterThan(ch.paragraphStarts[i]));
      }

      final light = parseEpub(buildEpub(), '测试之书.epub',
          withParagraphs: false);
      expect(light.chapters.first.paragraphStarts, isEmpty);
      expect(light.chapters.first.bodyText, isNotEmpty);
      expect(light.chapters.first.bodyText, ch.bodyText);
    });

    test('HTML 实体/裸 &/注释不会让整章退化成正则粗提', () {
      final blocks = extractChapterBlocks(
        '<html><body><h1>第一章&nbsp;开始</h1>'
        '<p>他说：&ldquo;你好&rdquo; &amp; 再见 AT&T</p>'
        '<!-- 注释 --></body></html>',
      );
      expect(blocks.map((b) => b.text),
          ['第一章 开始', '他说：“你好” & 再见 AT&T']);
      expect(blocks.every((b) => !b.text.contains('div class')), isTrue);
    });

    group('扫描重排版合并（一行一个 <p> 拼回逻辑段落）', () {
      test('被硬拆的正文行拼回一段（《十扇窗》实测样本）', () {
        final blocks = extractChapterBlocks(
          '<html><body>'
          '<p>我深感喜悦，一种发现的喜悦。芭蕉这样的创作，正如简为我们所</p>'
          '<p>指出的那样：“他将这种简短轻快的诗歌形式转变成能够承载情感、心</p>'
          '<p>理和精神启示的容器，让俳句能抒写动人、广阔、复杂和全新的经</p>'
          '<p>验。”“即使是最简短的诗歌形式，也能拥有无限宽广的翼展。……都跨</p>'
          '<p>越了广阔、多变与精确的心灵地形和现实地形。……它们革新、扩展和</p>'
          '<p>强化了经验与语言的边界。” </p>'
          '<p>的确如此，简的译解，不仅译出了芭蕉俳句的“现代质感”或生命本</p>'
          '<p>身的质地，而且在禅宗式的“顿悟”背后，还译出了诗人的同情、悲悯和</p>'
          '<p>时间经验。这里如实说。</p>'
          '</body></html>',
        );
        // 行 1~5 逐行以「非句末标点 + 行宽 ≥ 25」衔接，拼回一段；
        // 行 6 以 ” 收尾 → 段落结束；行 7~9 拼回一段（行 8 仍接行 9）。
        expect(blocks, hasLength(2));
        expect(blocks[0].text, contains('翼展。……都跨越了广阔、多变'));
        expect(blocks[0].text, endsWith('经验与语言的边界。”'));
        expect(blocks[1].text, startsWith('的确如此'));
        expect(blocks[1].text, contains('生命本身的质地'));
        expect(blocks[1].text, endsWith('时间经验。这里如实说。'));
      });

      test('诗行不合并（海子《亚洲铜》：行宽 21 < 25）', () {
        final blocks = extractChapterBlocks(
          '<html><body>'
          '<p>亚洲铜，亚洲铜</p>'
          '<p>祖父死在这里，父亲死在这里，我也将死在这里</p>'
          '<p>你是唯一的一块埋人的地方</p>'
          '</body></html>',
        );
        expect(blocks.map((b) => b.text), [
          '亚洲铜，亚洲铜',
          '祖父死在这里，父亲死在这里，我也将死在这里',
          '你是唯一的一块埋人的地方',
        ]);
      });

      test('标题/页码行不参与合并；句末标点阻断合并', () {
        final blocks = extractChapterBlocks(
          '<html><body>'
          '<h2>第二章 抵达</h2>'
          '<p>像王维的“泉声咽危石”，不是更具有语言难度，也更绝妙吗？</p>'
          '<p>8</p>'
          '<p>好在在简的倾心翻译和热情介绍中，我们读到了这样的诗句：</p>'
          '</body></html>',
        );
        expect(blocks.map((b) => b.text), [
          '第二章 抵达',
          '像王维的“泉声咽危石”，不是更具有语言难度，也更绝妙吗？',
          '8',
          '好在在简的倾心翻译和热情介绍中，我们读到了这样的诗句：',
        ]);
        expect(blocks[0].level, 2);
      });

      test('英文书拼接时补空格，中文边界直接相连', () {
        final blocks = extractChapterBlocks(
          '<html><body>'
          '<p>It was the best of times, it was the worst of times, it was the</p>'
          '<p>age of wisdom, it was the age of foolishness.</p>'
          '</body></html>',
        );
        expect(blocks, hasLength(1));
        expect(blocks.single.text, contains('it was the age of wisdom'));
      });
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

  group('书名清洗（下载站元数据的推广语 / 作者后缀）', () {
    test('dc:title 去【推广语】段与「 - 作者」后缀', () {
      const opf = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:1</dc:identifier>
    <dc:title>孤独是迷人的（磨铁经典）【女性创造力的绝美样本，先锋诗人撰写万字导读！】 (磨铁经典第一辑 3) - 艾米莉·狄金森</dc:title>
    <dc:creator>艾米莉·狄金森</dc:creator>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="ch1"/></spine>
</package>
''';
      final parsed = parseEpub(buildEpub(opfContent: opf), 'x.epub');
      expect(parsed.title, '孤独是迷人的（磨铁经典） (磨铁经典第一辑 3)');
    });

    test('短的【】标注保留（作者国籍）', () {
      const opf = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:1</dc:identifier>
    <dc:title>【日】村上春树的书</dc:title>
    <dc:creator>村上春树</dc:creator>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="ch1"/></spine>
</package>
''';
      final parsed = parseEpub(buildEpub(opfContent: opf), 'x.epub');
      expect(parsed.title, '【日】村上春树的书');
    });

    test('文件名兜底同样去掉「 - 作者」后缀', () {
      // _opfNoTitle 无 dc:title，作者张三 → 文件名后缀「- 张三」应被去掉
      final parsed = parseEpub(buildEpub(withTitle: false), '无名之书 - 张三.epub');
      expect(parsed.title, '无名之书');
    });
  });
}
