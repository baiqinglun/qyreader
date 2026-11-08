/// 朗读控制条：当前句预览 + 暂停/继续 + 停止 + 定时剩余。
library;

import 'package:flutter/material.dart';

import '../../../app/theme/reading_theme.dart';
import '../tts/tts_playback.dart';

/// 朗读控制条（固定在底栏上方，播放中显示）。
class TtsBar extends StatelessWidget {
  const TtsBar({
    required this.state,
    required this.theme,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    super.key,
  });

  /// 播放状态。
  final TtsPlaybackState state;

  /// 阅读主题。
  final ReadingTheme theme;

  /// 暂停。
  final VoidCallback onPause;

  /// 继续。
  final VoidCallback onResume;

  /// 停止。
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final fg = theme.chromeForeground;
    final playing = state.status == TtsPlaybackStatus.playing;
    final preparing = state.status == TtsPlaybackStatus.preparing;
    final progress = state.total == 0
        ? ''
        : '${state.index + 1}/${state.total} 句';
    final remaining = state.remaining;
    final remainingText = remaining == null
        ? ''
        : ' · ${remaining.inMinutes}:'
            '${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';
    return Material(
      color: theme.chromeSurface,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(
              Icons.headphones,
              size: 18,
              color: theme.accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preparing
                        ? '准备朗读…'
                        : '${playing ? '朗读中' : '已暂停'} · $progress$remainingText',
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.currentText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: playing ? '暂停' : '继续',
              onPressed: preparing ? null : (playing ? onPause : onResume),
              icon: Icon(
                playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                color: theme.accent,
                size: 32,
              ),
            ),
            IconButton(
              tooltip: '停止',
              onPressed: onStop,
              icon: Icon(Icons.stop_circle_outlined, color: fg, size: 28),
            ),
          ],
        ),
      ),
    );
  }
}
