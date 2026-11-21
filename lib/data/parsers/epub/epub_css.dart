/// EPUB 内嵌 CSS 的极简解析器（精排用）。
///
/// 只支持常见的简单选择器（tag / .class / #id / tag.class）和排版相关
/// 声明；复杂选择器、伪类、@media 里的规则会保守跳过，不能解析时返回
/// null，让阅读器回到默认排版。
library;

import 'package:xml/xml.dart';

import 'epub_block_style.dart';

/// 从 XHTML（含 `<style>`）与外部样式表文本中解析段落样式。
class EpubCssResolver {
  EpubCssResolver._(
    this._byTag,
    this._byClass,
    this._byId,
    this._universal,
  );

  /// 空解析器：任何元素都没有样式。
  static final EpubCssResolver empty = EpubCssResolver._(
    const <String, List<_CssRule>>{},
    const <String, List<_CssRule>>{},
    const <String, List<_CssRule>>{},
    const <_CssRule>[],
  );

  final Map<String, List<_CssRule>> _byTag;
  final Map<String, List<_CssRule>> _byClass;
  final Map<String, List<_CssRule>> _byId;
  final List<_CssRule> _universal;

  /// 解析 [rawHtml] 中的 `<style>` 以及 [externalCss]。
  factory EpubCssResolver.parse(
    String rawHtml, {
    String externalCss = '',
  }) {
    final buffer = StringBuffer(externalCss);
    for (final match in RegExp(
      r'<style[^>]*>(.*?)</style>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(rawHtml)) {
      buffer.writeln(match.group(1));
    }
    final rules = _parseRules(buffer.toString());
    final byTag = <String, List<_CssRule>>{};
    final byClass = <String, List<_CssRule>>{};
    final byId = <String, List<_CssRule>>{};
    final universal = <_CssRule>[];
    for (final rule in rules) {
      final tags = <String>{};
      final classes = <String>{};
      final ids = <String>{};
      for (final selector in rule.selectors) {
        if (selector.tag != null) tags.add(selector.tag!);
        if (selector.id != null) ids.add(selector.id!);
        classes.addAll(selector.classes);
      }
      if (tags.isEmpty && classes.isEmpty && ids.isEmpty) {
        universal.add(rule);
        continue;
      }
      for (final tag in tags) {
        byTag.putIfAbsent(tag, () => <_CssRule>[]).add(rule);
      }
      for (final cls in classes) {
        byClass.putIfAbsent(cls, () => <_CssRule>[]).add(rule);
      }
      for (final id in ids) {
        byId.putIfAbsent(id, () => <_CssRule>[]).add(rule);
      }
    }
    return EpubCssResolver._(byTag, byClass, byId, universal);
  }

  /// 计算 [el] 的原始样式；没有任何命中返回 null。
  EpubBlockStyle? styleFor(XmlElement el) {
    if (_byTag.isEmpty &&
        _byClass.isEmpty &&
        _byId.isEmpty &&
        _universal.isEmpty) {
      return null;
    }
    final chain = <XmlElement>[];
    XmlElement? current = el;
    while (current != null) {
      chain.add(current);
      final parent = current.parent;
      current = parent is XmlElement ? parent : null;
    }
    final style = _MutableStyle();
    for (final node in chain.reversed) {
      final isBlock = identical(node, el);
      for (final rule in _matching(node)) {
        style.apply(rule.decls, inheritOnly: !isBlock);
      }
      if (isBlock) style.applyInline(el.getAttribute('style'));
    }
    return style.toStyle();
  }

  List<_CssRule> _matching(XmlElement el) {
    final tag = el.name.local.toLowerCase();
    final classes = (el.getAttribute('class') ?? '')
        .split(RegExp(r'\s+'))
        .where((c) => c.isNotEmpty)
        .toSet();
    final id = el.getAttribute('id');
    final candidates = <_CssRule>{..._universal};
    final tagRules = _byTag[tag];
    if (tagRules != null) candidates.addAll(tagRules);
    if (id != null) {
      final idRules = _byId[id];
      if (idRules != null) candidates.addAll(idRules);
    }
    for (final cls in classes) {
      final classRules = _byClass[cls];
      if (classRules != null) candidates.addAll(classRules);
    }
    final matches = <_CssRule>[
      for (final rule in candidates)
        if (rule.matches(tag, classes, id)) rule,
    ];
    matches.sort((a, b) {
      final bySpecificity = a.specificity.compareTo(b.specificity);
      if (bySpecificity != 0) return bySpecificity;
      return a.order.compareTo(b.order);
    });
    return matches;
  }
}

/// 选择器中的一段（只保留最右侧简单选择器）。
class _SimpleSelector {
  const _SimpleSelector({
    this.tag,
    this.id,
    this.classes = const <String>{},
    required this.specificity,
  });

  final String? tag;
  final String? id;
  final Set<String> classes;
  final int specificity;

