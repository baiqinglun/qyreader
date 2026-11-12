/// 应用主框架：底部三个 Tab（书架 / 统计 / 设置）。
///
/// 用 `IndexedStack` 而不是按路由重建：切 Tab 时书架滚动位置、统计的周期
/// 选择都能保留，不会每次回来都跳回顶部。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/open_with.dart';
import '../../app/providers.dart';
import '../../app/router.dart' show readerPath;
import 'widgets/floating_nav_bar.dart';
import '../reader/reader_active_marker.dart';
import '../shelf/shelf_controller.dart';
import '../shelf/shelf_page.dart';
import '../settings/settings_page.dart';
import '../stats/stats_page.dart';

/// 三个 Tab 的下标。
enum HomeTab { shelf, stats, settings }

/// 主框架。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({this.initialTab = HomeTab.shelf, super.key});

  /// 起始 Tab（深链 /stats 直接进统计）。
  final HomeTab initialTab;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late int _index = widget.initialTab.index;
  StreamSubscription<String>? _openSub;

  @override
  void initState() {
    super.initState();
    // 从文件管理器「打开方式」进来的文件：导入并直接打开
    _openSub = OpenWithService.files.listen(_onOpenFile);
    final queued = OpenWithService.drainQueue();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (queued.isNotEmpty) {
        for (final path in queued) {
          _onOpenFile(path);
        }
        return;
      }
      // 冷启动（进程在后台被杀后回来）：之前在读的书直接回到阅读页，
      // 不让用户重新从书架点一遍。主动退出过阅读器时标记已清除，不会
      // 误恢复。
      _maybeResumeReading();
    });
  }

  /// 上次退出时阅读器还开着 → 冷启动直接回到那本书。
  Future<void> _maybeResumeReading() async {
    final bookId = await activeReaderBook();
    if (bookId == null || bookId.isEmpty || !mounted) return;
    try {
      final repo = await ref.read(bookRepositoryProvider.future);
      final book = await repo.getById(bookId);
      if (!mounted) return;
      if (book == null) {
        // 书已删除：清掉失效标记。
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('reader.activeBook');
        return;
      }
      unawaited(context.push(readerPath(book.id)));
    } catch (_) {
      // 恢复失败不阻塞应用启动
    }
  }

  Future<void> _onOpenFile(String path) async {
    if (!mounted) return;
    setState(() => _index = HomeTab.shelf.index);
    final book =
        await ref.read(importControllerProvider.notifier).importFromPath(path);
    if (!mounted || book == null) return;
    unawaited(context.push(readerPath(book.id)));
  }

  @override
  void dispose() {
    _openSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 各页面自带 AppBar，这里只放内容 + 底部导航
      body: IndexedStack(
        index: _index,
        children: const [
          ShelfPage(),
          StatsPage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: FloatingNavBar(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
      ),
    );
  }
}
