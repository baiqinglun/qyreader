/// 微信读书 Agent API Gateway 客户端。
///
/// 官方入口：`POST https://i.weread.qq.com/api/agent/gateway`
/// - Header `Authorization: Bearer <w r k-...>`；
/// - Body 里 `api_name` 指定接口，业务参数平铺，另带 `skill_version`；
/// - 回包 `errcode != 0` 表示失败，错误文案在 `errmsg` / `message`。
///
/// 本客户端不缓存、不落盘 API Key（Key 由 `WeReadCredentials` 从
/// flutter_secure_storage 读取后注入）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'weread_models.dart';

/// 微信读书 Agent API Gateway 地址。
const String kWeReadGatewayUrl = 'https://i.weread.qq.com/api/agent/gateway';

/// 官方 Skills 版本号；接口升级时服务端会回 `upgrade_info`。
const String kWeReadSkillVersion = '1.0.6';

/// 发送 POST 并解析 JSON（测试可注入）。
typedef WeReadPostFn =
    Future<Map<String, dynamic>> Function(
      Uri url,
      Map<String, String> headers,
      Map<String, dynamic> body,
    );

/// 微信读书 API Key 凭据（flutter_secure_storage）。
///
/// 单独放在 client 文件里会让 secure storage 依赖混进纯解析测试；真实
/// 读取逻辑在 `weread_credentials.dart`。这里只留常量避免重复。
const String kWeReadApiKeySecureKey = 'weread.apiKey';

/// 微信读书推荐书籍。
class WeReadRecommendation {
  const WeReadRecommendation({
    required this.title,
    this.bookId = '',
    this.author,
    this.cover,
    this.reason,
    this.intro,
    this.metadata = const {},
  });
  final Map<String, dynamic> metadata;
  final String title;
  final String bookId;
  final String? author;
  final String? cover;
  final String? reason;
  final String? intro;
}

/// 微信读书 API 客户端。
class WeReadClient {
  /// 构造。[post] 供测试注入（默认走 dart:io HttpClient）。
  WeReadClient({
    required String apiKey,
    this.baseUrl = kWeReadGatewayUrl,
    this.skillVersion = kWeReadSkillVersion,
    this.onUpgrade,
    WeReadPostFn? post,
  }) : _apiKey = apiKey,
       _post = post ?? _postJson;

  final String _apiKey;
  final String baseUrl;
  final String skillVersion;

  /// 可选的非阻塞版本提示回调。
  final void Function(String message)? onUpgrade;
  final WeReadPostFn _post;

  /// 获取基于阅读记录的个性化推荐。
  Future<List<WeReadRecommendation>> fetchRecommendations() async {
    final json = await _call('/book/recommend', {
      'context': '根据我的阅读记录推荐书籍',
      'count': 12,
      'maxIdx': 0,
    });
    return [
      for (final raw in _listOf(json['books']))
        if (_mapOf(raw) case final map?)
          if ((_strOf(map['title']) ?? '').isNotEmpty)
            WeReadRecommendation(
              title: _strOf(map['title'])!,
              bookId: _strOf(map['bookId']) ?? '',
              author: _strOf(map['author']),
              cover: _strOf(map['cover']),
              reason: _strOf(map['reason']),
              intro: _strOf(map['intro']),
              metadata: Map<String, dynamic>.of(map),
            ),
    ];
  }

  /// 获取推荐详情、热门划线和公开书评。
  Future<Map<String, dynamic>> fetchRecommendationInfo(String id) =>
      _call('/book/info', {'bookId': id});

  /// 获取书籍目录。
  Future<List<Map<String, dynamic>>> fetchChapters(String id) async {
    final json = await _call('/book/chapterinfo', {'bookId': id});
    return [
      for (final raw in _listOf(json['chapters']))
        if (_mapOf(raw) case final item?) item,
    ];
  }

  Future<List<String>> fetchPopularHighlights(String id) async {
    final json = await _call('/book/bestbookmarks', {
      'bookId': id,
      'chapterUid': 0,
    });
    return [
      for (final raw in _listOf(json['items']))
        if (_mapOf(raw) case final item?)
          if ((_strOf(item['markText']) ?? '').isNotEmpty)
            _strOf(item['markText'])!,
    ];
  }

  Future<List<String>> fetchPopularReviews(String id) async {
    final json = await _call('/review/list', {
      'bookId': id,
      'reviewListType': 1,
      'count': 20,
      'maxIdx': 0,
    });
    return [
      for (final raw in _listOf(json['reviews']))
        if (_mapOf(raw) case final item?)
          if (_mapOf(item['review']) case final outer?)
            if ((_mapOf(outer['review']) ?? outer) case final review)
              if ((_strOf(review['content']) ?? '').isNotEmpty)
                _strOf(review['content'])!,
    ];
  }

