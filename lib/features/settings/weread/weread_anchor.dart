/// 微信读书划线 → 本机章节坐标的定位（纯函数，可单测）。
///
/// 微信读书的 `range` 是它自己的字符区间，换版本/换排版就对不上；这里
/// 用划线原文在本地章节正文里搜位置，先精确匹配，再忽略空白匹配。
library;

import '../../../domain/entities/annotation.dart';
import '../../reader/native/native_chapter_source.dart';
import 'weread_models.dart';

/// 一条划线在本机章节里的坐标。
class WeReadAnchor {
  /// 构造。
  const WeReadAnchor({
    required this.chapterIndex,
    required this.href,
    required this.start,
    required this.end,
  });

  /// 章序号（0 基）。
  final int chapterIndex;

  /// 章 href。
  final String href;

  /// 章内起始字符偏移。
  final int start;

  /// 章内结束字符偏移（不含）。
  final int end;
}

/// 在本机章节里定位一条微信读书划线；找不到返回 null。
WeReadAnchor? locateWeReadNote(List<NativeChapter> chapters, WeReadNote note) {
  final quote = note.quote.trim();
  if (quote.isEmpty || chapters.isEmpty) return null;

  final preferred = _preferredChapterIndex(chapters, note);
  final order = <int>[
    if (preferred != null) preferred,
    for (var i = 0; i < chapters.length; i++)
      if (i != preferred) i,
  ];
  for (final index in order) {
    final chapter = chapters[index];
    final exact = chapter.text.indexOf(quote);
    if (exact >= 0) {
      return WeReadAnchor(
        chapterIndex: index,
        href: chapter.href,
        start: exact,
        end: exact + quote.length,
      );
    }
    final normalized = _normalizeWithMap(chapter.text);
    final normalizedQuote = _normalize(quote);
    if (normalizedQuote.isEmpty) continue;
    final position = normalized.text.indexOf(normalizedQuote);
    if (position < 0) continue;
    final start = normalized.map[position];
    final end = normalized.map[position + normalizedQuote.length - 1] + 1;
    return WeReadAnchor(
      chapterIndex: index,
      href: chapter.href,
      start: start,
      end: end,
    );
  }
  return null;
}

/// 找不到原文时的兜底：优先用章节标题/序号对齐的章，定位到该章开头。
///
/// 宁可位置不精确，也不要把整条划线/想法丢掉——标注列表里至少能看到
/// 原文与想法，用户可再手动调整位置。
WeReadAnchor? locateWeReadNoteFallback(
  List<NativeChapter> chapters,
  WeReadNote note,
) {
  if (chapters.isEmpty) return null;
  final preferred = _preferredChapterIndex(chapters, note);
  int index;
  if (preferred != null) {
    index = preferred;
  } else {
    index = 0;
    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i].text.trim().isNotEmpty) {
        index = i;
        break;
      }
    }
  }
  return WeReadAnchor(
    chapterIndex: index,
    href: chapters[index].href,
    start: 0,
    end: 0,
  );
}

/// 把外部阅读百分比换算成本机章节坐标（按各章正文长度）。
///
/// 微信读书只给百分比；本机 locator 需要章索引 + 章内字符偏移。这里直接用
/// 解析好的 `NativeChapter.text.length`，不依赖数据库里可能为 0 的
/// `chapters.char_count`。
WeReadAnchor? locatePercentInChapters(
  List<NativeChapter> chapters,
  double percent,
) {
  if (chapters.isEmpty) return null;
  var total = 0;
  for (final chapter in chapters) {
    total += chapter.text.length;
  }
  if (total <= 0) return null;
  final target = (percent.clamp(0.0, 1.0) * total).round();
  var before = 0;
  for (var i = 0; i < chapters.length; i++) {
    final chapter = chapters[i];
    final length = chapter.text.length;
    final isLast = i == chapters.length - 1;
    if (target < before + length || isLast) {
      final offset = (target - before).clamp(0, length);
      return WeReadAnchor(
        chapterIndex: i,
        href: chapter.href,
        start: offset,
        end: offset,
      );
    }
    before += length;
  }
  return null;
}

/// 微信读书划线颜色样式 → 本机语义色。
///
/// 微信读书常见 0/1/2/3 四档；未知值统一黄色，至少不丢划线。
AnnotationColor colorForWeReadStyle(int? style) => switch (style) {
  1 => AnnotationColor.green,
  2 => AnnotationColor.blue,
  3 => AnnotationColor.rose,
  _ => AnnotationColor.yellow,
};

int? _preferredChapterIndex(List<NativeChapter> chapters, WeReadNote note) {
  final name = _normalize(note.chapterName ?? '');
  if (name.isNotEmpty) {
    for (var i = 0; i < chapters.length; i++) {
      final title = _normalize(chapters[i].title);
      if (title.isEmpty) continue;
      if (title == name || title.contains(name) || name.contains(title)) {
        return i;
      }
    }
  }
  final idx = note.chapterIdx;
  if (idx == null) return null;
  // 接口的 chapterIdx 可能是 0 基也可能是 1 基；两个都试，后续仍会全表搜。
  if (idx >= 0 && idx < chapters.length) return idx;
  final oneBased = idx - 1;
  if (oneBased >= 0 && oneBased < chapters.length) return oneBased;
  return null;
}

({String text, List<int> map}) _normalizeWithMap(String input) {
  final buffer = StringBuffer();
  final map = <int>[];
  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    if (_isIgnorable(char)) continue;
    buffer.write(char.toLowerCase());
    map.add(i);
  }
  return (text: buffer.toString(), map: map);
}

String _normalize(String input) {
  final buffer = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    if (_isIgnorable(char)) continue;
    buffer.write(char.toLowerCase());
  }
  return buffer.toString();
}

/// 匹配时忽略空白与常见标点：不同版本的 EPUB 常把逗号/引号排版成
/// 全角/半角或省略标点，只差这些字符不算「原文找不到」。
bool _isIgnorable(String char) =>
    char == ' ' ||
    char == '\n' ||
    char == '\r' ||
    char == '\t' ||
    char == '\u3000' ||
    char == '\u00a0' ||
    '，。！？；：、,.!?;:"\'“”‘’「」『』（）()【】《》〈〉…—'.contains(char);
