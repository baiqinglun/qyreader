/// 全屏听书页面（「文稿」式）：整章句子随朗读滚动，当前句高亮，点句跳转；
/// 底部功能行（原文/语速/音色/音乐/设置）+ 进度滑杆 + 运输排。
///
/// 从阅读页的朗读控制条（TtsBar）或全局控制条进入；控制器是全局单例
/// （`ttsPlaybackProvider`），页面被盖住时阅读页的计时守卫（isListening）
/// 自动继续，本页不碰会话。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart' show readerPath;
import '../../../app/theme/motion.dart';
import '../../../app/theme/reading_theme.dart';
import '../../home/widgets/global_tts_bar.dart';
import '../reader_active_marker.dart';
import '../reader_settings.dart';
import 'audio_library.dart';
import 'tts_playback.dart';
import 'tts_settings.dart';
import 'tts_settings_sheet.dart';
import 'voice_picker_sheet.dart';

/// 全屏听书页面。
class TtsPage extends ConsumerStatefulWidget {
  /// 构造（bookId 来自路由；控制器是全局单例，从 provider 取）。
  const TtsPage({required this.bookId, super.key});

  /// 正在听的书 id。
  final String bookId;

  @override
  ConsumerState<TtsPage> createState() => _TtsPageState();
}

class _TtsPageState extends ConsumerState<TtsPage> {
  /// 文稿句子的 GlobalKey（自动滚动到当前句用，按需生长）。
  final List<GlobalKey> _sentenceKeys = <GlobalKey>[];

  int _lastAutoScrollIndex = -1;

  TtsPlayback get _tts => ref.read(ttsPlaybackProvider.notifier);

  /// 状态快照（Notifier.state 是 protected，外部一律走 provider）。
  TtsPlaybackState get _ttsState => ref.read(ttsPlaybackProvider);

  @override
  void initState() {
    super.initState();
    // 听书页本身就是听书界面：藏掉全局控制条（dispose 归还）
    TtsBarOverlay.suppress();
  }

  @override
  void dispose() {
    TtsBarOverlay.unsuppress();
    super.dispose();
  }

  /// 回到书籍：阅读页还在栈里就退回，否则直接打开那本书的阅读页。
  void _backToBook() {
    if (ref.read(ttsPlaybackProvider).bookId == null) return;
    if (activeReaderBookSync() == widget.bookId) {
      context.pop();
    } else {
      context.push(readerPath(widget.bookId));
    }
  }

  /// 当前句变化后把文稿滚动到可见位置（只对已构建的句生效）。
  void _scheduleAutoScroll(int index) {
    if (index == _lastAutoScrollIndex) return;
    _lastAutoScrollIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (index < 0 || index >= _sentenceKeys.length) return;
      final itemContext = _sentenceKeys[index].currentContext;
      if (itemContext == null) return;
      Scrollable.ensureVisible(
        itemContext,
        alignment: 0.32,
        duration: const Duration(milliseconds: 320),
        curve: kSmoothCurve,
      );
    });
  }

  Future<void> _togglePlay() async {
    final status = _ttsState.status;
    switch (status) {
      case TtsPlaybackStatus.playing:
        await _tts.pause();
      case TtsPlaybackStatus.paused:
        await _tts.resume();
      case TtsPlaybackStatus.preparing:
        // 启动窗口期也能挂起暂停（开读即停）
        await _tts.pause();
      case TtsPlaybackStatus.idle:
        // 有上次会话（同本书）就从停下的句子继续；否则提示去书里开始
        if (_tts.canRestart && _tts.lastBookId == widget.bookId) {
          await _tts.restart();
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('先在书籍里开始朗读，再来听书页控制')));
        }
    }
  }

  /// 底栏「语速」：0.1 步进滑杆（拖动即时生效并保存）。
  Future<void> _showSpeedSheet(ReadingTheme theme) {
    return showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: kSmoothSheetAnimation,
      backgroundColor: theme.chromeSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => Consumer(
        builder: (context, sheetRef, _) {
          final rate = sheetRef.watch(ttsSettingsControllerProvider).rate;
          final fg = theme.chromeForeground;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '语速',
                    style: TextStyle(
                      color: fg,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 56,
                        child: Text('倍速', style: TextStyle(color: fg)),
                      ),
                      Expanded(
                        child: Slider(
                          key: const ValueKey('tts-page-rate'),
                          value: rate,
                          min: 0.5,
                          max: 2.0,
                          divisions: 15,
                          label: '${rate.toStringAsFixed(1)}×',
                          activeColor: theme.accent,
                          onChanged: (v) => sheetRef
                              .read(ttsPlaybackProvider.notifier)
                              .updateRate(v),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          '${rate.toStringAsFixed(1)}×',
                          textAlign: TextAlign.right,
                          style: TextStyle(color: fg),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '0.1 步进；MiMo 云端当前句即时变速。',
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.45),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _bgmDisplayName(String? bgmId) {
    if (bgmId == null) return '音乐';
    final track = findAudioTrack(
      allAudioTracks(ref.read(audioLibraryControllerProvider)),
      bgmId,
    );
    return track?.name ?? '音乐';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(readingSettingsControllerProvider).theme;
    final settings = ref.watch(ttsSettingsControllerProvider);
    final tts = ref.watch(ttsPlaybackProvider);
    final bookTitle = tts.bookTitle ?? '听书';

    // 当前句变化 → 滚动文稿
    ref.listen(ttsPlaybackProvider, (prev, next) {
      _scheduleAutoScroll(next.index);
    });

    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              bookTitle: bookTitle,
              theme: theme,
              canBackToBook: tts.bookId != null,
              onBackToBook: _backToBook,
            ),
            Expanded(
              child: _ManuscriptView(
                tts: tts,
                theme: theme,
                keys: _sentenceKeys,
              ),
            ),
            _Deck(
              tts: tts,
              theme: theme,
              voiceName: settings.voiceName ?? '音色',
              bgmName: _bgmDisplayName(settings.bgmId),
              onBackToBook: _backToBook,
              onOpenSpeed: () => unawaited(_showSpeedSheet(theme)),
              onOpenVoice: () =>
                  unawaited(showVoicePickerSheet(context, theme: theme)),
              onOpenSettings: () =>
                  unawaited(showTtsSettingsSheet(context, theme)),
              onTogglePlay: _togglePlay,
            ),
          ],
        ),
      ),
    );
  }
}

