/// 微信读书 ↔ 本机书籍的对比逻辑（纯函数，可单测）。
///
/// 匹配策略（从强到弱）：
/// 1. 上次同步记下的 bookId → 本机书籍 id；
/// 2. 规范化书名 + 作者完全一致；
/// 3. 规范化书名唯一；
/// 4. 去掉「（全集）/（新版）」这类括注后的书名唯一。
///
/// 对比只产生「需要写入本机」的方向：微信读书进度比本机靠后、微信读书
/// 已读完、微信读书多了划线/想法、最近阅读时间更晚。本机进度更靠后时
/// 不产生更新（同步绝不回退本地进度）。
library;

import 'dart:math' as math;

import '../../../domain/entities/book.dart';
import 'weread_models.dart';
import 'weread_sync_state.dart';

/// 单本书的对比结果。
enum WeReadDiffKind {
  /// 微信读书有、本机没有。
  added,

  /// 两边都有，但微信读书有更新的数据。
  updated,

  /// 两边一致。
  synced,

  /// 上次在书架、这次已从微信读书移除。
  deleted,
}

/// 一本书的对比结果。
class WeReadDiff {
  /// 构造。
  const WeReadDiff({
    required this.kind,
    required this.remote,
    this.local,
    this.localPercent = 0,
    this.localAnnotationCount = 0,
    this.newNoteCount = 0,
    this.changes = const <String>[],
  });

  /// 对比结论。
  final WeReadDiffKind kind;

  /// 微信读书一侧（已移除的书用上次缓存的元数据合成）。
  final WeReadBook remote;

  /// 匹配到的本机书籍。
  final Book? local;

  /// 本机阅读进度 0..1。
  final double localPercent;

  /// 本机标注条数。
  final int localAnnotationCount;

  /// 微信读书新增、尚未导入的划线/想法数。
  final int newNoteCount;

  /// 人类可读的差异说明。
  final List<String> changes;

  /// 复制并覆盖展示字段。
  WeReadDiff copyWith({
    WeReadDiffKind? kind,
    List<String>? changes,
    int? newNoteCount,
    Book? localOverride,
    double? localPercentOverride,
  }) {
    return WeReadDiff(
      kind: kind ?? this.kind,
      remote: remote,
      local: localOverride ?? local,
      localPercent: localPercentOverride ?? localPercent,
      localAnnotationCount: localAnnotationCount,
      newNoteCount: newNoteCount ?? this.newNoteCount,
      changes: changes ?? this.changes,
    );
  }
}

