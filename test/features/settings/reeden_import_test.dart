/// Reeden 导入：JSON 解析 + 差异对比 + 落库全链路（内存 SQLite）。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/db/app_database.dart';
import 'package:qy_reader/core/hlc.dart';
import 'package:qy_reader/data/repositories/annotation_repository_impl.dart';
import 'package:qy_reader/data/repositories/book_repository_impl.dart';
import 'package:qy_reader/data/repositories/progress_repository_impl.dart';
import 'package:qy_reader/data/repositories/stats_repository_impl.dart';
import 'package:qy_reader/domain/entities/annotation.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/domain/repositories/annotation_repository.dart';
import 'package:qy_reader/domain/repositories/book_repository.dart';
import 'package:qy_reader/domain/repositories/progress_repository.dart';
import 'package:qy_reader/domain/repositories/stats_repository.dart';
import 'package:qy_reader/features/reader/native/native_chapter_source.dart';
import 'package:qy_reader/features/settings/reeden_import.dart';
import 'package:qy_reader/features/settings/reeden_import_service.dart';

import '../../data/parsers/epub_parser_test.dart' show buildEpub;

const String _sample = '''
[
  {
    "title": "《苏东坡传》",
    "author": "林语堂",
    "description": "林语堂著，详细记述苏东坡的生平事迹",
    "rating": 4.5,
    "tags": ["历史", "文学艺术"],
    "category": "人物传记",
    "readingState": {
      "readStatus": "finished",
      "progress": 0.9971,
      "readStartTime": "2026-01-05T18:25:58.087586",
      "readFinishTime": "2026-06-26T18:45:04.561209",
      "lastReadTime": "2026-07-08T10:44:02.757060",
      "readRoundNo": 1
    },
    "readRounds": [],
    "notes": [
      {
        "sectionIndex": 2, "sectionName": "原 序",
        "paragraphIndex": 3, "startIndex": 387,
        "endParagraphIndex": 3, "endIndex": 404,
        "content": "终其一生他对自己完全自然，完全忠实。",
        "type": "underline", "styleType": "solid", "color": "red",
        "timestamp": 1767609044000,
        "updatedAt": "2026-07-13T03:22:10.000Z",
        "comment": "真纯粹"
      },
      {
        "sectionIndex": 3, "sectionName": "第一章",
        "paragraphIndex": 1, "startIndex": 1, "endParagraphIndex": 1,
        "endIndex": 9,
        "content": "本地没有的原文，导入时按章首兜底",
        "type": "underline", "color": "blue", "timestamp": 1767609050000
      }
    ],
    "reviews": [
      {
        "content": "这本书更像是一部宋朝神宗哲宗年间的政治史。",
        "createdAt": "2026-06-26T18:49:42.695654",
        "updatedAt": "2026-06-26T18:49:42.695654",
        "isDefault": false
      }
    ],
    "readingStatistics": {
      "totalReadSeconds": 28957,
      "totalWordCount": 271691,
      "readingRecords": [
        {"date": "2026-01-05", "readSeconds": 1568, "wordCount": 17356},
        {"date": "2026-01-06", "readSeconds": 3805, "wordCount": 16298},
        {"date": "2026-01-07", "readSeconds": 5, "wordCount": 934}
      ]
    }
  }
]
''';

/// 模拟「本机已有这本书的正文」：第一条划线的原文能在里面搜到。
const String _chapterTextWithQuote =
    '原 序　林语堂　这本书写的是一个 personalities。'
    '终其一生他对自己完全自然，完全忠实。之后还有一段内容。';

