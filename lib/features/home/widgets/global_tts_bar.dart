/// 全局听书控制条：正在听书时（即使已退出书籍）在所有页面底部显示。
///
/// 两个挂载点：
/// - [GlobalTtsBar]：主框架（HomeShell）底栏上方——首页/书架/统计/设置的
///   主出口，条排在导航栏上不遮导航；
/// - [TtsBarOverlay]：挂在 `MaterialApp.builder` 的覆盖层，只对**非主框架**
///   路由（书籍详情、我的阅读等二级页）显示，避免双层条。
///
/// 阅读页与全屏听书页各自在 initState/dispose 调 [TtsBarOverlay.suppress] /
/// [TtsBarOverlay.unsuppress]（可重入计数）声明「我盖住了」——它们有自己的
/// 听书 UI。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart' show readerTtsPath, routerProvider;
import '../../../app/theme/reading_theme.dart';
import '../../reader/tts/tts_playback.dart';
import '../../reader/widgets/tts_bar.dart';

/// 主框架路由（HomeShell 自带控制条，覆盖层在这些路径上不重复显示）。
const Set<String> _kShellRoutes = <String>{'/', '/shelf', '/stats'};

/// 构建控制条本体（两个挂载点共用）。
Widget _buildTtsBar(
  WidgetRef ref,
  TtsPlaybackState tts,
  bool dark, {
  required String barKey,
  required bool tooltips,
}) {
  return TtsBar(
    key: ValueKey(barKey),
    state: tts,
    theme: dark ? ReadingTheme.night : ReadingTheme.paper,
    tooltips: tooltips,
    onOpen: () =>
        unawaited(ref.read(routerProvider).push(readerTtsPath(tts.bookId!))),
    onPause: () => ref.read(ttsPlaybackProvider.notifier).pause(),
    onResume: () => ref.read(ttsPlaybackProvider.notifier).resume(),
    onStop: () => ref.read(ttsPlaybackProvider.notifier).stop(),
  );
}

/// 主框架（HomeShell）底栏上方的听书控制条；空闲时收缩为 0 高。
class GlobalTtsBar extends ConsumerWidget {
  /// 构造。
  const GlobalTtsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tts = ref.watch(ttsPlaybackProvider);
    if (!tts.active || tts.bookId == null) {
      return const SizedBox.shrink();
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    // 在 Navigator 覆盖层内：tooltip 可用
    return _buildTtsBar(ref, tts, dark, barKey: 'home-tts-bar', tooltips: true);
  }
}

/// 全局覆盖层（MaterialApp.builder 挂载）：非主框架页面的听书控制条。
class TtsBarOverlay extends ConsumerWidget {
  /// 构造（[child] 是 Navigator）。
  const TtsBarOverlay({required this.child, super.key});

  /// 应用导航树。
  final Widget? child;

  static final ValueNotifier<int> _suppressCount = ValueNotifier<int>(0);

  /// 阅读页/听书页挂载时调用：盖住控制条（可重入计数）。
  static void suppress() => _suppressCount.value++;

  /// 阅读页/听书页卸载时调用。
  static void unsuppress() {
    if (_suppressCount.value > 0) _suppressCount.value--;
  }

  /// 测试用：清零计数。
  @visibleForTesting
  static void resetForTest() => _suppressCount.value = 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tts = ref.watch(ttsPlaybackProvider);
    return Stack(
      children: [
        if (child != null) child!,
        // 控制条层：听书中、没人声明盖住、且当前栈顶不是主框架
        // （主框架自己的 GlobalTtsBar 在导航栏上方，这里再放会叠两层）
        ValueListenableBuilder<int>(
          valueListenable: _suppressCount,
          builder: (context, suppressed, _) {
            if (suppressed > 0 || !tts.active || tts.bookId == null) {
              return const SizedBox.shrink();
            }
            final router = ref.read(routerProvider);
            return ListenableBuilder(
              listenable: router.routerDelegate,
              builder: (context, _) {
                final top = router
                    .routerDelegate
                    .currentConfiguration
                    .last
                    .matchedLocation;
                if (_kShellRoutes.contains(top)) {
                  return const SizedBox.shrink();
                }
                final dark = Theme.of(context).brightness == Brightness.dark;
                // 在 Navigator 覆盖层之外：关掉 tooltip（IconButton 的
                // Tooltip 需要 Overlay 祖先）
                return Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildTtsBar(
                    ref,
                    tts,
                    dark,
                    barKey: 'overlay-tts-bar',
                    tooltips: false,
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
