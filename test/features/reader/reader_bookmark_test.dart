/// 书签定位：原生排版没有 CFI 也要能加书签。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/locator.dart';
import 'package:qy_reader/features/reader/reader_bookmark.dart';

void main() {
  test('原生 locator（无 CFI）也能得到书签键', () {
    final loc = Locator(
      href: 'chapter-1.xhtml',
      chapterIndex: 2,
      offset: 1280,
      page: 3,
      pages: 9,
    );
    expect(bookmarkKeyFor(loc), 'native:chapter-1.xhtml|2|3|1280');
  });

  test('同一页的键稳定，换页后键不同', () {
    final a = Locator(
      href: 'chapter-1.xhtml',
      chapterIndex: 2,
      offset: 1280,
      page: 3,
    );
    final same = Locator(
      href: 'chapter-1.xhtml',
      chapterIndex: 2,
      offset: 1280,
      page: 3,
      percent: 0.5,
    );
    final next = Locator(
      href: 'chapter-1.xhtml',
      chapterIndex: 2,
      offset: 1800,
      page: 4,
    );
    expect(bookmarkKeyFor(a), bookmarkKeyFor(same));
    expect(bookmarkKeyFor(a), isNot(bookmarkKeyFor(next)));
  });

  test('CFI 优先，且空 locator 不可加书签', () {
    expect(bookmarkKeyFor(const Locator(cfi: 'epubcfi(/6/2)')), 'cfi:epubcfi(/6/2)');
    expect(bookmarkKeyFor(const Locator()), isNull);
    expect(bookmarkKeyFor(null), isNull);
  });
}
