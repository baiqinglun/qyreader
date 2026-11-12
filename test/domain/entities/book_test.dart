/// Book 实体个人化字段 JSON 往返。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';

Book _book({
  int? rating,
  String? review,
  List<String> tags = const [],
  int? pinnedAt,
}) =>
    Book(
      id: 'b1',
      title: '测试书',
      format: BookFormat.epub,
      filePath: '/tmp/b1.epub',
      fileSha256: 'sha',
      fileSize: 1,
      addedAt: 1,
      updatedAt: 2,
      rating: rating,
      review: review,
      tags: tags,
      pinnedAt: pinnedAt,
      hlc: '1-dev',
      deviceId: 'dev',
    );

void main() {
  test('评分/书评/标签/置顶 JSON 往返一致', () {
    final restored = bookFromJson(bookToJson(_book(
      rating: 4,
      review: '很好读',
      tags: const ['科幻', '经典'],
      pinnedAt: 1700000000000,
    )));
    expect(restored.rating, 4);
    expect(restored.review, '很好读');
    expect(restored.tags, ['科幻', '经典']);
    expect(restored.pinnedAt, 1700000000000);
  });

  test('未设置时为空/空列表', () {
    final restored = bookFromJson(bookToJson(_book()));
    expect(restored.rating, isNull);
    expect(restored.review, isNull);
    expect(restored.tags, isEmpty);
    expect(restored.pinnedAt, isNull);
  });

  test('兼容逗号分隔的旧标签数据', () {
    final json = bookToJson(_book())..['tags'] = '科幻，经典、待读';
    expect(bookFromJson(json).tags, ['科幻', '经典', '待读']);
  });
}
