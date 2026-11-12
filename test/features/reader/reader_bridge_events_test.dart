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
  test('selected 事件解析出 CFI/原文/矩形', () {
    final e = parseReaderEvent(
      '{"type":"selected","cfiRange":"epubcfi(/6/4,/1:0,/1:20)",'
      '"text":"山川湖海","x":12.5,"y":88,"w":160,"h":24}',
    );
    expect(e, isA<ReaderSelected>());
    final sel = e! as ReaderSelected;
    expect(sel.cfiRange, 'epubcfi(/6/4,/1:0,/1:20)');
    expect(sel.text, '山川湖海');
    expect(sel.rect.left, 12.5);
    expect(sel.rect.height, 24);
  });

  test('selected 缺 cfiRange 返回 null', () {
    expect(parseReaderEvent('{"type":"selected","text":"x"}'), isNull);
  });

  test('markClicked 解析 id；缺失 id 为 null', () {
    final e = parseReaderEvent(
      '{"type":"markClicked","cfiRange":"epubcfi(/6/4)","id":"a-1"}',
    );
    final m = e! as ReaderMarkClicked;
    expect(m.annotationId, 'a-1');

    final e2 = parseReaderEvent(
      '{"type":"markClicked","cfiRange":"epubcfi(/6/4)"}',
    );
    final m2 = e2! as ReaderMarkClicked;
    expect(m2.annotationId, isNull);
  });

  test('拖拽事件：start / move / end / cancel', () {
    final start = parseReaderEvent(
      '{"type":"dragStart","dx":-12,"dy":2}',
    )! as ReaderDragStart;
    expect(start.dx, -12);
    expect(start.dy, 2);

    final move = parseReaderEvent(
      '{"type":"dragMove","dx":-48.5,"dy":3}',
    )! as ReaderDragMove;
    expect(move.dx, -48.5);

    final end = parseReaderEvent(
      '{"type":"dragEnd","dx":-120,"dy":4,"dt":180,"vx":-0.667}',
    )! as ReaderDragEnd;
    expect(end.dx, -120);
    expect(end.dt, 180);
    expect(end.vx, closeTo(-0.667, 1e-9));

    expect(parseReaderEvent('{"type":"dragCancel"}'),
        isA<ReaderDragCancel>());
  });

  test('syncDone 解析 ok（缺省为 false）', () {
    final ok = parseReaderEvent('{"type":"syncDone","ok":true}')!;
    expect((ok as ReaderSyncDone).ok, isTrue);
    final fail = parseReaderEvent('{"type":"syncDone"}')!;
    expect((fail as ReaderSyncDone).ok, isFalse);
  });

  test('relocated 解析章内页码与全书估算页', () {
    final e = parseReaderEvent(
      '{"type":"relocated","locator":{"v":1,"cfi":"epubcfi(/6/4)"},'
      '"page":12,"pages":34,"bookPage":120,"bookPages":860}',
    )! as ReaderRelocated;
    expect(e.page, 12);
    expect(e.pages, 34);
    expect(e.bookPage, 120);
    expect(e.bookPages, 860);
  });

  test('syncDone 带 seq；边缘手势事件解析', () {
    final sync = parseReaderEvent(
      '{"type":"syncDone","ok":true,"seq":7}',
    )! as ReaderSyncDone;
    expect(sync.seq, 7);

    final start = parseReaderEvent(
      '{"type":"edgeStart","edge":"left"}',
    )! as ReaderEdgeStart;
    expect(start.edge, 'left');

    final move = parseReaderEvent(
      '{"type":"edgeMove","edge":"right","dy":-42.5}',
    )! as ReaderEdgeMove;
    expect(move.edge, 'right');
    expect(move.dy, -42.5);

    final end = parseReaderEvent(
      '{"type":"edgeEnd","edge":"right","dy":-60,"dt":300}',
    )! as ReaderEdgeEnd;
    expect(end.dt, 300);
    expect(parseReaderEvent('{"type":"edgeCancel"}'),
        isA<ReaderEdgeCancel>());
  });
}
