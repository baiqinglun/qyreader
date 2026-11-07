/// HLC 混合逻辑时钟单测。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/hlc.dart';

void main() {
  group('Hlc 编码', () {
    test('encode 定宽格式，decode 往返一致', () {
      final hlc = Hlc.decode('1730969461234-00007-a1b2c3d4');
      expect(hlc.encode(), '1730969461234-00007-a1b2c3d4');
      expect(hlc.physicalMs, 1730969461234);
      expect(hlc.counter, 7);
      expect(hlc.deviceId, 'a1b2c3d4');
    });

    test('decode 非法格式抛 FormatException', () {
      expect(() => Hlc.decode('123-1-x'), throwsFormatException);
      expect(() => Hlc.decode('not-an-hlc'), throwsFormatException);
    });

    test('字符串比较即时间序', () {
      final a = Hlc.decode('1730969461234-00007-a1b2c3d4');
      final b = Hlc.decode('1730969461234-00008-a1b2c3d4');
      final c = Hlc.decode('1730969461235-00000-a1b2c3d4');
      expect(a.isAfter(b), isFalse);
      expect(b.isAfter(a), isTrue);
      expect(c.isAfter(b), isTrue);
    });
  });

  group('HlcClock.tick', () {
    test('同一物理毫秒内计数递增', () {
      final clock = HlcClock(deviceId: 'testdev1', nowMs: 1000);
      final t1 = clock.tick(1000);
      final t2 = clock.tick(1000);
      final t3 = clock.tick(1000);
      expect(t1.counter, 0);
      expect(t2.counter, 1);
      expect(t3.counter, 2);
      expect(t3.isAfter(t2), isTrue);
    });

    test('物理毫秒前进时计数归零', () {
      final clock = HlcClock(deviceId: 'testdev1', nowMs: 1000);
      clock.tick(1000);
      final t = clock.tick(1001);
      expect(t.physicalMs, 1001);
      expect(t.counter, 0);
    });

    test('物理时钟回拨仍严格递增（不受时钟漂移影响）', () {
      final clock = HlcClock(deviceId: 'testdev1', nowMs: 2000);
      clock.tick(2000);
      final t = clock.tick(1500); // 手机时钟回拨
      expect(t.physicalMs, 2000);
      expect(t.counter, 1);
    });
  });

  group('HlcClock.updateFromRemote', () {
    test('远端毫秒更新 → 本地采纳且计数归零，下次发送 +1', () {
      final clock = HlcClock(deviceId: 'testdev1', nowMs: 1000);
      clock.tick(1000);
      clock.updateFromRemote(Hlc.decode('0000000002000-00005-dev00002'));
      // 接收规则：新毫秒 → counter 归零
      expect(clock.snapshot().physicalMs, 2000);
      expect(clock.snapshot().counter, 0);
      // 发送规则：物理时间未前进 → 复用远端毫秒，计数 +1
      final t = clock.tick(1000);
      expect(t.physicalMs, 2000);
      expect(t.counter, 1);
    });

    test('同毫秒 → 本地计数取远端计数 + 1', () {
      final clock = HlcClock(deviceId: 'testdev1', nowMs: 1000);
      clock.tick(1000);
      clock.updateFromRemote(Hlc.decode('0000000001000-00009-dev00002'));
      expect(clock.snapshot().counter, 10);
      final t = clock.tick(1000);
      expect(t.counter, 11);
    });

    test('本地已更新 → 不回退', () {
      final clock = HlcClock(deviceId: 'testdev1', nowMs: 3000);
      clock.tick(3000);
      clock.updateFromRemote(Hlc.decode('0000000002000-00099-dev00002'));
      expect(clock.snapshot().physicalMs, 3000);
      final t = clock.tick(2000);
      expect(t.physicalMs, 3000);
      expect(t.counter, 1);
    });
  });
}
