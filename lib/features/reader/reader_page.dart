/// 阅读器占位页（M0）。正文渲染在 M1 接入 WebView + epub.js。
library;

import 'package:flutter/material.dart';

/// 阅读器页面。
class ReaderPage extends StatelessWidget {
  const ReaderPage({required this.bookId, super.key});

  /// 书籍 id。
  final String bookId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('阅读器')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '正文渲染将在 M1 实现。\n当前书籍 id：$bookId',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
