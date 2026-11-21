/// 微信读书同步服务：拉取 → 对比 → 写入本机。
///
/// 页面只依赖 [WeReadSyncApi]；生产实现用 Riverpod `Ref` 取仓储，测试可以
/// 覆盖 `wereadSyncApiProvider` 注入假实现，不需要网络/数据库。
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/providers.dart';
import '../../../core/locator.dart' as app_locator;
import '../../../domain/entities/annotation.dart';
import '../../../domain/entities/book.dart';
import '../../reader/native/native_chapter_source.dart';
import 'weread_anchor.dart';
import 'weread_client.dart';
import 'weread_compare.dart';
import 'weread_credentials.dart';
import 'weread_epub.dart';
import 'weread_models.dart';
import 'weread_sync_state.dart';

/// 一次拉取 + 对比的结果。
class WeReadFetchResult {
  /// 构造。
  const WeReadFetchResult({
    required this.snapshot,
    required this.diffs,
    required this.state,
    this.progressFailures = 0,
  });

  /// 微信读书快照。
  final WeReadSnapshot snapshot;

  /// 对比结果。
  final List<WeReadDiff> diffs;

  /// 更新后的本地状态。
  final WeReadSyncState state;

  /// 阅读进度接口失败的本数（其它数据仍会展示）。
  final int progressFailures;
}

/// 单本同步的写入结果。
class WeReadApplyResult {
  /// 构造。
  const WeReadApplyResult({
    required this.message,
    this.importedNotes = 0,
    this.skippedNotes = 0,
    this.progressUpdated = false,
    this.statusUpdated = false,
    this.readTimeUpdated = false,
    this.reviewImported = false,
    this.retryable = false,
    this.importedBook,
  });

  /// 可直接展示的摘要。
  final String message;

  /// 本次导入的划线/想法数。
  final int importedNotes;

  /// 原文在本机书里找不到、跳过的条数。
  final int skippedNotes;

  /// 是否更新了阅读进度。
  final bool progressUpdated;

  /// 是否更新了阅读状态。
  final bool statusUpdated;

  /// 是否更新了最近阅读时间。
  final bool readTimeUpdated;

  /// 是否导入了整本书评。
  final bool reviewImported;

  /// 是否有可重试的失败（划线接口失败 / 章节没解析出来）。
  final bool retryable;

  /// 本次导入生成本机书籍时返回（added 行「导入」用）。
  final Book? importedBook;
}

/// 页面可用的微信读书能力。
abstract interface class WeReadSyncApi {
  /// 是否已配置 API Key。
  Future<bool> hasKey();

  /// 保存 API Key。
  Future<void> saveKey(String apiKey);

  /// 清除 API Key。
  Future<void> clearKey();

  /// 拉取并对比。
  Future<WeReadFetchResult> fetch({void Function(String message)? onProgress});

  /// 读取上次抓取快照，并与当前本机书架重新对比（不联网）。
  Future<WeReadFetchResult?> loadCached();

  /// 拉取（并缓存）某本书的划线 / 想法，供查看面板使用。
  Future<List<WeReadNote>> notesFor(String bookId);

  /// 把一本书的微信读书数据写入本机。
  Future<WeReadApplyResult> apply(WeReadDiff diff);

  /// 本机没有正文时，用微信读书元数据生成一本「只有书名」的 EPUB 并导入，
  /// 随后继续同步进度 / 状态 / 划线。
  Future<WeReadApplyResult> importAdded(WeReadDiff diff);

  /// 忽略一条「已从微信读书移除」的记录。
  Future<void> ignore(WeReadDiff diff);
}

/// 生产实现。
class WeReadSyncService implements WeReadSyncApi {
  /// 构造。
  WeReadSyncService(
    this.ref, {
    WeReadCredentials? credentials,
    WeReadSyncStore store = const WeReadSyncStore(),
  }) : _credentials = credentials ?? WeReadCredentials(),
       _store = store;

  /// Riverpod 依赖入口。
  final Ref ref;

  final WeReadCredentials _credentials;
  final WeReadSyncStore _store;

  /// 本次运行里按书缓存的划线/想法（查看面板与同步共用，避免重复请求）。
  final Map<String, List<WeReadNote>> _notesCache =
      <String, List<WeReadNote>>{};

  @override
  Future<bool> hasKey() async => (await _credentials.read()) != null;

  @override
  Future<void> saveKey(String apiKey) => _credentials.save(apiKey);

