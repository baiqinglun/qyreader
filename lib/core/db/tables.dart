/// SQLite 表定义（drift）。
///
/// 设计要点（与架构文档一致）：
/// - 不用 `is_deleted` 布尔，统一 `deleted_at` 时间戳（参与 LWW 合并）。
/// - `color` 存语义 token（yellow|green|blue|rose），不是色值。
/// - `book_fts` 为 FTS5 trigram 虚拟表，SQLite 不支持用 drift Table 声明
///   tokenizer，见 [AppDatabase] 迁移中的 customStatement。
library;

import 'package:drift/drift.dart';

/// 书籍主表。
@DataClassName('BookRow')
class Books extends Table {
  /// uuid v4。
  TextColumn get id => text()();

  /// 书名。
  TextColumn get title => text()();

  /// 作者。
  TextColumn? get author => text().nullable()();

  /// 丛书名。
  TextColumn? get series => text().nullable()();

  /// 丛书序号。
  RealColumn get seriesIndex => real().withDefault(const Constant(0))();

  /// 语言（BCP-47，如 zh-CN）。
  TextColumn? get language => text().nullable()();

  /// 简介。
  TextColumn? get description => text().nullable()();

  /// 格式：epub|pdf|txt|md。
  TextColumn get format => text()();

  /// 应用私有目录内的文件路径。
  TextColumn get filePath => text()();

  /// 内容寻址哈希：去重 + 同步校验。
  TextColumn get fileSha256 => text()();

  /// 文件字节数。
  IntColumn get fileSize => integer()();

  /// 封面图路径。
  TextColumn? get coverPath => text().nullable()();

  /// 章节数。
  IntColumn get chapterCount => integer().withDefault(const Constant(0))();

  /// 全文字数（近似）。
  IntColumn get wordCount => integer().withDefault(const Constant(0))();

  /// 入库时间（epoch ms）。
  IntColumn get addedAt => integer()();

  /// 元数据更新时间（epoch ms）。
  IntColumn get updatedAt => integer()();

  /// 最近打开时间（epoch ms）。
  IntColumn? get lastOpenedAt => integer().nullable()();

  /// 是否标记读完。
  BoolColumn get isFinished => boolean().withDefault(const Constant(false))();

  /// 是否归档。
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  /// 墓碑：删除时间（epoch ms），参与同步合并。
  IntColumn? get deletedAt => integer().nullable()();

  /// 原始 OPF 其余字段（JSON）。
  TextColumn? get metaJson => text().nullable()();

  /// 最后写入的 HLC 时间戳。
  TextColumn get hlc => text()();

