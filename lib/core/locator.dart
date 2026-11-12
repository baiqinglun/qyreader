/// 全 App 唯一的「阅读位置」概念。
///
/// 进度、书签、标注、TTS 位置都存这个 JSON，不做第二种格式：
/// - EPUB：`cfi` 为主定位（跨设备稳定），`chapterIndex + offset` 为兜底
///   （CFI 解析失败时自动降级），`percent` 只用于展示。
/// - PDF：`page + x + y`（x/y 为页内比例 0..1）。
/// - TXT/MD：`offset`（字符偏移），`href` 固定填 `txt`。
///
/// 注：json_serializable 与 freezed 3 在 Dart 3.8 下无兼容版本，
/// 序列化为本文件内手写实现。
library;

import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'locator.freezed.dart';

/// 阅读位置。
@freezed
abstract class Locator with _$Locator {
  const factory Locator({
    /// 格式版本，当前恒为 1。
    @Default(1) int v,

    /// EPUB spine href / PDF 为 null / TXT 填 `txt`。
    String? href,

    /// EPUB CFI 主定位，如 `epubcfi(/6/14!/4/2/2,/1:0,/1:120)`。
    String? cfi,

    /// 兜底定位：章索引（0 基）。
    int? chapterIndex,

    /// 兜底定位：章内字符偏移（原生渲染模式的页首/标注起点）。
    int? offset,

    /// 章内字符偏移区间终点（标注/划线用；null = 单点位置）。
    int? offsetEnd,

    /// 全书百分比 0..1，仅展示用，不参与定位。
    double? percent,

    /// 细粒度全书位置 0..1（章索引 + 章内页比例）。percent 受 locations
    /// 分块量化（同一 location 内多页百分比相同），统计字数用这个。
    double? pos,

    /// PDF 页码（1 基）；EPUB 为章内页码（1 基）。
    int? page,

    /// EPUB 本章总页数（判断下一页是否跨章用）。
    int? pages,

    /// PDF 页内横向比例 0..1。
    double? x,

    /// PDF 页内纵向比例 0..1。
    double? y,
  }) = _Locator;
}

/// 序列化：Locator → JSON 字符串（null 字段省略）。
String locatorToJson(Locator l) =>
    jsonEncode(<String, dynamic>{
      'v': l.v,
      if (l.href != null) 'href': l.href,
      if (l.cfi != null) 'cfi': l.cfi,
      if (l.chapterIndex != null) 'chapterIndex': l.chapterIndex,
      if (l.offset != null) 'offset': l.offset,
      if (l.offsetEnd != null) 'offsetEnd': l.offsetEnd,
      if (l.percent != null) 'percent': l.percent,
      if (l.pos != null) 'pos': l.pos,
      if (l.page != null) 'page': l.page,
      if (l.pages != null) 'pages': l.pages,
      if (l.x != null) 'x': l.x,
      if (l.y != null) 'y': l.y,
    });

/// 反序列化：JSON 字符串 → Locator；损坏输入返回 null（降级路径用）。
Locator? locatorFromJson(String raw) {
  try {
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) return null;
    return Locator(
      v: (json['v'] as num?)?.toInt() ?? 1,
      href: json['href'] as String?,
      cfi: json['cfi'] as String?,
      chapterIndex: (json['chapterIndex'] as num?)?.toInt(),
      offset: (json['offset'] as num?)?.toInt(),
      offsetEnd: (json['offsetEnd'] as num?)?.toInt(),
      percent: (json['percent'] as num?)?.toDouble(),
      pos: (json['pos'] as num?)?.toDouble(),
      page: (json['page'] as num?)?.toInt(),
      pages: (json['pages'] as num?)?.toInt(),
      x: (json['x'] as num?)?.toDouble(),
      y: (json['y'] as num?)?.toDouble(),
    );
  } catch (_) {
    return null;
  }
}
