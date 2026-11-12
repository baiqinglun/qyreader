/// 封面压缩：大图缩到最长边 512 的 JPEG，坏图原样返回。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qy_reader/data/covers/cover_image.dart';

void main() {
  test('大封面压到最长边 512 的 JPEG，体积变小', () {
    final source = img.Image(width: 1200, height: 1600);
    img.fill(source, color: img.ColorRgb8(120, 180, 240));
    final png = Uint8List.fromList(img.encodePng(source));

    final out = compressCover(png);
    expect(out.length, lessThan(png.length));
    expect(out[0], 0xFF);
    expect(out[1], 0xD8, reason: 'JPEG SOI');
    final decoded = img.decodeImage(out)!;
    expect(math.max(decoded.width, decoded.height), 512);
  });

  test('无法解码的字节原样返回，不抛异常', () {
    final junk = Uint8List.fromList([1, 2, 3, 4, 5]);
    expect(compressCover(junk), junk);
  });
}
