/// 覆盖导入后的笔记位置匹配。
///
/// 场景：微信读书 / Reeden 导入的占位书只有书名页，笔记先落在章首；用户
/// 后来拿到真正的 EPUB，用书架长按 →「覆盖导入」替换正文。这里按笔记原文
/// 在新章节里重新找位置：
///
/// 1. 先用完整原文搜索（精确 → 忽略空白/标点）；
/// 2. 找不到就一点点减少两端的字（先按 1..24 个字递减，再按比例缩到更短），
///    每次仍先精确再忽略标点，直到匹配到一段够用的文字；
/// 3. 优先在原来的章里找，避免同样的句子在多章出现时跳错地方。
library;

import 'dart:convert';

import '../../core/locator.dart';
import '../../domain/entities/annotation.dart';
import '../../domain/repositories/annotation_repository.dart';
import 'native/native_chapter_source.dart';

/// 一条笔记在新书里的落点。
class NoteAnchorUpdate {
  /// 构造。
  const NoteAnchorUpdate({
    required this.annotationId,
    required this.chapterIndex,
    required this.href,
    required this.start,
    required this.end,
    required this.locatorStart,
    required this.locatorEnd,
  });

  /// 标注 id。
  final String annotationId;

  /// 章序号（0 基）。
  final int chapterIndex;

  /// 章 href。
  final String href;

  /// 章内起始偏移。
  final int start;

  /// 章内结束偏移（不含）。
  final int end;

  /// 新的 locatorStart JSON。
  final String locatorStart;

  /// 新的 locatorEnd JSON（与 start 同一区间，保持旧数据语义）。
  final String locatorEnd;
}

/// 一次笔记匹配的结果。
class NoteRematchPlan {
  /// 构造。
  const NoteRematchPlan({
    required this.total,
    required this.matched,
    required this.updates,
  });

  /// 有原文、可参与匹配的笔记条数。
  final int total;

  /// 成功找到新位置的笔记条数（含锚点本来就正确的）。
  final int matched;

  /// 需要写库的锚点（已经在新位置的不重复写）。
  final List<NoteAnchorUpdate> updates;

  /// 没找到的条数（保持原位置）。
  int get unmatched => total - matched;
}

/// 计算每一条笔记在新章节里的位置（纯函数，不落库，方便单测）。
NoteRematchPlan planNoteRematch(
  List<Annotation> annotations,
  List<NativeChapter> chapters,
) {
  final locator = NoteLocator(chapters);
  final updates = <NoteAnchorUpdate>[];
  var total = 0;
  var matched = 0;
  for (final annotation in annotations) {
    final quote = (annotation.quotedText ?? '').trim();
    if (quote.isEmpty) continue;
    total++;
    final old = locatorFromJson(annotation.locatorStart);
    final match = locator.locate(
      quote,
      preferredChapterIndex: old?.chapterIndex,
      preferredHref: old?.href,
    );
    if (match == null) continue;
    matched++;
    final json = locatorToJson(
      Locator(
        href: match.href,
        chapterIndex: match.chapterIndex,
        offset: match.start,
        offsetEnd: match.end,
      ),
    );
    // 已经在这个位置：不重复写库 / 不刷同步日志。
    if (annotation.locatorStart == json && annotation.locatorEnd == json) {
      continue;
    }
    updates.add(
      NoteAnchorUpdate(
        annotationId: annotation.id,
        chapterIndex: match.chapterIndex,
        href: match.href,
        start: match.start,
        end: match.end,
        locatorStart: json,
        locatorEnd: json,
      ),
    );
  }
  return NoteRematchPlan(total: total, matched: matched, updates: updates);
}

/// 匹配并写回笔记锚点；返回本次的匹配统计。
Future<NoteRematchPlan> rematchBookNotes({
  required List<Annotation> annotations,
  required List<NativeChapter> chapters,
  required AnnotationRepository repository,
  void Function(int done, int total)? onProgress,
}) async {
  final plan = planNoteRematch(annotations, chapters);
  var done = 0;
  for (final update in plan.updates) {
    await repository.setAnchor(
      update.annotationId,
      update.locatorStart,
      locatorEnd: update.locatorEnd,
    );
    done++;
    onProgress?.call(done, plan.updates.length);
  }
  return plan;
}

