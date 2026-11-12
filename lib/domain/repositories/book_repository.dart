/// 书籍仓储接口（领域层；实现见 data/repositories）。
library;

import '../../core/result.dart';
import '../entities/book.dart';

/// 书籍仓储。
abstract interface class BookRepository {
  /// 监听书架（未删除书籍，按最近打开排序）。
  Stream<List<ShelfItem>> watchShelf();

  /// 从本地文件导入书籍。
  ///
  /// 流程：流式 SHA-256 → 魔数嗅探 → 复制进应用私有目录 →
  /// isolate 解析 → 事务写库（books/chapters + sync_ops）。
  /// 同哈希已存在时返回 `import.duplicate` 失败，不产生第二本。
  ///
  /// [returnExistingOnDuplicate]：书已在架时不报重复错误，而是返回书架
  /// 上的已有书籍。文件管理器「打开方式」用它——系统重建 Activity 重新
  /// 投递同一文件时，直接回到这本书的阅读页而不是停在书架。
  Future<Result<Book>> importFromFile(
    String sourcePath, {
    bool returnExistingOnDuplicate = false,
  });

  /// 按 id 查书；不存在返回 null。
  Future<Book?> getById(String bookId);

  /// 查询书籍章节目录（按 idx 升序）。
  Future<List<BookChapter>> getChapters(String bookId);

  /// 记录「打开书」的时间戳（阅读期间只暂存不落库：书架按最近打开排序，
  /// 打开瞬间落库会让书架重排闪动；退出阅读器时调 [flushOpened] 统一落库）。
  Future<void> touchOpened(String bookId);

  /// 把 [touchOpened] 暂存的打开时间落库（退出阅读器时调用）。
  /// 没有暂存记录时是空操作。
  Future<void> flushOpened(String bookId);

  /// 保存个人化信息。
  ///
  /// 参数 `null` = 该字段不改；显式传值才更新：`rating <= 0`、书评空串、
  /// 空标签列表、分类空串表示清除对应字段。详情页每改一项只传一个字段，
  /// 因此这里不能把未传的字段当成「清空」。
  Future<void> setPersonalization(
    String bookId, {
    int? rating,
    String? review,
    List<String>? tags,
    String? category,
    BookReadStatus? readStatus,
  });

  /// 把所有书的标签 [from] 重命名为 [to]；返回受影响的书数。
  ///
  /// 目标标签已存在时直接合并去重；只改未删除的书籍，并追加同步日志。
  Future<int> renameTag(String from, String to);

  /// 从所有书移除标签 [tag]；返回受影响的书数。
  ///
  /// 只改未删除的书籍，并追加同步日志；不删除书籍本身。
  Future<int> deleteTag(String tag);

  /// 书架置顶开关（置顶时间用于多本置顶时的排序）。
  Future<void> setPinned(String bookId, bool pinned);

  /// 编辑书籍元数据（书籍详情页：书名 / 作者）。
  ///
  /// [title] 非空才更新；[author] 传空串清除作者，null 不变。
  /// 元数据参与多设备同步，走与个人化相同的 hlc + sync_ops 流程。
  Future<void> updateBookMeta(String bookId, {String? title, String? author});

  /// 删除书籍。
  ///
  /// [deleteAnnotations] = true 时一并删除该书的标注与书签（用户在确认
  /// 对话框里选择「同时删除笔记」）；false 则保留标注数据（可先导出）。
  /// 书籍文件、章节目录、阅读进度、阅读会话始终删除，并写一条同步墓碑。
  Future<void> deleteBook(String bookId, {required bool deleteAnnotations});
}
