/// 纯文本 / Markdown 书的原生阅读章节源。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/data/parsers/epub/epub_parser.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/reader/native/native_chapter_source.dart';

Book _book(String path, BookFormat format) => Book(
      id: 'b1',
      title: '测试文档',
      format: format,
      filePath: path,
      fileSha256: 'sha',
      fileSize: 1,
      addedAt: 0,
      updatedAt: 0,
      hlc: '0000000000000-00000-aaaaaaaa',
      deviceId: 'aaaaaaaa',
    );

void main() {
  firstReadableTests();
  test('TXT：按章切分后标题/正文/段落级别正确', () async {
    final dir = await Directory.systemTemp.createTemp('qy_plain_reader');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/book.txt');
    await file.writeAsString('''
第一章 起程
　　第一章的正文。

第二章 抵达
　　第二章的正文。
''');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final chapters =
        await container.read(nativeChaptersProvider(NativeChaptersKey.of(_book(file.path, BookFormat.txt))).future);

    expect(chapters, hasLength(2));
    expect(chapters[0].title, '第一章 起程');
    expect(chapters[0].text, contains('第一章的正文'));
    expect(chapters[0].paragraphs.first.isHeading, isTrue);
    expect(chapters[1].title, '第二章 抵达');
  });

  test('Markdown：# 标题切章', () async {
    final dir = await Directory.systemTemp.createTemp('qy_plain_reader');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/book.md');
    await file.writeAsString('# 第一篇\n\n正文一。\n\n# 第二篇\n\n正文二。\n');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final chapters =
        await container.read(nativeChaptersProvider(NativeChaptersKey.of(_book(file.path, BookFormat.md))).future);
    expect(chapters.map((c) => c.title), ['第一篇', '第二篇']);
    expect(chapters.first.paragraphs.first.level, 1);
  });

  test('PDF：明确报错（不静默空白）', () async {
    final dir = await Directory.systemTemp.createTemp('qy_plain_reader');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/book.pdf');
    await file.writeAsBytes([1, 2, 3]);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await expectLater(
      container.read(nativeChaptersProvider(NativeChaptersKey.of(_book(file.path, BookFormat.pdf))).future),
      throwsA(isA<StateError>()),
    );
  });
}


NativeChapter _chapter(String title, String text) => NativeChapter.fromBlocks(
      idx: 0,
      title: title,
      href: 'h',
      blocks: [ParsedBlock(text: text)],
      fallbackText: '',
    );

void firstReadableTests() {
  group('firstReadableChapterIndex', () {
    test('跳过扉页/版权页/目录与过短占位页', () {
      final chapters = [
        _chapter('扉页', '未知'),
        _chapter('版权页', 'x' * 500),
        _chapter('目录', 'y' * 300),
        _chapter('自序', 'z' * 2000),
        _chapter('正文', 'w' * 3000),
      ];
      expect(firstReadableChapterIndex(chapters), 3);
    });

    test('章标题正常但正文开头是版权页 → 也跳过', () {
      expect(
        firstReadableChapterIndex([
          _chapter('第 1 章', '版权信息 图书在版编目（CIP）数据 ISBN 978-7-5598'),
          _chapter('第 2 章', '正文开始，这是一段真正的书籍内容。' * 5),
        ]),
        1,
      );
    });

    test('长章节即使标题像版权页也不跳过（单文件 EPUB 含正文）', () {
      expect(
        firstReadableChapterIndex([
          _chapter('版权信息', '版权信息 ${'正文内容。' * 1200}'),
          _chapter('第四章', '真正的章节。' * 100),
        ]),
        0,
      );
    });

    test('全是短诗时退回第一个非前置页', () {
      expect(
        firstReadableChapterIndex([
          _chapter('扉页', 'x'),
          _chapter('亚洲铜', '短诗十四行'),
        ]),
        1,
      );
    });

    test('空列表 → 0', () {
      expect(firstReadableChapterIndex(const []), 0);
    });
  });

  test('章节缓存 key 只认书源文件，不认 lastOpenedAt', () {
    final a = _book('/tmp/a.epub', BookFormat.epub);
    final opened = a.copyWith(lastOpenedAt: 123, updatedAt: 999);
    expect(NativeChaptersKey.of(a), NativeChaptersKey.of(opened));
    expect(
      NativeChaptersKey.of(a).hashCode,
      NativeChaptersKey.of(opened).hashCode,
    );
    expect(
      NativeChaptersKey.of(a.copyWith(fileSize: 2)),
      isNot(NativeChaptersKey.of(a)),
    );
  });
}