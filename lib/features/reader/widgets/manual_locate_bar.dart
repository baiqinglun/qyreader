/// 阅读页「手动定位标注」悬浮条。
///
/// 用户从标注列表点「手动定位」后，抽屉收起、正文仍可翻页；翻到目标页时
/// 点这里的「设为当前页」就把标注锚到当前页首。取消则不改位置。
library;

import 'package:flutter/material.dart';

import '../../../app/theme/reading_theme.dart';

/// 手动定位悬浮条。
class ManualLocateBar extends StatelessWidget {
  const ManualLocateBar({
    required this.theme,
    required this.quote,
    required this.onCancel,
    required this.onConfirm,
    super.key,
  });

  /// 阅读主题。
  final ReadingTheme theme;

  /// 待定位标注的原文（截断展示）。
  final String quote;

  /// 取消手动定位。
  final VoidCallback onCancel;

  /// 把当前页设为该标注位置。
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final fg = theme.chromeForeground;
    final text = quote.trim();
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: theme.chromeSurface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.my_location_rounded, size: 16, color: theme.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '翻到目标页后，点「设为当前页」',
                    style: TextStyle(
                      color: fg,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                InkWell(
                  onTap: onCancel,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.close,
                      size: 17,
                      color: fg.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
            if (text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 30),
                child: Text(
                  '「$text」',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onCancel,
                  child: Text(
                    '取消',
                    style: TextStyle(color: fg.withValues(alpha: 0.7)),
                  ),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  key: const ValueKey('manual-locate-confirm'),
                  onPressed: onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.accent,
                    foregroundColor: theme.chromeSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('设为当前页'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
