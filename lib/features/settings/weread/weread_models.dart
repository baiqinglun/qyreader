/// 微信读书同步用的数据模型。
///
/// 官方 Agent API Gateway 把「书架 / 笔记本概览 / 阅读进度 / 划线想法」
/// 拆成多个接口；这里统一收敛成 [WeReadBook] + [WeReadNote]，页面与
/// 对比逻辑只消费这份视图，不直接碰接口 JSON。
library;

/// 微信读书书架里的一本书（合并书架、笔记本概览、阅读进度后的视图）。
class WeReadBook {
  /// 构造。
  const WeReadBook({
    required this.bookId,
    required this.title,
    this.author,
    this.cover,
    this.category,
    this.readerLink,
    this.deepLink,
    this.finished = false,
    this.secret = false,
    this.isTop = false,
    this.readUpdateTime,
    this.updateTime,
    this.progressPercent,
    this.readingSeconds,
    this.finishTime,
    this.noteCount = 0,
    this.reviewCount = 0,
    this.bookmarkCount = 0,
  });

  /// 微信读书 bookId。
  final String bookId;

  /// 书名。
  final String title;

  /// 作者。
  final String? author;

  /// 封面 URL。
  final String? cover;

  /// 分类。
  final String? category;

  /// 阅读器深链。
  final String? readerLink;

  /// 书籍详情深链。
  final String? deepLink;

  /// 是否读完。
  final bool finished;

  /// 是否私密阅读。
  final bool secret;

  /// 是否置顶。
  final bool isTop;

  /// 最近阅读时间（Unix 秒）。
  final int? readUpdateTime;

  /// 书籍更新时间（Unix 秒）。
  final int? updateTime;

  /// 阅读进度（0..100）。
  final int? progressPercent;

  /// 累计阅读时长（秒）。
  final int? readingSeconds;

  /// 读完时间（Unix 秒）。
  final int? finishTime;

  /// 划线数。
  final int noteCount;

  /// 想法/点评数。
  final int reviewCount;

  /// 书签数。
  final int bookmarkCount;

  /// 最近阅读时间（Unix 秒）：优先用阅读进度接口的 updateTime，
  /// 书架接口的 readUpdateTime 兜底。
  int? get lastReadAt => readUpdateTime;

  /// 笔记总数（划线 + 想法/点评）。
  int get totalNotes => noteCount + reviewCount;

  /// 序列化（缓存上次抓取结果用）。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'bookId': bookId,
    'title': title,
    if (author != null) 'author': author,
    if (cover != null) 'cover': cover,
    if (category != null) 'category': category,
    if (readerLink != null) 'readerLink': readerLink,
    if (deepLink != null) 'deepLink': deepLink,
    if (finished) 'finished': true,
    if (secret) 'secret': true,
    if (isTop) 'isTop': true,
    if (readUpdateTime != null) 'readUpdateTime': readUpdateTime,
    if (updateTime != null) 'updateTime': updateTime,
    if (progressPercent != null) 'progressPercent': progressPercent,
    if (readingSeconds != null) 'readingSeconds': readingSeconds,
    if (finishTime != null) 'finishTime': finishTime,
    if (noteCount != 0) 'noteCount': noteCount,
    if (reviewCount != 0) 'reviewCount': reviewCount,
    if (bookmarkCount != 0) 'bookmarkCount': bookmarkCount,
  };

  /// 反序列化（损坏字段按默认值兜底）。
  factory WeReadBook.fromJson(Map<String, dynamic> json) => WeReadBook(
    bookId: _jsonString(json['bookId']) ?? '',
    title: _jsonString(json['title']) ?? '',
    author: _jsonString(json['author']),
    cover: _jsonString(json['cover']),
    category: _jsonString(json['category']),
    readerLink: _jsonString(json['readerLink']),
    deepLink: _jsonString(json['deepLink']),
    finished: json['finished'] == true,
    secret: json['secret'] == true,
    isTop: json['isTop'] == true,
    readUpdateTime: _jsonInt(json['readUpdateTime']),
    updateTime: _jsonInt(json['updateTime']),
    progressPercent: _jsonInt(json['progressPercent']),
    readingSeconds: _jsonInt(json['readingSeconds']),
    finishTime: _jsonInt(json['finishTime']),
    noteCount: _jsonInt(json['noteCount']) ?? 0,
    reviewCount: _jsonInt(json['reviewCount']) ?? 0,
    bookmarkCount: _jsonInt(json['bookmarkCount']) ?? 0,
  );

  /// 复制并覆盖部分字段。
  WeReadBook copyWith({
    String? title,
    String? author,
    String? cover,
    String? category,
    String? readerLink,
    String? deepLink,
    bool? finished,
    bool? secret,
    bool? isTop,
    int? readUpdateTime,
    int? updateTime,
    int? progressPercent,
    int? readingSeconds,
    int? finishTime,
    int? noteCount,
    int? reviewCount,
    int? bookmarkCount,
  }) {
    return WeReadBook(
      bookId: bookId,
      title: title ?? this.title,
      author: author ?? this.author,
      cover: cover ?? this.cover,
      category: category ?? this.category,
      readerLink: readerLink ?? this.readerLink,
      deepLink: deepLink ?? this.deepLink,
      finished: finished ?? this.finished,
      secret: secret ?? this.secret,
      isTop: isTop ?? this.isTop,
      readUpdateTime: readUpdateTime ?? this.readUpdateTime,
      updateTime: updateTime ?? this.updateTime,
      progressPercent: progressPercent ?? this.progressPercent,
      readingSeconds: readingSeconds ?? this.readingSeconds,
      finishTime: finishTime ?? this.finishTime,
      noteCount: noteCount ?? this.noteCount,
      reviewCount: reviewCount ?? this.reviewCount,
      bookmarkCount: bookmarkCount ?? this.bookmarkCount,
    );
  }
}

