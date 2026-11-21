/// 阅读数据 JSON 导出：结构 / 隐私字段 / 汇总 / 书籍选择。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/locator.dart';
import 'package:qy_reader/domain/entities/annotation.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/domain/entities/bookmark.dart';
import 'package:qy_reader/domain/entities/reading_progress.dart';
import 'package:qy_reader/domain/entities/reading_stats.dart';
import 'package:qy_reader/features/settings/reading_data_export.dart';

Book _book() => Book(
  id: 'b1',
  title: '测试之书',
  author: '张三',
  format: BookFormat.epub,
  filePath: '/private/books/b1.epub',
  fileSha256: 'abc123',
  fileSize: 1024,
  coverPath: '/private/covers/b1.jpg',
  chapterCount: 12,
  wordCount: 3456,
  addedAt: 1000,
  updatedAt: 2000,
  lastOpenedAt: 3000,
  finishedAt: 4000,
  readStatus: BookReadStatus.finished,
  isFinished: true,
  rating: 5,
  review: '很好看',
  tags: const ['小说'],
  category: '文学',
  pinnedAt: 5000,
  hlc: 'hlc',
  deviceId: 'dev',
);

void main() {
  test('导出 JSON：书籍 / 进度 / 标注 / 书签 / 阅读时长齐全', () {
    final locator = locatorToJson(
      const Locator(chapterIndex: 1, offset: 10, offsetEnd: 20),
    );
    final json = buildReadingDataJson(
      exportedAt: DateTime.utc(2026, 11, 18, 8, 30),
      books: [_book()],
      progress: {
        'b1': ReadingProgressSnapshot(
          bookId: 'b1',
          locator: locator,
          percent: 0.42,
          furthestLocator: locator,
          furthestPercent: 0.6,
          updatedAt: 6000,
        ),
      },
      annotations: {
        'b1': [
          Annotation(
            id: 'a1',
            bookId: 'b1',
            type: AnnotationType.note,
            color: AnnotationColor.rose,
            locatorStart: locator,
            locatorEnd: locator,
            quotedText: '山川湖海',
            note: '想法',
            createdAt: 7000,
            updatedAt: 8000,
          ),
        ],
      },
      bookmarks: {
        'b1': [
          Bookmark(
            id: 'm1',
            bookId: 'b1',
            locator: locator,
            label: '这里',
            createdAt: 9000,
          ),
        ],
      },
      totals: {
        'b1': const BookReadingTotal(
          bookId: 'b1',
          durationMs: 3600000,
          charsRead: 12000,
        ),
      },
      dailyDurations: {
        'b1': {'2026-11-17': 120000, '2026-11-16': 60000},
      },
      dailyGoalMinutes: 30,
    );

    expect(json['format'], 'qyreader-reading-data');
    expect(json['version'], 1);
    expect(json['dailyGoalMinutes'], 30);
    final summary = json['summary'] as Map<String, dynamic>;
    expect(summary['books'], 1);
    expect(summary['annotations'], 1);
    expect(summary['bookmarks'], 1);
    expect(summary['readingDurationMs'], 3600000);
    expect(summary['charsRead'], 12000);
    expect(summary['daysWithReading'], 2);

    final book = (json['books'] as List).single as Map<String, dynamic>;
    expect(book['title'], '测试之书');
    expect(book['author'], '张三');
    expect(book['readStatus'], 'finished');
    expect(book['rating'], 5);
    expect(book['review'], '很好看');
    expect(book['tags'], ['小说']);
    // 本机路径 / 哈希 / 设备信息不导出
    expect(book.containsKey('filePath'), isFalse);
    expect(book.containsKey('coverPath'), isFalse);
    expect(book.containsKey('fileSha256'), isFalse);
    expect(book.containsKey('deviceId'), isFalse);

    final progress = book['progress'] as Map<String, dynamic>;
    expect(progress['percent'], 0.42);
    expect(progress['locator'], isA<Map>());
    expect(progress['furthestPercent'], 0.6);

    final annotation =
        (book['annotations'] as List).single as Map<String, dynamic>;
    expect(annotation['type'], 'note');
    expect(annotation['color'], 'rose');
    expect(annotation['quote'], '山川湖海');
    expect(annotation['note'], '想法');
    expect(annotation['locatorStart'], isA<Map>());

    final bookmark = (book['bookmarks'] as List).single as Map<String, dynamic>;
    expect(bookmark['label'], '这里');
    expect(bookmark['locator'], isA<Map>());

    final reading = book['reading'] as Map<String, dynamic>;
    expect(reading['durationMs'], 3600000);
    final daily = reading['dailyDurations'] as List;
    expect(daily.first['day'], '2026-11-16'); // 按日期升序
    expect(daily.last['day'], '2026-11-17');

    // 必须能正常序列化 / 反序列化（含中文）。
    final encoded = jsonEncode(json);
    expect(jsonDecode(encoded), isA<Map<String, dynamic>>());
  });

  test('空书架也能导出合法 JSON', () {
    final json = buildReadingDataJson(
      exportedAt: DateTime.utc(2026, 11, 18),
      books: const [],
      progress: const {},
      annotations: const {},
      bookmarks: const {},
      totals: const {},
      dailyDurations: const {},
      dailyGoalMinutes: 0,
    );
    expect(json['books'], isEmpty);
    final summary = json['summary'] as Map<String, dynamic>;
    expect(summary['books'], 0);
    expect(summary['annotations'], 0);
    expect(summary['daysWithReading'], 0);
    expect(jsonDecode(jsonEncode(json)), isA<Map<String, dynamic>>());
  });

  testWidgets('导出书籍选择：默认全选，可取消单本后应用', (tester) async {
    final b1 = _book();
    final b2 = Book(
      id: 'b2',
      title: '第二本',
      author: '',
      format: BookFormat.epub,
      filePath: '/books/b2.epub',
      fileSha256: 'sha-b2',
      fileSize: 1,
      addedAt: 2,
      updatedAt: 2,
      hlc: 'hlc',
      deviceId: 'dev',
    );
    List<Book>? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                picked = await showReadingDataBookPicker(context, [b1, b2]);
              },
              child: const Text('打开选择'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开选择'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已选 2/2 本'), findsOneWidget);
    expect(find.byKey(const ValueKey('reading-data-pick-b1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reading-data-pick-b2')));
    await tester.pumpAndSettle();
    expect(find.textContaining('已选 1/2 本'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reading-data-pick-apply')));
    await tester.pumpAndSettle();
    expect(picked, [b1]);
  });
}