/// 页头：收起 + 书名 + 回到书籍。
class _Header extends StatelessWidget {
  const _Header({
    required this.bookTitle,
    required this.theme,
    required this.canBackToBook,
    required this.onBackToBook,
  });

  final String bookTitle;
  final ReadingTheme theme;
  final bool canBackToBook;
  final VoidCallback onBackToBook;

  @override
  Widget build(BuildContext context) {
    final fg = theme.chromeForeground;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: '收起',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: fg, size: 28),
          ),
          Expanded(
            child: Text(
              bookTitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (canBackToBook)
            IconButton(
              key: const ValueKey('tts-page-back-to-book'),
              tooltip: '回到书籍',
              onPressed: onBackToBook,
              icon: Icon(Icons.menu_book_outlined, color: theme.accent),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

/// 文稿视图：整章句子随朗读滚动，当前句高亮（accent 下划线），点句跳转。
class _ManuscriptView extends ConsumerWidget {
  const _ManuscriptView({
    required this.tts,
    required this.theme,
    required this.keys,
  });

  final TtsPlaybackState tts;
  final ReadingTheme theme;
  final List<GlobalKey> keys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fg = theme.chromeForeground;
    if (tts.sentences.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.graphic_eq_rounded,
              size: 44,
              color: fg.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              tts.error ?? '点下方播放键开始听书',
              textAlign: TextAlign.center,
              style: TextStyle(color: fg.withValues(alpha: 0.5), fontSize: 14),
            ),
          ],
        ),
      );
    }

    final current = tts.status == TtsPlaybackStatus.idle ? -1 : tts.index;
    // 按需生长句子 key
    while (keys.length < tts.sentences.length) {
      keys.add(GlobalKey());
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      itemCount: tts.sentences.length,
      itemBuilder: (context, i) {
        final isCurrent = i == current;
        final isPast = i < current;
        final TextStyle style;
        if (isCurrent) {
          style = TextStyle(
            color: fg,
            fontSize: 18,
            height: 1.7,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: theme.accent,
            decorationThickness: 2,
          );
        } else {
          style = TextStyle(
            color: fg.withValues(alpha: isPast ? 0.32 : 0.78),
            fontSize: 18,
            height: 1.7,
          );
        }
        return Padding(
          key: keys.length > i ? keys[i] : null,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => ref.read(ttsPlaybackProvider.notifier).goToSentence(i),
            child: Text(tts.sentences[i], style: style),
          ),
        );
      },
    );
  }
}

