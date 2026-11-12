/// 分页自检、测量缓存复用与保守回退的单测。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/data/parsers/epub/epub_parser.dart';
import 'package:qy_reader/features/reader/native/native_chapter_source.dart';
import 'package:qy_reader/features/reader/native/native_paginator.dart';
import 'package:qy_reader/features/reader/reader_settings.dart';

NativeChapter _chapter() => NativeChapter.fromBlocks(
      idx: 0,
      title: '第一章',
      href: 'c1.xhtml',
      blocks: <ParsedBlock>[
        const ParsedBlock(text: '第一章 开端', level: 1),
        for (var i = 0; i < 30; i++)
          ParsedBlock(
            text: '这是第$i段正文，用来验证分页自检与测量缓存。'
                '在秋日午后的光线里，我数着归途上的每一片叶子。',
          ),
      ],
      fallbackText: '',
    );

ReaderTypeSpec _spec({
  double fontSize = 18,
  double lineHeight = 1.7,
  double paragraphSpacing = 0.4,
}) =>
    ReaderTypeSpec.fromSettings(
      ReadingSettings(
        fontSize: fontSize,
        lineHeight: lineHeight,
        paragraphSpacing: paragraphSpacing,
      ),
      ReadingTheme.paper,
    );

void main() {
  group('分页自检', () {
    test('合法分页通过：字符守恒 + 页间连续 + 页高不溢出', () {
      final chapter = _chapter();
      final spec = _spec();
      final layout = ChapterLayout.build(chapter: chapter, spec: spec);
      final paginator = NativePaginator();
      final measurement = paginator.measurementFor(
        layout: layout,
        chapterIdx: 0,
        width: 220,
        textScale: 1,
      );
      final pagination = measurement.packAllExact(
        layout,
        maxHeight: 120,
        width: 220,
        textScale: 1,
      );
      expect(
        PaginationValidator.validate(
          pagination: pagination,
          layout: layout,
          maxHeight: 120,
          width: 220,
          textScale: 1,
        ),
        isTrue,
      );
    });

    test('页首非 0 / 页首不递增 / 页首越界都判失败', () {
      final chapter = _chapter();
      final layout = ChapterLayout.build(chapter: chapter, spec: _spec());
      bool validate(List<int> starts, {double maxHeight = 200}) =>
          PaginationValidator.validate(
            pagination: Pagination(
              starts: starts,
              textLength: layout.displayText.length,
            ),
            layout: layout,
            maxHeight: maxHeight,
            width: 220,
            textScale: 1,
          );
      expect(validate(const [1, 10, 20]), isFalse);
      expect(validate([0, 20, 10]), isFalse);
      expect(validate([0, layout.displayText.length]), isFalse);
      // 单页（整章一页）只有在页高够大时合法
      expect(validate(const [0]), isFalse);
      expect(validate(const [0], maxHeight: 100000), isTrue);
    });

    test('页高溢出判失败（触发保守重排）', () {
      final chapter = _chapter();
      final layout = ChapterLayout.build(chapter: chapter, spec: _spec());
      // 用极小的页高装箱：每页只强放一行，必然溢出 → 自检失败。
      final task = PaginationTask(
        paginator: NativePaginator(),
        layout: layout,
        key: const PaginationKey(
          chapterIdx: 0,
          width: 220,
          height: 1,
          textScale: 1,
          signature: 0,
        ),
        measurement: NativePaginator().measurementFor(
          layout: layout,
          chapterIdx: 0,
          width: 220,
          textScale: 1,
        ),
      );
      var guard = 0;
      while (!task.done && guard++ < 1000) {
        task.advance(const Duration(milliseconds: 5));
      }
      expect(task.done, isTrue);
      expect(task.usedSafeFallback, isTrue);
      expect(task.result, isNotNull);
    });
  });

  group('测量与装箱分离', () {
    test('改段距复用测量（只重装箱）；改字号必须重测', () {
      final chapter = _chapter();
      final baseSpec = _spec();
      final spacingSpec = _spec(paragraphSpacing: 1.6);
      final fontSpec = _spec(fontSize: 22);
      final baseLayout = ChapterLayout.build(chapter: chapter, spec: baseSpec);
      final spacingLayout =
          ChapterLayout.build(chapter: chapter, spec: spacingSpec);
      final fontLayout = ChapterLayout.build(chapter: chapter, spec: fontSpec);

      final paginator = NativePaginator();
      final base = paginator.measurementFor(
        layout: baseLayout,
        chapterIdx: 0,
        width: 220,
        textScale: 1,
      );
      final same = paginator.measurementFor(
        layout: spacingLayout,
        chapterIdx: 0,
        width: 220,
        textScale: 1,
      );
      final resized = paginator.measurementFor(
        layout: fontLayout,
        chapterIdx: 0,
        width: 220,
        textScale: 1,
      );
      expect(identical(base, same), isTrue,
          reason: '段距不影响断行与行高，测量应复用');
      expect(identical(base, resized), isFalse,
          reason: '字号变了必须重新测量');

      // 段距变化后重新装箱，页数应不同（间距变大页数不会减少）。
      final tight = base.packAllExact(
        baseLayout,
        maxHeight: 160,
        width: 220,
        textScale: 1,
      );
      final loose = same.packAllExact(
        spacingLayout,
        maxHeight: 160,
        width: 220,
        textScale: 1,
      );
      expect(loose.pageCount, greaterThanOrEqualTo(tight.pageCount));
    });
  });
}
