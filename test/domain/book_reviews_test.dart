/// 书评多条编解码：单条纯文本兼容旧数据，多条存 JSON 数组。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/services/book_reviews.dart';

void main() {
  test('空 / null 解出空列表', () {
    expect(decodeBookReviews(null), isEmpty);
    expect(decodeBookReviews('  '), isEmpty);
  });

  test('单条纯文本（旧数据）解出一条', () {
    expect(decodeBookReviews('写得真好'), ['写得真好']);
  });

  test('多条 JSON 数组按序解出', () {
    final raw = encodeBookReviews(['第一条', '第二条']);
    expect(decodeBookReviews(raw), ['第一条', '第二条']);
  });

  test('编码：单条存纯文本，多条存 JSON', () {
    expect(encodeBookReviews(['只有一条']), '只有一条');
    expect(encodeBookReviews([]), '');
    final multi = encodeBookReviews(['a', 'b']);
    expect(multi.startsWith('['), isTrue);
  });

  test('坏 JSON 回退单条原文', () {
    expect(decodeBookReviews('[broken'), ['[broken']);
  });
}
