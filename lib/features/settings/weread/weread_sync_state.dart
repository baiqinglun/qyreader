/// 微信读书同步的本地状态（shared_preferences）。
///
/// 存四类信息：
/// - `links`：微信读书 bookId → 本机书籍 id（用于稳定匹配、检测移除）；
/// - `seen`：上次拉到的书架 bookId（这次不在书架里的算「已从微信读书移除」）；
/// - `importedMarks` / `importedCounts`：已导入的划线 id 与每本计数（防重复）；
/// - `syncedNoteTotals`：上次成功处理时微信读书那本书的笔记总数（含书评），
///   用来判断「是否新增」——不能再用 imported + skipped 反推：整本书评不计入
///   划线导入，同一 range 的多条想法也会合并成一条，反推会永远差几条；
/// - `skippedCounts`：原文在本机书里找不到、已跳过的划线数（避免反复提示）。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'weread_models.dart';

/// 微信读书同步状态。
class WeReadSyncState {
  /// 构造。
  const WeReadSyncState({
    this.links = const <String, String>{},
    this.seen = const <String>{},
    this.known = const <String, WeReadKnownBook>{},
    this.importedMarks = const <String>{},
    this.importedCounts = const <String, int>{},
    this.syncedNoteTotals = const <String, int>{},
    this.skippedCounts = const <String, int>{},
    this.importedReadingSeconds = const <String, int>{},
    this.lastSyncAt,
  });

  /// 空状态。
  static const WeReadSyncState empty = WeReadSyncState();

  /// 微信读书 bookId → 本机书籍 id。
  final Map<String, String> links;

  /// 上次书架上的微信读书 bookId。
  final Set<String> seen;

  /// 上次书架上的书籍元数据（用于展示「已移除」的书名）。
  final Map<String, WeReadKnownBook> known;

  /// 已导入的划线/想法 id。
  final Set<String> importedMarks;

  /// 每本书已导入的划线数。
  final Map<String, int> importedCounts;

  /// 每本书上次成功处理时的远端笔记总数（含整本书评、合并前的想法）。
  ///
  /// 比对「新增」以这个基线为准，避免整本书评 / 同一 range 多条想法
  /// 让 `totalNotes` 永远大于 `importedCounts + skippedCounts`。
  final Map<String, int> syncedNoteTotals;

  /// 每本书因原文找不到而跳过的划线数。
  final Map<String, int> skippedCounts;

  /// 每本书已导入到本机统计的微信读书累计阅读秒数（只补差额，防重复）。
  final Map<String, int> importedReadingSeconds;

  /// 上次同步时间（epoch ms）。
  final int? lastSyncAt;

  /// 复制并覆盖部分字段。
  WeReadSyncState copyWith({
    Map<String, String>? links,
    Set<String>? seen,
    Map<String, WeReadKnownBook>? known,
    Set<String>? importedMarks,
    Map<String, int>? importedCounts,
    Map<String, int>? syncedNoteTotals,
    Map<String, int>? skippedCounts,
    Map<String, int>? importedReadingSeconds,
    int? lastSyncAt,
  }) {
    return WeReadSyncState(
      links: links ?? this.links,
      seen: seen ?? this.seen,
      known: known ?? this.known,
      importedMarks: importedMarks ?? this.importedMarks,
      importedCounts: importedCounts ?? this.importedCounts,
      syncedNoteTotals: syncedNoteTotals ?? this.syncedNoteTotals,
      skippedCounts: skippedCounts ?? this.skippedCounts,
      importedReadingSeconds:
          importedReadingSeconds ?? this.importedReadingSeconds,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }

  /// 序列化（数组化 Set，避免 JSON 不支持 Set）。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'links': links,
    'seen': seen.toList(),
    'known': {
      for (final entry in known.entries) entry.key: entry.value.toJson(),
    },
    'importedMarks': importedMarks.toList(),
    'importedCounts': importedCounts,
    'syncedNoteTotals': syncedNoteTotals,
    'skippedCounts': skippedCounts,
    'importedReadingSeconds': importedReadingSeconds,
    if (lastSyncAt != null) 'lastSyncAt': lastSyncAt,
  };