/// 底部功能行 + 进度滑杆 + 运输排。
class _Deck extends ConsumerWidget {
  const _Deck({
    required this.tts,
    required this.theme,
    required this.voiceName,
    required this.bgmName,
    required this.onBackToBook,
    required this.onOpenSpeed,
    required this.onOpenVoice,
    required this.onOpenSettings,
    required this.onTogglePlay,
  });

  final TtsPlaybackState tts;
  final ReadingTheme theme;
  final String voiceName;
  final String bgmName;
  final VoidCallback onBackToBook;
  final VoidCallback onOpenSpeed;
  final VoidCallback onOpenVoice;
  final VoidCallback onOpenSettings;
  final VoidCallback onTogglePlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fg = theme.chromeForeground;
    final playing = tts.status == TtsPlaybackStatus.playing;
    final preparing = tts.status == TtsPlaybackStatus.preparing;
    final active = tts.active;
    final total = tts.total;
    final sliderMax = total > 1 ? (total - 1).toDouble() : 1.0;
    final sliderValue = total > 0
        ? tts.index.clamp(0, total - 1).toDouble()
        : 0.0;
    final rate = ref.watch(ttsSettingsControllerProvider).rate;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: theme.chromeSurface.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 功能行：原文 / 语速 / 音色 / 音乐 / 设置
          Row(
            children: [
              _DeckSlot(
                icon: Icons.menu_book_outlined,
                label: '原文',
                fg: fg,
                onTap: onBackToBook,
              ),
              _DeckSlot(
                customIcon: Text(
                  '${rate.toStringAsFixed(1)}x',
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                label: '语速',
                fg: fg,
                onTap: onOpenSpeed,
              ),
              _DeckSlot(
                icon: Icons.record_voice_over_outlined,
                label: voiceName,
                fg: fg,
                onTap: onOpenVoice,
              ),
              _DeckSlot(
                icon: Icons.music_note_outlined,
                label: bgmName,
                fg: fg,
                onTap: onOpenSettings,
              ),
              _DeckSlot(
                icon: Icons.settings_outlined,
                label: '设置',
                fg: fg,
                onTap: onOpenSettings,
              ),
            ],
          ),
          // 进度滑杆：上一句 / 全章句进度 / 下一句
          Row(
            children: [
              IconButton(
                key: const ValueKey('tts-page-prev'),
                tooltip: '上一句',
                onPressed: active
                    ? () => ref
                          .read(ttsPlaybackProvider.notifier)
                          .previousSentence()
                    : null,
                icon: Icon(Icons.rotate_left_rounded, color: fg, size: 26),
              ),
              Expanded(
                child: Slider(
                  key: const ValueKey('tts-page-slider'),
                  value: sliderValue,
                  min: 0,
                  max: sliderMax,
                  label: total > 0 ? '${tts.index + 1}/$total 句' : null,
                  activeColor: theme.accent,
                  onChanged: active && total > 0
                      ? (v) => ref
                            .read(ttsPlaybackProvider.notifier)
                            .goToSentence(v.round())
                      : null,
                ),
              ),
              IconButton(
                key: const ValueKey('tts-page-next'),
                tooltip: '下一句',
                onPressed: active
                    ? () =>
                          ref.read(ttsPlaybackProvider.notifier).nextSentence()
                    : null,
                icon: Icon(Icons.rotate_right_rounded, color: fg, size: 26),
              ),
            ],
          ),
          // 运输排：停止 / 播放暂停 / 定时（设置面板）
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const ValueKey('tts-page-stop'),
                tooltip: '停止',
                onPressed: active
                    ? () => ref.read(ttsPlaybackProvider.notifier).stop()
                    : null,
                icon: Icon(Icons.stop_rounded, color: fg, size: 32),
              ),
              const SizedBox(width: 24),
              GestureDetector(
                key: const ValueKey('tts-page-play'),
                onTap: onTogglePlay,
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: theme.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    preparing
                        ? Icons.hourglass_top_rounded
                        : (playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              IconButton(
                key: const ValueKey('tts-page-timer'),
                tooltip: '定时 / 设置',
                onPressed: onOpenSettings,
                icon: Icon(Icons.alarm_rounded, color: fg, size: 28),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一个功能位：图标（或自定义内容）+ 标签。
class _DeckSlot extends StatelessWidget {
  const _DeckSlot({
    required this.label,
    required this.fg,
    required this.onTap,
    this.icon,
    this.customIcon,
  });

  final String label;
  final Color fg;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? customIcon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 24,
                child: customIcon ?? Icon(icon, color: fg, size: 24),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg.withValues(alpha: 0.75),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