  /// 拉取书架（电子书 + 专辑/文章收藏计数）。
  Future<WeReadShelf> fetchShelf() async {
    final json = await _call('/shelf/sync');
    final books = <WeReadBook>[];
    for (final raw in _listOf(json['books'])) {
      final map = _mapOf(raw);
      if (map == null) continue;
      books.add(_parseShelfBook(map));
    }
    final mp = json['mp'];
    return WeReadShelf(
      books: books,
      albumCount: _listOf(json['albums']).length,
      hasMp: mp is Map ? mp.isNotEmpty : mp != null,
      bookCount: _intOf(json['bookCount']),
    );
  }

  /// 拉取单本书的阅读进度；没有进度数据时返回 null。
  Future<WeReadProgress?> fetchProgress(String bookId) async {
    final json = await _call('/book/getprogress', <String, dynamic>{
      'bookId': bookId,
    });
    final raw = _mapOf(json['book']) ?? json;
    final bookMap = _mapOf(raw);
    if (bookMap == null) return null;
    final progress = (_intOf(bookMap['progress']) ?? 0).clamp(0, 100);
    return WeReadProgress(
      bookId: bookId,
      progressPercent: progress,
      updateTime: _intOf(bookMap['updateTime']),
      readingSeconds: _intOf(bookMap['recordReadingTime']),
      finishTime: _intOf(bookMap['finishTime']),
      chapterUid: _intOf(bookMap['chapterUid']),
      chapterOffset: _intOf(bookMap['chapterOffset']),
    );
  }

  /// 拉取书籍详情（`/book/info`）：导入占位 EPUB 时用来补简介等元数据。
  Future<WeReadBookInfo> fetchBookInfo(String bookId) async {
    final json = await _call('/book/info', <String, dynamic>{'bookId': bookId});
    return WeReadBookInfo(
      bookId: bookId,
      title: _strOf(json['title']) ?? '',
      author: _strOf(json['author']),
      cover: _strOf(json['cover']),
      intro: _strOf(json['intro']),
      category: _strOf(json['category']),
      publisher: _strOf(json['publisher']),
      publishTime: _strOf(json['publishTime']),
      isbn: _strOf(json['isbn']),
      wordCount: _intOf(json['wordCount']),
    );
  }

  /// 拉取一页笔记本概览（`/user/notebooks`）。
  Future<WeReadNotebookPage> fetchNotebooksPage({
    int count = 100,
    int? lastSort,
  }) async {
    final json = await _call('/user/notebooks', <String, dynamic>{
      'count': count,
      if (lastSort != null) 'lastSort': lastSort,
    });
    final notebooks = <WeReadNotebook>[];
    for (final raw in _listOf(json['books'])) {
      final map = _mapOf(raw);
      if (map == null) continue;
      final bookMap = _mapOf(map['book']) ?? const <String, dynamic>{};
      final bookId = _strOf(map['bookId']) ?? _strOf(bookMap['bookId']) ?? '';
      if (bookId.isEmpty) continue;
      notebooks.add(
        WeReadNotebook(
          bookId: bookId,
          title: _strOf(bookMap['title']) ?? '',
          author: _strOf(bookMap['author']),
          cover: _strOf(bookMap['cover']),
          noteCount: _intOf(map['noteCount']) ?? 0,
          reviewCount: _intOf(map['reviewCount']) ?? 0,
          bookmarkCount: _intOf(map['bookmarkCount']) ?? 0,
          readingProgress: _intOf(map['readingProgress']),
          finished: (_intOf(map['markedStatus']) ?? 0) == 1,
          sort: _intOf(map['sort']),
        ),
      );
    }
    final last = notebooks.isEmpty ? null : notebooks.last.sort;
    return WeReadNotebookPage(
      notebooks: notebooks,
      hasMore: (_intOf(json['hasMore']) ?? 0) == 1,
      totalBookCount: _intOf(json['totalBookCount']),
      totalNoteCount: _intOf(json['totalNoteCount']),
      lastSort: last,
    );
  }

