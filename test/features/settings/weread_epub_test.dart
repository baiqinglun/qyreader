/// 微信读书占位 EPUB：生成合法书源、元数据与「正文只有书名」。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/data/parsers/epub/epub_parser.dart';
import 'package:qy_reader/features/settings/weread/weread_epub.dart';

void main() {
  final png = Uint8List.fromList(<int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A, // PNG 签名
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
  ]);

  test('mimetype 是 zip 第一项且不压缩', () {
    final bytes = buildWeReadEpub(bookId: 'r1', title: '三体');
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.first.name, 'mimetype');
    expect(archive.first.compression, CompressionType.none);
    expect(utf8.decode(archive.first.content), 'application/epub+zip');
  });

  test('解析后书名 / 作者 / 简介 / 封面齐全，正文只有书名', () {
    final bytes = buildWeReadEpub(
      bookId: 'r1',
      title: '三体 & 文明',
      author: '刘慈欣',
      description: '给岁月以文明，而不是给文明以岁月。',
      category: '科幻',
      publisher: '重庆出版社',
      publishTime: '2008-01-01',
      coverBytes: png,
    );

    final parsed = parseEpub(bytes, 'we-read.epub');
    expect(parsed.title, '三体 & 文明');
    expect(parsed.author, '刘慈欣');
    expect(parsed.description, contains('给岁月以文明'));
    expect(parsed.coverBytes, isNotNull);
    expect(parsed.coverMediaType, 'image/png');
    expect(parsed.chapters, hasLength(1));
    final body = parsed.chapters.single.bodyText;
    expect(body, contains('三体 & 文明'));
    // 正文只有书名页，不塞简介/笔记等大段内容。
    expect(body.trim(), '三体 & 文明');
  });

  test('没有封面也能生成可解析的 EPUB', () {
    final bytes = buildWeReadEpub(bookId: 'r2', title: '无封面');
    final parsed = parseEpub(bytes, 'no-cover.epub');
    expect(parsed.title, '无封面');
    expect(parsed.coverBytes, isNull);
    expect(parsed.chapters, isNotEmpty);
  });
}
