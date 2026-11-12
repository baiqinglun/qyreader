/// 自定义字体 manifest 与文件校验单测。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/reader/fonts/reader_fonts.dart';

Uint8List _bytes(List<int> head) =>
    Uint8List.fromList(List<int>.filled(16, 0)..setRange(0, head.length, head));

void main() {
  group('supportedFontExtension', () {
    test('ttf / otf / ttc（大小写不敏感）', () {
      expect(supportedFontExtension('/tmp/a.ttf'), 'ttf');
      expect(supportedFontExtension(r'D:\字体\B.OTF'), 'otf');
      expect(supportedFontExtension('c.ttc'), 'ttc');
    });

    test('woff / 无扩展名 / 其它格式一律拒绝', () {
      expect(supportedFontExtension('a.woff'), isNull);
      expect(supportedFontExtension('a.woff2'), isNull);
      expect(supportedFontExtension('a.epub'), isNull);
      expect(supportedFontExtension('noext'), isNull);
    });
  });

  group('looksLikeSfnt', () {
    test('TrueType / OpenType / 字体集合文件头通过', () {
      expect(looksLikeSfnt(_bytes([0x00, 0x01, 0x00, 0x00])), isTrue);
      expect(looksLikeSfnt(_bytes([0x4F, 0x54, 0x54, 0x4F])), isTrue); // OTTO
      expect(looksLikeSfnt(_bytes([0x74, 0x74, 0x63, 0x66])), isTrue); // ttcf
    });

    test('改后缀的其它文件被拦住', () {
      expect(looksLikeSfnt(_bytes([0x50, 0x4B, 0x03, 0x04])), isFalse); // zip
      expect(looksLikeSfnt(_bytes([0xFF, 0xD8, 0xFF, 0xE0])), isFalse); // jpg
      expect(looksLikeSfnt(Uint8List(4)), isFalse); // 过短
    });
  });

  group('ReaderFont.fromMap', () {
    test('正常条目还原', () {
      final font = ReaderFont.fromMap(<String, dynamic>{
        'id': 'abc123',
        'name': '霞鹜文楷',
        'file': 'abc123.ttf',
      });
      expect(font!.id, 'abc123');
      expect(font.name, '霞鹜文楷');
      expect(font.fileName, 'abc123.ttf');
      expect(font.family, 'qyfont_abc123');
    });

    test('缺字段 / 类型不对 / 路径穿越条目一律丢弃', () {
      expect(ReaderFont.fromMap(null), isNull);
      expect(ReaderFont.fromMap('x'), isNull);
      expect(ReaderFont.fromMap(<String, dynamic>{'id': 'a'}), isNull);
      expect(
        ReaderFont.fromMap(<String, dynamic>{
          'id': 'a',
          'name': 'b',
          'file': '../b.ttf',
        }),
        isNull,
      );
      expect(
        ReaderFont.fromMap(<String, dynamic>{
          'id': 'a',
          'name': 'b',
          'file': 'sub/b.ttf',
        }),
        isNull,
      );
    });
  });

  group('parseReaderFontManifest', () {
    test('坏 JSON / 缺 fonts 字段 → 空列表', () {
      expect(parseReaderFontManifest('not-json{'), isEmpty);
      expect(parseReaderFontManifest('[]'), isEmpty);
      expect(parseReaderFontManifest('{"v":1}'), isEmpty);
    });

    test('跳过坏条目与重复 id，保留好条目', () {
      final raw = jsonEncode(<String, dynamic>{
        'v': 1,
        'fonts': [
          {'id': 'a1', 'name': '字体A', 'file': 'a1.ttf'},
          {'id': 'a1', 'name': '重复', 'file': 'a1b.ttf'},
          {'id': '', 'name': '空 id', 'file': 'x.ttf'},
          {'id': 'b2', 'name': '字体B', 'file': '../evil.ttf'},
          {'id': 'c3', 'name': '字体C', 'file': 'c3.otf'},
        ],
      });
      final fonts = parseReaderFontManifest(raw);
      expect(fonts.map((f) => f.id), ['a1', 'c3']);
    });
  });

  group('findReaderFont', () {
    test('按 family 查找；空 family 找不到', () {
      const font = ReaderFont(id: 'x', name: 'X', fileName: 'x.ttf');
      expect(findReaderFont([font], font.family)?.id, 'x');
      expect(findReaderFont([font], 'qyfont_nope'), isNull);
      expect(findReaderFont([font], ''), isNull);
    });
  });
}