  static _SimpleSelector? parse(String raw) {
    var text = raw.trim().toLowerCase();
    if (text.isEmpty || text.contains('>') || text.contains('+')) return null;
    // 复杂后代选择器只取最右侧（`.chapter p` 当 `p` 用），保守但可提升
    // 常见书籍 CSS 的命中率。
    final space = text.lastIndexOf(RegExp(r'\s'));
    if (space >= 0) text = text.substring(space + 1).trim();
    // 去掉伪类/伪元素与属性选择器。
    final colon = text.indexOf(':');
    if (colon >= 0) text = text.substring(0, colon);
    final bracket = text.indexOf('[');
    if (bracket >= 0) text = text.substring(0, bracket);
    if (text.isEmpty || text == '*' || text.contains('(')) return null;

    String? tag;
    String? id;
    final classes = <String>{};
    final first = RegExp(r'^[a-z][a-z0-9_-]*').firstMatch(text)?.group(0);
    if (first != null) {
      tag = first;
      text = text.substring(first.length);
    }
    final parts = RegExp(r'([.#])([a-z0-9_-]+)').allMatches(text);
    for (final part in parts) {
      final value = part.group(2)!;
      if (part.group(1) == '.') {
        classes.add(value);
      } else {
        id = value;
      }
    }
    if (tag == null && id == null && classes.isEmpty) return null;
    final specificity =
        (id != null ? 100 : 0) + classes.length * 10 + (tag != null ? 1 : 0);
    return _SimpleSelector(
      tag: tag,
      id: id,
      classes: classes,
      specificity: specificity,
    );
  }

  bool matches(String tag, Set<String> classes, String? id) {
    if (this.tag != null && this.tag != tag) return false;
    if (this.id != null && this.id != id) return false;
    if (this.classes.isNotEmpty && !classes.containsAll(this.classes)) {
      return false;
    }
    return true;
  }
}

class _CssRule {
  _CssRule(this.selectors, this.decls, this.order)
    : specificity = selectors
          .map((s) => s.specificity)
          .fold<int>(0, (a, b) => a > b ? a : b);

  final List<_SimpleSelector> selectors;
  final Map<String, String> decls;
  final int order;
  final int specificity;

  bool matches(String tag, Set<String> classes, String? id) {
    for (final selector in selectors) {
      if (selector.matches(tag, classes, id)) return true;
    }
    return false;
  }
}

List<_CssRule> _parseRules(String css) {
  final text = css.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  final rules = <_CssRule>[];
  var order = 0;
  for (final match in RegExp(r'([^{}]+)\{([^{}]*)\}').allMatches(text)) {
    final selectorText = match.group(1)!.trim();
    if (selectorText.startsWith('@')) continue;
    final selectors = <_SimpleSelector>[];
    for (final part in selectorText.split(',')) {
      final selector = _SimpleSelector.parse(part);
      if (selector != null) selectors.add(selector);
    }
    if (selectors.isEmpty) continue;
    final decls = _parseDecls(match.group(2)!);
    if (decls.isEmpty) continue;
    rules.add(_CssRule(selectors, decls, order++));
  }
  return rules;
}

Map<String, String> _parseDecls(String raw) {
  final out = <String, String>{};
  for (final part in raw.split(';')) {
    final colon = part.indexOf(':');
    if (colon <= 0) continue;
    final name = part.substring(0, colon).trim().toLowerCase();
    final value = part.substring(colon + 1).trim().toLowerCase();
    if (name.isEmpty || value.isEmpty || value.contains('!important')) {
      out[name] = value.replaceAll('!important', '').trim();
    } else {
      out[name] = value;
    }
  }
  return out;
}

class _MutableStyle {
  double font = 16;
  bool fontSpecified = false;
  double? lineHeight;
  EpubTextAlign? align;
  // 缩进/段距先存原始值，最后按最终字号换算（CSS 的 em 是相对最终
  // font-size，不是规则应用顺序里的中间值）。
  String? indentRaw;
  String? marginTopRaw;
  String? marginBottomRaw;
  bool bold = false;
  bool italic = false;
  bool hasStyle = false;

  void applyInline(String? raw) {
    if (raw == null || raw.trim().isEmpty) return;
    apply(_parseDecls(raw), inheritOnly: false);
  }

