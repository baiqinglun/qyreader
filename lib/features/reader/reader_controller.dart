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
    this.chapterPage = 0,
    this.chapterPages = 0,
    this.bookPage = 0,
    this.bookPages = 0,
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

  /// 章内当前页（1 起；0 = 未知）。
  final int chapterPage;

  /// 章内总页数（0 = 未知）。
  final int chapterPages;

  /// 全书估算当前页（1 起；0 = 未知）。
  final int bookPage;

  /// 全书估算总页数（0 = 未知）。
  final int bookPages;

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
    int? chapterPage,
    int? chapterPages,
    int? bookPage,
    int? bookPages,
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
        chapterPage: chapterPage ?? this.chapterPage,
        chapterPages: chapterPages ?? this.chapterPages,
        bookPage: bookPage ?? this.bookPage,
        bookPages: bookPages ?? this.bookPages,
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

/// 位置百分比：percent 缺失时用页级 pos 兜底。
///
/// 渲染页不再生成整本书的 locations（epub.js 的 locations.generate 会把
/// 全书渲染一遍，手机上几十秒，还和首屏渲染抢 WebView 主线程），
/// 百分比改由页级位置（章索引 + 章内页比例）给出。
///
/// 进度条、阅读统计、进度落库都只依赖这个值，所以两者口径必须一致。
double? locatorPercent(Locator locator) => locator.percent ?? locator.pos;

/// 进度百分比视为「已读」的阈值（页级百分比有浮点误差，不要求严格 1.0）。
const double kReadFinishedThreshold = 0.999;

/// 按阅读进度给出应处的阅读状态：到 100% 即已读，否则在读。
BookReadStatus readStatusForProgress(double? percent) =>
    (percent ?? 0) >= kReadFinishedThreshold
    ? BookReadStatus.finished
    : BookReadStatus.reading;

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
    // 打开即「在读」；如果上次读到 100%，保持「已读」。
    // 导入时的默认状态是「未读」，所以这里是 未读/弃读 → 在读 的入口。
    final desired = readStatusForProgress(progress?.percent);
    state = state.copyWith(
      book: book,
      chapters: chapters,
      initialLocator: pickInitialLocator(progress),
    );
    await _syncReadStatus(desired);
  }

  /// 把阅读状态写到书籍（已相同则不重复写，避免每次翻页都产生同步日志）。
  Future<void> _syncReadStatus(BookReadStatus status) async {
    final book = state.book;
    if (book == null || book.readStatus == status) return;
    state = state.copyWith(book: book.copyWith(readStatus: status));
    try {
      final repo = await ref.read(bookRepositoryProvider.future);
      await repo.setPersonalization(bookId, readStatus: status);
    } catch (e) {
      // 状态写库失败不影响阅读
      debugPrint('阅读状态保存失败: $e');
    }
  }

  /// 可视页位置回报（WebView relocated）。
  void onRelocated(
    Locator locator, {
    required bool atStart,
    required bool atEnd,
    int chapterPage = 0,
    int chapterPages = 0,
    int bookPage = 0,
    int bookPages = 0,
  }) {
    state = state.copyWith(
      currentLocator: locator,
      // percent 缺失时用页级 pos 兜底：渲染页不再生成整本书的 locations
      // （那要把全书渲染一遍），百分比改由页级位置给出。
      percent: locatorPercent(locator),
      currentChapterIndex: locator.chapterIndex,
      atStart: atStart,
      atEnd: atEnd,
      chapterPage: chapterPage,
      chapterPages: chapterPages,
      bookPage: bookPage,
      bookPages: bookPages,
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
      final percent = state.percent ?? locator?.pos;
      if (locator == null || percent == null) return;
      await _write(locator, percent);
    });
  }

  /// 立即落库（退出阅读器时调用）。
  Future<void> flushProgress() async {
    _saveDebounce?.cancel();
    final locator = state.currentLocator;
    final percent = state.percent ?? locator?.pos;
    if (locator == null || percent == null) return;
    await _write(locator, percent);
  }

  /// 落库指定位置（退出阅读时用渲染页给的最终位置）。
  ///
  /// 与 [flushProgress] 的区别：位置来自页面而不是最后一次 relocated 回报，
  /// 保证存的是用户最后看到的那一页。
  Future<void> saveLocator(Locator locator) async {
    _saveDebounce?.cancel();
    final percent = locatorPercent(locator);
    state = state.copyWith(
      currentLocator: locator,
      percent: percent,
      currentChapterIndex: locator.chapterIndex,
    );
    if (percent == null) return;
    await _write(locator, percent);
  }

  Future<void> _write(Locator locator, double percent) async {
    final progressRepo = await ref.read(progressRepositoryProvider.future);
    try {
      await progressRepo.saveProgress(
        bookId: bookId,
        locator: locatorToJson(locator),
        percent: percent.clamp(0.0, 1.0),
      );
      // 读到 100% 自动「已读」；从已读回翻到前面则回到「在读」。
      await _syncReadStatus(readStatusForProgress(percent));
    } catch (e) {
      // 落库失败不阻塞阅读；下一次 relocated 会重试
      debugPrint('进度保存失败: $e');
    }
  }
}
