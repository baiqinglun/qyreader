/// 重复书籍检测：按书名强匹配 / 疑似匹配，或按文件内容分组。
///
/// 纯函数，方便单测；页面只负责展示与删除。
library;

import '../../domain/entities/book.dart';

/// 检测类型。
enum DuplicateDetectType {
  /// 按书名。
  title('书名重复'),

  /// 按文件 SHA-256（同一本书的多个副本）。
  file('文件重复');

  const DuplicateDetectType(this.label);

  /// 展示名。
  final String label;
}

/// 匹配范围。
enum DuplicateMatchScope {
  /// 强匹配 + 疑似匹配。
  all('全部', '同时显示强匹配和疑似匹配'),

  /// 只显示强匹配。
  strong('强匹配', '只显示忽略大小写、空白和格式后缀后的同名书'),

  /// 只显示疑似匹配。
  suspected('疑似匹配', '显示忽略版本、括号和卷号等常见噪声后的疑似重复书');

  const DuplicateMatchScope(this.label, this.detail);

  /// 展示名。
  final String label;

  /// 说明。
  final String detail;
}

/// 一组重复书籍。
class DuplicateGroup {
  /// 构造。
  const DuplicateGroup({
    required this.key,
    required this.books,
    required this.strong,
    required this.type,
  });

  /// 组键（忽略/选择用）。
  final String key;

  /// 组内书籍（按加入时间升序）。
  final List<Book> books;

  /// 是否强匹配（书名完全一致 / 文件哈希一致）。
  final bool strong;

  /// 检测类型。
  final DuplicateDetectType type;

  /// 组标题：取最短的书名（通常噪声最少）。
  String get displayTitle {
    var best = books.first.title.trim();
    for (final book in books.skip(1)) {
      final title = book.title.trim();
      if (title.isNotEmpty && title.length < best.length) best = title;
    }
    return best.isEmpty ? '未命名书籍' : best;
  }

  /// 组内最大的文件 id（用于「最大」角标）。
  String? get largestFileId {
    if (books.isEmpty) return null;
    var best = books.first;
    for (final book in books.skip(1)) {
      if (book.fileSize > best.fileSize) best = book;
    }
    return best.id;
  }

  /// 组内字数最多的书 id（用于「最多」角标）。
  String? get mostWordsId {
    if (books.isEmpty) return null;
    var best = books.first;
    for (final book in books.skip(1)) {
      if (book.wordCount > best.wordCount) best = book;
    }
    return best.id;
  }

  /// 建议保留的书：字数最多 → 文件最大 → 加入时间最早。
  Book get keepCandidate {
    final sorted = [...books]
      ..sort((a, b) {
        final words = b.wordCount.compareTo(a.wordCount);
        if (words != 0) return words;
        final size = b.fileSize.compareTo(a.fileSize);
        if (size != 0) return size;
        return a.addedAt.compareTo(b.addedAt);
      });
    return sorted.first;
  }
}

/// 强匹配归一化：忽略大小写、空白、文件扩展名。
String normalizeDuplicateTitleStrong(String raw) {
  var title = raw.trim().toLowerCase();
  title = title.replaceAll(
    RegExp(r'\.(epub|mobi|azw3|azw|txt|md|markdown)$'),
    '',
  );
  title = title.replaceAll(RegExp(r'[\s\u3000]+'), '');
  return title;
}

/// 疑似匹配归一化：再去掉括号内容、卷号、版本词和常见标点。
String normalizeDuplicateTitleLoose(String raw) {
  var title = raw.trim().toLowerCase();
  // 去掉成对括号里的内容（版本、卷册、宣传语等）。
  title = title.replaceAll(RegExp(r'[（(【\[〔<][^）)】\]〕>]*[）)】\]〕>]'), '');
  // 第 N 卷 / 册 / 部 / 集 / 版。
  title = title.replaceAll(RegExp(r'第[0-9一二三四五六七八九十百千万两]+[卷册部集版季]'), '');
  // 全 7 册 / 共 3 卷 / 7 册。
  title = title.replaceAll(
    RegExp(r'(全|共)?[0-9一二三四五六七八九十百千万两]+[卷册部集季](套)?'),
    '',
  );
  // 卷 N。
  title = title.replaceAll(RegExp(r'卷[0-9一二三四五六七八九十百千万两]+'), '');
  // 上 / 中 / 下册。
  title = title.replaceAll(RegExp(r'[上中下]册$'), '');
  // 常见版本词。
  title = title.replaceAll(
    RegExp(
      r'(完结|全本|全集|修订版|新版|增订版|珍藏版|典藏版|精校版|'
      r'未删减|完整版|插图版|epub|mobi|azw3|azw|txt|md|markdown)',
      caseSensitive: false,
    ),
    '',
  );
  title = title.replaceAll(RegExp(r'[\s\u3000]+'), '');
  title = title.replaceAll(
    RegExp(
      r'[《》〈〉「」『』()（）\[\]【】〔〕<>·•:：,，.。!！?？、;；'
      r'''\'"“”‘’_\-—–]''',
    ),
    '',
  );
  return title;
}

