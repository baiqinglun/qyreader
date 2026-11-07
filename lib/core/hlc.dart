/// 混合逻辑时钟（Hybrid Logical Clock）。
///
/// 用于多设备同步时给每条写操作一个**全序**：
/// 字符串比较即时间序，且不受手机时钟漂移/回拨影响。
///
/// 格式：`{毫秒:13位}-{计数:5位}-{deviceId:8位}`
/// 例：`1730969461234-00007-a1b2c3d4`
///
/// 因为三段都是定宽的十进制数字/字符串，直接用字符串比较就能得到
/// 与 (ms, counter, deviceId) 字典序一致的结果。
library;

/// 单个 HLC 时间戳的不可变值。
class Hlc implements Comparable<Hlc> {
  const Hlc._(this.physicalMs, this.counter, this.deviceId)
      : assert(deviceId.length == 8, 'deviceId 必须定宽 8 位');

  /// 物理毫秒时间。
  final int physicalMs;

  /// 同一物理毫秒内的单调计数。
  final int counter;

  /// 设备标识（定宽 8 位），同毫秒冲突时的最后裁决字段。
  final String deviceId;

  /// 编码为定宽字符串：`13位毫秒-5位计数-8位设备`。
  String encode() =>
      '${physicalMs.toString().padLeft(13, '0')}'
      '-${counter.toString().padLeft(5, '0')}-$deviceId';

  /// 从编码字符串解析；格式非法抛 [FormatException]。
  static Hlc decode(String encoded) {
    final parts = encoded.split('-');
    if (parts.length != 3 || parts[0].length != 13 || parts[1].length != 5) {
      throw FormatException('非法 HLC 字符串: $encoded');
    }
    final ms = int.parse(parts[0]);
    final counter = int.parse(parts[1]);
    final device = parts[2];
    if (device.length != 8) {
      throw FormatException('HLC deviceId 必须为 8 位: $encoded');
    }
    return Hlc._(ms, counter, device);
  }

  @override
  int compareTo(Hlc other) => encode().compareTo(other.encode());

  /// 本时间戳是否严格晚于 [other]。
  bool isAfter(Hlc other) => compareTo(other) > 0;

  @override
  String toString() => encode();
}

/// 单设备持有的 HLC 时钟。非线程安全，调用方需保证串行访问
/// （同步器本身就是单任务 Mutex 模型）。
class HlcClock {
  /// [deviceId] 必须为 8 位定宽字符串。
  HlcClock({required String deviceId, int? nowMs})
      : assert(deviceId.length == 8, 'deviceId 必须定宽 8 位'),
        _deviceId = deviceId,
        _lastMs = nowMs ?? 0,
        _counter = -1;

  final String _deviceId;
  int _lastMs;
  int _counter;

  /// 本设备的 8 位标识。
  String get deviceId => _deviceId;

  /// 取下一个时间戳。
  ///
  /// 物理时间不前进时计数 +1，保证同毫秒内严格递增。
  Hlc tick([int? nowMs]) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    if (now > _lastMs) {
      _lastMs = now;
      _counter = 0;
    } else {
      _counter += 1;
    }
    return Hlc._(_lastMs, _counter, _deviceId);
  }

  /// 收到远端时间戳时更新本地时钟（接收规则）。
  ///
  /// `last = max(local, remote)`；同毫秒则计数取远端计数 +1。
  void updateFromRemote(Hlc remote) {
    if (remote.physicalMs > _lastMs ||
        (remote.physicalMs == _lastMs && remote.counter > _counter)) {
      if (remote.physicalMs == _lastMs) {
        _counter = remote.counter + 1;
      } else {
        _lastMs = remote.physicalMs;
        _counter = 0;
      }
    }
  }

  /// 当前时钟状态（调试/持久化用）。
  Hlc snapshot() => Hlc._(_lastMs, _counter < 0 ? 0 : _counter, _deviceId);
}
