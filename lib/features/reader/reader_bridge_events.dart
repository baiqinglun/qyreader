/// 桥事件解析（纯函数，可单测）。
///
/// reader.html 经 callHandler('readerEvent', json) 上行 JSON，
/// 这里解码为类型化事件；损坏消息静默丢弃返回 null。
library;

import 'dart:convert';

import '../../core/locator.dart';

/// 桥事件。
sealed class ReaderEvent {
  const ReaderEvent();
}

/// WebView 页面脚本就绪（最早事件，Dart 可开始 loadBook）。
class ReaderBridgeReady extends ReaderEvent {
  const ReaderBridgeReady();
}

/// 书籍渲染完成（rendition 已显示起始内容，relocated 已先行发出）。
class ReaderBookReady extends ReaderEvent {
  const ReaderBookReady();
}

/// locations 生成完成（百分比可用）。
class ReaderLocationsReady extends ReaderEvent {
  const ReaderLocationsReady(this.total);

  /// location 条目数。
  final int total;
}

/// 翻页/跳转后位置回报。
class ReaderRelocated extends ReaderEvent {
  const ReaderRelocated({
    required this.locator,
    required this.atStart,
    required this.atEnd,
  });

  /// 新位置（CFI 主定位 + 章索引 + percent）。
  final Locator locator;

  /// 是否书首。
  final bool atStart;

  /// 是否书末。
  final bool atEnd;
}

/// 正文区点击（三分区判定由原生做）。
class ReaderTap extends ReaderEvent {
  const ReaderTap(this.x, this.y);

  /// 视口内坐标。
  final double x;
  final double y;
}

/// 渲染/解析错误。
class ReaderError extends ReaderEvent {
  const ReaderError(this.code, this.message);

  /// 错误码。
  final String code;

  /// 描述。
  final String message;
}

/// 解析桥消息；格式非法返回 null。
ReaderEvent? parseReaderEvent(String raw) {
  dynamic json;
  try {
    json = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (json is! Map<String, dynamic>) return null;
  switch (json['type']) {
    case 'bridgeReady':
      return const ReaderBridgeReady();
    case 'ready':
      return const ReaderBookReady();
    case 'locationsReady':
      return ReaderLocationsReady((json['total'] as num?)?.toInt() ?? 0);
    case 'relocated':
      final loc = _locatorFromBridgeJson(json['locator']);
      if (loc == null) return null;
      return ReaderRelocated(
        locator: loc,
        atStart: json['atStart'] == true,
        atEnd: json['atEnd'] == true,
      );
    case 'tap':
      return ReaderTap(
        (json['x'] as num?)?.toDouble() ?? 0,
        (json['y'] as num?)?.toDouble() ?? 0,
      );
    case 'error':
      return ReaderError(
        json['code'] as String? ?? 'unknown',
        json['message']?.toString() ?? '',
      );
    default:
      return null;
  }
}

/// 桥传来的 locator 是简化结构（v/href/cfi/chapterIndex/percent）。
Locator? _locatorFromBridgeJson(dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;
  try {
    return Locator(
      v: (raw['v'] as num?)?.toInt() ?? 1,
      href: raw['href'] as String?,
      cfi: raw['cfi'] as String?,
      chapterIndex: (raw['chapterIndex'] as num?)?.toInt(),
      percent: (raw['percent'] as num?)?.toDouble(),
    );
  } catch (_) {
    return null;
  }
}
