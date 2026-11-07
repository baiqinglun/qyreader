/// 通用空态组件：图标 + 标题 + 说明 + 可选主操作按钮。
///
/// 设计规范要求「不要居中转圈」，空态必须给出下一步动作引导。
library;

import 'package:flutter/material.dart';

import 'pressable_scale.dart';

/// 空态视图。
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// 引导图标（如「书架空空如也」用书本图标）。
  final IconData icon;

  /// 一句话标题。
  final String title;

  /// 补充说明文案。
  final String message;

  /// 主操作按钮文案；为 null 则不显示按钮。
  final String? actionLabel;

  /// 主操作回调。
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 24),
              PressableScale(
                onTap: onAction,
                child: FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