  /// 反序列化；损坏字段按空处理，不让一条坏数据卡住整个页面。
  factory WeReadSyncState.fromJson(Map<String, dynamic> json) {
    return WeReadSyncState(
      links: _stringMap(json['links']),
      seen: _stringSet(json['seen']),
      known: _knownMap(json['known']),
      importedMarks: _stringSet(json['importedMarks']),
      importedCounts: _intMap(json['importedCounts']),
      syncedNoteTotals: _intMap(json['syncedNoteTotals']),
      skippedCounts: _intMap(json['skippedCounts']),
      importedReadingSeconds: _intMap(json['importedReadingSeconds']),
      lastSyncAt: _intValue(json['lastSyncAt']),
    );
  }
}

/// 上次看到的微信读书书籍元数据。
class WeReadKnownBook {
  /// 构造。
  const WeReadKnownBook({this.title = '', this.author, this.cover});

  /// 书名。
  final String title;

  /// 作者。
  final String? author;

  /// 封面 URL。
  final String? cover;

  /// 序列化。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    if (author != null) 'author': author,
    if (cover != null) 'cover': cover,
  };

  /// 反序列化。
  factory WeReadKnownBook.fromJson(Map<String, dynamic> json) {
    return WeReadKnownBook(
      title: json['title'] is String ? json['title'] as String : '',
      author: json['author'] is String ? json['author'] as String : null,
      cover: json['cover'] is String ? json['cover'] as String : null,
    );
  }
}

/// 同步状态存储。
class WeReadSyncStore {
  /// 构造。
  const WeReadSyncStore();

  /// prefs key。
  static const String prefsKey = 'weread.syncState';

  /// 上次抓取快照的 prefs key（进入页面先展示，不立刻联网）。
  static const String snapshotKey = 'weread.lastSnapshot';

  /// 读取状态。
  Future<WeReadSyncState> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return WeReadSyncState.empty;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return WeReadSyncState.empty;
      return WeReadSyncState.fromJson(decoded);
    } catch (_) {
      return WeReadSyncState.empty;
    }
  }

  /// 保存状态。
  Future<void> save(WeReadSyncState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode(state.toJson()));
  }

  /// 清空状态。
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
  }

  /// 读取上次抓取快照；没有或损坏返回 null。
  Future<WeReadSnapshot?> loadSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(snapshotKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return WeReadSnapshot.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// 保存上次抓取快照。
  Future<void> saveSnapshot(WeReadSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(snapshotKey, jsonEncode(snapshot.toJson()));
  }

  /// 清空上次抓取快照。
  Future<void> clearSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(snapshotKey);
  }
}

Map<String, String> _stringMap(Object? raw) {
  if (raw is! Map) return const <String, String>{};
  final out = <String, String>{};
  raw.forEach((key, value) {
    if (key is String && value is String) out[key] = value;
  });
  return out;
}

Set<String> _stringSet(Object? raw) {
  if (raw is! List) return const <String>{};
  return raw.whereType<String>().toSet();
}

Map<String, int> _intMap(Object? raw) {
  if (raw is! Map) return const <String, int>{};
  final out = <String, int>{};
  raw.forEach((key, value) {
    if (key is String && value is num) out[key] = value.toInt();
  });
  return out;
}

Map<String, WeReadKnownBook> _knownMap(Object? raw) {
  if (raw is! Map) return const <String, WeReadKnownBook>{};
  final out = <String, WeReadKnownBook>{};
  raw.forEach((key, value) {
    if (key is String && value is Map) {
      out[key] = WeReadKnownBook.fromJson(
        value.map((k, v) => MapEntry('$k', v)),
      );
    }
  });
  return out;
}

int? _intValue(Object? raw) => raw is num ? raw.toInt() : null;
