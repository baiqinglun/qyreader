/// 页面布局编辑器：九宫格 + 页眉/页脚左右区域。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/motion.dart';
import '../page_layout.dart';

/// 打开页面布局编辑器；完成时写入 prefs 并立即生效。
Future<void> showPageLayoutEditor(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PageLayoutEditor(),
  );
}

/// 页面布局编辑页。
class PageLayoutEditor extends ConsumerStatefulWidget {
  const PageLayoutEditor({super.key});

  @override
  ConsumerState<PageLayoutEditor> createState() => _PageLayoutEditorState();
}

class _PageLayoutEditorState extends ConsumerState<PageLayoutEditor> {
  late PageLayoutSettings _draft;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(pageLayoutControllerProvider);
  }

  Future<void> _pickZone(int index) async {
    final action = await showModalBottomSheet<TapZoneAction>(
      context: context,
      sheetAnimationStyle: kSmoothSheetAnimation,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                '区域 ${index + 1} 的动作',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final action in TapZoneAction.values)
              ListTile(
                key: ValueKey('page-layout-zone-option-${action.name}'),
                leading: Icon(_zoneIcon(action), size: 20),
                title: Text(action.label),
                trailing: _draft.zones[index] == action
                    ? const Icon(Icons.check, size: 20)
                    : null,
                onTap: () => Navigator.of(ctx).pop(action),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    setState(() => _draft = _draft.withZone(index, action));
  }

  Future<void> _pickEdge({
    required String title,
    required EdgeZoneAction current,
    required ValueChanged<EdgeZoneAction> onPicked,
  }) async {
    final action = await showModalBottomSheet<EdgeZoneAction>(
      context: context,
      sheetAnimationStyle: kSmoothSheetAnimation,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                '$title的动作',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final action in EdgeZoneAction.values)
              ListTile(
                key: ValueKey('page-layout-edge-option-${action.name}'),
                leading: Icon(_edgeIcon(action), size: 20),
                title: Text(action.label),
                trailing: current == action
                    ? const Icon(Icons.check, size: 20)
                    : null,
                onTap: () => Navigator.of(ctx).pop(action),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    setState(() => onPicked(action));
  }

  Future<void> _done() async {
    await ref.read(pageLayoutControllerProvider.notifier).save(_draft);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '页面布局',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '点击区域设置动作；左右滑动翻页始终可用',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _edgeRow(
                leftLabel: '页眉左侧',
                rightLabel: '页眉右侧',
                left: _draft.headerLeft,
                right: _draft.headerRight,
                leftKey: const ValueKey('page-layout-header-left'),
                rightKey: const ValueKey('page-layout-header-right'),
                onLeft: () => _pickEdge(
                  title: '页眉左侧',
                  current: _draft.headerLeft,
                  onPicked: (v) => _draft = _draft.copyWith(headerLeft: v),
                ),
                onRight: () => _pickEdge(
                  title: '页眉右侧',
                  current: _draft.headerRight,
                  onPicked: (v) => _draft = _draft.copyWith(headerRight: v),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(child: _grid(scheme)),
              const SizedBox(height: 10),
              _edgeRow(
                leftLabel: '页脚左侧',
                rightLabel: '页脚右侧',
                left: _draft.footerLeft,
                right: _draft.footerRight,
                leftKey: const ValueKey('page-layout-footer-left'),
                rightKey: const ValueKey('page-layout-footer-right'),
                onLeft: () => _pickEdge(
                  title: '页脚左侧',
                  current: _draft.footerLeft,
                  onPicked: (v) => _draft = _draft.copyWith(footerLeft: v),
                ),
                onRight: () => _pickEdge(
                  title: '页脚右侧',
                  current: _draft.footerRight,
                  onPicked: (v) => _draft = _draft.copyWith(footerRight: v),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('page-layout-reset'),
                      onPressed: () => setState(
                        () => _draft = PageLayoutSettings.defaults,
                      ),
                      child: const Text('重置'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('page-layout-done'),
                      onPressed: _done,
                      child: const Text('完成'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(ColorScheme scheme) {
    return Column(
      children: [
        for (var row = 0; row < 3; row++)
          Expanded(
            child: Row(
              children: [
                for (var col = 0; col < 3; col++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: _zoneCell(
                        index: row * 3 + col,
                        scheme: scheme,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _zoneCell({required int index, required ColorScheme scheme}) {
    final action = _draft.zones[index];
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        key: ValueKey('page-layout-zone-$index'),
        borderRadius: BorderRadius.circular(22),
        onTap: () => _pickZone(index),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                action.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '区域 ${index + 1}',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _edgeRow({
    required String leftLabel,
    required String rightLabel,
    required EdgeZoneAction left,
    required EdgeZoneAction right,
    required Key leftKey,
    required Key rightKey,
    required VoidCallback onLeft,
    required VoidCallback onRight,
  }) {
    return Row(
      children: [
        Expanded(
          child: _edgeButton(
            key: leftKey,
            label: leftLabel,
            action: left,
            onTap: onLeft,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _edgeButton(
            key: rightKey,
            label: rightLabel,
            action: right,
            onTap: onRight,
          ),
        ),
      ],
    );
  }

  Widget _edgeButton({
    required Key key,
    required String label,
    required EdgeZoneAction action,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${action.label} $label',
                  style: TextStyle(
                    fontSize: 15,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static IconData _zoneIcon(TapZoneAction action) => switch (action) {
        TapZoneAction.previousPage => Icons.chevron_left,
        TapZoneAction.nextPage => Icons.chevron_right,
        TapZoneAction.menu => Icons.menu,
      };

  static IconData _edgeIcon(EdgeZoneAction action) => switch (action) {
        EdgeZoneAction.followGrid => Icons.grid_on,
        EdgeZoneAction.previousPage => Icons.chevron_left,
        EdgeZoneAction.nextPage => Icons.chevron_right,
        EdgeZoneAction.menu => Icons.menu,
      };
}
