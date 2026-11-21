/// TTS 切句：句末标点后的闭合引号/括号并回本句，不剩半截引号。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/reader/native/native_tts_surface.dart';

void main() {
  List<String> texts(String s) =>
      splitSentences(s).map((e) => e.text).toList();

  test('半角引号：闭合引号并回本句', () {
    expect(texts('你说："很好吃。"'), ['你说："很好吃。"']);
  });

  test('全角弯引号：同上；引语与叙述自然分成两句', () {
    expect(texts('她说："走吧！"'), ['她说："走吧！"']);
    expect(texts('“很好吃。”他点点头。'), ['“很好吃。”', '他点点头。']);
  });

  test('引号后还有句末标点（交错）一并吞掉', () {
    expect(texts('他说："完了。"……'), ['他说："完了。"……']);
  });

  test('括号 / 书名号收尾', () {
    expect(texts('（真的吗？）他问。'), ['（真的吗？）', '他问。']);
    expect(texts('这段出自《背影》。后来……'), ['这段出自《背影》。', '后来……']);
  });

  test('普通句子不受影响，连续标点仍并一句', () {
    expect(texts('第一句。第二句。'), ['第一句。', '第二句。']);
    expect(texts('真的？！'), ['真的？！']);
  });

  test('区间连续且覆盖到闭合引号（高亮用）', () {
    final segs = splitSentences('你说："很好吃。"');
    expect(segs, hasLength(1));
    expect(segs.single.start, 0);
    expect(segs.single.end, '你说："很好吃。"'.length);
  });
}
