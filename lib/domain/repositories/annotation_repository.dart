/// 标注与书签仓储接口（领域层）。
///
/// 所有写入同事务追加 sync_ops（entity: annotation|bookmark），
/// 删除为软删（deleted_at 墓碑），同步合并在 M4 接入。
library;

import '../entities/annotation.dart';
import '../entities/bookmark.dart';

/// 标注 + 书签仓储。
abstract interface class AnnotationRepository {
  // ---- 标注 ----

  /// 某本书的全部标注（新在前）。
  Future<List<Annotation>> listForBook(String bookId);

  /// 监听某本书的标注（增删改实时刷新）。
  Stream<List<Annotation>> watchForBook(String bookId);

  /// 新增划线。
  Future<Annotation> addHighlight({
    required String bookId,

    /// 选区范围 CFI（epub.js annotations API 直接可用）。
    required String cfiRange,
    required AnnotationColor color,
    required String quotedText,
    String? href,
    int? chapterIndex,
    /// 原生文本模式的章内字符区间（null = 靠 CFI 定位）。
    int? offset,
    int? offsetEnd,
  });

  /// 修改划线颜色。
  Future<void> setColor(String id, AnnotationColor color);

  /// 保存笔记正文（空串即清除）。
  Future<void> setNote(String id, String note);

  /// 改写划线的锚点（原生文本模式把 CFI 迁移成章索引+字符偏移）。
  Future<void> setAnchor(String id, String locatorJson);

  /// 删除标注（软删）。
  Future<void> remove(String id);

  // ---- 书签 ----

  /// 某本书的全部书签（新在前）。
  Future<List<Bookmark>> listBookmarks(String bookId);

  /// 监听某本书的书签。
  Stream<List<Bookmark>> watchBookmarks(String bookId);

  /// 新增书签。
  Future<Bookmark> addBookmark({
    required String bookId,
    required String locatorJson,
    String? label,
  });

  /// 删除书签（软删）。
  Future<void> removeBookmark(String id);
}
