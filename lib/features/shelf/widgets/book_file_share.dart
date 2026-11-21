/// 分享或导出书籍源文件。
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/providers.dart';
import '../../../domain/entities/book.dart';

/// 文件名只保留跨平台可用字符，并避免空名称。
String bookExportName(String title, String extension) {
  final name = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '')
      .trim();
  final reserved = RegExp(
    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$',
    caseSensitive: false,
  );
  final safe = name.isEmpty
      ? '未命名书籍'
      : reserved.hasMatch(name)
      ? '_$name'
      : name;
  final truncated = safe.length > 100 ? safe.substring(0, 100) : safe;
  return '$truncated$extension';
}

/// 防止同名书覆盖，使用大小写不敏感的名称比较。
List<String> uniqueBookExportNames(List<Book> books) {
  final used = <String>{};
  return [
    for (final book in books)
      () {
        final ext = p.extension(book.filePath).toLowerCase();
        final name = bookExportName(book.title, ext);
        final stem = name.substring(0, name.length - ext.length);
        var candidate = name;
        var index = 2;
        while (!used.add(candidate.toLowerCase())) {
          candidate = '$stem (${index++})$ext';
        }
        return candidate;
      }(),
  ];
}

/// 将多本书打包为 ZIP，打包和文件读取不阻塞界面。
Future<Uint8List> archiveBookFiles(List<String> paths, List<String> names) {
  if (paths.length != names.length) throw ArgumentError('书籍文件与名称数量不一致');
  return Isolate.run(() {
    final archive = Archive();
    for (var i = 0; i < paths.length; i++) {
      final data = File(paths[i]).readAsBytesSync();
      archive.addFile(ArchiveFile(names[i], data.length, data));
    }
    return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
  });
}

/// 提示用户选择保存或系统分享，失败时显示原因。
Future<void> shareOrExportBooks(
  BuildContext context,
  WidgetRef ref,
  List<Book> books,
) async {
  if (books.isEmpty) return;
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('book-export-local'),
            leading: const Icon(Icons.save_alt),
            title: const Text('导出到本地'),
            subtitle: Text(books.length > 1 ? '多本书打包为 ZIP' : '保存书籍文件'),
            onTap: () => Navigator.pop(context, 'save'),
          ),
          ListTile(
            key: const ValueKey('book-export-share'),
            leading: const Icon(Icons.share_outlined),
            title: const Text('分享书籍'),
            onTap: () => Navigator.pop(context, 'share'),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final overlay = ValueNotifier<String>('正在准备书籍…');
  var open = true;
  final dialog = _showPreparingDialog(context, overlay);
  try {
    final repo = await ref.read(bookRepositoryProvider.future);
    final paths = <String>[];
    for (var i = 0; i < books.length; i++) {
      overlay.value = '正在准备 ${i + 1}/${books.length}：${books[i].title}';
      var current = await repo.getById(books[i].id);
      if (current == null) throw StateError('书籍不存在：${books[i].title}');
      if (!await File(current.filePath).exists()) {
        final sync = await ref.read(syncRepositoryProvider.future);
        if (!await sync.ensureBookFileLocal(current.id)) {
          throw StateError('无法从同步库下载《${current.title}》');
        }
        current = await repo.getById(current.id);
      }
      if (current == null || !await File(current.filePath).exists()) {
        throw StateError('书源文件不存在：${books[i].title}');
      }
      paths.add(current.filePath);
    }
    final names = uniqueBookExportNames(books);
    if (!context.mounted) return;
    if (action == 'share') {
      final directory = await (await getTemporaryDirectory()).createTemp(
        'qyreader_share_',
      );
      final files = <XFile>[];
      for (var i = 0; i < paths.length; i++) {
        final copy = await File(
          paths[i],
        ).copy(p.join(directory.path, names[i]));
        files.add(XFile(copy.path));
      }
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      open = false;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: files,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } else {
      final Uint8List bytes;
      final String name;
      if (books.length == 1) {
        bytes = await File(paths.single).readAsBytes();
        name = names.single;
      } else {
        bytes = await archiveBookFiles(paths, names);
        name = 'QYReader-书籍.zip';
      }
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      open = false;
      final saved = await FilePicker.saveFile(
        dialogTitle: '保存书籍',
        fileName: name,
        bytes: bytes,
      );
      if (saved != null && context.mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('书籍已保存')));
      }
    }
  } catch (e) {
    if (context.mounted) {
      if (open) {
        Navigator.of(context, rootNavigator: true).pop();
        open = false;
      }
      messenger.showSnackBar(SnackBar(content: Text('操作失败：$e')));
    }
  } finally {
    if (!open) await dialog;
    overlay.dispose();
  }
}

/// 弹出准备进度，防止重复操作。
Future<void> _showPreparingDialog(
  BuildContext context,
  ValueNotifier<String> progress,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: progress,
                builder: (_, value, __) => Text(value),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
