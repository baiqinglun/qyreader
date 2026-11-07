/// Locator 序列化单测。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/locator.dart';

void main() {
  test('toJson 只包含非空字段', () {
    final locator = Locator(
      href: 'text/ch003.xhtml',
      cfi: 'epubcfi(/6/14!/4/2/2,/1:0,/1:120)',
      chapterIndex: 2,
      offset: 1120,
      percent: 0.184,
    );
    final json = locatorToJson(locator);
    expect(json, contains('"href":"text/ch003.xhtml"'));
    expect(json, isNot(contains('"page"')));
    expect(json, isNot(contains('"x"')));
    expect(json, isNot(contains('"y"')));
  });

  test('序列化往返一致', () {
    final locator = Locator(
      href: 'txt',
      offset: 12400,
      percent: 0.5,
    );
    final parsed = locatorFromJson(locatorToJson(locator));
    expect(parsed, isNotNull);
    expect(parsed!.href, 'txt');
    expect(parsed.offset, 12400);
    expect(parsed.percent, 0.5);
    expect(parsed.v, 1);
  });

  test('PDF 位置（page/x/y）往返一致', () {
    const locator = Locator(page: 42, x: 0, y: 0.31);
    final parsed = locatorFromJson(locatorToJson(locator));
    expect(parsed!.page, 42);
    expect(parsed.y, 0.31);
  });

  test('损坏输入返回 null（降级路径）', () {
    expect(locatorFromJson('not json'), isNull);
    expect(locatorFromJson('{"chapterIndex": "abc"}'), isNull);
    expect(locatorFromJson('[]'), isNull);
  });
}