  /// 拉取单本书的划线 + 想法（`/book/bookmarklist` + `/review/list/mine`）。
  ///
  /// 同一个 range 的划线与想法会合并成一条 [WeReadNote]；无法定位到原文
  /// 的整本书评/普通想法标记为 `wholeBookReview`。
  Future<List<WeReadNote>> fetchNotes(String bookId) async {
    final notes = <String, WeReadNote>{};

    // 两个接口各自容错：划线接口失败时仍展示想法，反之亦然。
    Map<String, dynamic>? markJson;
    Object? markError;
    try {
      markJson = await _call('/book/bookmarklist', <String, dynamic>{
        'bookId': bookId,
      });
    } catch (error) {
      markError = error;
    }
    final chapterNames = <int, String>{};
    final chapterIdxs = <int, int>{};
    for (final raw in _listOf(markJson?['chapters'])) {
      final map = _mapOf(raw);
      if (map == null) continue;
      final uid = _intOf(map['chapterUid']);
      if (uid == null) continue;
      final title = _strOf(map['title']);
      final idx = _intOf(map['chapterIdx']);
      if (title != null && title.isNotEmpty) chapterNames[uid] = title;
      if (idx != null) chapterIdxs[uid] = idx;
    }
    var markEntries = _listOf(markJson?['updated']);
    if (markEntries.isEmpty) markEntries = _listOf(markJson?['bookmarks']);
    for (final raw in markEntries) {
      final map = _mapOf(raw);
      if (map == null) continue;
      final quote = _strOf(map['markText'])?.trim() ?? '';
      if (quote.isEmpty) continue;
      final uid = _intOf(map['chapterUid']);
      final range = _strOf(map['range']) ?? '';
      final id =
          _strOf(map['bookmarkId']) ??
          '$bookId:${range.isEmpty ? quote.hashCode : range}';
      notes[range.isEmpty ? id : range] = WeReadNote(
        id: id,
        bookId: bookId,
        quote: quote,
        chapterUid: uid,
        chapterIdx: uid == null ? null : chapterIdxs[uid],
        chapterName:
            _strOf(map['chapterTitle']) ??
            (uid == null ? null : chapterNames[uid]),
        range: range,
        colorStyle: _intOf(map['colorStyle']),
        createdAt: _intOf(map['createTime']),
        updatedAt: _intOf(map['createTime']),
      );
    }

    Map<String, dynamic>? reviewJson;
    Object? reviewError;
    try {
      reviewJson = await _call('/review/list/mine', <String, dynamic>{
        'bookid': bookId,
        'count': 100,
      });
    } catch (error) {
      reviewError = error;
    }
    if (markJson == null && reviewJson == null) {
      if (markError is WeReadApiException) throw markError;
      throw WeReadApiException('划线/想法拉取失败：${markError ?? reviewError}');
    }
    for (final raw in _listOf(reviewJson?['reviews'])) {
      final outer = _mapOf(raw);
      final review = _mapOf(outer?['review']) ?? outer;
      if (review == null) continue;
      final content = _strOf(review['content'])?.trim() ?? '';
      if (content.isEmpty) continue;
      final range = _strOf(review['range']) ?? '';
      final abstractText = _strOf(review['abstract'])?.trim() ?? '';
      final id =
          _strOf(review['reviewId']) ??
          '$bookId:${range.isEmpty ? content.hashCode : range}';
      final wholeBook =
          abstractText.isEmpty &&
          (range.isEmpty || _intOf(review['chapterUid']) == null);
      final existing = range.isEmpty ? null : notes[range];
      if (existing != null) {
        final merged = [
          if (existing.thought.isNotEmpty) existing.thought,
          content,
        ].join('\n');
        final reviewUpdated =
            _intOf(review['updateTime']) ?? _intOf(review['createTime']);
        notes[range] = existing.copyWith(
          thought: merged,
          quote: existing.quote.isEmpty ? abstractText : existing.quote,
          chapterIdx: existing.chapterIdx ?? _intOf(review['chapterIdx']),
          chapterName: existing.chapterName ?? _strOf(review['chapterName']),
          updatedAt: _maxInt(existing.updatedAt, reviewUpdated),
        );
        continue;
      }
      notes[range.isEmpty ? id : range] = WeReadNote(
        id: id,
        bookId: bookId,
        quote: abstractText,
        thought: content,
        chapterUid: _intOf(review['chapterUid']),
        chapterIdx: _intOf(review['chapterIdx']),
        chapterName: _strOf(review['chapterName']),
        range: range,
        createdAt: _intOf(review['createTime']),
        updatedAt: _intOf(review['updateTime']) ?? _intOf(review['createTime']),
        wholeBookReview: wholeBook,
      );
    }

    return notes.values.toList()
      ..sort((a, b) => (a.createdAt ?? 0).compareTo(b.createdAt ?? 0));
  }