  /// 写入设备标识。
  TextColumn get deviceId => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 章节表：目录 + 定位基准。
@DataClassName('ChapterRow')
class Chapters extends Table {
  /// 所属书籍。
  TextColumn get bookId => text().references(Books, #id)();

  /// 章序号（0 基，spine/目录顺序）。
  IntColumn get idx => integer()();

  /// 章标题。
  TextColumn? get title => text().nullable()();

  /// EPUB spine href / PDF 页段 / TXT 偏移段描述。
  TextColumn get href => text()();

  /// 目录层级（0 顶）。
  IntColumn get level => integer().withDefault(const Constant(0))();

  /// 章内起始字符偏移。
  IntColumn get startOffset => integer().withDefault(const Constant(0))();

  /// 章内字符数。
  IntColumn get charCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {bookId, idx};
}

/// 阅读进度：`locator`（最近一次翻到哪）与 `furthest`（读过的最远处）语义不同。
@DataClassName('ReadingProgressRow')
class ReadingProgress extends Table {
  /// 所属书籍。
  TextColumn get bookId => text().references(Books, #id)();

  /// 当前位置（Locator JSON）。
  TextColumn get locator => text()();

  /// 当前百分比 0..1。
  RealColumn get percent => real()();

  /// 最远位置（Locator JSON）。
  TextColumn? get furthestLocator => text().nullable()();

  /// 最远百分比，合并时取 max 永不回退。
  RealColumn get furthestPercent => real().withDefault(const Constant(0))();

  /// 更新时间（epoch ms）。
  IntColumn get updatedAt => integer()();

  /// HLC。
  TextColumn get hlc => text()();

  /// 写入设备。
  TextColumn get deviceId => text()();

  @override
  Set<Column> get primaryKey => {bookId};
}

/// 划线 / 下划线 / 笔记。
@DataClassName('AnnotationRow')
@TableIndex(name: 'idx_ann_book', columns: {#bookId, #createdAt})
class Annotations extends Table {
  /// uuid v4。
  TextColumn get id => text()();

  /// 所属书籍。
  TextColumn get bookId => text().references(Books, #id)();

  /// 类型：highlight|underline|note。
  TextColumn get type => text()();

  /// 语义色 token：yellow|green|blue|rose。
  TextColumn get color => text()();

  /// 起始 Locator（JSON）。
  TextColumn get locatorStart => text()();

  /// 结束 Locator（JSON）。
  TextColumn get locatorEnd => text()();

  /// 划选原文的冗余副本（笔记列表与导出用）。
  TextColumn? get quotedText => text().nullable()();

  /// 笔记正文。
  TextColumn? get note => text().nullable()();

  /// 创建时间（epoch ms）。
  IntColumn get createdAt => integer()();

  /// 更新时间（epoch ms）。
  IntColumn get updatedAt => integer()();

  /// 墓碑。
  IntColumn? get deletedAt => integer().nullable()();

  /// HLC。
  TextColumn get hlc => text()();

  /// 写入设备。
  TextColumn get deviceId => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 书签。
@DataClassName('BookmarkRow')
class Bookmarks extends Table {
  /// uuid v4。
  TextColumn get id => text()();

  /// 所属书籍。
  TextColumn get bookId => text().references(Books, #id)();

  /// 位置（Locator JSON）。
  TextColumn get locator => text()();

  /// 用户标签。
  TextColumn? get label => text().nullable()();

  /// 创建时间（epoch ms）。
  IntColumn get createdAt => integer()();

  /// 墓碑。
  IntColumn? get deletedAt => integer().nullable()();

  /// HLC。
  TextColumn get hlc => text()();

  /// 写入设备。
  TextColumn get deviceId => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 阅读会话原始数据（可重算 daily_stats）。
@DataClassName('ReadingSessionRow')
class ReadingSessions extends Table {
  /// uuid v4。
  TextColumn get id => text()();

  /// 所属书籍。
  TextColumn get bookId => text()();

  /// 开始时间（epoch ms）。
  IntColumn get startedAt => integer()();

  /// 结束时间（epoch ms）。
  IntColumn get endedAt => integer()();

  /// 会话时长（ms）。
  IntColumn get durationMs => integer()();

  /// 会话读过的字符数。
  IntColumn get charsRead => integer().withDefault(const Constant(0))();

  /// 设备标识。
  TextColumn get deviceId => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 按本地时区日物化的统计聚合（缓存，可由 sessions 重算）。
@DataClassName('DailyStatRow')
class DailyStats extends Table {
  /// 本地日期，格式 yyyy-MM-dd。
  TextColumn get day => text()();

  /// 书籍 id；空串表示全书合计。
  TextColumn get bookId => text().withDefault(const Constant(''))();

  /// 当日阅读时长（ms）。
  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  /// 当日读过的字符数。
  IntColumn get charsRead => integer().withDefault(const Constant(0))();

  /// 当日会话数。
  IntColumn get sessions => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {day, bookId};
}

/// 待上传操作日志（同步是日志复制，见架构文档第六节）。
@DataClassName('SyncOpRow')
class SyncOps extends Table {
  /// 自增序号，分段打包时用 [start, end]。
  IntColumn get seq => integer().autoIncrement()();

  /// 操作唯一 id（幂等合并的键）。
  TextColumn get opId => text().unique()();

  /// 实体类型：book|progress|annotation|bookmark|session。
  TextColumn get entity => text()();

  /// 实体 id。
  TextColumn get entityId => text()();

  /// 操作：upsert|delete。
  TextColumn get op => text()();

  /// 实体快照 JSON（含 hlc/deviceId）。
  TextColumn get payload => text()();

  /// HLC。
  TextColumn get hlc => text()();

  /// 创建时间（epoch ms）。
  IntColumn get createdAt => integer()();

  /// 上传完成时间；NULL = 待上传。
  IntColumn? get uploadedAt => integer().nullable()();

  /// 重试次数。
  IntColumn get retry => integer().withDefault(const Constant(0))();
}

/// 同步键值状态（游标、HLC 快照等）。
@DataClassName('SyncStateRow')
class SyncState extends Table {
  /// 状态键。
  TextColumn get key => text()();

  /// 状态值。
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
