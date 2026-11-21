/// EPUB 原始段落样式（精排用）。
///
/// 只保留会影响阅读观感、且能在原生排版里还原的字段：字号、行高、对齐、
/// 首行缩进、段前/段后距、粗体、斜体。颜色与字体族不做还原——阅读主题要
/// 保证夜间可读，且书内嵌字体没有导入到 Flutter。
library;

/// 原书对齐方式。
enum EpubTextAlign { left, center, right, justify }

/// 一段的原书样式（所有字段为空 = 没解析到样式）。
class EpubBlockStyle {
  /// 构造。
  const EpubBlockStyle({
    this.fontSize,
    this.lineHeight,
    this.textAlign,
    this.indentPx,
    this.marginTop,
    this.marginBottom,
    this.bold = false,
    this.italic = false,
  });

  /// 字号（逻辑像素）。
  final double? fontSize;

  /// 行高倍数。
  final double? lineHeight;

  /// 对齐。
  final EpubTextAlign? textAlign;

  /// 首行缩进（逻辑像素）。
  final double? indentPx;

  /// 段前距（逻辑像素）。
  final double? marginTop;

  /// 段后距（逻辑像素）。
  final double? marginBottom;

  /// 粗体。
  final bool bold;

  /// 斜体。
  final bool italic;

  /// 是否有任何可还原的样式。
  bool get isEmpty =>
      fontSize == null &&
      lineHeight == null &&
      textAlign == null &&
      indentPx == null &&
      marginTop == null &&
      marginBottom == null &&
      !bold &&
      !italic;

  @override
  bool operator ==(Object other) =>
      other is EpubBlockStyle &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.textAlign == textAlign &&
      other.indentPx == indentPx &&
      other.marginTop == marginTop &&
      other.marginBottom == marginBottom &&
      other.bold == bold &&
      other.italic == italic;

  @override
  int get hashCode => Object.hash(
    fontSize,
    lineHeight,
    textAlign,
    indentPx,
    marginTop,
    marginBottom,
    bold,
    italic,
  );

  @override
  String toString() =>
      'EpubBlockStyle(size: $fontSize, lh: $lineHeight, align: $textAlign, '
      'indent: $indentPx, mt: $marginTop, mb: $marginBottom, '
      'bold: $bold, italic: $italic)';
}
