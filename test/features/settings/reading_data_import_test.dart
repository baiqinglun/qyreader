/// 阅读数据 JSON 导入：解析 / 匹配 / 落库（幂等）。
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/db/app_database.dart';
import 'package:qy_reader/core/hlc.dart';
import 'package:qy_reader/core/locator.dart';
import 'package:qy_reader/data/repositories/annotation_repository_impl.dart';
import 'package:qy_reader/data/repositories/progress_repository_impl.dart';
import 'package:qy_reader/data/repositories/stats_repository_impl.dart';
import 'package:qy_reader/domain/entities/annotation.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/domain/entities/bookmark.dart';
import 'package:qy_reader/domain/entities/reading_progress.dart';
import 'package:qy_reader/domain/repositories/annotation_repository.dart';
import 'package:qy_reader/domain/repositories/progress_repository.dart';
import 'package:qy_reader/domain/repositories/stats_repository.dart';
import 'package:qy_reader/features/settings/reading_data_export.dart';
import 'package:qy_reader/features/settings/reading_data_import.dart';

Book _book() => const Book(
  id: 'b1',
  title: '测试之书',
  author: '张三',
  format: BookFormat.epub,
  filePath: '/books/b1.epub',
  fileSha256: 'sha-b1',
  fileSize: 1024,
  chapterCount: 10,
  wordCount: 5000,
  addedAt: 1,
  updatedAt: 1,
  hlc: 'hlc',
  deviceId: 'dev',
);

/// 用导出器拼一份单书 JSON 文本（保证与导出格式一致）。
String _exportJson({
  required double percent,
  List<Map<String, dynamic>> annotations = const [],
  List<Map<String, dynamic>> bookmarks = const [],
  Map<String, int> daily = const {},
}) {
  final locator = locatorToJson(
    const Locator(chapterIndex: 2, offset: 40, offsetEnd: 60, href: 'c3.xhtml'),
  );
  final progress = percent > 0
      ? {
          'b1': ReadingProgressSnapshot(
            bookId: 'b1',
            locator: locator,
            percent: percent,
            furthestLocator: locator,
            furthestPercent: percent,
            updatedAt: 100,
          ),
        }
      : <String, ReadingProgressSnapshot?>{};
  final json = buildReadingDataJson(
    exportedAt: DateTime.utc(2026, 11, 18),
    books: [_book()],
    progress: progress,
    annotations: {
      'b1': [
        for (final a in annotations)
          Annotation(
            id: a['id'] as String,
            bookId: 'b1',
            type: AnnotationType.fromToken(a['type'] as String),
            color: AnnotationColor.fromToken(a['color'] as String),
            locatorStart: a['locator'] as String,
            locatorEnd: a['locator'] as String,
            quotedText: a['quote'] as String,
            note: a['note'] as String?,
            createdAt: 1,
            updatedAt: 1,
          ),
      ],
    },
    bookmarks: {
      'b1': [
        for (final b in bookmarks)
          Bookmark(
            id: b['id'] as String,
            bookId: 'b1',
            locator: b['locator'] as String,
            label: b['label'] as String?,
            createdAt: 1,
          ),
      ],
    },
    totals: const {},
    dailyDurations: {'b1': daily},
    dailyGoalMinutes: 30,
  );
  return jsonEncode(json);
}

