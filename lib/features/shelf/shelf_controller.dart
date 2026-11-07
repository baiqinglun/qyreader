/// 书架控制器：书籍流 + 导入状态机。
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/providers.dart';
import '../../domain/entities/book.dart';

part 'shelf_controller.freezed.dart';
part 'shelf_controller.g.dart';

/// 导入状态。
@freezed
sealed class ImportState with _$ImportState {
  /// 空闲。
  const factory ImportState.idle() = ImportIdle;

  /// 解析/写库中。
  const factory ImportState.loading() = ImportLoading;

  /// 导入成功。
  const factory ImportState.done(Book book) = ImportDone;

  /// 导入失败（含重复导入提示）。
  const factory ImportState.error(String message) = ImportError;
}

/// 书架书籍流（未删除、按最近打开排序）。
@riverpod
Stream<List<ShelfItem>> shelfItems(Ref ref) async* {
  final repo = await ref.watch(bookRepositoryProvider.future);
  yield* repo.watchShelf();
}

/// 导入控制器。
@riverpod
class ImportController extends _$ImportController {
  @override
  ImportState build() => const ImportState.idle();

  /// 弹出文件选择器并导入一本 EPUB。
  Future<void> importFromPicker() async {
    if (state is ImportLoading) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
      withData: false,
    );
    final path = (picked == null || picked.files.isEmpty)
        ? null
        : picked.files.first.path;
    if (path == null) return; // 用户取消选择
    state = const ImportState.loading();
    try {
      final repo = await ref.read(bookRepositoryProvider.future);
      final result = await repo.importFromFile(path);
      state = result.when(
        ok: ImportState.done,
        failure: (e) => ImportState.error(e.message),
      );
    } catch (e) {
      state = ImportState.error('导入失败：$e');
    }
  }

  /// UI 消费完 done/error 状态后回到 idle。
  void consume() => state = const ImportState.idle();
}
