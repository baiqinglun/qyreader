/// 应用数据库（drift）。SQLite 是唯一真相：所有写先落本地，
/// 同事务追加 sync_ops，由后台同步器复制到对象存储。
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/book_dao.dart';
import 'daos/progress_dao.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// 主数据库类。
@DriftDatabase(
  tables: [
    Books,
    Chapters,
    ReadingProgress,
    Annotations,
    Bookmarks,
    ReadingSessions,
    DailyStats,
    SyncOps,
    SyncState,
  ],
  daos: [BookDao, ProgressDao],
)
class AppDatabase extends _$AppDatabase {
  /// 注入 QueryExecutor（生产用 [openAppDatabase]，测试用 NativeDatabase.memory）。
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // FTS5 全文索引：中文必须 trigram（unicode61 分词对中文无效）。
          // drift 表模型无法声明虚拟表 tokenizer，这里用原生 SQL；
          // M2 接入检索时再补写入同步。
          await customStatement(
            'CREATE VIRTUAL TABLE IF NOT EXISTS book_fts USING fts5('
            'book_id UNINDEXED, chapter_idx UNINDEXED, title, body, '
            "tokenize = 'trigram')",
          );
        },
        onUpgrade: (m, from, to) async {
          // 迁移纪律：每个版本单独处理，永不删表重建。
          // schemaVersion 1 为初始版本，暂无升级路径。
        },
      );
}

/// 用应用支持目录打开生产数据库（后台线程执行 IO）。
AppDatabase openAppDatabase() {
  return AppDatabase(LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'qy_reader.sqlite3'));
    return NativeDatabase.createInBackground(file);
  }));
}
