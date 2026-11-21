/// 桌面组件同步：把书架 / 统计的变化推给原生组件。
///
/// 触发时机：App 启动、书架流或统计修订号变化、回到前台、每 5 分钟一次
/// （跨零点 / 长时间停留时刷新今日组件）。推送做 600ms 防抖，避免书架
/// 流短时间内多次发射时反复解码封面。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/stats_revision.dart';
import '../../domain/entities/book.dart';
import '../shelf/shelf_controller.dart';
import 'home_widget_data.dart';
import 'home_widget_service.dart';

/// 应用级单例：`QyReaderApp` 构建时 watch 一次即可启动。
final Provider<HomeWidgetSync> homeWidgetSyncProvider =
    Provider<HomeWidgetSync>((ref) {
      final sync = HomeWidgetSync(ref);
      ref.onDispose(sync.dispose);
      sync.start();
      return sync;
    });

/// 桌面组件数据同步器。
class HomeWidgetSync with WidgetsBindingObserver {
  /// 构造。
  HomeWidgetSync(this._ref);

  final Ref _ref;

  Timer? _debounce;
  Timer? _periodic;
  bool _started = false;
  bool _busy = false;
  bool _pending = false;

  /// 开始监听（非 Android / 测试环境直接返回）。
  void start() {
    if (_started || !HomeWidgetService.supported) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _ref.listen<AsyncValue<List<ShelfItem>>>(
      shelfItemsProvider,
      (_, _) => schedule(),
    );
    statsRevision.addListener(schedule);
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) => schedule());
    schedule();
  }

  /// 防抖后推一次快照。
  void schedule() {
    if (!_started) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _push);
  }

  Future<void> _push() async {
    if (_busy) {
      _pending = true;
      return;
    }
    _busy = true;
    try {
      final items = await _ref.read(shelfItemsProvider.future);
      final stats = await (await _ref.read(
        statsRepositoryProvider.future,
      )).overview();
      await HomeWidgetService.update(
        buildHomeWidgetData(items: items, stats: stats),
      );
    } catch (_) {
      // 组件是增强功能：数据库尚未就绪 / 查询失败都静默
    } finally {
      _busy = false;
      if (_pending) {
        _pending = false;
        schedule();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) schedule();
  }

  /// 停止监听（provider 销毁时）。
  void dispose() {
    _debounce?.cancel();
    _periodic?.cancel();
    statsRevision.removeListener(schedule);
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      _started = false;
    }
  }
}
