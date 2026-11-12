/// 纯文本 / Markdown 章节切分单测。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/data/parsers/plain_text_parser.dart';

String _join(List<PlainChapter> chapters) =>
    chapters.map((c) => c.text).join('\n');

void main() {
  test('TXT：按「第 N 章」切章，标题作为章标题与首段', () {
    const text = '''
第一章 起程
　　这是第一章的正文。
继续第一章。

第二章 抵达
　　这是第二章的正文。
''';
    final chapters = splitPlainText(text, title: '测试之书');
    expect(chapters, hasLength(2));
    expect(chapters[0].title, '第一章 起程');
    expect(chapters[1].title, '第二章 抵达');
    expect(chapters[0].text, startsWith('第一章 起程\n'));
    expect(chapters[0].paragraphLevels.first, 1);
    expect(chapters[0].paragraphLevels[1], 0);
    expect(chapters[1].paragraphStarts.first, 0);
  });

  test('Markdown：# 标题切章并识别级数', () {
    const md = '''
# 第一章

正文一。

## 小节

正文二。

# 第二章

正文三。
''';
    final chapters = splitPlainText(md, markdown: true, title: 'MD 书');
    expect(chapters, hasLength(3)); // 第一章 / 小节 / 第二章 各起一章
    expect(chapters[0].title, '第一章');
    expect(chapters[0].paragraphLevels.first, 1);
    expect(chapters[1].title, '小节');
    expect(chapters[1].paragraphLevels.first, 2);
    expect(chapters[2].title, '第二章');
  });

  test('没有章节标题：按约 1.2 万字在段落边界切分', () {
    final line = '这是一句用于测试的正文。' * 20; // 240 字
    final text = List.filled(80, line).join('\n'); // 约 1.9 万字
    final chapters = splitPlainText(text, title: '散文集');
    expect(chapters.length, greaterThan(1));
    // 段落数组与正文严格对齐
    for (final c in chapters) {
      expect(c.paragraphStarts.first, 0);
      for (var i = 0; i < c.paragraphStarts.length; i++) {
        final end = i + 1 < c.paragraphStarts.length
            ? c.paragraphStarts[i + 1] - 1
            : c.text.length;
        expect(end, greaterThan(c.paragraphStarts[i]));
      }
    }
    // 不丢字（忽略换行差异）
    expect(_join(chapters).replaceAll('\n', '').length,
        text.replaceAll('\n', '').length);
  });

  test('空文本 → 空结果', () {
    expect(splitPlainText('   \n\n  '), isEmpty);
  });
}