void main() {
  group('parseReedenExport', () {
    test('解析书籍 / 状态 / 笔记 / 书评 / 每日记录', () {
      final books = parseReedenExport(_sample);
      expect(books, hasLength(1));
      final book = books.single;
      expect(book.title, '《苏东坡传》');
      expect(book.author, '林语堂');
      expect(book.rating, 4.5);
      expect(book.tags, ['历史', '文学艺术']);
      expect(book.category, '人物传记');
      expect(book.state?.statusRaw, 'finished');
      expect(book.state?.progress, closeTo(0.9971, 0.0001));
      expect(book.state?.finishMs, greaterThan(0));
      expect(book.notes, hasLength(2));
      expect(book.notes.first.content, '终其一生他对自己完全自然，完全忠实。');
      expect(book.notes.first.comment, '真纯粹');
      expect(book.notes.first.timestampMs, 1767609044000);
      expect(book.reviews, hasLength(1));
      expect(book.reviews.first.content, contains('政治史'));
      expect(
        book.records.map((r) => r.day),
        ['2026-01-05', '2026-01-06', '2026-01-07'],
      );
      expect(book.records.first.seconds, 1568);
    });

    test('坏输入：顶层不是数组 / 字段缺失都兜底', () {
      expect(() => parseReedenExport('{"a":1}'), throwsFormatException);
      expect(parseReedenExport('[]'), isEmpty);
      final books = parseReedenExport('[{"title":"无字段的书"}]');
      expect(books, hasLength(1));
      expect(books.single.notes, isEmpty);
      expect(books.single.state, isNull);
      expect(books.single.records, isEmpty);
    });
  });

  group('compareReedenBooks / importReedenData', () {
    late AppDatabase db;
    late Directory tempDir;
    late BookRepository bookRepo;
    late AnnotationRepository annotationRepo;
    late StatsRepository statsRepo;
    late ProgressRepository progressRepo;
    late Future<List<NativeChapter>> Function(Book book) loadChapters;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      tempDir = await Directory.systemTemp.createTemp('qy_reeden_test');
      final clock = HlcClock(deviceId: 'testdev1');
      bookRepo = BookRepositoryImpl(
        db: db,
        hlcClock: clock,
        deviceId: 'testdev1',
        libraryDir: tempDir,
      );
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
      await File('${tempDir.path}/fixture.epub').writeAsBytes(buildEpub());
      // 模拟本机章节：第一条划线的原文可在全文中搜到，第二条搜不到
      //（走章首兜底）。
      loadChapters = (book) async => [
        NativeChapter.fromCompact(
          idx: 0,
          title: '原 序',
          href: 'OEBPS/text/ch1.xhtml',
          text: _chapterTextWithQuote,
          paragraphStarts: const [0],
          paragraphLevels: const [0],
          paragraphCentered: const [false],
        ),
      ];
    });

    tearDown(() async {
      await db.close();
      await tempDir.delete(recursive: true);
    });

    Future<ReedenImportSummary> importAll() => importReedenData(
      parseReedenExport(_sample),
      bookRepo: bookRepo,
      annotationRepo: annotationRepo,
      statsRepo: statsRepo,
      progressRepo: progressRepo,
      tempDir: tempDir.path,
      loadChapters: loadChapters,
    );

    test('对比：新书是「新增」，导入后再对比是「一致」', () async {
      final books = parseReedenExport(_sample);
      final before = await compareReedenBooks(
        books,
        bookRepo: bookRepo,
        annotationRepo: annotationRepo,
        statsRepo: statsRepo,
      );
      expect(before.single.state, ReedenDiffState.create);
      expect(before.single.notesNew, 2);

      await importAll();

      final after = await compareReedenBooks(
        books,
        bookRepo: bookRepo,
        annotationRepo: annotationRepo,
        statsRepo: statsRepo,
      );
      expect(after.single.state, ReedenDiffState.same);
      expect(after.single.hasUpdates, isFalse);
    });

    test('导入：占位书入库，书评 / 状态 / 划线定位 / 时长全部落库', () async {
      final summary = await importAll();

      expect(summary.created, 1);
      expect(summary.merged, 0);
      expect(summary.reviews, 1);
      expect(summary.notes, 2);
      // 第一条按原文搜到（全文定位），第二条退章首兜底。
      expect(summary.notesLocated, 1);
      expect(summary.notesFallback, 1);
      // 5 秒的记录低于 10 秒会话门槛，跳过。
      expect(summary.days, 2);
      expect(summary.daysSkipped, 1);

      final shelf = await bookRepo.watchShelf().first;
      final item = shelf.singleWhere((s) => s.book.title == '《苏东坡传》');
      expect(item.book.review, contains('政治史'));
      expect(item.book.rating, 5); // 4.5 取整
      expect(item.book.readStatus, BookReadStatus.finished);
      expect(item.book.finishedAt, isNotNull);

      // 划线：带想法的类型标记为 note；定位一章第 0 章。
      final annotations = await annotationRepo.listForBook(item.book.id);
      expect(annotations, hasLength(2));
      final withNote = annotations.firstWhere(
        (a) => (a.quotedText ?? '').contains('终其一生'),
      );
      expect(withNote.note, '真纯粹');
      expect(withNote.type, AnnotationType.note);
      expect(withNote.color, AnnotationColor.rose); // red → rose
      expect(withNote.chapterIndex, 0);
      expect(withNote.locatorStart, contains('@0:'));
      final plain = annotations.firstWhere(
        (a) => (a.quotedText ?? '').contains('本地没有的原文'),
      );
      expect(plain.note, isNull);
      expect(plain.type, AnnotationType.underline);
      expect(plain.color, AnnotationColor.blue);
      expect(plain.chapterIndex, 0);

      // 每日时长落库（bookDailyDurations 返回毫秒）。
      final daily = await statsRepo.bookDailyDurations(item.book.id, days: 3660);
      expect(daily['2026-01-05'], 1568 * 1000);
      expect(daily['2026-01-06'], 3805 * 1000);
      expect(daily.containsKey('2026-01-07'), isFalse);

      // 进度落库。
      final progress = await progressRepo.getProgress(item.book.id);
      expect(progress?.percent, closeTo(0.9971, 0.0001));
    });

    test('重复导入：同书合并，笔记 / 时长不叠加', () async {
      await importAll();
      final second = await importAll();

      expect(second.created, 0);
      expect(second.merged, 1);
      expect(second.notes, 0);
      expect(second.notesSkipped, 2);
      expect(second.days, 0);
      expect(second.daysSkipped, 3);

      final shelf = await bookRepo.watchShelf().first;
      expect(shelf.where((s) => s.book.title == '《苏东坡传》'), hasLength(1));
      final item = shelf.single;
      final annotations = await annotationRepo.listForBook(item.book.id);
      expect(annotations, hasLength(2));
      final daily = await statsRepo.bookDailyDurations(item.book.id, days: 3660);
      expect(daily['2026-01-05'], 1568 * 1000);
    });

    test('书架已有同名同作者的书：合并不新建，空字段才补', () async {
      final created = await bookRepo.importFromFile(
        '${tempDir.path}/fixture.epub',
      );
      final fixture = created.when(
        ok: (b) => b,
        failure: (e) => throw StateError('$e'),
      );
      expect(fixture.title, '测试之书');
      // fixture 书名 / 作者与导入数据不同，这里手动改成同名同作者，
      // 造「书架已有这本书」的场景。
      await bookRepo.updateBookMeta(
        fixture.id,
        title: '苏东坡传',
        author: '林语堂',
      );

      final books = parseReedenExport(_sample);
      final diffs = await compareReedenBooks(
        books,
        bookRepo: bookRepo,
        annotationRepo: annotationRepo,
        statsRepo: statsRepo,
      );
      expect(diffs.single.state, ReedenDiffState.update);
      expect(diffs.single.local?.book.id, fixture.id);

      final summary = await importReedenData(
        books,
        bookRepo: bookRepo,
        annotationRepo: annotationRepo,
        statsRepo: statsRepo,
        progressRepo: progressRepo,
        tempDir: tempDir.path,
        loadChapters: loadChapters,
      );

      expect(summary.merged, 1);
      expect(summary.created, 0);
      final shelf = await bookRepo.watchShelf().first;
      expect(shelf, hasLength(1));
      final merged = shelf.single.book;
      expect(merged.id, fixture.id);
      // 本地没有书评 / 评分 / 标签：补上。
      expect(merged.review, contains('政治史'));
      expect(merged.rating, 5);
      expect(merged.tags, isNotEmpty);
    });
  });
}