/// `/book/info` 的书籍详情（导入占位 EPUB 时补简介 / 出版社等元数据）。
class WeReadBookInfo {
  /// 构造。
  const WeReadBookInfo({
    required this.bookId,
    required this.title,
    this.author,
    this.cover,
    this.intro,
    this.category,
    this.publisher,
    this.publishTime,
    this.isbn,
    this.wordCount,
  });

  /// 微信读书 bookId。
  final String bookId;

  /// 书名。
  final String title;

  /// 作者。
  final String? author;

  /// 封面 URL。
  final String? cover;

  /// 简介。
  final String? intro;

  /// 分类。
  final String? category;

  /// 出版社。
  final String? publisher;

  /// 出版时间。
  final String? publishTime;

  /// ISBN。
  final String? isbn;

  /// 总字数。
  final int? wordCount;
}

/// 书架接口的轻量结果（电子书 + 专辑/文章收藏入口计数）。
class WeReadShelf {
  /// 构造。
  const WeReadShelf({
    required this.books,
    this.albumCount = 0,
    this.hasMp = false,
    this.bookCount,
  });

  /// 电子书。
  final List<WeReadBook> books;

  /// 专辑/有声书数量（本应用不导入音频，只做提示）。
  final int albumCount;

  /// 是否有「文章收藏」入口。
  final bool hasMp;

  /// 服务端给的可枚举电子书数量。
  final int? bookCount;
}

/// 单本书的阅读进度。
class WeReadProgress {
  /// 构造。
  const WeReadProgress({
    required this.bookId,
    required this.progressPercent,
    this.updateTime,
    this.readingSeconds,
    this.finishTime,
    this.chapterUid,
    this.chapterOffset,
  });

  /// 微信读书 bookId。
  final String bookId;

  /// 0..100 的整数（1 = 1%，不是 100%）。
  final int progressPercent;

  /// 最后阅读时间（Unix 秒）。
  final int? updateTime;

  /// 累计阅读时长（秒）。
  final int? readingSeconds;

  /// 读完时间（Unix 秒）。
  final int? finishTime;

  /// 当前章节 UID。
  final int? chapterUid;

  /// 当前章节内偏移。
  final int? chapterOffset;
}

/// 笔记本概览里的一本书。
class WeReadNotebook {
  /// 构造。
  const WeReadNotebook({
    required this.bookId,
    required this.title,
    this.author,
    this.cover,
    this.noteCount = 0,
    this.reviewCount = 0,
    this.bookmarkCount = 0,
    this.readingProgress,
    this.finished = false,
    this.sort,
  });

  /// 微信读书 bookId。
  final String bookId;

  /// 书名。
  final String title;

  /// 作者。
  final String? author;

  /// 封面 URL。
  final String? cover;

  /// 划线数。
  final int noteCount;

  /// 想法/点评数。
  final int reviewCount;

  /// 书签数。
  final int bookmarkCount;

  /// 阅读进度（0..100）。
  final int? readingProgress;

  /// 是否读完（markedStatus = 1）。
  final bool finished;

  /// 最近笔记时间（分页游标，Unix 秒）。
  final int? sort;

  /// 笔记总数。
  int get totalNotes => noteCount + reviewCount;
}

/// 一条微信读书划线/想法。
class WeReadNote {
  /// 构造。
  const WeReadNote({
    required this.id,
    required this.bookId,
    this.quote = '',
    this.thought = '',
    this.chapterUid,
    this.chapterIdx,
    this.chapterName,
    this.range = '',
    this.colorStyle,
    this.createdAt,
    this.updatedAt,
    this.wholeBookReview = false,
  });

  /// 唯一 id（划线的 bookmarkId 或想法 reviewId）。
  final String id;

  /// 所属微信读书书籍。
  final String bookId;

  /// 划线原文（想法可能没有）。
  final String quote;

  /// 想法正文。
  final String thought;

  /// 章节 UID。
  final int? chapterUid;

  /// 章节序号（接口原值，可能 0/1 基，定位时只作偏好）。
  final int? chapterIdx;

  /// 章节标题。
  final String? chapterName;

  /// 原文位置范围（如 `2959-3007`）。
  final String range;

