import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/features/reader/reader_input.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('保存的快捷键控制上一页和下一页', (tester) async {
    SharedPreferences.setMockInitialValues({
      'reader.key.previous': LogicalKeyboardKey.keyA.keyId,
      'reader.key.next': LogicalKeyboardKey.keyD.keyId,
    });
    var previous = 0;
    var next = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderInput(
            previous: () => previous++,
            next: () => next++,
            child: const Text('正文'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(previous, 1);
    expect(next, 1);
  });
}
