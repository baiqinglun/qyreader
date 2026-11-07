/// 桥事件解析单测。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/reader/reader_bridge_events.dart';

void main() {
  test('bridgeReady / ready / locationsReady', () {
    expect(parseReaderEvent('{"type":"bridgeReady"}'), isA<ReaderBridgeReady>());
    expect(parseReaderEvent('{"type":"ready"}'), isA<ReaderBookReady>());
    final locations =
        parseReaderEvent('{"type":"locationsReady","total":123}');
    expect(locations, isA<ReaderLocationsReady>());
    expect((locations as ReaderLocationsReady).total, 123);
  });

  test('relocated：Locator 字段齐全', () {
    final event = parseReaderEvent(
      '{"type":"relocated","locator":{"v":1,"cfi":"epubcfi(/6/4)","href":"OEBPS/text/ch1.xhtml","chapterIndex":0,"percent":0.1},"atStart":true,"atEnd":false}',
    );
    expect(event, isA<ReaderRelocated>());
    final relocated = event as ReaderRelocated;
    expect(relocated.locator.cfi, 'epubcfi(/6/4)');
    expect(relocated.locator.href, 'OEBPS/text/ch1.xhtml');
    expect(relocated.locator.chapterIndex, 0);
    expect(relocated.locator.percent, 0.1);
    expect(relocated.atStart, isTrue);
    expect(relocated.atEnd, isFalse);
  });

  test('relocated：locator 缺失时丢弃消息', () {
    expect(parseReaderEvent('{"type":"relocated"}'), isNull);
  });

  test('tap / error', () {
    final tap = parseReaderEvent('{"type":"tap","x":100.5,"y":200}');
    expect(tap, isA<ReaderTap>());
    expect((tap as ReaderTap).x, 100.5);
    expect(tap.y, 200);

    final error = parseReaderEvent(
      '{"type":"error","code":"render.display","message":"boom"}',
    );
    expect(error, isA<ReaderError>());
    expect((error as ReaderError).code, 'render.display');
    expect(error.message, 'boom');
  });

  test('损坏消息返回 null', () {
    expect(parseReaderEvent('not json'), isNull);
    expect(parseReaderEvent('[]'), isNull);
    expect(parseReaderEvent('{"type":"unknown"}'), isNull);
  });
}