  /// 划线颜色样式。
  final int? colorStyle;

  /// 创建时间（Unix 秒）。
  final int? createdAt;

  /// 最后编辑时间（Unix 秒；想法有 updateTime 时优先）。
  final int? updatedAt;

  /// 是否是整本书评/无法定位到原文的想法。
  final bool wholeBookReview;

  /// 判断新旧用的时间（Unix 秒）。
  int? get editedAt => updatedAt ?? createdAt;

  /// 复制并覆盖部分字段。
  WeReadNote copyWith({
    String? quote,
    String? thought,
    int? chapterUid,
    int? chapterIdx,
    String? chapterName,
    String? range,
    int? colorStyle,
    int? createdAt,
    int? updatedAt,
    bool? wholeBookReview,
  }) {
    return WeReadNote(
      id: id,
      bookId: bookId,
      quote: quote ?? this.quote,
      thought: thought ?? this.thought,
      chapterUid: chapterUid ?? this.chapterUid,
      chapterIdx: chapterIdx ?? this.chapterIdx,
      chapterName: chapterName ?? this.chapterName,
      range: range ?? this.range,
      colorStyle: colorStyle ?? this.colorStyle,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      wholeBookReview: wholeBookReview ?? this.wholeBookReview,
    );
  }
}

/// 一次拉取后的完整微信读书快照。
class WeReadSnapshot {
  /// 构造。
  const WeReadSnapshot({
    required this.books,
    required this.fetchedAt,
    this.albumCount = 0,
    this.hasMp = false,
    this.progressFailures = 0,
  });

  /// 电子书。
  final List<WeReadBook> books;

  /// 拉取时间。
  final DateTime fetchedAt;

  /// 专辑/有声书数量。
  final int albumCount;

  /// 是否有文章收藏入口。
  final bool hasMp;

  /// 阅读进度接口失败的本数（缓存上次结果时一并展示）。
  final int progressFailures;

  /// 序列化（缓存上次抓取结果用）。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'books': <Map<String, dynamic>>[for (final book in books) book.toJson()],
    'fetchedAt': fetchedAt.millisecondsSinceEpoch,
    if (albumCount != 0) 'albumCount': albumCount,
    if (hasMp) 'hasMp': true,
    if (progressFailures != 0) 'progressFailures': progressFailures,
  };

  /// 反序列化（损坏字段按默认值兜底；没有书则返回 null）。
  static WeReadSnapshot? fromJson(Map<String, dynamic> json) {
    final rawBooks = json['books'];
    if (rawBooks is! List) return null;
    final books = <WeReadBook>[];
    for (final raw in rawBooks) {
      if (raw is! Map) continue;
      final map = <String, dynamic>{
        for (final entry in raw.entries) '${entry.key}': entry.value,
      };
      final book = WeReadBook.fromJson(map);
      if (book.bookId.isNotEmpty && book.title.isNotEmpty) books.add(book);
    }
    if (books.isEmpty) return null;
    final fetchedAt = _jsonInt(json['fetchedAt']);
    return WeReadSnapshot(
      books: books,
      fetchedAt: fetchedAt == null || fetchedAt <= 0
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(fetchedAt),
      albumCount: _jsonInt(json['albumCount']) ?? 0,
      hasMp: json['hasMp'] == true,
      progressFailures: _jsonInt(json['progressFailures']) ?? 0,
    );
  }

  /// 笔记总数。
  int get totalNotes =>
      books.fold<int>(0, (sum, book) => sum + book.totalNotes);

  /// 累计阅读时长（秒）。
  int get totalReadingSeconds =>
      books.fold<int>(0, (sum, book) => sum + (book.readingSeconds ?? 0));
}

/// 微信读书请求异常（message 可直接展示）。
class WeReadApiException implements Exception {
  /// 构造。
  const WeReadApiException(this.message);

  /// 用户可读原因。
  final String message;

  @override
  String toString() => message;
}

/// 合并一次 `/book/getprogress` 结果（空字段不覆盖已有值）。
///
/// 书架快照的进度是 4 并发 + 45 秒预算批量拉的，书多时很多书会拉不到；
/// 单本同步 / 导入时再拉一次，用这个函数把进度、累计时长、读完时间补进来。
WeReadBook mergeWeReadProgress(WeReadBook book, WeReadProgress? progress) {
  if (progress == null) return book;
  return book.copyWith(
    // 进度接口偶发返回 0（没读到 / 只返回累计时长）时，别把快照里的进度冲掉。
    progressPercent: progress.progressPercent > 0
        ? progress.progressPercent
        : book.progressPercent,
    readingSeconds: progress.readingSeconds ?? book.readingSeconds,
    finishTime: progress.finishTime ?? book.finishTime,
    readUpdateTime: _laterTime(book.readUpdateTime, progress.updateTime),
    finished: book.finished || progress.progressPercent >= 100,
  );
}

int? _laterTime(int? a, int? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a > b ? a : b;
}

String? _jsonString(Object? raw) => raw is String ? raw : null;

int? _jsonInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}
