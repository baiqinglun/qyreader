/// 导入结果弹窗：成功 / 重复 / 失败计数 + 可回看的导入记录。
///
/// 弹窗关掉后从书架「⋯ → 导入记录」再打开；记录存在 SharedPreferences，
/// 只有点「清空记录」才会消失（不影响已导入的书）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/motion.dart';
import '../import_history.dart';

/// 打开导入结果弹窗。
///
/// [batch] 非空 = 刚完成一次导入（标题「导入完成」，顶部统计本次）；
/// 为空 = 从菜单回看全部记录（标题「导入记录」）。
Future<void> showImportResultDialog(
  BuildContext context, {
  List<ImportRecord> batch = const <ImportRecord>[],
}) {
  return showDialog<void>(
    context: context,
    animationStyle: kSmoothSheetAnimation,
    builder: (_) => ImportResultDialog(batch: batch),
  );
}

/// 导入结果 / 历史弹窗。
class ImportResultDialog extends ConsumerStatefulWidget {
  /// 构造。
  const ImportResultDialog({this.batch = const <ImportRecord>[], super.key});

  /// 本次导入的记录；空 = 回看全部历史。
  final List<ImportRecord> batch;

  @override
  ConsumerState<ImportResultDialog> createState() => _ImportResultDialogState();
}

class _ImportResultDialogState extends ConsumerState<ImportResultDialog> {
  bool _clearing = false;
  bool _clearedBatch = false;

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: kSmoothSheetAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('清空导入记录？'),
        content: const Text('只清除记录，已经加入书架的书不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('import-history-clear-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _clearing = true;
      _clearedBatch = true;
    });
    await ref.read(importHistoryControllerProvider.notifier).clear();
    if (mounted) setState(() => _clearing = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final history = ref.watch(importHistoryControllerProvider);
    final all = history.valueOrNull ?? const <ImportRecord>[];
    final showingBatch = widget.batch.isNotEmpty && !_clearedBatch;
    final list = showingBatch && all.isEmpty ? widget.batch : all;
    final summary = importRecordSummary(showingBatch ? widget.batch : all);
    final title = showingBatch ? '导入完成' : '导入记录';

    return AlertDialog(
      key: const ValueKey('import-result-dialog'),
      title: Row(
        children: [
          Icon(
            showingBatch ? Icons.file_download_done_rounded : Icons.history,
            color: scheme.primary,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (history.isLoading && all.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            _SummaryRow(summary: summary),
            const SizedBox(height: 10),
            Text(
              showingBatch
                  ? '本次导入 ${widget.batch.length} 个文件'
                        '${all.length > widget.batch.length ? ' · 累计 ${all.length} 条记录' : ''}'
                  : '共 ${all.length} 条记录',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: list.isEmpty
                  ? const _EmptyHistory()
                  : ListView.separated(
                      key: const ValueKey('import-history-list'),
                      shrinkWrap: true,
                      itemCount: list.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, thickness: 0.5),
                      itemBuilder: (context, index) =>
                          _RecordRow(record: list[index]),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('import-history-clear'),
          onPressed: list.isEmpty || _clearing ? null : _clearHistory,
          child: Text(_clearing ? '清空中…' : '清空记录'),
        ),
        FilledButton(
          key: const ValueKey('import-result-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

/// 顶部的成功 / 重复 / 失败计数。
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summary});

  final ImportRecordSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _SummaryCell(
            key: const ValueKey('import-summary-success'),
            label: '成功',
            count: summary.success,
            color: const Color(0xFF2E9E6B),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCell(
            key: const ValueKey('import-summary-duplicate'),
            label: '重复',
            count: summary.duplicate,
            color: const Color(0xFFD79A2B),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCell(
            key: const ValueKey('import-summary-failure'),
            label: '失败',
            count: summary.failure,
            color: scheme.error,
          ),
        ),
      ],
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.label,
    required this.count,
    required this.color,
    super.key,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 20,
              height: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

/// 一条记录：状态图标 + 书名 / 文件名 + 说明 + 时间。
class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});

  final ImportRecord record;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (record.status) {
      ImportRecordStatus.success => (
        Icons.check_circle_rounded,
        const Color(0xFF2E9E6B),
      ),
      ImportRecordStatus.duplicate => (
        Icons.content_copy_rounded,
        const Color(0xFFD79A2B),
      ),
      ImportRecordStatus.failure => (Icons.error_rounded, scheme.error),
    };
    final primary = record.title.isNotEmpty ? record.title : record.fileName;
    final subtitle = _subtitle();
    final at = record.at > 0
        ? DateFormat(
            'MM-dd HH:mm',
          ).format(DateTime.fromMillisecondsSinceEpoch(record.at))
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (at.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              at,
              style: TextStyle(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 10.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _subtitle() {
    final message = record.message.trim();
    return switch (record.status) {
      ImportRecordStatus.success =>
        record.fileName == record.title
            ? message
            : '${record.fileName}${message.isEmpty ? '' : ' · $message'}',
      ImportRecordStatus.duplicate => message.isEmpty ? '内容重复，已跳过' : message,
      ImportRecordStatus.failure => message.isEmpty ? '导入失败' : message,
    };
  }
}

/// 空记录。
class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 110,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 30,
            color: scheme.outline.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 6),
          Text(
            '还没有导入记录',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
