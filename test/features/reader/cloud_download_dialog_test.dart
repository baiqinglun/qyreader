/// 按需下载确认弹窗：文案、取消 / 下载两个按钮、下载中转圈提示。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/domain/entities/book.dart';
import 'package:qy_reader/features/reader/widgets/cloud_download_dialog.dart';

Book _book({int size = 5 * 1024 * 1024}) => Book(
      id: 'b1',
      title: '三体',
      format: BookFormat.epub,
      filePath: '/tmp/b1.epub',
      fileSha256: 'x',
      fileSize: size,
      addedAt: 0,
      updatedAt: 0,
      chapterCount: 1,
      hlc: '0000000000000-00000-aaaaaaaa',
      deviceId: 'aaaaaaaa',
    );

void main() {
  testWidgets('确认弹窗写明书名与体积，取消返回 false、下载返回 true', (tester) async {
    var result = true;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showCloudDownloadConfirm(context, _book());
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('从云端下载'), findsOneWidget);
    expect(find.textContaining('《三体》'), findsOneWidget);
    expect(find.textContaining('5.0 MB'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-download-confirm')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('下载中弹窗显示「正在下载《书名》的书籍…」', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: cloudDownloadProgress(_book())),
    ));
    await tester.pump();

    expect(find.text('正在下载'), findsOneWidget);
    expect(find.text('正在下载《三体》的书籍…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
