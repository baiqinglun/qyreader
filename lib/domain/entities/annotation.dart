/// 标注实体：划线（4 色语义色）+ 笔记。
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'annotation.freezed.dart';

/// 标注类型。
enum AnnotationType {
  /// 划线（背景高亮）。
  highlight('highlight'),

  /// 下划线。
  underline('underline'),

  /// 笔记（无原文选区也可独立存在，v1 依附于划线）。
  note('note');

  const AnnotationType(this.token);

  /// 存储层语义 token。
  final String token;

  /// 从 token 反解；未知值回退 highlight。
  static AnnotationType fromToken(String token) =>
      AnnotationType.values.firstWhere(
        (t) => t.token == token,
        orElse: () => AnnotationType.highlight,
      );
}

/// 划线语义色（存储 token，渲染色值由主题决定）。
enum AnnotationColor {
  yellow('yellow'),
  green('green'),
  blue('blue'),
  rose('rose');

  const AnnotationColor(this.token);

  /// 存储层语义 token。
  final String token;

  /// 从 token 反解；未知值回退 yellow。
  static AnnotationColor fromToken(String token) =>
      AnnotationColor.values.firstWhere(
        (c) => c.token == token,
        orElse: () => AnnotationColor.yellow,
      );
}

/// 一条标注。
@freezed
abstract class Annotation with _$Annotation {
  const factory Annotation({
    /// uuid v4。
    required String id,

    /// 所属书籍。
    required String bookId,

    /// 类型。
    required AnnotationType type,

    /// 语义色。
    required AnnotationColor color,

    /// 起始位置 Locator JSON（EPUB: cfi 存的是选区范围 CFI，
    /// 即 epub.js annotations API 直接可用的值）。
    required String locatorStart,

    /// 结束位置 Locator JSON（v1 与起始相同，预留点选区拆分）。
    required String locatorEnd,

    /// 划选原文冗余副本（列表/导出展示用）。
    String? quotedText,

    /// 笔记正文。
    String? note,

    /// 所在章 href（跳转兜底用）。
    String? href,

    /// 所在章索引。
    int? chapterIndex,

    /// 创建时间（epoch ms）。
    required int createdAt,

    /// 更新时间（epoch ms）。
    required int updatedAt,
  }) = _Annotation;
}
