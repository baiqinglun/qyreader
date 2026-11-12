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
    this.page = 0,
    this.pages = 0,
    this.bookPage = 0,
    this.bookPages = 0,
    this.scrollPage = 0,
  });

  /// 新位置（CFI 主定位 + 章索引 + percent）。
  final Locator locator;

  /// 是否书首。
  final bool atStart;

  /// 是否书末。
  final bool atEnd;

  /// 章内页码（1 起，0 = 未知）。
  final int page;

  /// 按容器真实滚动位置算出的章内页码（0 = 未知）。
  ///
  /// epub.js 的 displayed.page 在滚动/同步过程中可能滞后，用它判断
  /// 「隐藏层是不是下一页」会判错（翻页盖骨架 → 白屏）。滚动位置是真值。
  final int scrollPage;

  /// 章内总页数（0 = 未知）。
  final int pages;

  /// 全书估算页码（1 起，0 = 未知）。
  final int bookPage;

  /// 全书估算总页数（0 = 未知）。
  final int bookPages;
}

/// 正文区点击（三分区判定由原生做）。
class ReaderTap extends ReaderEvent {
  const ReaderTap(this.x, this.y);

  /// 视口内坐标。
  final double x;
  final double y;
}

/// 文本选区完成（M2 划线入口）。
class ReaderSelected extends ReaderEvent {
  const ReaderSelected({
    required this.cfiRange,
    required this.text,
    required this.rect,
  });

  /// 选区范围 CFI（epub.js annotations API 直接可用）。
  final String cfiRange;

  /// 选中的原文。
  final String text;

  /// 选区在视口内的矩形（CSS px ≈ 逻辑 px，用于定位标注菜单）。
  final SelectionRect rect;
}

/// 轻量矩形（纯 Dart，便于单测；不用 dart:ui）。
class SelectionRect {
  const SelectionRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// 左上角 X。
  final double left;

  /// 左上角 Y。
  final double top;

  /// 宽。
  final double width;

  /// 高。
  final double height;
}

/// 划线点击（epub.js markClicked 转发）。
class ReaderMarkClicked extends ReaderEvent {
  const ReaderMarkClicked({required this.cfiRange, required this.annotationId});

  /// 划线选区 CFI。
  final String cfiRange;

  /// 标注 id（data.id；可能为 null，由 Dart 按 cfi 兜底匹配）。
  final String? annotationId;
}

/// 横向滑动（HC 模式 JS 侧检测上报；dx<0 为向左=前翻方向）。
class ReaderSwipe extends ReaderEvent {
  const ReaderSwipe({required this.dx, required this.dt});

  /// 横向位移（CSS px，负=向左）。
  final double dx;

  /// 时长 ms。
  final int dt;
}

/// 横向拖拽开始（JS 判定为翻页手势后立即上报）。
class ReaderDragStart extends ReaderEvent {
  const ReaderDragStart({required this.dx, required this.dy});

  /// 当前累计横向位移（CSS px，负=向左）。
  final double dx;

  /// 当前累计纵向位移。
  final double dy;
}

/// 横向拖拽过程（逐帧上报，Dart 据此实时平移页面）。
class ReaderDragMove extends ReaderEvent {
  const ReaderDragMove({required this.dx, required this.dy});

  /// 累计横向位移（CSS px，负=向左）。
  final double dx;

  /// 累计纵向位移。
  final double dy;
}

/// 横向拖拽结束（决定提交或回弹）。
class ReaderDragEnd extends ReaderEvent {
  const ReaderDragEnd({
    required this.dx,
    required this.dy,
    required this.dt,
    required this.vx,
  });

  /// 累计横向位移（CSS px，负=向左）。
  final double dx;

  /// 累计纵向位移。
  final double dy;

  /// 时长 ms。
  final int dt;

  /// 横向速度（CSS px/ms）。
  final double vx;
}

/// 横向拖拽被系统取消（来电/手势冲突）。
class ReaderDragCancel extends ReaderEvent {
  const ReaderDragCancel();
}

/// 隐藏层预渲染就绪（syncNext 完成，带最终页位）。
class ReaderSyncDone extends ReaderEvent {
  const ReaderSyncDone({
    required this.ok,
    this.seq = 0,
    this.locator,
    this.atStart = false,
    this.atEnd = false,
    this.page = 0,
    this.pages = 0,
    this.bookPage = 0,
    this.bookPages = 0,
    this.scrollPage = 0,
  });

  /// 对齐并前进是否成功。
  final bool ok;

  /// 请求序号（Dart 用于丢弃过期回调）。
  final int seq;

  /// 完成后的最终位置（ok 时可用）。
  final Locator? locator;

  /// 是否书首。
  final bool atStart;

  /// 是否书末。
  final bool atEnd;

  /// 章内页码。
  final int page;

  /// 按容器**真实滚动位置**算出的章内页码（0 = 未知）。
  ///
  /// epub.js 的 displayed.page 在同步过程中可能还是旧值，用它判断
  /// 「隐藏层是不是下一页」会判错（翻页出白屏）。滚动位置是真值。
  final int scrollPage;

