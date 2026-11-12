/// 阅读主题管理：默认主题 + 我的主题（新增 / 编辑 / 删除 / 应用）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../reader/reader_themes.dart';

/// 阅读主题列表页。
class ReaderThemesPage extends ConsumerWidget {
  const ReaderThemesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(readerThemesControllerProvider);
    final controller = ref.read(readerThemesControllerProvider.notifier);
    final builtIns = state.all.where((t) => t.builtIn).toList(growable: false);
    final custom = state.all.where((t) => !t.builtIn).toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('阅读主题')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('reader-theme-add'),
        onPressed: () => context.push(kReaderThemeEditPath),
        icon: const Icon(Icons.add),
        label: const Text('新建主题'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Text(
            '主题是一整份排版快照：底色、正文、标题、页面、页眉页脚都在里面。'
            '在阅读页的「排版」面板点「+」可以复制当前排版为主题，之后的调整会自动存进它。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          const _Section('默认主题'),
          for (final theme in builtIns)
            _ThemeCard(
              preset: theme,
              active: theme.id == state.activeId,
              onApply: () => _apply(context, controller, theme),
            ),
          const SizedBox(height: 20),
          const _Section('我的主题'),
          if (custom.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text('还没有自定义主题，点右下角「新建主题」开始。'),
            )
          else
            for (final theme in custom)
              _ThemeCard(
                preset: theme,
                active: theme.id == state.activeId,
                onApply: () => _apply(context, controller, theme),
                onEdit: () => context.push(kReaderThemeEditPath, extra: theme),
                onDelete: () => _delete(context, controller, theme),
              ),
        ],
      ),
    );
  }

  Future<void> _apply(
    BuildContext context,
    ReaderThemesController controller,
    ReaderThemePreset theme,
  ) async {
    await controller.apply(theme);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已应用「${theme.name}」')));
  }

  Future<void> _delete(
    BuildContext context,
    ReaderThemesController controller,
    ReaderThemePreset theme,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除主题'),
        content: Text('确定删除「${theme.name}」吗？只删主题，阅读内容不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await controller.delete(theme.id);
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.preset,
    required this.active,
    required this.onApply,
    this.onEdit,
    this.onDelete,
  });

  final ReaderThemePreset preset;
  final bool active;
  final VoidCallback onApply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = preset.backgroundImage;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onApply,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _Swatch(
                  preset: preset,
                  image: image,
                  scheme: scheme,
                  active: active,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              preset.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          if (active) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.check_circle,
                              size: 17,
                              color: scheme.primary,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${preset.background.label} · ${preset.fontSize.round()}px'
                        ' · 行距 ${preset.lineHeight.toStringAsFixed(1)}'
                        ' · 段距 ${preset.paragraphSpacing.toStringAsFixed(1)}'
                        ' · 边距 ${preset.marginLeft.round()}/'
                        '${preset.marginRight.round()}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (image.isNotEmpty)
                        Text(
                          '自定义背景图',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.primary),
                        ),
                    ],
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    tooltip: '编辑',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                if (onDelete != null)
                  IconButton(
                    tooltip: '删除',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.preset,
    required this.image,
    required this.scheme,
    required this.active,
  });

  final ReaderThemePreset preset;
  final String image;
  final ColorScheme scheme;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 52,
        height: 68,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: preset.background.background),
            if (image.isNotEmpty)
              Image.file(
                File(image),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            if (image.isNotEmpty)
              ColoredBox(
                color: preset.background.background.withValues(alpha: 0.3),
              ),
            Center(
              child: Text(
                '字',
                style: TextStyle(
                  color: preset.background.foreground,
                  fontSize: 20,
                ),
              ),
            ),
            if (active)
              Positioned(
                right: 4,
                bottom: 4,
                child: Icon(
                  Icons.check_circle,
                  size: 16,
                  color: scheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 供设置页显示当前主题名。
ReaderThemePreset? readerThemeById(ReaderThemesState state, String id) {
  for (final t in state.all) {
    if (t.id == id) return t;
  }
  return null;
}
