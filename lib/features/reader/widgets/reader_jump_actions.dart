/// 从划线/想法跳转后悬浮在右下角的两个选择：回原位置或把当前页设为进度。
library;

import 'package:flutter/material.dart';

import '../../../app/theme/reading_theme.dart';

/// 划线跳转后的进度选择条。
///
/// 跳转本身不改变阅读进度；用户点「返回原位置」回到跳转前的阅读进度，
/// 点「设为阅读进度」才把当前页写成新的阅读进度。
class ReaderJumpActions extends StatelessWidget {
  /// 构造。
  const ReaderJumpActions({
    super.key,
    required this.theme,
    required this.onReturn,
    required this.onSetProgress,
  });

  /// 阅读主题（与阅读器悬浮控件同色）。
  final ReadingTheme theme;

  /// 返回跳转前的阅读位置。
  final VoidCallback onReturn;

  /// 把当前页设为阅读进度。
  final VoidCallback onSetProgress;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('reader-annotation-jump-actions'),
      color: theme.chromeSurface,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextButton.icon(
              key: const ValueKey('reader-annotation-jump-return'),
              onPressed: onReturn,
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: const Text('返回原位置'),
              style: TextButton.styleFrom(
                foregroundColor: theme.chromeForeground,
                alignment: Alignment.centerLeft,
              ),
            ),
            Divider(
              height: 1,
              color: theme.chromeForeground.withValues(alpha: 0.12),
            ),
            FilledButton.icon(
              key: const ValueKey('reader-annotation-jump-set'),
              onPressed: onSetProgress,
              icon: const Icon(Icons.bookmark_added_rounded, size: 18),
              label: const Text('设为阅读进度'),
              style: FilledButton.styleFrom(
                backgroundColor: theme.accent,
                foregroundColor: theme.background,
                alignment: Alignment.centerLeft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
