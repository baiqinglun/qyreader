/// 每本书的数据分片（同步用）：把一本书相关的行导出成 JSON，按书增量上传。
///
/// 不做「整库上传」：500 本书只改 1 本时只传 `shards/<bookId>.json`。
/// 表结构用通用 SQL 读写（列名来自 sqlite 本身），加列不需要改这里；
/// 表名不在 [tables] 里的数据不进分片。
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/db/app_database.dart';

/// 分片格式版本（以后加字段时用来迁移）。
const int kBookShardSchema = 1;

/// 每本书涉及的表 → 取该书的列名。
///
/// `chapters` 也随分片走：书籍按需下载（v2.30.0）后，新设备没有书源文件
/// 也能先看到目录与章节数，不用等首次打开。分片只含章节元数据（标题/href/
/// 偏移），不含正文。
const Map<String, String> _shardTables = {
  'books': 'id',
  'chapters': 'book_id',
  'reading_progress': 'book_id',
  'annotations': 'book_id',
  'bookmarks': 'book_id',
  'reading_sessions': 'book_id',
};

/// 导出 / 应用单本书的数据分片。
class BookShard {
  BookShard._();

  /// 导出一本书的全部本地数据（书本身 + 进度 + 标注 + 书签 + 会话）。
  static Future<Map<String, dynamic>> export(
    AppDatabase db,
    String bookId,
  ) async {
    final out = <String, dynamic>{
      'schema': kBookShardSchema,
      'bookId': bookId,
    };
    for (final e in _shardTables.entries) {
      try {
        final rows = await db
            .customSelect(
              'SELECT * FROM ${e.key} WHERE ${e.value} = ?',
              variables: [Variable.withString(bookId)],
            )
            .get();
        out[e.key] = [for (final row in rows) row.data];
      } catch (_) {
        // 表不存在（旧库）时跳过
      }
    }
    return out;
  }

  /// 应用一个分片（整本覆盖该书的行；分片里没有的表不动）。
  static Future<void> apply(
    AppDatabase db,
    Map<String, dynamic> shard,
  ) async {
    final bookId = shard['bookId'] as String?;
    if (bookId == null || bookId.isEmpty) return;
    for (final e in _shardTables.entries) {
      final raw = shard[e.key];
      if (raw is! List) continue;
      final rows = raw.whereType<Map>().cast<Map<String, dynamic>>().toList();
      try {
        await db.customStatement(
          'DELETE FROM ${e.key} WHERE ${e.value} = ?',
          [bookId],
        );
        for (final row in rows) {
          final cols = row.keys.toList();
          final sql = 'INSERT OR REPLACE INTO ${e.key} '
              '(${cols.join(',')}) VALUES '
              '(${List.filled(cols.length, '?').join(',')})';
          await db.customStatement(sql, [for (final c in cols) row[c]]);
        }
      } catch (_) {
        // 单表失败不影响其他表
      }
    }
  }

  /// 只应用分片里的章节表（目录元数据）。
  ///
  /// 书籍元数据已是最新、只是本地没有章节（按需下载的新设备首次同步）时用，
  /// 避免整本覆盖把较新的本地元数据冲掉。
  static Future<void> applyChapters(
    AppDatabase db,
    Map<String, dynamic> shard,
  ) async {
    final bookId = shard['bookId'] as String?;
    final raw = shard['chapters'];
    if (bookId == null || bookId.isEmpty || raw is! List) return;
    final rows = raw.whereType<Map>().cast<Map<String, dynamic>>().toList();
    if (rows.isEmpty) return;
    try {
      await db.customStatement(
        'DELETE FROM chapters WHERE book_id = ?',
        [bookId],
      );
      for (final row in rows) {
        final cols = row.keys.toList();
        final sql = 'INSERT OR REPLACE INTO chapters '
            '(${cols.join(',')}) VALUES '
            '(${List.filled(cols.length, '?').join(',')})';
        await db.customStatement(sql, [for (final c in cols) row[c]]);
      }
    } catch (_) {
      // 单表失败不影响其他数据
    }
  }

  /// 分片字节（上传前的编码）。
  static Uint8List encode(Map<String, dynamic> shard) =>
      Uint8List.fromList(utf8.encode(jsonEncode(shard)));

  /// 解码对象存储里的分片；坏数据返回 null。
  static Map<String, dynamic>? decode(List<int> bytes) {
    try {
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
