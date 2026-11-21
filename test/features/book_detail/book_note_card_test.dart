/// 书籍信息笔记卡：整卡可跳转，分享按钮独立。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/annotation.dart';
import 'package:qy_reader/features/book_detail/widgets/book_note_card.dart';

Annotation _annotation() => const Annotation(
  id: 'a1',
  bookId: 'b1',
  type: AnnotationType.note,
  color: AnnotationColor.yellow,
  locatorStart: '{"chapterIndex":2,"offset":30}',
  locatorEnd: '{"chapterIndex":2,"offset":42}',
  quotedText: '山川湖海',
  note: '写得好',
  createdAt: 1700000000000,
  updatedAt: 1700000000000,
);

void main() {
  testWidgets('点卡片跳转，点分享不触发跳转', (tester) async {
    var opened = 0;
    var shared = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookNoteCard(
            item: _annotation(),
            foreground: Colors.black,
            muted: Colors.grey,
            onTap: () => opened++,
            onShare: () => shared++,
          ),
        ),
      ),
    );

    expect(find.text('山川湖海'), findsOneWidget);
    expect(find.text('写得好'), findsOneWidget);
    expect(find.byKey(const ValueKey('book-note-share-a1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('book-note-a1')));
    expect(opened, 1);
    expect(shared, 0);

    await tester.tap(find.byKey(const ValueKey('book-note-share-a1')));
    expect(shared, 1);
    expect(opened, 1);
  });
}
