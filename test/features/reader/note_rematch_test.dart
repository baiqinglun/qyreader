/// 覆盖导入 / 阅读器兜底定位共用的笔记原文匹配。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/locator.dart';
import 'package:qy_reader/domain/entities/annotation.dart';
import 'package:qy_reader/features/reader/native/native_chapter_source.dart';
import 'package:qy_reader/features/reader/note_rematch.dart';

NativeChapter _chapter(int idx, String text) => NativeChapter.fromCompact(
  idx: idx,
  title: '第 ${idx + 1} 章',
  href: 'c$idx.xhtml',
  text: text,
  paragraphStarts: const [0],
  paragraphLevels: const [0],
  paragraphCentered: const [false],
);

Annotation _note({
  required String id,
  required String quote,
  int? chapterIndex,
  int? offset,
  int? offsetEnd,
}) {
  final json = locatorToJson(
    Locator(chapterIndex: chapterIndex, offset: offset, offsetEnd: offsetEnd),
  );
  return Annotation(
    id: id,
    bookId: 'b1',
    type: AnnotationType.highlight,
    color: AnnotationColor.yellow,
    locatorStart: json,
    locatorEnd: json,
    quotedText: quote,
    createdAt: 0,
    updatedAt: 0,
  );
}

Annotation _noteAt(String quote, int start, int end, {bool manual = false}) {
  final json = jsonEncode(<String, dynamic>{
    'v': 1,
    'href': 'c0.xhtml',
    'chapterIndex': 0,
    'offset': start,
    'offsetEnd': end,
    if (manual) 'manual': true,
  });
  return Annotation(
    id: 'a1',
    bookId: 'b1',
    type: AnnotationType.highlight,
    color: AnnotationColor.yellow,
    locatorStart: json,
    locatorEnd: json,
    quotedText: quote,
    createdAt: 0,
    updatedAt: 0,
  );
}

void main() {
  group('NoteLocator', () {
    test('完整原文精确命中，范围与原文一致', () {
      final chapters = [_chapter(0, '前面的话。轻舟已过万重山。后面的话。')];
      final match = NoteLocator(chapters).locate('轻舟已过万重山');
      expect(match, isNotNull);
      expect(match!.chapterIndex, 0);
      expect(match.start, 5);
      expect(match.end, 12);
    });

    test('优先在旧章里找：多章出现同一句时不会跳到第一处', () {
      final chapters = [_chapter(0, '重复的句子。'), _chapter(1, '前面。重复的句子。后面。')];
      final match = NoteLocator(
        chapters,
      ).locate('重复的句子', preferredChapterIndex: 1);
      expect(match!.chapterIndex, 1);
      expect(match.start, 3);
    });

    test('忽略空白与标点后仍能定位，并还原到原文范围', () {
      final chapters = [_chapter(0, '轻舟已过万重山。')];
      final match = NoteLocator(chapters).locate('轻舟，已过 万重山！');
      expect(match, isNotNull);
      expect(match!.start, 0);
      expect(match.end, 7);
    });

    test('完整原文搜不到时，一点点减少两端的字继续匹配', () {
      const body = '正文里有一句非常重要的话需要找回来。';
      final chapters = [_chapter(0, '开头。$body结尾。')];
      final match = NoteLocator(chapters).locate('多余前缀$body多余后缀');
      expect(match, isNotNull);
      final bodyStart = '开头。'.length;
      expect(match!.start, bodyStart);
      expect(match.end, bodyStart + body.length);
    });

    test('旧章索引越界也继续搜全书（章节重排后仍能定位）', () {
      final chapters = [_chapter(0, '新的第一章。轻舟已过万重山。')];
      final match = NoteLocator(
        chapters,
      ).locate('轻舟已过万重山', preferredChapterIndex: 99);
      expect(match, isNotNull);
      expect(match!.chapterIndex, 0);
    });

    test('实在找不到返回 null（保持原位置）', () {
      final chapters = [_chapter(0, '这里只有一段完全不同的文字。')];
      expect(NoteLocator(chapters).locate('另一本书里的一句话'), isNull);
    });
  });

  group('planNoteRematch', () {
    test('只统计有原文的笔记；已在新位置的不重复写', () {
      final chapters = [_chapter(0, '轻舟已过万重山。')];
      final correct = locatorToJson(
        const Locator(
          href: 'c0.xhtml',
          chapterIndex: 0,
          offset: 0,
          offsetEnd: 7,
        ),
      );
      final oldJson = locatorToJson(
        const Locator(chapterIndex: 0, offset: 0, offsetEnd: 0),
      );
      final notes = [
        Annotation(
          id: 'a1',
          bookId: 'b1',
          type: AnnotationType.highlight,
          color: AnnotationColor.yellow,
          locatorStart: oldJson,
          locatorEnd: oldJson,
          quotedText: '轻舟已过万重山',
          createdAt: 0,
          updatedAt: 0,
        ),
        Annotation(
          id: 'a2',
          bookId: 'b1',
          type: AnnotationType.note,
          color: AnnotationColor.yellow,
          locatorStart: correct,
          locatorEnd: correct,
          quotedText: '轻舟已过万重山',
          createdAt: 0,
          updatedAt: 0,
        ),
        _note(id: 'a3', quote: '   '),
      ];

      final plan = planNoteRematch(notes, chapters);
      expect(plan.total, 2);
      expect(plan.matched, 2); // a2 锚点本来就正确，也算匹配成功
      expect(plan.updates.single.annotationId, 'a1');
      expect(plan.updates.single.start, 0);
      expect(plan.updates.single.end, 7);
      expect(plan.unmatched, 0);
    });

    test('按旧 locator 的章优先匹配', () {
      final chapters = [_chapter(0, '无关内容。'), _chapter(1, '这里有一句需要定位的话。')];
      final plan = planNoteRematch([
        _note(
          id: 'a1',
          quote: '需要定位的话',
          chapterIndex: 1,
          offset: 0,
          offsetEnd: 0,
        ),
      ], chapters);
      expect(plan.updates.single.chapterIndex, 1);
      expect(plan.updates.single.href, 'c1.xhtml');
      expect(plan.updates.single.locatorStart, contains('"chapterIndex":1'));
    });
  });

  group('annotationAnchorLocated', () {
    final chapters = [_chapter(0, '轻舟已过万重山。')];

    test('章首 0..0 的占位锚点算未定位', () {
      expect(
        annotationAnchorLocated(_noteAt('轻舟已过万重山', 0, 0), chapters),
        isFalse,
      );
    });

    test('锚点处正文与原文一致算已定位', () {
      expect(
        annotationAnchorLocated(_noteAt('轻舟已过万重山', 0, 7), chapters),
        isTrue,
      );
    });

    test('只匹配到原文中间一段也算已定位（覆盖导入的逐字缩短）', () {
      expect(
        annotationAnchorLocated(_noteAt('轻舟已过万重山。', 2, 6), chapters),
        isTrue,
      );
    });

    test('锚点处正文对不上算未定位', () {
      expect(annotationAnchorLocated(_noteAt('另一句话', 0, 4), chapters), isFalse);
    });

    test('手动定位带 manual 标记，不再按原文校验', () {
      expect(
        annotationAnchorLocated(_noteAt('另一句话', 0, 4, manual: true), chapters),
        isTrue,
      );
    });
  });
}
