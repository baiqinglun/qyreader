/// 微信读书划线定位：精确匹配、忽略空白、章节偏好与颜色映射。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/annotation.dart';
import 'package:qy_reader/features/reader/native/native_chapter_source.dart';
import 'package:qy_reader/features/settings/weread/weread_anchor.dart';
import 'package:qy_reader/features/settings/weread/weread_models.dart';

void main() {
  NativeChapter chapter(int idx, String title, String text) {
    return NativeChapter.fromCompact(
      idx: idx,
      title: title,
      href: 'ch$idx.xhtml',
      text: text,
      paragraphStarts: const <int>[0],
      paragraphLevels: const <int>[0],
      paragraphCentered: const <bool>[false],
    );
  }

  test('精确匹配：优先按章节标题落到对应章', () {
    final chapters = <NativeChapter>[
      chapter(0, '第一章', '开头没有这句话。'),
      chapter(1, '第二章', '山川湖海，日月星辰。'),
    ];
    final anchor = locateWeReadNote(
      chapters,
      const WeReadNote(
        id: 'm1',
        bookId: 'r1',
        quote: '日月星辰',
        chapterName: '第二章',
      ),
    );

    expect(anchor, isNotNull);
    expect(anchor!.chapterIndex, 1);
    expect(anchor.href, 'ch1.xhtml');
    expect(anchor.start, 5);
    expect(anchor.end, 9);
  });

  test('忽略空白：划线原文与本机排版换行不同也能定位', () {
    final chapters = <NativeChapter>[chapter(0, '第一章', '山川 湖海\n日月星辰')];
    final anchor = locateWeReadNote(
      chapters,
      const WeReadNote(id: 'm1', bookId: 'r1', quote: '山川湖海'),
    );

    expect(anchor, isNotNull);
    expect(anchor!.start, 0);
    expect(anchor.end, 5);
  });

  test('章节标题对不上时继续全表搜，chapterIdx 只作偏好', () {
    final chapters = <NativeChapter>[
      chapter(0, '第一章', '无关内容'),
      chapter(1, '第二章', '目标句子在这里'),
      chapter(2, '第三章', '也无关'),
    ];
    final anchor = locateWeReadNote(
      chapters,
      const WeReadNote(id: 'm1', bookId: 'r1', quote: '目标句子', chapterIdx: 3),
    );

    expect(anchor, isNotNull);
    expect(anchor!.chapterIndex, 1);
  });

  test('找不到原文返回 null，不瞎标位置', () {
    final chapters = <NativeChapter>[chapter(0, '第一章', '完全不同的正文')];
    final anchor = locateWeReadNote(
      chapters,
      const WeReadNote(id: 'm1', bookId: 'r1', quote: '不存在的句子'),
    );

    expect(anchor, isNull);
  });

  test('忽略标点差异：全角/半角逗号不影响定位', () {
    final chapters = <NativeChapter>[chapter(0, '第一章', '山川湖海，日月星辰。')];
    final anchor = locateWeReadNote(
      chapters,
      const WeReadNote(id: 'm1', bookId: 'r1', quote: '山川,湖海'),
    );

    expect(anchor, isNotNull);
    expect(anchor!.chapterIndex, 0);
    expect(anchor.start, 0);
  });

  test('原文找不到时兜底到对齐章节开头，不丢这条划线', () {
    final chapters = <NativeChapter>[
      chapter(0, '第一章', '无关内容'),
      chapter(1, '第二章', '另一种排版'),
    ];
    final fallback = locateWeReadNoteFallback(
      chapters,
      const WeReadNote(
        id: 'm1',
        bookId: 'r1',
        quote: '原文完全对不上',
        chapterName: '第二章',
      ),
    );

    expect(fallback, isNotNull);
    expect(fallback!.chapterIndex, 1);
    expect(fallback.start, 0);
  });

  test('百分比按章节正文长度换算落点（不依赖 DB 的 char_count）', () {
    final chapters = <NativeChapter>[
      chapter(0, '第一章', 'a' * 100),
      chapter(1, '第二章', 'b' * 200),
      chapter(2, '第三章', 'c' * 300),
    ];
    final anchor = locatePercentInChapters(chapters, 0.4);

    expect(anchor, isNotNull);
    expect(anchor!.chapterIndex, 1);
    expect(anchor.start, 140);
    expect(anchor.end, 140);
  });

  test('颜色样式映射：未知值回退黄色', () {
    expect(colorForWeReadStyle(0), AnnotationColor.yellow);
    expect(colorForWeReadStyle(1), AnnotationColor.green);
    expect(colorForWeReadStyle(2), AnnotationColor.blue);
    expect(colorForWeReadStyle(3), AnnotationColor.rose);
    expect(colorForWeReadStyle(null), AnnotationColor.yellow);
    expect(colorForWeReadStyle(99), AnnotationColor.yellow);
  });
}
