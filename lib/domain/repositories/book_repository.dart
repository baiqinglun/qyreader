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
  Future<Result<Book>> importFromFile(String sourcePath);

  /// 更新最近打开时间（epoch ms）。
  Future<void> touchOpened(String bookId);
}
