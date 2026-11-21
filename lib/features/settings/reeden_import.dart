/// Reeden 阅读数据导出 JSON 解析（纯函数，可单测）。
///
/// 导出结构（顶层是书籍数组）：
/// ```json
/// [{
///   "title": "...", "author": "...", "description": "...",
///   "rating": 4.5, "tags": [...], "category": "...",
///   "readingState": { "readStatus": "reading|finished|...",
///     "progress": 0.38, "readStartTime": "...", "readFinishTime": "...",
///     "lastReadTime": "..." },
///   "notes": [{ "sectionName": "...", "content": "原文", "comment": "想法",
///     "type": "underline", "color": "red", "timestamp": 1767609044000 }],
///   "reviews": [{ "content": "...", "createdAt": "...", "updatedAt": "..." }],
///   "readingStatistics": { "totalReadSeconds": 1, "totalWordCount": 1,
///     "readingRecords": [{ "date": "2026-01-05", "readSeconds": 1568,
///       "wordCount": 17356 }] }
/// }]
/// ```
/// 字段缺失 / 类型不对都按 null 兜底，不让一条坏记录拖垮整份导入。
library;

import 'dart:convert';

/// 一条划线 / 笔记。
class ReedenNote {
  const ReedenNote({
    required this.sectionIndex,
    required this.sectionName,
    required this.content,
    this.comment,
    required this.type,
    required this.color,
    required this.timestampMs,
  });

  /// 所在章序号（原书章节序号，仅作定位偏好；0 基 / 1 基都有可能）。
  final int? sectionIndex;

  /// 所在章节名（原书目录章节）。
  final String sectionName;

  /// 划选原文。
  final String content;

  /// 想法（Reeden 的 comment 字段；空 = 没写想法）。
  final String? comment;

  /// 类型（underline / ...）。
  final String type;

  /// 颜色名（red / green / blue / yellow / ...）。
  final String color;

  /// 创建时间（epoch ms）。
  final int timestampMs;
}