/// 对比微信读书书架与本机书架。
///
/// [localAnnotationCounts] 是 bookId → 本机标注数，只用于展示。
List<WeReadDiff> compareWeReadBooks({
  required List<WeReadBook> remote,
  required List<ShelfItem> localShelf,
  required WeReadSyncState state,
  Map<String, int> localAnnotationCounts = const <String, int>{},
}) {
  final byId = <String, ShelfItem>{
    for (final item in localShelf) item.book.id: item,
  };
  final exact = <String, ShelfItem>{};
  final byTitle = <String, List<ShelfItem>>{};
  final byBaseTitle = <String, List<ShelfItem>>{};
  for (final item in localShelf) {
    final title = normalizeWeReadTitle(item.book.title);
    if (title.isEmpty) continue;
    final author = normalizeWeReadAuthor(item.book.author);
    if (author.isNotEmpty) exact['$title|$author'] = item;
    byTitle.putIfAbsent(title, () => <ShelfItem>[]).add(item);
    final base = baseWeReadTitle(item.book.title);
    if (base.isNotEmpty && base != title) {
      byBaseTitle.putIfAbsent(base, () => <ShelfItem>[]).add(item);
    }
  }

  ShelfItem? findLocal(WeReadBook book) {
    final linked = state.links[book.bookId];
    if (linked != null) {
      final item = byId[linked];
      if (item != null) return item;
    }
    final title = normalizeWeReadTitle(book.title);
    final author = normalizeWeReadAuthor(book.author);
    if (title.isNotEmpty && author.isNotEmpty) {
      final item = exact['$title|$author'];
      if (item != null) return item;
    }
    if (title.isNotEmpty) {
      final candidates = byTitle[title];
      if (candidates != null && candidates.length == 1) {
        return candidates.single;
      }
      if (candidates != null && candidates.isNotEmpty && author.isNotEmpty) {
        for (final item in candidates) {
          final localAuthor = normalizeWeReadAuthor(item.book.author);
          if (localAuthor.isNotEmpty &&
              (localAuthor.contains(author) || author.contains(localAuthor))) {
            return item;
          }
        }
      }
    }
    final base = baseWeReadTitle(book.title);
    if (base.isNotEmpty && base != title) {
      final candidates = byBaseTitle[base];
      if (candidates != null && candidates.length == 1) {
        return candidates.single;
      }
    }
    return null;
  }

  final diffs = <WeReadDiff>[];
  final remoteIds = <String>{
    for (final book in remote)
      if (book.bookId.isNotEmpty) book.bookId,
  };

  for (final book in remote) {
    if (book.bookId.isEmpty) continue;
    final local = findLocal(book);
    final localPercent = local?.percent ?? 0;
    final localAnnotationCount = local == null
        ? 0
        : (localAnnotationCounts[local.book.id] ?? 0);
    final imported = state.importedCounts[book.bookId] ?? 0;
    final skipped = state.skippedCounts[book.bookId] ?? 0;
    // 有处理基线时以基线为准：整本书评不计入划线、同一 range 的多条想法会
    // 合并成一条，用 imported + skipped 反推会永远差几条，表现为「同步完再进
    // 又提示新增划线」。老状态没有基线时仍按旧口径兜底。
    final baseline = state.syncedNoteTotals[book.bookId];
    final newNotes = math.max(
      0,
      book.totalNotes - (baseline ?? (imported + skipped)),
    );

    if (local == null) {
      diffs.add(
        WeReadDiff(
          kind: WeReadDiffKind.added,
          remote: book,
          newNoteCount: newNotes,
          changes: const <String>['本地书架没有这本书'],
        ),
      );
      continue;
    }

    final changes = <String>[];
    final remotePercent = (book.progressPercent ?? 0) / 100;
    final remoteFinished = book.finished || (book.progressPercent ?? 0) >= 100;
    final remoteReadMs = (book.lastReadAt ?? 0) * 1000;
    final localReadMs = local.book.lastOpenedAt ?? 0;
    // 本机阅读时间更新时，微信读书更旧的进度不参与覆盖。
    final remoteNotOlder =
        localReadMs == 0 ||
        (remoteReadMs > 0 && remoteReadMs >= localReadMs - 60 * 1000);
    if (remotePercent > localPercent + 0.005 && remoteNotOlder) {
      changes.add(
        '阅读进度 ${_percent(localPercent)} → ${_percent(remotePercent)}',
      );
    }
    if (remoteFinished && local.book.readStatus != BookReadStatus.finished) {
      changes.add('微信读书已读完');
    }
    // finishTime 是「读完时间」；老数据没有该字段时退回最后阅读时间。
    final remoteFinishMs = math.max(
      (book.finishTime ?? 0) * 1000,
      remoteFinished ? remoteReadMs : 0,
    );
    if (remoteFinished &&
        remoteFinishMs > (local.book.finishedAt ?? 0) + 1000) {
      changes.add('读完时间 ${_dateLabel(remoteFinishMs)}');
    }
    if (local.book.readStatus == BookReadStatus.unread && remotePercent > 0) {
      changes.add('本机尚未开始阅读');
    }
    if (newNotes > 0) {
      changes.add('新增 $newNotes 条划线/想法');
    }
    final importedReading = state.importedReadingSeconds[book.bookId] ?? 0;
    final remoteReading = book.readingSeconds ?? 0;
    if (remoteReading > importedReading + 60) {
      changes.add('阅读时长 +${_durationLabel(remoteReading - importedReading)}');
    }
    if (remoteReadMs > localReadMs + 60 * 1000) {
      changes.add('最近阅读时间更晚');
    }
    if (remotePercent < localPercent - 0.005 &&
        remoteReadMs > localReadMs + 60 * 1000) {
      changes.add(
        '阅读进度 ${_percent(localPercent)} → ${_percent(remotePercent)}（微信读书更晚）',
      );
    }

    diffs.add(
      WeReadDiff(
        kind: changes.isEmpty ? WeReadDiffKind.synced : WeReadDiffKind.updated,
        remote: book,
        local: local.book,
        localPercent: localPercent,
        localAnnotationCount: localAnnotationCount,
        newNoteCount: newNotes,
        changes: changes,
      ),
    );
  }

  for (final bookId in state.seen.difference(remoteIds)) {
    final linked = state.links[bookId];
    final localItem = linked == null ? null : byId[linked];
    final known = state.known[bookId];
    if (localItem == null && known == null) continue;
    final remoteBook = WeReadBook(
      bookId: bookId,
      title: known?.title.isNotEmpty == true
          ? known!.title
          : (localItem?.book.title ?? '未知书籍'),
      author: known?.author ?? localItem?.book.author,
      cover: known?.cover ?? localItem?.book.coverPath,
    );
    diffs.add(
      WeReadDiff(
        kind: WeReadDiffKind.deleted,
        remote: remoteBook,
        local: localItem?.book,
        localPercent: localItem?.percent ?? 0,
        localAnnotationCount: localItem == null
            ? 0
            : (localAnnotationCounts[localItem.book.id] ?? 0),
        changes: const <String>['已从微信读书书架移除'],
      ),
    );
  }

  diffs.sort((a, b) {
    final byKind = _kindOrder(a.kind).compareTo(_kindOrder(b.kind));
    if (byKind != 0) return byKind;
    return a.remote.title.compareTo(b.remote.title);
  });
  return diffs;
}

