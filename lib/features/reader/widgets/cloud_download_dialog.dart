/// 打开「云端才有」的书时的确认与下载中弹窗（按需下载，v2.33.0）。
library;

import 'package:flutter/material.dart';

import '../../../app/theme/motion.dart';
import '../../../domain/entities/book.dart';

/// 询问是否从云端下载这本书；返回用户是否同意（取消 / 点外部 = false）。
Future<bool> showCloudDownloadConfirm(
  BuildContext context,
  Book book,
) async {
  final sizeText = _sizeText(book.fileSize);
  final ok = await showDialog<bool>(
    context: context,
    animationStyle: kSmoothSheetAnimation,
    builder: (dialogContext) => AlertDialog(
      title: const Text('从云端下载'),
      content: Text(
        '《${book.title}》还没有下载到本地（约 $sizeText）。'
        '阅读前需要先从云端下载这本书。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('reader-download-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('下载'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 下载中的弹窗内容：转圈 + 「正在下载《书名》的书籍…」。
Widget cloudDownloadProgress(Book book) {
  return AlertDialog(
    title: const Text('正在下载'),
    content: Row(
      children: [
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            '正在下载《${book.title}》的书籍…',
            style: const TextStyle(height: 1.4),
          ),
        ),
      ],
    ),
  );
}

String _sizeText(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}