  @override
  Future<void> clearKey() => _credentials.clear();

  @override
  Future<WeReadFetchResult> fetch({
    void Function(String message)? onProgress,
  }) async {
    final key = await _credentials.read();
    if (key == null) {
      throw const WeReadApiException('请先在右上角扫码登录微信读书');
    }
    final client = WeReadClient(apiKey: key);
    _notesCache.clear();

    onProgress?.call('正在读取微信读书书架…');
    final shelf = await client.fetchShelf();

    onProgress?.call('正在读取笔记概览…');
    final notebooks = await _fetchNotebooks(client);

    final progress = <WeReadProgress?>[];
    var failures = 0;
    if (shelf.books.isNotEmpty) {
      final results = List<WeReadProgress?>.filled(shelf.books.length, null);
      final failed = List<bool>.filled(shelf.books.length, false);
      var cursor = 0;
      var done = 0;
      // 书架可能有几百本；逐本进度只给 45 秒总预算，超时先出结果，
      // 免得页面卡在「正在读取阅读进度」。
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      Future<void> worker() async {
        while (true) {
          if (DateTime.now().isAfter(deadline)) return;
          final index = cursor++;
          if (index >= shelf.books.length) return;
          try {
            results[index] = await client
                .fetchProgress(shelf.books[index].bookId)
                .timeout(const Duration(seconds: 12));
          } catch (_) {
            // 单本失败不拖垮整次拉取。
            failed[index] = true;
          }
          done++;
          onProgress?.call('正在读取阅读进度 $done/${shelf.books.length}');
        }
      }

      await Future.wait(<Future<void>>[
        for (var i = 0; i < math.min(4, shelf.books.length); i++) worker(),
      ]);
      failures = failed.where((item) => item).length;
      progress.addAll(results);
    }

    final books = <WeReadBook>[];
    for (var i = 0; i < shelf.books.length; i++) {
      var book = shelf.books[i];
      final notebook = notebooks[book.bookId];
      if (notebook != null) {
        book = book.copyWith(
          noteCount: notebook.noteCount,
          reviewCount: notebook.reviewCount,
          bookmarkCount: notebook.bookmarkCount,
          progressPercent: book.progressPercent ?? notebook.readingProgress,
          finished: book.finished || notebook.finished,
        );
      }
      final item = i < progress.length ? progress[i] : null;
      books.add(mergeWeReadProgress(book, item));
    }

    final snapshot = WeReadSnapshot(
      books: books,
      fetchedAt: DateTime.now(),
      albumCount: shelf.albumCount,
      hasMp: shelf.hasMp,
      progressFailures: failures,
    );
    // 先缓存快照：下次进入页面直接展示，不必等网络。缓存写失败不影响本次结果。
    try {
      await _store.saveSnapshot(snapshot);
    } catch (_) {}

    onProgress?.call('正在与本机书籍对比…');
    final local = await _loadLocalContext();

    var state = await _store.load();
    final diffs = compareWeReadBooks(
      remote: books,
      localShelf: local.shelf,
      state: state,
      localAnnotationCounts: local.annotationCounts,
    );
    final links = Map<String, String>.of(state.links);
    for (final diff in diffs) {
      final local = diff.local;
      if (local != null && diff.kind != WeReadDiffKind.deleted) {
        links[diff.remote.bookId] = local.id;
      }
    }
    state = WeReadSyncState(
      links: links,
      seen: <String>{
        for (final book in books)
          if (book.bookId.isNotEmpty) book.bookId,
      },
      known: <String, WeReadKnownBook>{
        for (final book in books)
          if (book.bookId.isNotEmpty)
            book.bookId: WeReadKnownBook(
              title: book.title,
              author: book.author,
              cover: book.cover,
            ),
      },
      importedMarks: state.importedMarks,
      importedCounts: state.importedCounts,
      syncedNoteTotals: state.syncedNoteTotals,
      skippedCounts: state.skippedCounts,
      importedReadingSeconds: state.importedReadingSeconds,
      lastSyncAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _store.save(state);

    return WeReadFetchResult(
      snapshot: snapshot,
      diffs: diffs,
      state: state,
      progressFailures: failures,
    );
  }

  @override
  Future<WeReadFetchResult?> loadCached() async {
    final snapshot = await _store.loadSnapshot();
    if (snapshot == null) return null;
    try {
      final local = await _loadLocalContext();
      final state = await _store.load();
      final diffs = compareWeReadBooks(
        remote: snapshot.books,
        localShelf: local.shelf,
        state: state,
        localAnnotationCounts: local.annotationCounts,
      );
      return WeReadFetchResult(
        snapshot: snapshot,
        diffs: diffs,
        state: state,
        progressFailures: snapshot.progressFailures,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<WeReadNote>> notesFor(String bookId) async {
    final cached = _notesCache[bookId];
    if (cached != null) return cached;
    final key = await _credentials.read();
    if (key == null) {
      throw const WeReadApiException('请先在右上角扫码登录微信读书');
    }
    return _loadNotes(WeReadClient(apiKey: key), bookId);
  }

  Future<List<WeReadNote>> _loadNotes(
    WeReadClient client,
    String bookId,
  ) async {
    final cached = _notesCache[bookId];
    if (cached != null) return cached;
    final notes = await client.fetchNotes(bookId);
    _notesCache[bookId] = notes;
    return notes;
  }

  Future<({List<ShelfItem> shelf, Map<String, int> annotationCounts})>
  _loadLocalContext() async {
    final bookRepo = await ref.read(bookRepositoryProvider.future);
    final shelf = await bookRepo.watchShelf().first;
    final annotationRepo = await ref.read(annotationRepositoryProvider.future);
    final annotations = await annotationRepo.watchAll().first;
    final counts = <String, int>{};
    for (final annotation in annotations) {
      counts.update(annotation.bookId, (value) => value + 1, ifAbsent: () => 1);
    }
    return (shelf: shelf, annotationCounts: counts);
  }

  @override
  Future<WeReadApplyResult> apply(WeReadDiff diff) async {
    if (diff.kind == WeReadDiffKind.deleted) {
      await ignore(diff);
      return const WeReadApplyResult(message: '已忽略这条「已移除」记录');
    }
    final local = diff.local;
    if (local == null) {
      throw const WeReadApiException('本地书架没有这本书；请先导入同名 EPUB/TXT 后再同步。');
    }
    final key = await _credentials.read();
    if (key == null) {
      throw const WeReadApiException('请先在右上角扫码登录微信读书');
    }
    final client = WeReadClient(apiKey: key);

    final bookRepo = await ref.read(bookRepositoryProvider.future);
    final progressRepo = await ref.read(progressRepositoryProvider.future);
    final annotationRepo = await ref.read(annotationRepositoryProvider.future);
    final book = await bookRepo.getById(local.id);
    if (book == null) {
      throw const WeReadApiException('本机书籍已被删除，无法同步');
    }

    // 书架快照的进度是批量拉的（4 并发 + 45 秒预算），书多时很多书拿不到
    // recordReadingTime。单本同步 / 导入时再拉一次，免得「导入了书却没有阅读时间」。
    var remote = diff.remote;
    try {
      final fresh = await client
          .fetchProgress(remote.bookId)
          .timeout(const Duration(seconds: 15));
      remote = mergeWeReadProgress(remote, fresh);
    } catch (_) {
      // 单本进度失败不阻断同步，继续用快照里的数据。
    }

    var notesFailed = false;
    List<WeReadNote> notes;
    try {
      notes = await _loadNotes(client, remote.bookId);
    } catch (_) {
      // 划线接口失败不能拖累进度/状态：笔记单独报失败。
      notes = const <WeReadNote>[];
      notesFailed = true;
    }
    var chaptersLoaded = false;
    List<NativeChapter> chapters = const <NativeChapter>[];
    try {
      chapters = await _loadChapters(book);
      chaptersLoaded = true;
    } catch (_) {
      // 章节解析失败时仍写入进度/状态，只是无法导入划线。
      chapters = const <NativeChapter>[];
    }

    var state = await _store.load();
    final importedMarks = Set<String>.of(state.importedMarks);
    final existing = await annotationRepo.listForBook(book.id);
    final existingByKey = <String, Annotation>{
      for (final annotation in existing)
        if (annotation.quotedText != null && annotation.quotedText!.isNotEmpty)
          '${annotation.chapterIndex}|${annotation.quotedText}': annotation,
    };

    var imported = 0;
    var alreadyPresent = 0;
    var notesUpdated = 0;
    var skipped = 0;
    var fallbackAnchored = 0;
    var reviewImported = false;

    // 整本书评按编辑时间取最新：本机没有直接用；本机有则只接受更晚的。
    WeReadNote? latestReview;
    for (final note in notes) {
      if (!note.wholeBookReview || note.thought.trim().isEmpty) continue;
      final current = latestReview;
      if (current == null || (note.editedAt ?? 0) > (current.editedAt ?? 0)) {
        latestReview = note;
      }
    }
    if (latestReview != null) {
      final remoteReviewMs = (latestReview.editedAt ?? 0) * 1000;
      final localReview = (book.review ?? '').trim();
      final localReviewMs = book.updatedAt;
      if (localReview.isEmpty || remoteReviewMs > localReviewMs + 1000) {
        if (localReview != latestReview.thought.trim()) {
          await bookRepo.setPersonalization(
            book.id,
            review: latestReview.thought,
          );
          reviewImported = true;
        }
      }
    }

    for (final note in notes) {
      if (note.wholeBookReview) continue;
      if (note.quote.trim().isEmpty) {
        skipped++;
        continue;
      }
      final noteId = _noteId(note);
      var anchor = locateWeReadNote(chapters, note);
      var usedFallback = false;
      if (anchor == null && chaptersLoaded) {
        // 找不到原文也保留：落到该章开头，至少标注列表里能看到原文与想法。
        anchor = locateWeReadNoteFallback(chapters, note);
        usedFallback = anchor != null;
      }
      if (anchor == null) {
        // 章节没解析出来时不要把划线记成「已跳过」，下次打开书还能重试。
        if (chaptersLoaded) skipped++;
        continue;
      }
      final duplicateKey = '${anchor.chapterIndex}|${note.quote}';
      final localAnnotation = existingByKey[duplicateKey];
      if (localAnnotation != null) {
        // 本机标注已存在：只有微信读书这次编辑更晚才覆盖想法/颜色。
        final remoteMs = (note.editedAt ?? 0) * 1000;
        if (remoteMs > localAnnotation.updatedAt + 1000) {
          var changed = false;
          final thought = note.thought.trim();
          if (thought.isNotEmpty &&
              thought != (localAnnotation.note ?? '').trim()) {
            await annotationRepo.setNote(localAnnotation.id, thought);
            changed = true;
          }
          if (note.colorStyle != null) {
            final color = colorForWeReadStyle(note.colorStyle);
            if (color != localAnnotation.color) {
              await annotationRepo.setColor(localAnnotation.id, color);
              changed = true;
            }
          }
          if (changed) notesUpdated++;
        }
        importedMarks.add(noteId);
        alreadyPresent++;
        continue;
      }
      if (importedMarks.contains(noteId)) continue;
      final created = await annotationRepo.addHighlight(
        bookId: book.id,
        cfiRange: '@${anchor.chapterIndex}:${anchor.start}:${anchor.end}',
        color: colorForWeReadStyle(note.colorStyle),
        quotedText: note.quote,
        href: anchor.href,
        chapterIndex: anchor.chapterIndex,
        offset: anchor.start,
        offsetEnd: anchor.end,
      );
      if (note.thought.trim().isNotEmpty) {
        await annotationRepo.setNote(created.id, note.thought.trim());
      }
      importedMarks.add(noteId);
      existingByKey[duplicateKey] = created;
      imported++;
      if (usedFallback) fallbackAnchored++;
    }

    var progressUpdated = false;
    final targetPercent = (remote.progressPercent ?? 0) / 100;
    final currentProgress = await progressRepo.getProgress(book.id);
    final localPercent = currentProgress?.percent ?? diff.localPercent;
    final remoteReadMs = (remote.lastReadAt ?? 0) * 1000;
    final localProgressMs = currentProgress?.updatedAt ?? 0;
    final remoteHasTime = remoteReadMs > 0;
    // 进度按最后编辑时间 LWW：微信读书更晚就连回退也要跟；本机更晚则保留本机。
    // 远程没有时间戳时退回旧策略（只前进，不下调）。
    final remoteProgressNewer =
        remoteHasTime &&
        (localProgressMs == 0 || remoteReadMs > localProgressMs + 1000);
    final shouldApplyProgress = !remoteHasTime
        ? targetPercent > localPercent + 0.001
        : remoteProgressNewer && (targetPercent - localPercent).abs() > 0.001;
    if (shouldApplyProgress) {
      // 优先用刚解析出的章节正文长度换算落点：数据库里的 char_count 对旧书
      // 可能还是 0，直接按 DB 算会落到第一章。
      final anchor = locatePercentInChapters(chapters, targetPercent);
      if (anchor != null) {
        final locator = app_locator.Locator(
          href: anchor.href,
          chapterIndex: anchor.chapterIndex,
          offset: anchor.start,
          percent: targetPercent,
          pos: targetPercent,
        );
        await progressRepo.saveProgress(
          bookId: book.id,
          locator: app_locator.locatorToJson(locator),
          percent: targetPercent,
        );
      } else {
        await progressRepo.saveExternalProgress(
          bookId: book.id,
          percent: targetPercent,
        );
      }
      progressUpdated = true;
    }

    BookReadStatus? nextStatus;
    final remoteStatusWins =
        remoteProgressNewer ||
        (!remoteHasTime && (remote.finished || targetPercent >= 0.999));
    if (remoteStatusWins && book.readStatus != BookReadStatus.dropped) {
      final desired = (remote.finished || targetPercent >= 0.999)
          ? BookReadStatus.finished
          : targetPercent > 0.001
          ? BookReadStatus.reading
          : BookReadStatus.unread;
      if (book.readStatus != desired) nextStatus = desired;
    }
    final nextOpenedAt = remoteReadMs > (book.lastOpenedAt ?? 0) + 60 * 1000
        ? remoteReadMs
        : null;
    // 微信读书只在 progress=100 时返回 finishTime；没有时退回最后阅读时间。
    final remoteFinished = remote.finished || targetPercent >= 0.999;
    final finishCandidate = math.max(
      (remote.finishTime ?? 0) * 1000,
      remoteFinished ? remoteReadMs : 0,
    );
    final nextFinishedAt = finishCandidate > (book.finishedAt ?? 0) + 1000
        ? finishCandidate
        : null;
    var statusUpdated = false;
    var readTimeUpdated = false;
    var finishedAtUpdated = false;
    if (nextStatus != null || nextOpenedAt != null || nextFinishedAt != null) {
      await bookRepo.applyReadingState(
        book.id,
        readStatus: nextStatus,
        lastOpenedAt: nextOpenedAt,
        finishedAt: nextFinishedAt,
      );
      statusUpdated = nextStatus != null;
      readTimeUpdated = nextOpenedAt != null;
      finishedAtUpdated = nextFinishedAt != null;
    }

    // 微信读书的累计阅读秒数写进本机统计（只补差额，重复同步不累加）。
    // 导入是单向的：即使本机最近阅读时间更晚，微信读书那部分未导入的时长
    // 也照样补进来，这样书籍信息里的「阅读时间」能看到两边相加的总量。
    final statsRepo = await ref.read(statsRepositoryProvider.future);
    var importedReadingSeconds =
        state.importedReadingSeconds[remote.bookId] ?? 0;
    var readingTimeImported = 0;
    final remoteReadingSeconds = remote.readingSeconds ?? 0;
    // 旧版（v2.58.4）在「本机更晚」时会把差额记为已导入却没写会话。
    // 如果本机累计时长还小于这个「已导入」值，说明当时其实没写进来，
    // 清零后重新补，避免升级后这部分时长永远不出现。
    if (importedReadingSeconds > 0) {
      final localTotalMs = await statsRepo.bookTotalDurationMs(book.id);
      if (localTotalMs < importedReadingSeconds * 1000) {
        importedReadingSeconds = 0;
      }
    }
    if (remoteReadingSeconds > importedReadingSeconds + 9) {
      final delta = remoteReadingSeconds - importedReadingSeconds;
      final endedAt = remoteReadMs > 0
          ? remoteReadMs
          : DateTime.now().millisecondsSinceEpoch;
      // 只有总时长，没有每日明细：会话锚在最后阅读日（最多往前 1 小时，
      // 避免把整段时长算到很久以前的那一天），计入时长仍为完整差额。
      await statsRepo.recordSession(
        bookId: book.id,
        startedAt:
            endedAt -
            math.min(delta * 1000, const Duration(hours: 1).inMilliseconds),
        endedAt: endedAt,
        charsRead: 0,
        countedDurationMs: delta * 1000,
      );
      readingTimeImported = delta;
      importedReadingSeconds = remoteReadingSeconds;
    }

    // 只有「笔记拉取完成 + 章节可用」才推进处理基线；接口失败或章节没解析
    // 出来时保留旧基线，下次同步继续把没处理的笔记算成新增并重试。
    // 远端明明有笔记却一条都没拉到（空数组 200 / 权限异常）时也不要推进
    // 基线，否则会把没导入的笔记永久藏起来。
    final notesComplete =
        !notesFailed &&
        (chaptersLoaded || notes.isEmpty) &&
        (notes.isNotEmpty || remote.totalNotes == 0);
    state = state.copyWith(
      links: <String, String>{...state.links, remote.bookId: book.id},
      importedMarks: importedMarks,
      importedCounts: <String, int>{
        ...state.importedCounts,
        remote.bookId:
            (state.importedCounts[remote.bookId] ?? 0) +
            imported +
            alreadyPresent,
      },
      syncedNoteTotals: <String, int>{
        ...state.syncedNoteTotals,
        if (notesComplete) remote.bookId: remote.totalNotes,
      },
      skippedCounts: <String, int>{
        ...state.skippedCounts,
        remote.bookId: (state.skippedCounts[remote.bookId] ?? 0) + skipped,
      },
      importedReadingSeconds: <String, int>{
        ...state.importedReadingSeconds,
        remote.bookId: importedReadingSeconds,
      },
      lastSyncAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _store.save(state);

    final chapterBlocked = !chaptersLoaded && notes.isNotEmpty;
    final retryable = notesFailed || chapterBlocked;
    final parts = <String>[
      if (progressUpdated) '阅读进度已更新',
      if (statusUpdated) '阅读状态已更新',
      if (readTimeUpdated) '最近阅读时间已更新',
      if (finishedAtUpdated) '读完时间已更新',
      if (readingTimeImported > 0)
        '导入 ${_durationLabel(readingTimeImported)} 阅读时长',
      if (imported > 0) '导入 $imported 条划线/想法',
      if (notesUpdated > 0) '更新 $notesUpdated 条划线/想法',
      if (reviewImported) '更新书评',
      if (alreadyPresent > 0) '跳过 $alreadyPresent 条已有标注',
      if (fallbackAnchored > 0) '$fallbackAnchored 条原文未找到，已按章首定位',
      if (skipped > 0) '$skipped 条原文未找到，已跳过',
      if (notesFailed) '划线/想法没拉到，可稍后重试',
      if (chapterBlocked) '章节解析失败，划线未导入，可稍后重试',
    ];
    return WeReadApplyResult(
      message: parts.isEmpty ? '已是最新，没有需要写入的数据' : parts.join('，'),
      importedNotes: imported,
      skippedNotes: skipped,
      progressUpdated: progressUpdated,
      statusUpdated: statusUpdated,
      readTimeUpdated: readTimeUpdated,
      reviewImported: reviewImported,
      retryable: retryable,
    );
  }

  @override
  Future<WeReadApplyResult> importAdded(WeReadDiff diff) async {
    if (diff.kind != WeReadDiffKind.added) {
      throw const WeReadApiException('只有「新增」的书需要导入');
    }
    final key = await _credentials.read();
    if (key == null) {
      throw const WeReadApiException('请先在右上角扫码登录微信读书');
    }
    final client = WeReadClient(apiKey: key);
    WeReadBookInfo? info;
    try {
      info = await client.fetchBookInfo(diff.remote.bookId);
    } catch (_) {
      // 详情接口失败不阻塞导入，用书架字段兜底。
    }
    final title = (info?.title ?? '').trim().isNotEmpty
        ? info!.title.trim()
        : (diff.remote.title.trim().isEmpty
              ? '未命名书籍'
              : diff.remote.title.trim());
    final author = info?.author ?? diff.remote.author;
    final category = info?.category ?? diff.remote.category;
    final coverBytes = await _downloadCover(info?.cover ?? diff.remote.cover);
    final bytes = buildWeReadEpub(
      bookId: diff.remote.bookId,
      title: title,
      author: author,
      description: info?.intro,
      category: category,
      publisher: info?.publisher,
      publishTime: info?.publishTime,
      coverBytes: coverBytes,
    );

    final tempDir = await getTemporaryDirectory();
    final safeId = diff.remote.bookId.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '_',
    );
    final tempFile = File(p.join(tempDir.path, 'weread-$safeId.epub'));
    final bookRepo = await ref.read(bookRepositoryProvider.future);
    late final Book book;
    try {
      await tempFile.writeAsBytes(bytes, flush: true);
      final imported = await bookRepo.importFromFile(
        tempFile.path,
        returnExistingOnDuplicate: true,
      );
      final failure = imported.when(ok: (_) => null, failure: (error) => error);
      if (failure != null) {
        throw WeReadApiException('生成书籍导入失败：${failure.message}');
      }
      book = imported.dataOrNull!;
    } on WeReadApiException {
      rethrow;
    } catch (error) {
      throw WeReadApiException('生成占位书籍失败：$error');
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }

    final currentCategory = book.category?.trim() ?? '';
    final newCategory = (category ?? '').trim();
    if (currentCategory.isEmpty && newCategory.isNotEmpty) {
      await bookRepo.setPersonalization(book.id, category: newCategory);
    }

    final applied = await apply(
      WeReadDiff(
        kind: WeReadDiffKind.updated,
        remote: diff.remote,
        local: book,
        localPercent: 0,
        newNoteCount: diff.newNoteCount,
        changes: diff.changes,
      ),
    );
    final suffix = applied.message.startsWith('已是最新')
        ? ''
        : '，${applied.message}';
    return WeReadApplyResult(
      message: '已导入《${book.title}》$suffix',
      importedNotes: applied.importedNotes,
      skippedNotes: applied.skippedNotes,
      progressUpdated: applied.progressUpdated,
      statusUpdated: applied.statusUpdated,
      readTimeUpdated: applied.readTimeUpdated,
      reviewImported: applied.reviewImported,
      retryable: applied.retryable,
      importedBook: book,
    );
  }

  Future<Uint8List?> _downloadCover(String? url) async {
    var raw = url?.trim() ?? '';
    if (raw.startsWith('//')) raw = 'https:$raw';
    if (!raw.startsWith('http')) return null;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(Uri.parse(raw))
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.userAgentHeader, 'QYReader/2.57');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok) return null;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        builder.add(chunk);
        if (builder.length > 8 * 1024 * 1024) return null;
      }
      final bytes = builder.takeBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> ignore(WeReadDiff diff) async {
    if (diff.kind != WeReadDiffKind.deleted) return;
    final state = await _store.load();
    final links = Map<String, String>.of(state.links)
      ..remove(diff.remote.bookId);
    final known = Map<String, WeReadKnownBook>.of(state.known)
      ..remove(diff.remote.bookId);
    final seen = Set<String>.of(state.seen)..remove(diff.remote.bookId);
    final importedCounts = Map<String, int>.of(state.importedCounts)
      ..remove(diff.remote.bookId);
    final skippedCounts = Map<String, int>.of(state.skippedCounts)
      ..remove(diff.remote.bookId);
    await _store.save(
      state.copyWith(
        links: links,
        known: known,
        seen: seen,
        importedCounts: importedCounts,
        skippedCounts: skippedCounts,
      ),
    );
  }

  Future<Map<String, WeReadNotebook>> _fetchNotebooks(
    WeReadClient client,
  ) async {
    final result = <String, WeReadNotebook>{};
    int? lastSort;
    for (var page = 0; page < 20; page++) {
      final pageData = await client.fetchNotebooksPage(lastSort: lastSort);
      for (final notebook in pageData.notebooks) {
        result[notebook.bookId] = notebook;
      }
      if (!pageData.hasMore) break;
      final next = pageData.lastSort;
      if (next == null || next == lastSort) break;
      lastSort = next;
    }
    return result;
  }

  Future<List<NativeChapter>> _loadChapters(Book book) async {
    final provider = nativeChaptersProvider(NativeChaptersKey.of(book));
    // autoDispose family 只用 ref.read 可能在 await 期间被回收；挂一个
    // 监听保活，读完立刻关掉。
    final subscription = ref.listen<AsyncValue<List<NativeChapter>>>(
      provider,
      (_, __) {},
    );
    try {
      return await ref.read(provider.future);
    } finally {
      subscription.close();
    }
  }
}

/// 页面使用的 provider；测试可覆盖成假实现。
final wereadSyncApiProvider = Provider<WeReadSyncApi>(
  (ref) => WeReadSyncService(ref),
);

String _durationLabel(int seconds) {
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes / 60;
  return '${hours.toStringAsFixed(hours < 10 ? 1 : 0)} 小时';
}

String _noteId(WeReadNote note) {
  if (note.id.isNotEmpty) return note.id;
  return '${note.bookId}:${note.range}:${note.createdAt ?? note.quote.hashCode}';
}