int _kindOrder(WeReadDiffKind kind) => switch (kind) {
  WeReadDiffKind.updated => 0,
  WeReadDiffKind.added => 1,
  WeReadDiffKind.synced => 2,
  WeReadDiffKind.deleted => 3,
};

String _percent(double value) =>
    '${(value.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%';

String _durationLabel(int seconds) {
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes / 60;
  return '${hours.toStringAsFixed(hours < 10 ? 1 : 0)} 小时';
}

String _dateLabel(int epochMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// 规范化书名：小写、去括注、去空白与常见标点。
String normalizeWeReadTitle(String? raw) {
  var text = (raw ?? '').trim().toLowerCase();
  if (text.isEmpty) return '';
  text = text
      .replaceAll(RegExp(r'（[^）]*）'), '')
      .replaceAll(RegExp(r'\([^)]*\)'), '')
      .replaceAll(RegExp(r'【[^】]*】'), '')
      .replaceAll(RegExp(r'\[[^\]]*\]'), '');
  return text.replaceAll(_titleNoise, '');
}

/// 书名去掉括注后的主标题（用于「三体（全集）」匹配「三体」）。
String baseWeReadTitle(String? raw) {
  final text = (raw ?? '').trim().toLowerCase();
  if (text.isEmpty) return '';
  final cut = text.replaceAll(RegExp(r'[（(【\[].*$'), '').trim();
  return cut.replaceAll(_titleNoise, '');
}

/// 规范化作者：小写、去国籍括注、去「著/编著/译」等后缀。
String normalizeWeReadAuthor(String? raw) {
  var text = (raw ?? '').trim().toLowerCase();
  if (text.isEmpty) return '';
  text = text
      .replaceAll(RegExp(r'\[[^\]]*\]'), '')
      .replaceAll(RegExp(r'（[^）]*）'), '')
      .replaceAll(RegExp(r'\([^)]*\)'), '')
      .replaceAll(RegExp(r'(著|编著|主编|编|译|等)$'), '');
  return text.replaceAll(_authorNoise, '');
}

final RegExp _titleNoise = RegExp(r'[\s\u3000《》「」『』〈〉,，.。:：;；!！?？、·\-—_/\\|]+');
final RegExp _authorNoise = RegExp(
  r'[\s\u3000《》「」『』〈〉,，.。:：;；!！?？、·\-—_/\\|]+',
);
