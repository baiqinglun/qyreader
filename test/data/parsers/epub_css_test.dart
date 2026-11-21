/// 精排：从 EPUB 的 `<style>` / 内联 style 解析段落样式。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/data/parsers/epub/epub_block_style.dart';
import 'package:qy_reader/data/parsers/epub/epub_css.dart';
import 'package:qy_reader/data/parsers/epub/epub_parser.dart';
import 'package:xml/xml.dart';

void main() {
  const html = '''
<html><head><style>
body { font-size: 18px; }
p { text-indent: 2em; line-height: 1.6; margin: 0 0 0.8em 0;
    text-align: justify; }
.bold { font-weight: bold; }
.center { text-align: center; font-size: 1.2em; }
</style></head><body>
  <p>普通段落</p>
  <p class="bold" style="font-style: italic">加粗斜体</p>
  <p class="center">居中段落</p>
</body></html>
''';

  test('解析 font-size / line-height / text-indent / margin / 对齐', () {
    final blocks = extractChapterBlocks(html);
    expect(blocks.length, 3);

    final normal = blocks[0].style!;
    expect(normal.fontSize, closeTo(18, 0.01));
    expect(normal.lineHeight, closeTo(1.6, 0.01));
    expect(normal.indentPx, closeTo(36, 0.01));
    expect(normal.marginBottom, closeTo(14.4, 0.01));
    expect(normal.textAlign, EpubTextAlign.justify);

    final bold = blocks[1].style!;
    expect(bold.bold, isTrue);
    expect(bold.italic, isTrue);

    final center = blocks[2].style!;
    expect(center.textAlign, EpubTextAlign.center);
    expect(center.fontSize, closeTo(21.6, 0.01));
  });

  test('没有样式的书返回 null，不强行覆盖阅读设置', () {
    final blocks = extractChapterBlocks(
      '<html><body><p>普通正文</p></body></html>',
    );
    expect(blocks.single.style, isNull);
  });

  test('外部样式表也能匹配 .class / tag', () {
    final doc = XmlDocument.parse('<html><body>'
        '<p class="lead">开场</p><p>正文</p>'
        '</body></html>');
    final resolver = EpubCssResolver.parse(
      '',
      externalCss: '.lead { font-size: 20px; font-weight: bold; } '
          'p { text-indent: 1em; }',
    );
    final paragraphs = doc.findAllElements('p').toList();
    final lead = resolver.styleFor(paragraphs.first)!;
    expect(lead.fontSize, closeTo(20, 0.01));
    expect(lead.bold, isTrue);
    expect(lead.indentPx, closeTo(20, 0.01));
    expect(resolver.styleFor(paragraphs.last)!.indentPx, closeTo(16, 0.01));
  });
}
