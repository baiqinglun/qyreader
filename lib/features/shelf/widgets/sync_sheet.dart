/// 同步面板：空间信息 / 待上传数 / 上次同步时间 / 立即同步。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/reading_theme.dart';
import '../../../domain/sync/sync_status.dart';

/// 弹出同步面板。
Future<void> showSyncSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _SyncSheet(),
  );
}

class _SyncSheet extends ConsumerStatefulWidget {
  const _SyncSheet();

  @override
  ConsumerState<_SyncSheet> createState() => _SyncSheetState();
}

class _SyncSheetState extends ConsumerState<_SyncSheet> {
  SyncStatus? _status;
  SyncResult? _lastResult;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final repo = await ref.read(syncRepositoryProvider.future);
    final status = await repo.status();
    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _syncNow() async {
    if (_running) return;
    setState(() => _running = true);
    final repo = await ref.read(syncRepositoryProvider.future);
    final result = await repo.syncNow();
    final status = await repo.status();
    if (!mounted) return;
    setState(() {
      _running = false;
      _lastResult = result;
      _status = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 书架用系统主题；同步面板跟随亮暗取阅读主题配色
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reading = dark ? ReadingTheme.night : ReadingTheme.paper;
    final fg = reading.chromeForeground;
    final surface = reading.chromeSurface;
    final status = _status;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Material(
          color: surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud_sync_outlined, color: reading.accent),
                    const SizedBox(width: 8),
                    Text(
                      '同步',
                      style: TextStyle(
                        color: fg,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '空间：${status?.spaceId ?? '…'}',
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (status == null)
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '读取同步状态…',
                        style: TextStyle(color: fg.withValues(alpha: 0.7)),
                      ),
                    ],
                  )
                else ...[
                  _InfoRow(
                    label: '待上传',
                    value: '${status.pendingOps} 条操作',
                    fg: fg,
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: '上次同步',
                    value: status.lastSyncAt == null
                        ? '从未同步'
                        : _formatTime(status.lastSyncAt!),
                    fg: fg,
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: '本设备',
                    value: status.deviceId,
                    fg: fg,
                  ),
                  if (status.lastError != null &&
                      status.lastError!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '上次失败：${status.lastError}',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
                if (_lastResult != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _lastResult!.ok
                        ? '完成：上传 ${_lastResult!.pushed} 条，'
                            '拉取 ${_lastResult!.pulled} 条，'
                            '合并 ${_lastResult!.applied} 条'
                        : '同步失败：${_lastResult!.error}',
                    style: TextStyle(
                      color: _lastResult!.ok
                          ? reading.accent
                          : Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: reading.accent,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: _running ? null : _syncNow,
                  icon: _running
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.sync),
                  label: Text(_running ? '同步中…' : '立即同步'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.fg,
  });

  final String label;
  final String value;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: fg, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