/// 判断一条标注在当前书里是否已有可用的定位。
///
/// 占位书导出的笔记常是「章首 0..0」；覆盖导入后如果没匹配到，锚点仍是旧
/// 位置。这里用锚点处的正文和 `quotedText` 对照：对不上就算未定位，标注
/// 列表据此提供「自动查询 / 手动定位」。
///
/// 手动定位写回的 locator 带 `manual: true`（用户自己确认过），不再做原文
/// 对照，直接视为已定位。
bool annotationAnchorLocated(
  Annotation annotation,
  List<NativeChapter> chapters,
) {
  if (chapters.isEmpty) return false;
  final loc = locatorFromJson(annotation.locatorStart);
  if (loc == null) return false;
  final chapter = nativeChapterForLocator(chapters, loc);
  if (chapter == null || chapter.text.isEmpty) return false;
  final start = loc.offset;
  final end = loc.offsetEnd;
  if (start == null ||
      end == null ||
      start < 0 ||
      end <= start ||
      start >= chapter.text.length) {
    return false;
  }
  final safeEnd = end > chapter.text.length ? chapter.text.length : end;
  if (safeEnd <= start) return false;
  if (_isManualLocator(annotation.locatorStart)) return true;

  final quote = (annotation.quotedText ?? '').trim();
  if (quote.isEmpty) return true;
  // 自动匹配允许只匹配原文中间一段（逐字缩短），所以用包含关系而不是
  // 完全相等；太短的片段（1~3 字）容易误判，至少要求 min(4, 原文长度)。
  final slice = _normalize(chapter.text.substring(start, safeEnd));
  final normalizedQuote = _normalize(quote);
  if (slice.isEmpty || normalizedQuote.isEmpty) return false;
  final minLength = normalizedQuote.length < 4 ? normalizedQuote.length : 4;
  if (slice.length < minLength) return false;
  return slice == normalizedQuote ||
      normalizedQuote.contains(slice) ||
      slice.contains(normalizedQuote);
}

bool _isManualLocator(String raw) {
  try {
    final json = jsonDecode(raw);
    return json is Map && json['manual'] == true;
  } catch (_) {
    return false;
  }
}

/// 一次匹配命中的区间。
class NoteMatch {
  /// 构造。
  const NoteMatch({
    required this.chapterIndex,
    required this.href,
    required this.start,
    required this.end,
  });

  /// 章序号。
  final int chapterIndex;

  /// 章 href。
  final String href;

  /// 章内起始偏移。
  final int start;

  /// 章内结束偏移。
  final int end;
}

/// 带缓存的原文定位器（同一本书的笔记共用一个实例，归一化文本只建一次）。
class NoteLocator {
  /// 构造。
  NoteLocator(this.chapters);

  /// 新书的章节。
  final List<NativeChapter> chapters;

  final Map<int, _NormalizedText> _normalized = {};

  /// 在 [chapters] 里定位 [quote]；找不到返回 null。
  ///
  /// [preferredChapterIndex] / [preferredHref] 来自旧 locator：先在同一章
  /// 里找，再搜全书。
  NoteMatch? locate(
    String quote, {
    int? preferredChapterIndex,
    String? preferredHref,
  }) {
    final raw = quote.trim();
    if (raw.isEmpty || chapters.isEmpty) return null;
    final preferred = _resolvePreferred(preferredChapterIndex, preferredHref);
    final order = _chapterOrder(preferred);

    // 1) 完整原文：先精确，再忽略空白/标点。
    final fullExact = _findExact(raw, order);
    if (fullExact != null) return fullExact;
    final fullNormalized = _findNormalized(raw, order);
    if (fullNormalized != null) return fullNormalized;

    // 2) 一点点减少两端的字，直到找到一段能对上的原文。
    for (final candidate in _shorterCandidates(raw)) {
      final exact = _findExact(candidate, order);
      if (exact != null) return exact;
      final normalized = _findNormalized(candidate, order);
      if (normalized != null) return normalized;
    }
    return null;
  }