void main() {
  group('parseReadingDataJson / matchReadingDataEntry', () {
    test('解析条目：进度 / 标注 / 书签 / 每日时长', () {
      final locator = locatorToJson(
        const Locator(chapterIndex: 0, offset: 5, offsetEnd: 9),
      );
      final entries = parseReadingDataJson(
        _exportJson(
          percent: 0.5,
          annotations: [
            {
              'id': 'a1',
              'type': 'underline',
              'color': 'rose',
              'quote': '山川湖海',
              'note': '想法',
              'locator': locator,
            },
          ],
          bookmarks: [
            {'id': 'm1', 'locator': locator, 'label': '书签'},
          ],
          daily: {'2026-11-17': 120000},
        ),
      );
      expect(entries, hasLength(1));
      final entry = entries.single;
      expect(entry.title, '测试之书');
      expect(entry.author, '张三');
      expect(entry.percent, closeTo(0.5, 0.0001));
      expect(entry.annotations, hasLength(1));
      expect(entry.bookmarks, hasLength(1));
      expect(entry.dailyDurations['2026-11-17'], 120000);
    });

    test('格式不对抛 FormatException', () {
      expect(() => parseReadingDataJson('[]'), throwsFormatException);
      expect(
        () => parseReadingDataJson('{"format":"other","books":[]}'),
        throwsFormatException,
      );
    });

    test('匹配：书名号 / 空白 / 作者不一致都不影响', () {
      final entries = parseReadingDataJson(_exportJson(percent: 0.1));
      final book = _book();
      expect(matchReadingDataEntry(entries, book), same(entries.single));

      final renamed = parseReadingDataJson(_exportJson(percent: 0.1)).single;
      expect(
        matchReadingDataEntry([renamed], book.copyWith(title: '《 测试之书 》')),
        same(renamed),
      );

      // 作者不同且双方都非空 → 不匹配
      final other = parseReadingDataJson(_exportJson(percent: 0.1)).single;
      expect(
        matchReadingDataEntry([other], book.copyWith(author: '李四')),
        isNull,
      );
    });
  });

  group('importReadingDataIntoBook', () {
    late AppDatabase db;
    late AnnotationRepository annotationRepo;
    late ProgressRepository progressRepo;
    late StatsRepository statsRepo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      final clock = HlcClock(deviceId: 'testdev1');
      annotationRepo = AnnotationRepositoryImpl(
        db: db,
        hlcClock: clock,
        deviceId: 'testdev1',
      );
      statsRepo = StatsRepositoryImpl(
        db: db,
        hlcClock: clock,
        deviceId: 'testdev1',
      );
      progressRepo = ProgressRepositoryImpl(
        db: db,
        hlcClock: clock,
        deviceId: 'testdev1',
      );
    });

    tearDown(() async => db.close());

    Future<ReadingDataImportSummary> run(String json) {
      final entry = matchReadingDataEntry(parseReadingDataJson(json), _book())!;
      return importReadingDataIntoBook(
        entry: entry,
        book: _book(),
        annotationRepo: annotationRepo,
        progressRepo: progressRepo,
        statsRepo: statsRepo,
      );
    }

    test('进度 / 笔记 / 书签 / 时长全部导入', () async {
      final locator = locatorToJson(
        const Locator(chapterIndex: 1, offset: 10, offsetEnd: 20),
      );
      final json = _exportJson(
        percent: 0.8,
        annotations: [
          {
            'id': 'a1',
            'type': 'underline',
            'color': 'rose',
            'quote': '第一条划线',
            'note': '想法',
            'locator': locator,
          },
          {
            'id': 'a2',
            'type': 'highlight',
            'color': 'blue',
            'quote': '第二条高亮',
            'locator': locator,
          },
        ],
        bookmarks: [
          {'id': 'm1', 'locator': locator, 'label': '书签一'},
        ],
        daily: {'2026-11-17': 120000, '2026-11-18': 4000}, // 4 秒跳过
      );
      final summary = await run(json);
      expect(summary.progressApplied, isTrue);
      expect(summary.notesAdded, 2);
      expect(summary.bookmarksAdded, 1);
      expect(summary.daysAdded, 1);
      expect(summary.daysSkipped, 1);

      final local = await progressRepo.getProgress('b1');
      expect(local!.percent, closeTo(0.8, 0.0001));
      final notes = await annotationRepo.listForBook('b1');
      expect(notes, hasLength(2));
      expect(notes.where((a) => a.note != null).single.note, '想法');
      final bookmarks = await annotationRepo.listBookmarks('b1');
      expect(bookmarks.single.label, '书签一');
      final daily = await statsRepo.bookDailyDurations('b1', days: 3660);
      expect(daily['2026-11-17'], 120000);
    });

    test('重复导入幂等：全部跳过', () async {
      final json = _exportJson(
        percent: 0.6,
        annotations: [
          {
            'id': 'a1',
            'type': 'underline',
            'color': 'rose',
            'quote': '  同一条   划线  ',
            'locator': locatorToJson(
              const Locator(chapterIndex: 0, offset: 0, offsetEnd: 4),
            ),
          },
        ],
        bookmarks: [
          {
            'id': 'm1',
            'locator': locatorToJson(const Locator(chapterIndex: 3, offset: 7)),
          },
        ],
        daily: {'2026-11-17': 60000},
      );
      final first = await run(json);
      expect(first.notesAdded, 1);
      final second = await run(json);
      expect(second.hasChanges, isFalse);
      expect(second.progressApplied, isFalse);
      expect(second.notesSkipped, 1);
      expect(second.bookmarksSkipped, 1);
      expect(second.daysSkipped, 1);
    });

    test('本地进度更高时不回退', () async {
      await progressRepo.saveProgress(
        bookId: 'b1',
        locator: locatorToJson(const Locator(chapterIndex: 9, offset: 0)),
        percent: 0.95,
      );
      final summary = await run(_exportJson(percent: 0.3));
      expect(summary.progressApplied, isFalse);
      final local = await progressRepo.getProgress('b1');
      expect(local!.percent, closeTo(0.95, 0.0001));
    });
  });
}
