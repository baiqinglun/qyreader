/// 原生文本模式的 TTS 朗读适配层。
///
/// `TtsPlaybackController` 原本直接依赖 `ReaderBridge`（WebView + epub.js 的
/// CFI 句子）。原生模式下没有 WebView、也没有 CFI，这里用同一套接口
/// （`ttsSegments / ttsShow / ttsClear / ttsNextHref`）把「句子」表达成
/// **章索引 + 字符区间**，编码进 cfi 字符串里（`@章:起:止`），
/// 这样朗读控制器一行都不用改。
library;

import 'package:flutter/foundation.dart';

import '../reader_bridge.dart';
import 'native_chapter_source.dart';

/// 当前朗读高亮（章内字符区间）。
class TtsHighlight {
  const TtsHighlight({
    required this.chapterIndex,
    required this.start,
    required this.end,
  });

  /// 章序号。
  final int chapterIndex;

  /// 起点（章内字符偏移）。
  final int start;

  /// 终点（不含）。
  final int end;

  @override
  bool operator ==(Object other) =>
      other is TtsHighlight &&
      other.chapterIndex == chapterIndex &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(chapterIndex, start, end);
}

/// 句末标点（中英文）。
const String _sentenceEnds = '。！？!?…';

/// 把一章正文切成句子（保留标点，区间连续）。
List<({int start, int end, String text})> splitSentences(String text) {
  final out = <({int start, int end, String text})>[];
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    if (_sentenceEnds.contains(text[i])) {
      // 连续标点（？！…）并到同一句
      var end = i + 1;
      while (end < text.length && _sentenceEnds.contains(text[end])) {
        end++;
      }
      final seg = text.substring(start, end);
      if (seg.trim().isNotEmpty) {
        out.add((start: start, end: end, text: seg.trim()));
      }
      start = end;
      i = end - 1;
    }
  }
  if (start < text.length) {
    final seg = text.substring(start);
    if (seg.trim().isNotEmpty) {
      out.add((start: start, end: text.length, text: seg.trim()));
    }
  }
  return out;
}

/// 原生模式的 TTS 接口实现。
class NativeTtsSurface implements TtsSurface {
  NativeTtsSurface({
    required this.chapters,
    required this.currentChapter,
    required this.currentOffset,
    required this.onHighlight,
    required this.onJumpTo,
  });

  /// 章节文本。
  final List<NativeChapter> chapters;

  /// 当前章序号（由阅读视图实时更新）。
  final int Function() currentChapter;

  /// 当前页首字符偏移（用于「从当前页开始朗读」）。
  final int Function() currentOffset;

  /// 高亮变化回调（null = 清除）。
  final ValueChanged<TtsHighlight?> onHighlight;

  /// 跳转到（章，字符偏移）。
  final void Function(int chapterIdx, int offset) onJumpTo;

  @override
  Future<List<TtsSegment>?> ttsSegments() async {
    final idx = currentChapter();
    if (idx < 0 || idx >= chapters.length) return null;
    final text = chapters[idx].text;
    final from = currentOffset().clamp(0, text.length);
    // 从当前页首开始，避免朗读已经读过的句子
    final segs = splitSentences(text)
        .where((s) => s.end > from)
        .map((s) => TtsSegment(cfi: '@$idx:${s.start}:${s.end}', text: s.text))
        .toList();
    return segs;
  }

  @override
  Future<String?> ttsShow(String cfiRange) async {
    final parsed = _parse(cfiRange);
    if (parsed == null) return 'bad-cfi';
    final (chapterIdx, start, end) = parsed;
    if (chapterIdx < 0 || chapterIdx >= chapters.length) return 'bad-chapter';
    final text = chapters[chapterIdx].text;
    final s = start.clamp(0, text.length);
    final e = end.clamp(s, text.length);
    // 当前不在这一章 → 先跳章；返回 turning 让控制器稍后再高亮
    if (chapterIdx != currentChapter()) {
      onJumpTo(chapterIdx, s);
      onHighlight(TtsHighlight(chapterIndex: chapterIdx, start: s, end: e));
      return 'turning';
    }
    onHighlight(TtsHighlight(chapterIndex: chapterIdx, start: s, end: e));
    onJumpTo(chapterIdx, s); // 同一章：必要时翻到该句所在页
    return 'visible';
  }

  @override
  Future<void> ttsClear() async => onHighlight(null);

  @override
  Future<String?> ttsNextHref() async {
    final idx = currentChapter();
    if (idx < 0 || idx + 1 >= chapters.length) return null;
    // 原生模式直接给下一章的「章索引」编码，控制器只需原样传回
    return '@${idx + 1}:0:0';
  }

  @override
  Future<void> gotoChapter(String target) async {
    final parsed = _parse(target);
    if (parsed == null) return;
    onJumpTo(parsed.$1, parsed.$2);
  }

  /// `@章:起:止` → (章, 起, 止)。
  (int, int, int)? _parse(String raw) {
    if (!raw.startsWith('@')) return null;
    final parts = raw.substring(1).split(':');
    if (parts.length != 3) return null;
    final c = int.tryParse(parts[0]);
    final s = int.tryParse(parts[1]);
    final e = int.tryParse(parts[2]);
    if (c == null || s == null || e == null) return null;
    return (c, s, e);
  }
}