  /// 章内总页数。
  final int pages;

  /// 全书估算页码。
  final int bookPage;

  /// 全书估算总页数。
  final int bookPages;
}

/// 左右边缘纵向手势开始（左=亮度，右=字号）。
class ReaderEdgeStart extends ReaderEvent {
  const ReaderEdgeStart(this.edge);

  /// 'left' / 'right'。
  final String edge;
}

/// 边缘手势过程（dy 为累计纵向位移，向上为负）。
class ReaderEdgeMove extends ReaderEvent {
  const ReaderEdgeMove({required this.edge, required this.dy});

  /// 'left' / 'right'。
  final String edge;

  /// 累计纵向位移（CSS px）。
  final double dy;
}

/// 边缘手势结束。
class ReaderEdgeEnd extends ReaderEvent {
  const ReaderEdgeEnd({
    required this.edge,
    required this.dy,
    required this.dt,
  });

  /// 'left' / 'right'。
  final String edge;

  /// 累计纵向位移（CSS px）。
  final double dy;

  /// 时长 ms。
  final int dt;
}

/// 边缘手势被取消。
class ReaderEdgeCancel extends ReaderEvent {
  const ReaderEdgeCancel();
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
        page: (json['page'] as num?)?.toInt() ?? 0,
        scrollPage: (json['scrollPage'] as num?)?.toInt() ?? 0,
        pages: (json['pages'] as num?)?.toInt() ?? 0,
        bookPage: (json['bookPage'] as num?)?.toInt() ?? 0,
        bookPages: (json['bookPages'] as num?)?.toInt() ?? 0,
      );
    case 'tap':
      return ReaderTap(
        (json['x'] as num?)?.toDouble() ?? 0,
        (json['y'] as num?)?.toDouble() ?? 0,
      );
    case 'selected':
      final cfi = json['cfiRange'] as String?;
      if (cfi == null || cfi.isEmpty) return null;
      return ReaderSelected(
        cfiRange: cfi,
        text: json['text']?.toString() ?? '',
        rect: SelectionRect(
          left: (json['x'] as num?)?.toDouble() ?? 0,
          top: (json['y'] as num?)?.toDouble() ?? 0,
          width: (json['w'] as num?)?.toDouble() ?? 0,
          height: (json['h'] as num?)?.toDouble() ?? 0,
        ),
      );
    case 'markClicked':
      final cfi = json['cfiRange'] as String?;
      if (cfi == null || cfi.isEmpty) return null;
      return ReaderMarkClicked(
        cfiRange: cfi,
        annotationId: json['id'] as String?,
      );
    case 'swipe':
      return ReaderSwipe(
        dx: (json['dx'] as num?)?.toDouble() ?? 0,
        dt: (json['dt'] as num?)?.toInt() ?? 0,
      );
    case 'dragStart':
      return ReaderDragStart(
        dx: (json['dx'] as num?)?.toDouble() ?? 0,
        dy: (json['dy'] as num?)?.toDouble() ?? 0,
      );
    case 'dragMove':
      return ReaderDragMove(
        dx: (json['dx'] as num?)?.toDouble() ?? 0,
        dy: (json['dy'] as num?)?.toDouble() ?? 0,
      );
    case 'dragEnd':
      return ReaderDragEnd(
        dx: (json['dx'] as num?)?.toDouble() ?? 0,
        dy: (json['dy'] as num?)?.toDouble() ?? 0,
        dt: (json['dt'] as num?)?.toInt() ?? 0,
        vx: (json['vx'] as num?)?.toDouble() ?? 0,
      );
    case 'dragCancel':
      return const ReaderDragCancel();
    case 'syncDone':
      return ReaderSyncDone(
        ok: json['ok'] == true,
        seq: (json['seq'] as num?)?.toInt() ?? 0,
        locator: _locatorFromBridgeJson(json['locator']),
        atStart: json['atStart'] == true,
        atEnd: json['atEnd'] == true,
        page: (json['page'] as num?)?.toInt() ?? 0,
        pages: (json['pages'] as num?)?.toInt() ?? 0,
        bookPage: (json['bookPage'] as num?)?.toInt() ?? 0,
        bookPages: (json['bookPages'] as num?)?.toInt() ?? 0,
      );
    case 'edgeStart':
      return ReaderEdgeStart(json['edge']?.toString() ?? '');
    case 'edgeMove':
      return ReaderEdgeMove(
        edge: json['edge']?.toString() ?? '',
        dy: (json['dy'] as num?)?.toDouble() ?? 0,
      );
    case 'edgeEnd':
      return ReaderEdgeEnd(
        edge: json['edge']?.toString() ?? '',
        dy: (json['dy'] as num?)?.toDouble() ?? 0,
        dt: (json['dt'] as num?)?.toInt() ?? 0,
      );
    case 'edgeCancel':
      return const ReaderEdgeCancel();
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
      pos: (raw['pos'] as num?)?.toDouble(),
      page: (raw['page'] as num?)?.toInt(),
      pages: (raw['pages'] as num?)?.toInt(),
    );
  } catch (_) {
    return null;
  }
}
