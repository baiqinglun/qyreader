/// 书签定位键。
library;

import '../../core/locator.dart';

/// 当前页是否可加书签：有 CFI，或有原生排版用的章节/偏移。
///
/// 原生排版（当前唯一实现）不生成 CFI，只回报 href + chapterIndex +
/// offset + page；旧逻辑只认 `locator.cfi`，导致「添加书签」点了没反应。
String? bookmarkKeyFor(Locator? locator) {
  if (locator == null) return null;
  final cfi = locator.cfi;
  if (cfi != null && cfi.isNotEmpty) return 'cfi:$cfi';

  final href = locator.href;
  final chapter = locator.chapterIndex;
  final offset = locator.offset;
  if (href == null && chapter == null && offset == null) return null;

  // 同一章同一页的 offset 就是页首偏移；page 用章内页号区分同偏移的不同页。
  final page = locator.page;
  return 'native:${href ?? ''}|${chapter ?? ''}|${page ?? ''}|${offset ?? ''}';
}