  NoteMatch? _findExact(String candidate, List<int> order) {
    for (final index in order) {
      final chapter = chapters[index];
      final at = chapter.text.indexOf(candidate);
      if (at < 0) continue;
      return NoteMatch(
        chapterIndex: index,
        href: chapter.href,
        start: at,
        end: at + candidate.length,
      );
    }
    return null;
  }

  NoteMatch? _findNormalized(String candidate, List<int> order) {
    final normalizedQuote = _normalize(candidate);
    if (normalizedQuote.isEmpty) return null;
    for (final index in order) {
      final normalized = _normalizedOf(index);
      final at = normalized.text.indexOf(normalizedQuote);
      if (at < 0) continue;
      return NoteMatch(
        chapterIndex: index,
        href: chapters[index].href,
        start: normalized.map[at],
        end: normalized.map[at + normalizedQuote.length - 1] + 1,
      );
    }
    return null;
  }

  _NormalizedText _normalizedOf(int index) =>
      _normalized[index] ??= _normalizeWithMap(chapters[index].text);

  List<int> _chapterOrder(int? preferred) => <int>[
    if (preferred != null) preferred,
    for (var i = 0; i < chapters.length; i++)
      if (i != preferred) i,
  ];

  int? _resolvePreferred(int? index, String? href) {
    final indexValid = index != null && index >= 0 && index < chapters.length;
    if (indexValid && (href == null || chapters[index].href == href)) {
      return index;
    }
    if (href != null) {
      for (var i = 0; i < chapters.length; i++) {
        if (chapters[i].href == href) return i;
      }
    }
    return indexValid ? index : null;
  }

  /// 缩短候选：先每次少 1 个字（最多 24 次），再按比例和固定短长度兜底。
  ///
  /// 取中间窗口而不是只留开头：原文两端任意一侧多出/少掉字符都能对上。
  static List<String> _shorterCandidates(String quote) {
    final runes = quote.runes.toList();
    if (runes.length <= 4) return const [];
    final lengths = <int>{};
    for (var cut = 1; cut <= 24 && runes.length - cut >= 4; cut++) {
      lengths.add(runes.length - cut);
    }
    for (final ratio in const [0.75, 0.5, 0.35, 0.25]) {
      final n = (runes.length * ratio).round();
      if (n >= 4 && n < runes.length) lengths.add(n);
    }
    for (final n in const [16, 12, 8, 6, 4]) {
      if (n < runes.length) lengths.add(n);
    }
    final ordered = lengths.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final n in ordered)
        String.fromCharCodes(
          runes.sublist((runes.length - n) ~/ 2, (runes.length - n) ~/ 2 + n),
        ),
    ];
  }
}

class _NormalizedText {
  const _NormalizedText(this.text, this.map);

  final String text;
  final List<int> map;
}

/// 归一化并保留「归一化字符 → 原文下标」映射（还原高亮范围用）。
_NormalizedText _normalizeWithMap(String input) {
  final buffer = StringBuffer();
  final map = <int>[];
  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    if (_isIgnorable(char)) continue;
    buffer.write(char.toLowerCase());
    map.add(i);
  }
  return _NormalizedText(buffer.toString(), map);
}

/// 只用于搜索的归一化（忽略空白与常见中英文标点）。
String _normalize(String input) {
  final buffer = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    if (_isIgnorable(char)) continue;
    buffer.write(char.toLowerCase());
  }
  return buffer.toString();
}

bool _isIgnorable(String char) =>
    char == ' ' ||
    char == '\n' ||
    char == '\r' ||
    char == '\t' ||
    char == '\u3000' ||
    char == '\u00a0' ||
    '，。！？；：、,.!?;:"\'“”‘’「」『』（）()【】《》〈〉…—'.contains(char);