  /// 调用一个 gateway 接口。
  Future<Map<String, dynamic>> _call(
    String apiName, [
    Map<String, dynamic> params = const <String, dynamic>{},
  ]) async {
    final body = <String, dynamic>{
      'api_name': apiName,
      ...params,
      'skill_version': skillVersion,
    };
    final Map<String, dynamic> json;
    try {
      json = await _post(Uri.parse(baseUrl), <String, String>{
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      }, body);
    } on WeReadApiException {
      rethrow;
    } on TimeoutException {
      throw const WeReadApiException('请求超时，请检查网络后重试');
    } catch (e) {
      throw WeReadApiException('网络请求失败：$e');
    }

    final upgrade = _mapOf(json['upgrade_info']);
    final upgradeMessage = _strOf(upgrade?['message']);
    final errcode = _intOf(json['errcode']) ?? _intOf(json['errCode']) ?? 0;
    if (errcode != 0) {
      final message =
          _strOf(json['errmsg']) ??
          _strOf(json['errMsg']) ??
          _strOf(json['message']) ??
          _strOf(json['msg']) ??
          '接口错误（$errcode）';
      throw WeReadApiException(message);
    }
    if (upgradeMessage != null && upgradeMessage.isNotEmpty) {
      onUpgrade?.call(upgradeMessage);
    }
    // 少数网关版本会把业务数据包在 data 里；只在没有业务字段时解包。
    final data = _mapOf(json['data']);
    if (data != null &&
        !json.containsKey('books') &&
        !json.containsKey('book') &&
        !json.containsKey('updated') &&
        !json.containsKey('reviews')) {
      return data;
    }
    return json;
  }

  WeReadBook _parseShelfBook(Map<String, dynamic> map) {
    return WeReadBook(
      bookId: _strOf(map['bookId']) ?? '',
      title: _strOf(map['title']) ?? '',
      author: _strOf(map['author']),
      cover: _strOf(map['cover']),
      category: _strOf(map['category']),
      readerLink: _strOf(map['readerLink']),
      deepLink: _strOf(map['deepLink']),
      finished: (_intOf(map['finishReading']) ?? 0) == 1,
      secret: (_intOf(map['secret']) ?? 0) == 1,
      isTop: (_intOf(map['isTop']) ?? 0) == 1,
      readUpdateTime: _intOf(map['readUpdateTime']),
      updateTime: _intOf(map['updateTime']),
    );
  }

  /// 默认传输：dart:io HttpClient（不新增 http 依赖）。
  static Future<Map<String, dynamic>> _postJson(
    Uri url,
    Map<String, String> headers,
    Map<String, dynamic> body,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client
          .postUrl(url)
          .timeout(const Duration(seconds: 20));
      headers.forEach(request.headers.set);
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(
        const Duration(seconds: 45),
      );
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw WeReadApiException(
          'HTTP ${response.statusCode}：${_describeErrorBody(text)}',
        );
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const WeReadApiException('响应不是 JSON 对象');
      }
      return decoded;
    } on WeReadApiException {
      rethrow;
    } on TimeoutException {
      throw const WeReadApiException('请求超时，请检查网络后重试');
    } finally {
      client.close(force: true);
    }
  }

  /// 从错误响应体里提取可读文案。
  static String _describeErrorBody(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final key in ['errmsg', 'errMsg', 'message', 'msg']) {
          final value = decoded[key];
          if (value is String && value.isNotEmpty) return value;
        }
      }
    } catch (_) {}
    final trimmed = raw.trim();
    return trimmed.isEmpty
        ? '（无响应体）'
        : trimmed.substring(0, trimmed.length.clamp(0, 200));
  }
}

/// 一页笔记本概览。
class WeReadNotebookPage {
  /// 构造。
  const WeReadNotebookPage({
    required this.notebooks,
    required this.hasMore,
    this.totalBookCount,
    this.totalNoteCount,
    this.lastSort,
  });

  /// 本页数据。
  final List<WeReadNotebook> notebooks;

  /// 是否还有下一页。
  final bool hasMore;

  /// 有笔记的书籍总数。
  final int? totalBookCount;

  /// 笔记总数。
  final int? totalNoteCount;

  /// 下一页游标。
  final int? lastSort;
}

Map<String, dynamic>? _mapOf(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return <String, dynamic>{
      for (final entry in raw.entries) '${entry.key}': entry.value,
    };
  }
  return null;
}

List<Object?> _listOf(Object? raw) => raw is List ? raw : const <Object?>[];

int? _intOf(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

String? _strOf(Object? raw) {
  if (raw is String) return raw;
  if (raw is num || raw is bool) return '$raw';
  return null;
}

int? _maxInt(int? a, int? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a > b ? a : b;
}