  void apply(Map<String, String> decls, {required bool inheritOnly}) {
    if (decls.isEmpty) return;
    if (decls.containsKey('font-size')) {
      final size = _fontSize(decls['font-size']!, font);
      if (size != null) {
        font = size;
        fontSpecified = true;
        hasStyle = true;
      }
    }
    if (decls.containsKey('line-height')) {
      final height = _lineHeight(decls['line-height']!, font);
      if (height != null) {
        lineHeight = height;
        hasStyle = true;
      }
    }
    if (decls.containsKey('text-align')) {
      final value = _align(decls['text-align']!);
      if (value != null) {
        align = value;
        hasStyle = true;
      }
    }
    if (decls.containsKey('font-weight')) {
      final weight = _fontWeight(decls['font-weight']!);
      if (weight != null) {
        bold = weight;
        hasStyle = true;
      }
    }
    if (decls.containsKey('font-style')) {
      final value = decls['font-style']!;
      if (value.contains('italic') || value.contains('oblique')) {
        italic = true;
        hasStyle = true;
      } else if (value == 'normal') {
        italic = false;
        hasStyle = true;
      }
    }
    // text-indent 在 CSS 里是可继承属性，祖先上的缩进也要带下来。
    if (decls.containsKey('text-indent')) {
      indentRaw = decls['text-indent'];
      hasStyle = true;
    }
    if (inheritOnly) return;
    if (decls.containsKey('margin')) {
      final parts = decls['margin']!.split(RegExp(r'\s+'));
      if (parts.isNotEmpty) {
        marginTopRaw = parts.first;
        marginBottomRaw = parts.length >= 3 ? parts[2] : parts.first;
        hasStyle = true;
      }
    }
    if (decls.containsKey('margin-top')) {
      marginTopRaw = decls['margin-top'];
      hasStyle = true;
    }
    if (decls.containsKey('margin-bottom')) {
      marginBottomRaw = decls['margin-bottom'];
      hasStyle = true;
    }
  }

  EpubBlockStyle? toStyle() {
    if (!hasStyle) return null;
    double? resolve(String? raw, double upper) {
      if (raw == null) return null;
      final value = _length(raw, base: font);
      if (value == null) return null;
      return value.clamp(0, upper).toDouble();
    }

    final style = EpubBlockStyle(
      fontSize: fontSpecified ? font.clamp(8, 48) : null,
      lineHeight: lineHeight?.clamp(0.8, 3),
      textAlign: align,
      indentPx: resolve(indentRaw, font * 6),
      marginTop: resolve(marginTopRaw, font * 4),
      marginBottom: resolve(marginBottomRaw, font * 4),
      bold: bold,
      italic: italic,
    );
    return style.isEmpty ? null : style;
  }
}

double? _fontSize(String value, double parent) {
  final v = value.trim();
  final keyword = <String, double>{
    'xx-small': 10,
    'x-small': 11,
    'small': 13,
    'medium': 16,
    'large': 18,
    'x-large': 24,
    'xx-large': 32,
  }[v];
  if (keyword != null) return keyword;
  if (v == 'smaller') return parent * 0.85;
  if (v == 'larger') return parent * 1.2;
  return _length(v, base: parent);
}

double? _lineHeight(String value, double font) {
  final v = value.trim();
  if (v == 'normal') return null;
  if (v.endsWith('%')) {
    final n = double.tryParse(v.substring(0, v.length - 1));
    return n == null ? null : (n / 100).clamp(0.8, 3);
  }
  if (v.endsWith('px')) {
    final n = double.tryParse(v.substring(0, v.length - 2));
    return n == null || font <= 0 ? null : (n / font).clamp(0.8, 3);
  }
  if (v.endsWith('em')) {
    final n = double.tryParse(v.substring(0, v.length - 2));
    return n?.clamp(0.8, 3);
  }
  final n = double.tryParse(v);
  return n?.clamp(0.8, 3);
}

EpubTextAlign? _align(String value) {
  final v = value.trim();
  if (v.contains('center')) return EpubTextAlign.center;
  if (v.contains('right') || v.contains('end')) return EpubTextAlign.right;
  if (v.contains('justify')) return EpubTextAlign.justify;
  if (v.contains('left') || v.contains('start')) return EpubTextAlign.left;
  return null;
}

bool? _fontWeight(String value) {
  final v = value.trim();
  if (v == 'bold' || v == 'bolder') return true;
  if (v == 'normal' || v == 'lighter') return false;
  final n = int.tryParse(v);
  if (n == null) return null;
  return n >= 600;
}

double? _length(String raw, {required double base}) {
  var v = raw.trim().toLowerCase();
  if (v.isEmpty || v == 'auto' || v == 'inherit' || v == 'initial') {
    return null;
  }
  if (v.endsWith('px')) return double.tryParse(v.substring(0, v.length - 2));
  if (v.endsWith('pt')) {
    final n = double.tryParse(v.substring(0, v.length - 2));
    return n == null ? null : n * 96 / 72;
  }
  if (v.endsWith('rem')) {
    final n = double.tryParse(v.substring(0, v.length - 3));
    return n == null ? null : n * 16;
  }
  if (v.endsWith('em')) {
    final n = double.tryParse(v.substring(0, v.length - 2));
    return n == null ? null : n * base;
  }
  if (v.endsWith('%')) {
    final n = double.tryParse(v.substring(0, v.length - 1));
    return n == null ? null : n / 100 * base;
  }
  if (v.endsWith('mm')) {
    final n = double.tryParse(v.substring(0, v.length - 2));
    return n == null ? null : n * 96 / 25.4;
  }
  return double.tryParse(v);
}
