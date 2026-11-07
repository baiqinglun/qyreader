/// 排版面板（Aa）：主题 / 字号 / 行距 / 边距 / flow / 翻页模式。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/reading_theme.dart';
import '../reader_settings.dart';

/// 排版设置面板（模态底部弹层）。
class TypesettingPanel extends ConsumerWidget {
  const TypesettingPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readingSettingsControllerProvider);
    final controller = ref.read(readingSettingsControllerProvider.notifier);
    final fg = settings.theme.chromeForeground;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 主题色板
            Row(
              children: [
                for (final theme in ReadingTheme.values) ...[
                  Expanded(
                    child: _ThemeSwatch(
                      theme: theme,
                      selected: settings.theme == theme,
                      onTap: () => controller.patch(theme: theme),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            _StepperRow(
              label: '字号',
              value: settings.fontSize.round().toString(),
              fg: fg,
              onMinus: settings.fontSize > 14
                  ? () => controller.patch(fontSize: settings.fontSize - 1)
                  : null,
              onPlus: settings.fontSize < 28
                  ? () => controller.patch(fontSize: settings.fontSize + 1)
                  : null,
            ),
            _StepperRow(
              label: '行距',
              value: settings.lineHeight.toStringAsFixed(1),
              fg: fg,
              onMinus: settings.lineHeight > 1.2
                  ? () => controller.patch(lineHeight: settings.lineHeight - 0.1)
                  : null,
              onPlus: settings.lineHeight < 2.4
                  ? () => controller.patch(lineHeight: settings.lineHeight + 0.1)
                  : null,
            ),
            _StepperRow(
              label: '边距',
              value: settings.margin.round().toString(),
              fg: fg,
              onMinus: settings.margin > 0
                  ? () => controller.patch(margin: settings.margin - 4)
                  : null,
              onPlus: settings.margin < 48
                  ? () => controller.patch(margin: settings.margin + 4)
                  : null,
            ),
            const SizedBox(height: 16),
            _SegmentRow<ReadingFlow>(
              label: '排版',
              fg: fg,
              segments: {
                for (final f in ReadingFlow.values) f: f.label,
              },
              selected: settings.flow,
              onSelect: (v) => controller.patch(flow: v),
            ),
            const SizedBox(height: 12),
            _SegmentRow<PageTurnMode>(
              label: '翻页',
              fg: fg,
              segments: {
                for (final m in PageTurnMode.values) m: m.label,
              },
              selected: settings.pageTurnMode,
              onSelect: (v) => controller.patch(pageTurnMode: v),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final ReadingTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: theme.background,
              border: Border.all(
                color: selected ? theme.accent : Colors.black26,
                width: selected ? 2.5 : 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              '文',
              style: TextStyle(color: theme.foreground, fontSize: 16),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            theme.label,
            style: TextStyle(
              fontSize: 12,
              color: selected ? theme.accent : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.fg,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String value;
  final Color fg;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label, style: TextStyle(color: fg))),
          IconButton(
            onPressed: onMinus,
            icon: Icon(Icons.remove, color: fg),
          ),
          Expanded(
            child: Center(
              child: Text(value, style: TextStyle(color: fg)),
            ),
          ),
          IconButton(
            onPressed: onPlus,
            icon: Icon(Icons.add, color: fg),
          ),
        ],
      ),
    );
  }
}

class _SegmentRow<T> extends StatelessWidget {
  const _SegmentRow({
    required this.label,
    required this.fg,
    required this.segments,
    required this.selected,
    required this.onSelect,
  });

  final String label;
  final Color fg;
  final Map<T, String> segments;
  final T selected;
  final void Function(T value) onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label, style: TextStyle(color: fg))),
          Expanded(
            child: Wrap(
              spacing: 8,
              children: [
                for (final entry in segments.entries)
                  _Chip(
                    label: entry.value,
                    selected: entry.key == selected,
                    fg: fg,
                    onTap: () => onSelect(entry.key),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.fg,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? fg.withValues(alpha: 0.15) : Colors.transparent,
          border: Border.all(color: fg.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label, style: TextStyle(color: fg, fontSize: 13)),
      ),
    );
  }
}
