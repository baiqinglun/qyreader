/// 书籍领域实体。
///
/// 注：json_serializable 与 freezed 3 在 Dart 3.8 下无兼容版本，
/// JSON 序列化为本文件内手写实现（同步 payload 用）。
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'book.freezed.dart';

/// 支持的电子书格式。
enum BookFormat {
  /// EPUB 2/3。
  epub,

  /// PDF。
  pdf,

  /// 纯文本。
  txt,

  /// Markdown。
  md,
}

/// 从名称解析格式，未知值回退 epub。
BookFormat bookFormatFromName(String? name) => BookFormat.values
    .firstWhere((f) => f.name == name, orElse: () => BookFormat.epub);

/// 阅读状态：未读 / 在读 / 已读 / 弃读。
enum BookReadStatus {
  /// 未读。
  unread('未读'),

  /// 在读。
  reading('在读'),

  /// 已读。
  finished('已读'),

  /// 弃读。
  dropped('弃读');

  const BookReadStatus(this.label);

  /// 中文展示名。
  final String label;
}

/// 从名称解析阅读状态；未知值回退未读。
BookReadStatus bookReadStatusFromName(String? name) => BookReadStatus.values
    .firstWhere((s) => s.name == name, orElse: () => BookReadStatus.unread);
/// 书籍。
@freezed
abstract class Book with _$Book {
  const factory Book({
    /// uuid v4。
    required String id,

    /// 书名。
    required String title,

    /// 作者。
    String? author,

    /// 丛书名。
    String? series,

    /// 丛书序号。
    @Default(0) double seriesIndex,

    /// 语言（BCP-47）。
    String? language,

    /// 简介。
    String? description,

    /// 格式。
    required BookFormat format,

    /// 应用私有目录内的文件路径。
    required String filePath,

    /// 内容哈希（去重 + 同步校验）。
    required String fileSha256,

    /// 文件字节数。
    required int fileSize,

    /// 封面路径。
    String? coverPath,

    /// 章节数。
    @Default(0) int chapterCount,

    /// 全文字数（近似）。
    @Default(0) int wordCount,

    /// 入库时间（epoch ms）。
    required int addedAt,

    /// 元数据更新时间（epoch ms）。
    required int updatedAt,

    /// 最近打开时间（epoch ms）。
    int? lastOpenedAt,

    /// 是否读完（旧字段，保留兼容）。
    @Default(false) bool isFinished,

    /// 阅读状态（未读 / 在读 / 已读 / 弃读）。
    @Default(BookReadStatus.unread) BookReadStatus readStatus,

    /// 是否归档。
    @Default(false) bool isArchived,

    /// 个人评分 1..5；null = 未评分。
    int? rating,

    /// 个人书评。
    String? review,

    /// 个人标签。
    @Default(<String>[]) List<String> tags,

    /// 个人分类（单值；null = 未分类）。
    String? category,

    /// 书架置顶时间（epoch ms）；null = 未置顶。
    int? pinnedAt,

    /// 墓碑（epoch ms），参与 LWW 合并。
    int? deletedAt,

    /// 解析器原始元数据（JSON 字符串）。
    String? metaJson,

    /// 最后写入的 HLC。
    required String hlc,

    /// 写入设备标识。
    required String deviceId,
  }) = _Book;
}

/// 序列化：Book → JSON Map（同步 payload 用；null 字段省略）。
Map<String, dynamic> bookToJson(Book b) => <String, dynamic>{
      'id': b.id,
      'title': b.title,
      if (b.author != null) 'author': b.author,
      if (b.series != null) 'series': b.series,
      if (b.seriesIndex != 0) 'seriesIndex': b.seriesIndex,
      if (b.language != null) 'language': b.language,
      if (b.description != null) 'description': b.description,
      'format': b.format.name,
      'filePath': b.filePath,
      'fileSha256': b.fileSha256,
      'fileSize': b.fileSize,
      if (b.coverPath != null) 'coverPath': b.coverPath,
      if (b.chapterCount != 0) 'chapterCount': b.chapterCount,
      if (b.wordCount != 0) 'wordCount': b.wordCount,
      'addedAt': b.addedAt,
      'updatedAt': b.updatedAt,
      if (b.lastOpenedAt != null) 'lastOpenedAt': b.lastOpenedAt,
      if (b.isFinished) 'isFinished': b.isFinished,
      if (b.readStatus != BookReadStatus.unread)
        'readStatus': b.readStatus.name,
      if (b.isArchived) 'isArchived': b.isArchived,
      if (b.rating != null) 'rating': b.rating,
      if (b.review != null && b.review!.isNotEmpty) 'review': b.review,
      if (b.tags.isNotEmpty) 'tags': b.tags,
      if (b.category != null && b.category!.isNotEmpty) 'category': b.category,
      if (b.pinnedAt != null) 'pinnedAt': b.pinnedAt,
      if (b.deletedAt != null) 'deletedAt': b.deletedAt,
      if (b.metaJson != null) 'metaJson': b.metaJson,
      'hlc': b.hlc,
      'deviceId': b.deviceId,
    };

/// 反序列化：JSON Map → Book；损坏输入抛 FormatException（调用方兜底）。
Book bookFromJson(Map<String, dynamic> json) => Book(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String?,
      series: json['series'] as String?,
      seriesIndex: (json['seriesIndex'] as num?)?.toDouble() ?? 0,
      language: json['language'] as String?,
      description: json['description'] as String?,
      format: bookFormatFromName(json['format'] as String?),
      filePath: json['filePath'] as String,
      fileSha256: json['fileSha256'] as String,
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      coverPath: json['coverPath'] as String?,
      chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
      wordCount: (json['wordCount'] as num?)?.toInt() ?? 0,
      addedAt: (json['addedAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      lastOpenedAt: (json['lastOpenedAt'] as num?)?.toInt(),
      isFinished: json['isFinished'] as bool? ?? false,
      readStatus: bookReadStatusFromName(json['readStatus'] as String?),
      isArchived: json['isArchived'] as bool? ?? false,
      rating: (json['rating'] as num?)?.toInt(),
      review: json['review'] as String?,
      tags: _parseTags(json['tags']),
      category: json['category'] as String?,
      pinnedAt: (json['pinnedAt'] as num?)?.toInt(),
      deletedAt: (json['deletedAt'] as num?)?.toInt(),
      metaJson: json['metaJson'] as String?,
      hlc: json['hlc'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
    );

/// 标签解析：JSON 数组；兼容逗号分隔字符串。
List<String> _parseTags(dynamic raw) {
  if (raw is List) {
    return raw
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }
  if (raw is String && raw.isNotEmpty) {
    return raw
        .split(RegExp(r'[,，、;；\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }
  return const <String>[];
}

/// 书架条目：书籍 + 展示用进度百分比。
@freezed
abstract class ShelfItem with _$ShelfItem {
  const factory ShelfItem({
    /// 书籍实体。
    required Book book,

    /// 当前阅读百分比 0..1。
    @Default(0) double percent,
  }) = _ShelfItem;
}

/// 章节目录条目（阅读器目录抽屉与定位用）。
@freezed
abstract class BookChapter with _$BookChapter {
  const factory BookChapter({
    /// 章序号（0 基）。
    required int idx,

    /// 章标题。
    required String title,

    /// zip 内文档路径（epub.js display 直接可用）。
    required String href,

    /// 目录层级（0 顶）。
    @Default(0) int level,
  }) = _BookChapter;
}
