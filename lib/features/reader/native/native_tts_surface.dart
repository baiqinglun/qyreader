/// TTS 切句与高亮数据（原生的「句子」= 章索引 + 字符区间）。
///
/// 全局听书控制器（tts/tts_playback.dart）直接用这里的 [splitSentences]
/// 与 [TtsHighlight]；旧的 `NativeTtsSurface` 桥接层已随「控制器全局化」
/// 移除。
library;

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

/// 句末标点后的收尾字符：闭合引号 / 括号 / 书名号等要并回本句，
/// 否则 `你说："很好吃。"` 闭合引号会被切成下一"句"（只有半个引号）。
const String _sentenceClosers =
    '\'"\u2019\u201d\u300d\u300f\u3009\u300b'
    '\u3011\u3015\u301b\u3017\uff09\uff3d\uff5d>)\\]}';

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
      // 闭合引号/括号跟句末标点并回同一句；引号后如果还有句末标点
      // （如 `。"…`）继续吞（引号与标点的交错顺序不定）
      while (true) {
        while (end < text.length && _sentenceClosers.contains(text[end])) {
          end++;
        }
        if (end < text.length && _sentenceEnds.contains(text[end])) {
          end++;
          continue;
        }
        break;
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