/// 一条书评。
class ReedenReview {
  const ReedenReview({
    required this.content,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  final String content;
  final int createdAtMs;
  final int updatedAtMs;
}

/// 阅读状态。
class ReedenReadingState {
  const ReedenReadingState({
    required this.statusRaw,
    required this.progress,
    required this.startMs,
    required this.finishMs,
    required this.lastReadMs,
  });

  /// 原始状态名（reading / finished / ...）。
  final String statusRaw;

  /// 进度 0..1。
  final double progress;

  /// 开始阅读时间（epoch ms）；未知为 0。
  final int startMs;

  /// 读完时间（epoch ms）；未读完为 0。
  final int finishMs;

  /// 最近阅读时间（epoch ms）；未知为 0。
  final int lastReadMs;
}

/// 一天的阅读统计。
class ReedenDailyRecord {
  const ReedenDailyRecord({
    required this.day,
    required this.seconds,
    required this.words,
  });

  /// 本地日期（yyyy-MM-dd）。
  final String day;

  /// 当日阅读秒数。
  final int seconds;

  /// 当日阅读字数。
  final int words;
}

/// 一本书的导入数据。
class ReedenBookData {
  const ReedenBookData({
    required this.title,
    required this.author,
    required this.description,
    required this.rating,
    required this.tags,
    required this.category,
    required this.state,
    required this.notes,
    required this.reviews,
    required this.records,
  });

  final String title;
  final String author;
  final String description;
  final double? rating;
  final List<String> tags;
  final String category;
  final ReedenReadingState? state;
  final List<ReedenNote> notes;
  final List<ReedenReview> reviews;
  final List<ReedenDailyRecord> records;
}

/// 解析 Reeden 导出 JSON；顶层不是数组或整份损坏时抛 FormatException。
List<ReedenBookData> parseReedenExport(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! List) {
    throw const FormatException('Reeden 导出顶层必须是数组');
  }
  final out = <ReedenBookData>[];
  for (final entry in decoded) {
    if (entry is! Map<String, dynamic>) continue;
    final book = _parseBook(entry);
    if (book != null) out.add(book);
  }
  return out;
}

ReedenBookData? _parseBook(Map<String, dynamic> json) {
  final title = _string(json['title']);
  if (title == null || title.trim().isEmpty) return null;
  final stateJson = json['readingState'];
  final state = stateJson is Map<String, dynamic>
      ? ReedenReadingState(
          statusRaw: _string(stateJson['readStatus']) ?? '',
          progress: _progress(stateJson['progress']),
          startMs: _ms(stateJson['readStartTime']),
          finishMs: _ms(stateJson['readFinishTime']),
          lastReadMs: _ms(stateJson['lastReadTime']),
        )
      : null;
  return ReedenBookData(
    title: title.trim(),
    author: _string(json['author']) ?? '',
    description: _string(json['description']) ?? '',
    rating: _double(json['rating']),
    tags: [
      for (final tag in _listOrEmpty(json['tags']))
        if (tag is String && tag.trim().isNotEmpty) tag.trim(),
    ],
    category: _string(json['category']) ?? '',
    state: state,
    notes: [
      for (final n in _listOrEmpty(json['notes']))
        if (n is Map<String, dynamic>)
          if (_parseNote(n) case final ReedenNote note) note,
    ],
    reviews: [
      for (final r in _listOrEmpty(json['reviews']))
        if (r is Map<String, dynamic>)
          if (_parseReview(r) case final ReedenReview review) review,
    ],
    records: [
      for (final r in _listOrEmpty(
        (json['readingStatistics'] as Map<String, dynamic>?)?['readingRecords'],
      ))
        if (r is Map<String, dynamic>)
          if (_parseRecord(r) case final ReedenDailyRecord record) record,
    ],
  );
}

ReedenNote? _parseNote(Map<String, dynamic> json) {
  final content = _string(json['content']);
  if (content == null || content.trim().isEmpty) return null;
  return ReedenNote(
    sectionIndex: _double(json['sectionIndex'])?.toInt(),
    sectionName: _string(json['sectionName']) ?? '',
    content: content.trim(),
    comment: _string(json['comment']),
    type: _string(json['type']) ?? 'underline',
    color: _string(json['color']) ?? '',
    timestampMs: _ms(json['timestamp'] ?? json['updatedAt']),
  );
}

ReedenReview? _parseReview(Map<String, dynamic> json) {
  final content = _string(json['content']);
  if (content == null || content.trim().isEmpty) return null;
  return ReedenReview(
    content: content.trim(),
    createdAtMs: _ms(json['createdAt']),
    updatedAtMs: _ms(json['updatedAt']),
  );
}

ReedenDailyRecord? _parseRecord(Map<String, dynamic> json) {
  final day = _string(json['date']);
  final seconds = _double(json['readSeconds']);
  if (day == null || seconds == null || seconds <= 0) return null;
  return ReedenDailyRecord(
    day: day,
    seconds: seconds.round(),
    words: (_double(json['wordCount']) ?? 0).round(),
  );
}

String? _string(dynamic value) =>
    value is String && value.isNotEmpty ? value : null;

double? _double(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value');

List<dynamic> _listOrEmpty(dynamic value) =>
    value is List ? value : const <dynamic>[];

/// 进度夹紧到 0..1（Reeden 存的是 0..1；0..100 的旧导出也能兜住）。
double _progress(dynamic value) {
  final n = _double(value) ?? 0;
  if (n > 1) return (n / 100).clamp(0.0, 1.0);
  return n.clamp(0.0, 1.0);
}

/// 时间字段：epoch ms（int）或 ISO 字符串；解析失败返回 0。
int _ms(dynamic value) {
  if (value is num) return value.toInt();
  if (value is String && value.isNotEmpty) {
    final ms = int.tryParse(value);
    if (ms != null) return ms;
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.millisecondsSinceEpoch;
  }
  return 0;
}
