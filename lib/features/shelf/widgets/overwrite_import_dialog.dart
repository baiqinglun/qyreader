/// 书架长按 →「覆盖导入」的交互。
///
/// 用新的 EPUB / AZW3 / MOBI / TXT 替换已有书的正文，保留书籍 id、书名/作者/封面、阅读
/// 进度与笔记；导入完成后如果书里有笔记，会问要不要按原文重新匹配位置。
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../app/providers.dart';
import '../../../core/result.dart';
import '../../../domain/entities/book.dart';
import '../../reader/native/native_chapter_source.dart';
import '../../reader/note_rematch.dart';

/// 选文件 → 确认 → 覆盖 →（可选）匹配笔记位置。
Future<void> startOverwriteImport(
  BuildContext context,
  WidgetRef ref,
  Book book,
) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['epub', 'azw3', 'mobi', 'txt', 'md', 'markdown'],
    allowMultiple: false,
    withData: false,
  );
  final path = (picked == null || picked.files.isEmpty)
      ? null
      : picked.files.first.path;
  if (path == null || path.isEmpty) return;
  if (!context.mounted) return;

  final fileName = p.basename(path);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('覆盖导入'),
      content: Text(
        '将用「$fileName」替换《${book.title}》的正文。\n\n'
        '书籍信息、阅读进度和笔记都会保留；导入后可以再自动匹配笔记位置。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('book-overwrite-confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('覆盖导入'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final repo = await ref.read(bookRepositoryProvider.future);
  final progressRepo = await ref.read(progressRepositoryProvider.future);
  final annotationRepo = await ref.read(annotationRepositoryProvider.future);
  // 覆盖前记下百分比：章节重排后按新书字数重新落一个 locator。
  final before = await progressRepo.getProgress(book.id);
  if (!context.mounted) return;

  final outcome = await showDialog<_TaskOutcome<Result<Book>>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TaskDialog<Result<Book>>(
      message: '正在覆盖导入…',
      task: () => repo.replaceBookContent(book.id, path),
    ),
  );
  if (!context.mounted) return;
  if (outcome == null) return;
  if (outcome.error != null) {
    _toast(context, '覆盖导入失败：${outcome.error}');
    return;
  }
  final result = outcome.value!;
  Book? updated;
  AppException? failure;
  result.when(ok: (b) => updated = b, failure: (e) => failure = e);
  if (updated == null) {
    _toast(context, '覆盖导入失败：${failure?.message ?? '未知错误'}');
    return;
  }

  if (before != null && before.percent > 0) {
    try {
      await progressRepo.saveExternalProgress(
        bookId: updated!.id,
        percent: before.percent,
      );
    } catch (_) {
      // 进度换算失败不影响正文与笔记
    }
  }
  if (!context.mounted) return;

  final annotations = await annotationRepo.listForBook(updated!.id);
  final quotable = annotations
      .where((a) => (a.quotedText ?? '').trim().isNotEmpty)
      .length;
  if (!context.mounted) return;
  if (quotable == 0) {
    _toast(context, '覆盖导入完成');
    return;
  }

  final shouldMatch = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('匹配笔记位置'),
      content: Text(
        '这本书有 $quotable 条带原文的笔记。要在这本新书里自动查找它们的位置吗？\n\n'
        '会先用完整原文搜索；搜不到时再一点点减少文字继续匹配，'
        '仍找不到的保持原位置。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('暂不匹配'),
        ),
        FilledButton(
          key: const ValueKey('book-overwrite-match-notes'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('匹配笔记位置'),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  if (shouldMatch != true) {
    _toast(context, '覆盖导入完成，笔记保持原位置');
    return;
  }

  final matchOutcome = await showDialog<_TaskOutcome<NoteRematchPlan>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TaskDialog<NoteRematchPlan>(
      message: '正在新书里查找笔记位置…',
      task: () async {
        final chapters = await ref.read(
          nativeChaptersProvider(NativeChaptersKey.of(updated!)).future,
        );
        return rematchBookNotes(
          annotations: annotations,
          chapters: chapters,
          repository: annotationRepo,
        );
      },
    ),
  );
  if (!context.mounted) return;
  if (matchOutcome == null) return;
  if (matchOutcome.error != null) {
    _toast(context, '匹配笔记位置失败：${matchOutcome.error}');
    return;
  }
  final plan = matchOutcome.value!;
  if (plan.matched == 0) {
    _toast(context, '没有找到可匹配的笔记位置，已保持原位置');
  } else if (plan.unmatched == 0) {
    _toast(context, '已匹配 ${plan.matched} 条笔记的位置');
  } else {
    _toast(context, '已匹配 ${plan.matched} 条笔记，${plan.unmatched} 条没找到（保持原位置）');
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// 任务对话框的结果：成功值或异常。
class _TaskOutcome<T> {
  const _TaskOutcome.ok(this.value) : error = null;

  const _TaskOutcome.error(this.error) : value = null;

  final T? value;
  final Object? error;
}

/// 显示转圈对话框并执行 [task]，完成后自动关闭并带回结果。
///
/// 解析大书可能要几秒，不能只弹一个 SnackBar 让用户以为没反应；也不能
/// 先 showDialog 再在外部 pop（任务瞬间完成时会误关别的路由）。
class _TaskDialog<T> extends StatefulWidget {
  const _TaskDialog({required this.message, required this.task});

  final String message;
  final Future<T> Function() task;

  @override
  State<_TaskDialog<T>> createState() => _TaskDialogState<T>();
}

class _TaskDialogState<T> extends State<_TaskDialog<T>> {
  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final value = await widget.task();
      if (mounted) Navigator.of(context).pop(_TaskOutcome<T>.ok(value));
    } catch (e) {
      if (mounted) Navigator.of(context).pop(_TaskOutcome<T>.error(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(widget.message)),
          ],
        ),
      ),
    );
  }
}
