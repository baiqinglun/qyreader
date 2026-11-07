/// 阅读器控制器：书籍装载、进度恢复与防抖落库。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/locator.dart';
import '../../app/providers.dart';
import '../../domain/entities/book.dart';
import '../../domain/entities/reading_progress.dart';

part 'reader_controller.g.dart';

/// 阅读器状态。
class ReaderState {
  const ReaderState({
    this.book,
    this.chapters = const [],
    this.initialLocator,
    this.currentLocator,
    this.percent,
    this.currentChapterIndex,
    this.atStart = false,
    this.atEnd = false,
    this.locationsReady = false,
    this.loadError,
  });

  /// 当前书；null = 还在装载。
  final Book? book;

  /// 章节目录。
  final List<BookChapter> chapters;

  /// 打开时的初始位置（恢复进度或 null 从头读）。
  final Locator? initialLocator;

  /// 可视页当前位置。
  final Locator? currentLocator;

  /// 可视页百分比 0..1（locations 未就绪时为 null）。
  final double? percent;

  /// 当前章索引（目录高亮用）。
  final int? currentChapterIndex;

  /// 是否书首。
  final bool atStart;

  /// 是否书末。
  final bool atEnd;

  /// locations 是否生成完成（进度条可用）。
  final bool locationsReady;

  /// 装载失败信息。
  final String? loadError;

  /// 拷贝（控制器内部使用）。
  ReaderState copyWith({
    Book? book,
    List<BookChapter>? chapters,
    Object? initialLocator = _sentinel,
    Object? currentLocator = _sentinel,
    Object? percent = _sentinel,
    Object? currentChapterIndex = _sentinel,
    bool? atStart,
    bool? atEnd,
    bool? locationsReady,
    Object? loadError = _sentinel,
  }) =>
      ReaderState(
        book: book ?? this.book,
        chapters: chapters ?? this.chapters,
        initialLocator: initialLocator == _sentinel
            ? this.initialLocator
            : initialLocator as Locator?,
        currentLocator: currentLocator == _sentinel
            ? this.currentLocator
            : currentLocator as Locator?,
        percent: percent == _sentinel ? this.percent : percent as double?,
        currentChapterIndex: currentChapterIndex == _sentinel
            ? this.currentChapterIndex
            : currentChapterIndex as int?,
        atStart: atStart ?? this.atStart,
        atEnd: atEnd ?? this.atEnd,
        locationsReady: locationsReady ?? this.locationsReady,
        loadError:
            loadError == _sentinel ? this.loadError : loadError as String?,
      );

  static const Object _sentinel = Object();
}

/// 从已存进度挑出打开时的初始位置。
///
/// 恢复链：当前 locator（CFI 优先，percent 兜底）→ 最远 locator → null。
Locator? pickInitialLocator(ReadingProgressSnapshot? progress) {
  if (progress == null) return null;
  Locator? usable(String? raw) {
    final loc = locatorFromJson(raw ?? '');
    if (loc == null) return null;
    final usable = loc.cfi != null || loc.percent != null || loc.href != null;
    return usable ? loc : null;
  }

  return usable(progress.locator) ?? usable(progress.furthestLocator);
}

/// 阅读器控制器（按 bookId family）。
@riverpod
class ReaderController extends _$ReaderController {
  Timer? _saveDebounce;

  /// 页面销毁后异步链（init 的多次 await）不得再写 state，
  /// 否则触发 defunct 元素断言（debug 崩溃）。
  bool _disposed = false;

  @override
  ReaderState build(String bookId) {
    debugPrint('reader-ctrl: build($bookId) re-created');
    ref.onDispose(() {
      debugPrint('reader-ctrl: DISPOSED ($bookId)');
      _disposed = true;
      _saveDebounce?.cancel();
    });
    return const ReaderState();
  }

  /// 装载书籍与进度。页面 initState 时调用一次。
  Future<void> init() async {
    final bookRepo = await ref.read(bookRepositoryProvider.future);
    final progressRepo = await ref.read(progressRepositoryProvider.future);
    if (_disposed) return;

    final book = await bookRepo.getById(bookId);
    if (_disposed) return;
    if (book == null) {
      state = state.copyWith(loadError: '书籍不存在或已被删除');
      return;
    }
    await bookRepo.touchOpened(bookId);
    final chapters = await bookRepo.getChapters(bookId);
    if (_disposed) return;

    final progress = await progressRepo.getProgress(bookId);
    if (_disposed) return;
    state = state.copyWith(
      book: book,
      chapters: chapters,
      initialLocator: pickInitialLocator(progress),
    );
  }

  /// 可视页位置回报（WebView relocated）。
  void onRelocated(Locator locator,
      {required bool atStart, required bool atEnd}) {
    state = state.copyWith(
      currentLocator: locator,
      percent: locator.percent,
      currentChapterIndex: locator.chapterIndex,
      atStart: atStart,
      atEnd: atEnd,
    );
    _scheduleSave();
  }

  /// locations 生成完成。
  void onLocationsReady() {
    state = state.copyWith(locationsReady: true);
  }

  /// 渲染错误上报。
  void onLoadError(String message) {
    state = state.copyWith(loadError: message);
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () async {
      final locator = state.currentLocator;
      final percent = state.percent;
      if (locator == null || percent == null) return;
      final progressRepo = await ref.read(progressRepositoryProvider.future);
        try {
        await progressRepo.saveProgress(
          bookId: bookId,
          locator: locatorToJson(locator),
          percent: percent.clamp(0.0, 1.0),
        );
      } catch (e) {
        // 落库失败不阻塞阅读；下一次 relocated 会重试
        debugPrint('进度保存失败: $e');
      }
    });
  }

  /// 立即落库（退出阅读器时调用）。
  Future<void> flushProgress() async {
    _saveDebounce?.cancel();
    final locator = state.currentLocator;
    final percent = state.percent;
    if (locator == null || percent == null) return;
    final progressRepo = await ref.read(progressRepositoryProvider.future);
    try {
      await progressRepo.saveProgress(
        bookId: bookId,
        locator: locatorToJson(locator),
        percent: percent.clamp(0.0, 1.0),
      );
    } catch (e) {
      debugPrint('进度保存失败: $e');
    }
  }
}