/// 作者归一化：去掉空白、标点和「著/编/译」等后缀。
String normalizeDuplicateAuthor(String? raw) {
  var author = (raw ?? '').trim().toLowerCase();
  author = author.replaceAll(RegExp(r'[\s\u3000]+'), '');
  author = author.replaceAll(RegExp(r'(著|编著|主编|编|译|著绘)$'), '');
  author = author.replaceAll(
    RegExp(
      r'[《》〈〉「」『』()（）\[\]【】〔〕<>·•:：,，.。!！?？、;；'
      r'''\'"“”‘’_\-—–]''',
    ),
    '',
  );
  return author;
}

/// 按书名查找重复组（每组至少 2 本）。
List<DuplicateGroup> findDuplicateBookGroups(
  List<Book> books, {
  bool matchAuthor = false,
}) {
  final clusters = <String, List<Book>>{};
  for (final book in books) {
    final title = normalizeDuplicateTitleLoose(book.title);
    if (title.runes.length < 2) continue;
    final author = matchAuthor ? normalizeDuplicateAuthor(book.author) : '';
    // 开启「匹配作者」时，作者必须非空且一致；缺作者不参与分组。
    if (matchAuthor && author.isEmpty) continue;
    final key = '$title\u0000$author';
    clusters.putIfAbsent(key, () => <Book>[]).add(book);
  }

  final groups = <DuplicateGroup>[];
  for (final entry in clusters.entries) {
    final list = entry.value;
    if (list.length < 2) continue;
    final strongKeys = <String>{
      for (final book in list) normalizeDuplicateTitleStrong(book.title),
    };
    groups.add(
      DuplicateGroup(
        key: 'title:${entry.key}',
        books: _sortedByAdded(list),
        strong: strongKeys.length == 1,
        type: DuplicateDetectType.title,
      ),
    );
  }
  return _sortedGroups(groups);
}

/// 按文件哈希查找完全相同的副本。
///
/// 正常导入会按内容去重，这里主要兜底历史数据 / 同步产生的同文件多本书。
List<DuplicateGroup> findDuplicateFileGroups(List<Book> books) {
  final clusters = <String, List<Book>>{};
  for (final book in books) {
    final sha = book.fileSha256.trim().toLowerCase();
    if (sha.isEmpty) continue;
    clusters.putIfAbsent(sha, () => <Book>[]).add(book);
  }
  final groups = <DuplicateGroup>[];
  for (final entry in clusters.entries) {
    if (entry.value.length < 2) continue;
    groups.add(
      DuplicateGroup(
        key: 'file:${entry.key}',
        books: _sortedByAdded(entry.value),
        strong: true,
        type: DuplicateDetectType.file,
      ),
    );
  }
  return _sortedGroups(groups);
}

/// 按范围过滤。
List<DuplicateGroup> filterDuplicateGroups(
  List<DuplicateGroup> groups,
  DuplicateMatchScope scope,
) {
  switch (scope) {
    case DuplicateMatchScope.all:
      return groups;
    case DuplicateMatchScope.strong:
      return [
        for (final g in groups)
          if (g.strong) g,
      ];
    case DuplicateMatchScope.suspected:
      return [
        for (final g in groups)
          if (!g.strong) g,
      ];
  }
}

List<Book> _sortedByAdded(List<Book> books) {
  final sorted = [...books]..sort((a, b) => a.addedAt.compareTo(b.addedAt));
  return sorted;
}

List<DuplicateGroup> _sortedGroups(List<DuplicateGroup> groups) {
  groups.sort((a, b) {
    final byCount = b.books.length.compareTo(a.books.length);
    if (byCount != 0) return byCount;
    return a.displayTitle.compareTo(b.displayTitle);
  });
  return groups;
}
