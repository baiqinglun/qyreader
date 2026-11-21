/// 设置 → 实验性功能 → 微信读书。
///
/// 页面只做三件事：扫码登录、拉取并展示与本机书籍的差异、把单本/全部
/// 可更新项写回本机。微信读书有而本机没有的书只展示，不自动下载正文。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/book.dart';
import 'weread_compare.dart';
import 'weread_login.dart';
import 'weread_login_dialog.dart';
import 'weread_models.dart';
import 'weread_notes_sheet.dart';
import 'weread_sync_service.dart';

/// 微信读书同步页。
class WeReadPage extends ConsumerStatefulWidget {
  /// 构造。
  const WeReadPage({super.key});

  @override
  ConsumerState<WeReadPage> createState() => _WeReadPageState();
}

class _WeReadPageState extends ConsumerState<WeReadPage> {
  WeReadSyncApi get _api => ref.read(wereadSyncApiProvider);
  WeReadLoginApi get _login => ref.read(wereadLoginProvider);

  bool _keyConfigured = false;
  String? _accountName;
  bool _loading = false;
  bool _applying = false;
  String? _error;
  String? _progress;
  String? _applyProgress;
  WeReadFetchResult? _result;
  WeReadDiffKind? _filter;
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _progress = '正在读取上次结果…';
    });
    final configured = await _api.hasKey();
    final accountName = await _login.accountName();
    final cached = await _api.loadCached();
    if (!mounted) return;
    setState(() {
      _keyConfigured = configured;
      _accountName = accountName;
      _loading = false;
      _progress = null;
      if (cached != null) _result = cached;
    });
    // 上次抓取过就先展示缓存，不自动联网；用户点刷新才重新拉取。
    if (cached == null && configured) {
      await _fetch();
    }
  }

  Future<void> _fetch() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _progress = '正在准备…';
    });
    try {
      final result = await _api.fetch(
        onProgress: (message) {
          if (!mounted) return;
          setState(() => _progress = message);
        },
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
        _progress = null;
        _filter = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _progress = null;
        _error = error is WeReadApiException ? error.message : '$error';
      });
    }
  }

  Future<void> _showAccount() async {
    if (!_keyConfigured) {
      await _loginWithQr();
      return;
    }
    final action = await showDialog<_AccountAction>(
      context: context,
      builder: (context) => _AccountDialog(
        accountName: _accountName,
        onLogout: () => Navigator.of(context).pop(_AccountAction.logout),
        onRelogin: () => Navigator.of(context).pop(_AccountAction.relogin),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _AccountAction.relogin:
        await _loginWithQr();
      case _AccountAction.logout:
        await _logout();
      case null:
        break;
    }
  }

  Future<void> _loginWithQr() async {
    final name = await showWeReadLoginDialog(context, _login);
    if (name == null || !mounted) return;
    setState(() {
      _keyConfigured = true;
      _accountName = name.trim().isEmpty ? null : name.trim();
      _result = null;
      _error = null;
      _filter = null;
    });
    await _fetch();
  }

  Future<void> _logout() async {
    await _login.logout();
    if (!mounted) return;
    setState(() {
      _keyConfigured = false;
      _accountName = null;
      _result = null;
      _error = null;
      _filter = null;
    });
    _showSnack('已退出微信读书');
  }

  Future<void> _apply(WeReadDiff diff) async {
    if (_applying) return;
    setState(() {
      _applying = true;
      _busy.add(diff.remote.bookId);
    });
    try {
      final result = await _api.apply(diff);
      if (!mounted) return;
      _markSynced(diff, result.message, retryable: result.retryable);
      _showSnack(result.message);
    } catch (error) {
      if (!mounted) return;
      _showSnack(error is WeReadApiException ? error.message : '$error');
    } finally {
      if (mounted) {
        setState(() {
          _applying = false;
          _busy.remove(diff.remote.bookId);
        });
      }
    }
  }

  Future<void> _import(WeReadDiff diff) async {
    if (_applying) return;
    setState(() {
      _applying = true;
      _busy.add(diff.remote.bookId);
    });
    try {
      final result = await _api.importAdded(diff);
      if (!mounted) return;
      _markSynced(
        diff,
        result.message,
        retryable: result.retryable,
        localOverride: result.importedBook,
        localPercent: (diff.remote.progressPercent ?? 0) / 100,
      );
      _showSnack(result.message);
    } catch (error) {
      if (!mounted) return;
      _showSnack(error is WeReadApiException ? error.message : '$error');
    } finally {
      if (mounted) {
        setState(() {
          _applying = false;
          _busy.remove(diff.remote.bookId);
        });
      }
    }
  }

  Future<void> _openNotes(WeReadDiff diff) async {
    await showWeReadNotesSheet(
      context,
      bookTitle: diff.remote.title,
      loader: () => _api.notesFor(diff.remote.bookId),
    );
  }

  Future<void> _ignore(WeReadDiff diff) async {
    if (_applying) return;
    setState(() {
      _applying = true;
      _busy.add(diff.remote.bookId);
    });
    try {
      await _api.ignore(diff);
      if (!mounted) return;
      final result = _result;
      if (result != null) {
        setState(() {
          _result = WeReadFetchResult(
            snapshot: result.snapshot,
            diffs: <WeReadDiff>[
              for (final item in result.diffs)
                if (item.remote.bookId != diff.remote.bookId) item,
            ],
            state: result.state,
            progressFailures: result.progressFailures,
          );
        });
      }
    } catch (error) {
      if (!mounted) return;
      _showSnack(error is WeReadApiException ? error.message : '$error');
    } finally {
      if (mounted) {
        setState(() {
          _applying = false;
          _busy.remove(diff.remote.bookId);
        });
      }
    }
  }

  Future<void> _applyAll() async {
    final result = _result;
    if (result == null || _applying) return;
    final targets = <WeReadDiff>[
      for (final diff in result.diffs)
        if (diff.kind == WeReadDiffKind.updated) diff,
    ];
    if (targets.isEmpty) return;
    setState(() => _applying = true);
    var done = 0;
    var failed = 0;
    for (final diff in targets) {
      if (!mounted) return;
      setState(() {
        _applyProgress =
            '正在同步《${diff.remote.title}》 ${done + 1}/${targets.length}';
        _busy.add(diff.remote.bookId);
      });
      try {
        final applied = await _api.apply(diff);
        if (!mounted) return;
        _markSynced(diff, applied.message, retryable: applied.retryable);
        done++;
      } catch (_) {
        failed++;
      } finally {
        if (mounted) {
          setState(() => _busy.remove(diff.remote.bookId));
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _applying = false;
      _applyProgress = null;
    });
    _showSnack(failed == 0 ? '已同步 $done 本' : '已同步 $done 本，$failed 本失败，可稍后重试');
  }

  Future<void> _importAll() async {
    final result = _result;
    if (result == null || _applying) return;
    final targets = <WeReadDiff>[
      for (final diff in result.diffs)
        if (diff.kind == WeReadDiffKind.added) diff,
    ];
    if (targets.isEmpty) return;
    setState(() => _applying = true);
    var done = 0;
    var failed = 0;
    for (final diff in targets) {
      if (!mounted) return;
      setState(() {
        _applyProgress =
            '正在导入《${diff.remote.title}》 ${done + 1}/${targets.length}';
        _busy.add(diff.remote.bookId);
      });
      try {
        final imported = await _api.importAdded(diff);
        if (!mounted) return;
        _markSynced(
          diff,
          imported.message,
          retryable: imported.retryable,
          localOverride: imported.importedBook,
          localPercent: (diff.remote.progressPercent ?? 0) / 100,
        );
        done++;
      } catch (_) {
        failed++;
      } finally {
        if (mounted) {
          setState(() => _busy.remove(diff.remote.bookId));
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _applying = false;
      _applyProgress = null;
    });
    _showSnack(failed == 0 ? '已导入 $done 本' : '已导入 $done 本，$failed 本失败，可稍后重试');
  }

  void _markSynced(
    WeReadDiff diff,
    String message, {
    bool retryable = false,
    Book? localOverride,
    double? localPercent,
  }) {
    final result = _result;
    if (result == null) return;
    setState(() {
      _result = WeReadFetchResult(
        snapshot: result.snapshot,
        diffs: <WeReadDiff>[
          for (final item in result.diffs)
            if (item.remote.bookId == diff.remote.bookId)
              item.copyWith(
                kind: retryable
                    ? WeReadDiffKind.updated
                    : WeReadDiffKind.synced,
                newNoteCount: retryable ? item.newNoteCount : 0,
                changes: <String>[message],
                localOverride: localOverride,
                localPercentOverride: localPercent,
              )
            else
              item,
        ],
        state: result.state,
        progressFailures: result.progressFailures,
      );
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('微信读书'),
        actions: <Widget>[
          IconButton(
            key: const ValueKey('weread-login-button'),
            tooltip: _keyConfigured ? (_accountName ?? '已扫码登录') : '扫码登录',
            onPressed: _showAccount,
            icon: Icon(
              _keyConfigured
                  ? Icons.account_circle
                  : Icons.account_circle_outlined,
              color: _keyConfigured ? theme.colorScheme.primary : null,
            ),
          ),
          if (result != null)
            IconButton(
              key: const ValueKey('weread-refresh'),
              tooltip: '重新获取',
              onPressed: _loading ? null : _fetch,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            if (_loading && result == null) ...<Widget>[
              const SizedBox(height: 80),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  _progress ?? '正在获取微信读书数据…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ] else if (_error != null && result == null)
              _ErrorCard(message: _error!, onRetry: _fetch)
            else if (result == null)
              _IntroCard(
                configured: _keyConfigured,
                onPrimary: _keyConfigured ? _fetch : _loginWithQr,
              )
            else ...<Widget>[
              if (_loading) ...<Widget>[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(_progress ?? '正在获取…', style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
              ],
              _SummaryCard(
                result: result,
                applying: _applying,
                applyProgress: _applyProgress,
                onApplyAll: _applyAll,
                onImportAll: _importAll,
              ),
              const SizedBox(height: 12),
              _FilterBar(
                diffs: result.diffs,
                selected: _filter,
                onSelect: (value) => setState(() => _filter = value),
              ),
              const SizedBox(height: 8),
              ..._buildDiffs(result.diffs),
              const SizedBox(height: 8),
              const _FootnoteCard(),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDiffs(List<WeReadDiff> diffs) {
    final filtered = _filter == null
        ? diffs
        : <WeReadDiff>[
            for (final diff in diffs)
              if (diff.kind == _filter) diff,
          ];
    if (filtered.isEmpty) {
      return <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(
              diffs.isEmpty ? '微信读书书架是空的' : '这个分类下没有书',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ];
    }
    return <Widget>[
      for (final diff in filtered)
        _DiffCard(
          key: ValueKey('weread-diff-${diff.remote.bookId}'),
          diff: diff,
          busy: _busy.contains(diff.remote.bookId),
          applying: _applying,
          importedNotes: _result?.state.importedCounts[diff.remote.bookId] ?? 0,
          onSync: () => _apply(diff),
          onImport: () => _import(diff),
          onOpenNotes: () => _openNotes(diff),
          onIgnore: () => _ignore(diff),
          onCopyLink: () => _copyLink(diff.remote.readerLink),
        ),
    ];
  }

  Future<void> _copyLink(String? link) async {
    if (link == null || link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: link));
    _showSnack('已复制微信读书链接');
  }
}

enum _AccountAction { relogin, logout }

class _AccountDialog extends StatelessWidget {
  const _AccountDialog({
    required this.accountName,
    required this.onLogout,
    required this.onRelogin,
  });

  final String? accountName;
  final VoidCallback onLogout;
  final VoidCallback onRelogin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;
    return AlertDialog(
      key: const ValueKey('weread-account-dialog'),
      title: const Text('微信读书账号'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.account_circle, color: color.primary, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  accountName?.trim().isNotEmpty == true
                      ? accountName!.trim()
                      : '已扫码登录',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '已通过微信扫码登录，官方 API Key 已自动配置到本机安全存储。'
            '同步仍然走微信读书官方接口。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: color.onSurface.withValues(alpha: 0.65),
              height: 1.5,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey('weread-logout'),
          onPressed: onLogout,
          child: Text('退出登录', style: TextStyle(color: color.error)),
        ),
        TextButton(
          key: const ValueKey('weread-relogin'),
          onPressed: onRelogin,
          child: const Text('重新扫码'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.configured, required this.onPrimary});

  final bool configured;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.menu_book_outlined, size: 40, color: color.primary),
            const SizedBox(height: 14),
            Text('同步微信读书的阅读信息', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '扫码登录微信读书后，可拉取书架、阅读进度、阅读时长与'
              '划线/想法，并与本机书籍逐本对比。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: color.onSurface.withValues(alpha: 0.7),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            const _StepText(text: '1. 右上角头像按钮扫码登录（微信确认）'),
            const _StepText(text: '2. 点「获取阅读信息」拉取书架'),
            const _StepText(text: '3. 看差异后逐本同步，或一键同步全部'),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const ValueKey('weread-fetch'),
              onPressed: onPrimary,
              icon: Icon(configured ? Icons.cloud_download : Icons.qr_code_2),
              label: Text(configured ? '获取阅读信息' : '扫码登录'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepText extends StatelessWidget {
  const _StepText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;
    return Card(
      elevation: 0,
      color: color.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.error_outline, color: color.onErrorContainer),
                const SizedBox(width: 8),
                Text(
                  '获取失败',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color.onErrorContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color.onErrorContainer,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const ValueKey('weread-retry'),
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.result,
    required this.applying,
    required this.applyProgress,
    required this.onApplyAll,
    required this.onImportAll,
  });

  final WeReadFetchResult result;
  final bool applying;
  final String? applyProgress;
  final VoidCallback onApplyAll;
  final VoidCallback onImportAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;
    final snapshot = result.snapshot;
    final updated = result.diffs
        .where((diff) => diff.kind == WeReadDiffKind.updated)
        .length;
    final added = result.diffs
        .where((diff) => diff.kind == WeReadDiffKind.added)
        .length;
    final deleted = result.diffs
        .where((diff) => diff.kind == WeReadDiffKind.deleted)
        .length;
    final importedAll = result.state.importedCounts.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.compare_arrows, color: color.primary),
                const SizedBox(width: 8),
                Text('对比结果', style: theme.textTheme.titleMedium),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _formatDateTime(snapshot.fetchedAt),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: color.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: <Widget>[
                _Stat(label: '书架', value: '${snapshot.books.length} 本'),
                _Stat(
                  label: '累计阅读',
                  value: _formatDuration(snapshot.totalReadingSeconds),
                ),
                _Stat(label: '划线/想法', value: '${snapshot.totalNotes} 条'),
                _Stat(label: '已导入', value: '$importedAll 条'),
              ],
            ),
            if (snapshot.albumCount > 0 || snapshot.hasMp) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                '微信读书书架另有 ${snapshot.albumCount} 个有声书/专辑'
                '${snapshot.hasMp ? '、1 个文章收藏入口' : ''}，本应用暂不导入。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
            if (result.progressFailures > 0) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                '有 ${result.progressFailures} 本书的阅读进度没拉到，其余数据正常。',
                style: theme.textTheme.bodySmall?.copyWith(color: color.error),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _CountChip(label: '更新', count: updated, color: Colors.orange),
                _CountChip(label: '新增', count: added, color: color.primary),
                _CountChip(label: '移除', count: deleted, color: color.error),
                if (added > 0)
                  FilledButton.tonalIcon(
                    key: const ValueKey('weread-import-all'),
                    onPressed: applying ? null : onImportAll,
                    icon: const Icon(Icons.download, size: 18),
                    label: Text('全部导入（$added）'),
                  ),
                if (updated > 0)
                  FilledButton.tonalIcon(
                    key: const ValueKey('weread-sync-all'),
                    onPressed: applying ? null : onApplyAll,
                    icon: const Icon(Icons.sync, size: 18),
                    label: Text('全部同步（$updated）'),
                  ),
              ],
            ),
            if (applying) ...<Widget>[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              Text(
                applyProgress ?? '正在写入本机…',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label $count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.diffs,
    required this.selected,
    required this.onSelect,
  });

  final List<WeReadDiff> diffs;
  final WeReadDiffKind? selected;
  final ValueChanged<WeReadDiffKind?> onSelect;

  @override
  Widget build(BuildContext context) {
    final options = <(WeReadDiffKind?, String)>[
      (null, '全部'),
      (WeReadDiffKind.updated, '更新'),
      (WeReadDiffKind.added, '新增'),
      (WeReadDiffKind.synced, '一致'),
      (WeReadDiffKind.deleted, '删除'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final option in options) ...<Widget>[
            ChoiceChip(
              key: ValueKey('weread-filter-${option.$1?.name ?? 'all'}'),
              label: Text(
                '${option.$2} ${option.$1 == null ? diffs.length : diffs.where((diff) => diff.kind == option.$1).length}',
              ),
              selected: selected == option.$1,
              onSelected: (_) => onSelect(option.$1),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _DiffCard extends StatelessWidget {
  const _DiffCard({
    required this.diff,
    required this.busy,
    required this.applying,
    required this.importedNotes,
    required this.onSync,
    required this.onImport,
    required this.onOpenNotes,
    required this.onIgnore,
    required this.onCopyLink,
    super.key,
  });

  final WeReadDiff diff;
  final bool busy;
  final bool applying;
  final int importedNotes;
  final VoidCallback onSync;
  final VoidCallback onImport;
  final VoidCallback onOpenNotes;
  final VoidCallback onIgnore;
  final VoidCallback onCopyLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;
    final remote = diff.remote;
    final local = diff.local;
    final remotePercent = (remote.progressPercent ?? 0).clamp(0, 100);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 42,
                  height: 58,
                  decoration: BoxDecoration(
                    color: color.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.menu_book,
                    color: color.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              remote.title.isEmpty ? '未命名' : remote.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _StatusPill(kind: diff.kind),
                        ],
                      ),
                      if ((remote.author ?? '').isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          remote.author!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: color.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        _progressLine(diff, remotePercent),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _notesLine(remote),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _timeLine(remote),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: color.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      if (local != null &&
                          diff.kind == WeReadDiffKind.deleted) ...[
                        const SizedBox(height: 2),
                        Text(
                          '本机《${local.title}》仍保留，只解除微信读书关联。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: color.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                      if (local == null &&
                          diff.kind == WeReadDiffKind.added) ...[
                        const SizedBox(height: 2),
                        Text(
                          '导入后生成一本只含书名与简介的占位 EPUB。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: color.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (diff.changes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              for (final change in diff.changes)
                Padding(
                  padding: const EdgeInsets.only(left: 54, top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.circle,
                        size: 5,
                        color: diff.kind == WeReadDiffKind.updated
                            ? Colors.orange
                            : color.onSurface.withValues(alpha: 0.4),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          change,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: diff.kind == WeReadDiffKind.updated
                                ? Colors.orange.shade800
                                : color.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (remote.totalNotes > 0 || importedNotes > 0)
                  TextButton.icon(
                    key: ValueKey('weread-notes-${remote.bookId}'),
                    onPressed: onOpenNotes,
                    icon: const Icon(Icons.format_quote, size: 17),
                    label: const Text('划线/想法'),
                  ),
                if (diff.kind == WeReadDiffKind.added &&
                    (remote.readerLink ?? '').isNotEmpty)
                  IconButton(
                    key: ValueKey('weread-copy-${remote.bookId}'),
                    tooltip: '复制微信读书链接',
                    onPressed: onCopyLink,
                    icon: const Icon(Icons.link, size: 20),
                  ),
                if (diff.kind == WeReadDiffKind.added)
                  FilledButton.tonalIcon(
                    key: ValueKey('weread-import-${remote.bookId}'),
                    onPressed: applying ? null : onImport,
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download, size: 17),
                    label: const Text('导入'),
                  ),
                if (diff.kind == WeReadDiffKind.updated)
                  FilledButton.tonalIcon(
                    key: ValueKey('weread-sync-${remote.bookId}'),
                    onPressed: applying ? null : onSync,
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync, size: 17),
                    label: const Text('同步'),
                  ),
                if (diff.kind == WeReadDiffKind.deleted)
                  TextButton(
                    key: ValueKey('weread-ignore-${remote.bookId}'),
                    onPressed: applying ? null : onIgnore,
                    child: const Text('忽略'),
                  ),
                if (diff.kind == WeReadDiffKind.synced)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.check_circle_outline,
                        size: 17,
                        color: Colors.green.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '已一致',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.green.shade700,
                        ),
                      ),
                      IconButton(
                        key: ValueKey('weread-resync-${remote.bookId}'),
                        tooltip: '重新同步（补阅读时长等）',
                        onPressed: applying ? null : onSync,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.refresh, size: 18),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _progressLine(WeReadDiff diff, int remotePercent) {
    if (diff.local == null) {
      return '微信读书 $remotePercent% · 本机未收录';
    }
    final localPercent = (diff.localPercent * 100).toStringAsFixed(0);
    return '阅读进度 微信读书 $remotePercent% · 本机 $localPercent%';
  }

  String _notesLine(WeReadBook remote) {
    final imported = importedNotes;
    return '划线/想法 ${remote.totalNotes} 条'
        '${imported > 0 ? ' · 已同步 $imported 条' : ''}';
  }

  String _timeLine(WeReadBook remote) {
    final duration = _formatDuration(remote.readingSeconds ?? 0);
    final date = _formatDate(remote.lastReadAt);
    return '累计阅读 $duration · 最近 $date';
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.kind});

  final WeReadDiffKind kind;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (kind) {
      WeReadDiffKind.added => ('新增', Colors.blue),
      WeReadDiffKind.updated => ('更新', Colors.orange),
      WeReadDiffKind.synced => ('一致', Colors.green),
      WeReadDiffKind.deleted => ('删除', Colors.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FootnoteCard extends StatelessWidget {
  const _FootnoteCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('说明', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          _note(
            theme,
            '微信读书有、本机没有的书可点「导入」：自动生成一本只含书名、作者、封面与简介的占位 EPUB，'
            '之后可再替换成正式书源。',
          ),
          _note(theme, '划线按原文在本机书籍中定位，找不到原文的会跳过。'),
          _note(theme, '同步是单向导入：微信读书没有的本机进度、标注与阅读时长会保留，不会被删除。'),
        ],
      ),
    );
  }

  Widget _note(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '· $text',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
          height: 1.4,
        ),
      ),
    );
  }
}

String _formatDuration(int seconds) {
  if (seconds <= 0) return '—';
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0) return '$hours 小时 $minutes 分钟';
  if (minutes > 0) return '$minutes 分钟';
  return '$seconds 秒';
}

String _formatDate(int? unixSeconds) {
  if (unixSeconds == null || unixSeconds <= 0) return '—';
  final date = DateTime.fromMillisecondsSinceEpoch(
    unixSeconds * 1000,
  ).toLocal();
  return '${date.year}-${_two(date.month)}-${_two(date.day)}';
}

String _formatDateTime(DateTime date) {
  final local = date.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
