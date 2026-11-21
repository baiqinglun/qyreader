/// 首页：阅读概览（累计阅读 / 继续阅读 / 今日目标 / 今年读完的书）。
///
/// 每个区块都是一张白底大圆角卡片；数据来自书架流 + 统计仓储，不额外
/// 建表。页面常驻在 `IndexedStack` 里，切回首页时重新拉一次统计。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme/layout.dart';
import '../../app/theme/motion.dart';
import '../../core/stats_revision.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../domain/entities/book.dart';
import '../../domain/entities/reading_stats.dart';
import '../shelf/shelf_controller.dart';
import 'recommendations_card.dart';
import 'home_prefs.dart';
import 'home_stats.dart';
import 'home_tabs.dart';
import 'widgets/cover_thumb.dart';
import 'year_finished_page.dart';

/// 首页。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({this.active = true, this.onSelectTab, super.key});

  /// 当前是否选中「首页」Tab（切回来时重新加载统计）。
  final bool active;

  /// 切换底栏 Tab（去统计 / 去书架）。
  final ValueChanged<HomeTab>? onSelectTab;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  ReadingStats? _stats;
  int _yearlyGoal = HomePrefs.defaultYearlyGoal;
  bool _loading = false;
  String? _error;
  List<String> _cardOrder = List.of(HomePrefs.defaultCards);
  Set<String> _hiddenCards = {};
  static const _cardLabels = {
    'overview': '累计阅读',
    'continue': '继续阅读',
    'recommendations': '书籍推荐',
    'today': '今日目标',
    'year': '今年读完的书',
  };

  Future<void> _loadCards() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(HomePrefs.cardsKey) ?? [];
    if (!mounted) return;
    setState(() {
      _cardOrder = [
        ...saved.where(HomePrefs.defaultCards.contains).toSet(),
        ...HomePrefs.defaultCards.where((id) => !saved.contains(id)),
      ];
      _hiddenCards = (prefs.getStringList(HomePrefs.hiddenCardsKey) ?? [])
          .toSet();
    });
  }

  Future<void> _editCards() async {
    final order = List<String>.of(_cardOrder);
    final hidden = Set<String>.of(_hiddenCards);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('首页卡片'),
          content: SizedBox(
            width: 400,
            height: 380,
            child: ReorderableListView.builder(
              itemCount: order.length,
              onReorder: (oldIndex, newIndex) => update(() {
                if (newIndex > oldIndex) newIndex--;
                order.insert(newIndex, order.removeAt(oldIndex));
              }),
              itemBuilder: (context, index) {
                final id = order[index];
                return SwitchListTile(
                  key: ValueKey(id),
                  title: Text(_cardLabels[id]!),
                  value: !hidden.contains(id),
                  onChanged: (enabled) => update(() {
                    if (enabled) {
                      hidden.remove(id);
                    } else {
                      hidden.add(id);
                    }
                  }),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (save != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(HomePrefs.cardsKey, order);
    await prefs.setStringList(HomePrefs.hiddenCardsKey, hidden.toList());
    if (mounted) {
      setState(() {
        _cardOrder = order;
        _hiddenCards = hidden;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_loadCards());
    // 统计有写入（会话落库 / 同步合并）就重拉——本 Tab 可见时数字即时跟上
    statsRevision.addListener(_onStatsRevision);
  }

  void _onStatsRevision() {
    if (widget.active && mounted) unawaited(_load());
  }

  @override
  void dispose() {
    statsRevision.removeListener(_onStatsRevision);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 从别的 Tab 切回来：阅读时长/进度可能已经变了，重新拉一次。
    if (widget.active && !oldWidget.active) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final repo = await ref.read(statsRepositoryProvider.future);
      final overview = await repo.overview();
      final yearlyGoal = await HomePrefs.loadYearlyGoal();
      if (!mounted) return;
      setState(() {
        _stats = overview;
        _yearlyGoal = yearlyGoal;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final hadData = _stats != null;
      setState(() {
        _error = '$e';
        _loading = false;
      });
      if (hadData) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('首页数据刷新失败：$e')));
      }
    }
  }

  void _openTab(HomeTab tab) => widget.onSelectTab?.call(tab);

  Future<void> _openBook(ShelfItem item) async {
    await context.push(readerPath(item.book.id));
    if (mounted) await _load();
  }

  /// 打开「今年读完的书」完整列表页。
  Future<void> _openYearFinished(List<ShelfItem> books) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => YearFinishedPage(
          books: books,
          onOpen: (item) => unawaited(_openBook(item)),
        ),
      ),
    );
  }

  /// 「开始阅读」：优先接着最近在读的那本，否则打开最近打开 / 最近入库的书。
  Future<void> _startReading(
    List<ShelfItem> inProgress,
    List<ShelfItem> all,
  ) async {
    final target = inProgress.isNotEmpty ? inProgress.first : _mostRecent(all);
    if (target == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('书架还是空的，先去书架导入一本书吧')));
      _openTab(HomeTab.shelf);
      return;
    }
    await _openBook(target);
  }

  ShelfItem? _mostRecent(List<ShelfItem> items) {
    final opened = <ShelfItem>[
      for (final item in items)
        if (item.book.lastOpenedAt != null) item,
    ]..sort((a, b) => b.book.lastOpenedAt!.compareTo(a.book.lastOpenedAt!));
    if (opened.isNotEmpty) return opened.first;
    return items.isEmpty ? null : items.first;
  }

  /// 改每日目标（与统计页同一份数据）。
  Future<void> _editDailyGoal() async {
    final current = _stats?.dailyGoalMinutes ?? 30;
    var value = '$current';
    final result = await showDialog<int>(
      context: context,
      animationStyle: kSmoothSheetAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('今日阅读目标'),
        content: TextFormField(
          initialValue: value,
          keyboardType: TextInputType.number,
          onChanged: (text) => value = text,
          decoration: const InputDecoration(
            suffixText: '分钟',
            helperText: '填 0 表示不设目标',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(int.tryParse(value.trim())),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final repo = await ref.read(statsRepositoryProvider.future);
    await repo.setDailyGoalMinutes(result);
    await _load();
  }

  /// 改年度目标（首页自己的展示偏好）。
  Future<void> _editYearlyGoal() async {
    var value = '$_yearlyGoal';
    final result = await showDialog<int>(
      context: context,
      animationStyle: kSmoothSheetAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('年度阅读目标'),
        content: TextFormField(
          initialValue: value,
          keyboardType: TextInputType.number,
          onChanged: (text) => value = text,
          decoration: const InputDecoration(
            suffixText: '本',
            helperText: '今年计划读完多少本书',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(int.tryParse(value.trim())),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await HomePrefs.saveYearlyGoal(result);
    if (!mounted) return;
    setState(() => _yearlyGoal = result.clamp(1, 999));
  }

  @override
  Widget build(BuildContext context) {
    final items =
        ref.watch(shelfItemsProvider).valueOrNull ?? const <ShelfItem>[];
    final stats = _stats;
    final theme = Theme.of(context);
    final continueReading = continueReadingItems(items);
    final finished = finishedBooks(items);
    final thisYear = finishedThisYear(items);

    return Scaffold(
      appBar: AppBar(
        title: const Text('首页'),
        actions: [
          IconButton(
            key: const ValueKey('home-refresh'),
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          PopupMenuButton<_HomeMenu>(
            key: const ValueKey('home-more'),
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz),
            onSelected: (value) {
              if (value == _HomeMenu.cards) {
                unawaited(_editCards());
              } else if (value == _HomeMenu.dailyGoal) {
                unawaited(_editDailyGoal());
              } else {
                unawaited(_editYearlyGoal());
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: _HomeMenu.cards, child: Text('管理首页卡片')),
              PopupMenuItem(value: _HomeMenu.dailyGoal, child: Text('设置今日目标')),
              PopupMenuItem(value: _HomeMenu.yearlyGoal, child: Text('设置年度目标')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: stats == null
          ? (_error == null
                ? Center(
                    child: CircularProgressIndicator(
                      color: theme.colorScheme.primary,
                    ),
                  )
                : _ErrorView(error: _error!, onRetry: _load))
          : RefreshIndicator(
              onRefresh: _load,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
                  child: ListView(
                    key: const PageStorageKey('home-scroll'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    children: [
                      for (final id in _cardOrder)
                        if (!_hiddenCards.contains(id)) ...[
                          switch (id) {
                            'overview' => _OverviewCard(
                              stats: stats,
                              finishedCount: finished.length,
                              onTap: () => _openTab(HomeTab.stats),
                            ),
                            'continue' => _ContinueCard(
                              items: continueReading,
                              onOpen: (item) => unawaited(_openBook(item)),
                              onViewAll: () => _openTab(HomeTab.shelf),
                            ),
                            'recommendations' => const RecommendationsCard(),
                            'today' => _TodayGoalCard(
                              stats: stats,
                              onOpenStats: () => _openTab(HomeTab.stats),
                              onEditGoal: () => unawaited(_editDailyGoal()),
                              onStart: () => unawaited(
                                _startReading(continueReading, items),
                              ),
                            ),
                            'year' => _YearFinishedCard(
                              books: thisYear,
                              goal: _yearlyGoal,
                              onOpen: (item) => unawaited(_openBook(item)),
                              onOpenAll: () =>
                                  unawaited(_openYearFinished(thisYear)),
                              onEditGoal: () => unawaited(_editYearlyGoal()),
                              onOpenStats: () => _openTab(HomeTab.stats),
                            ),
                            _ => const SizedBox.shrink(),
                          },
                          const SizedBox(height: 18),
                        ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// 首页右上角「⋯」菜单项。
enum _HomeMenu { cards, dailyGoal, yearlyGoal }

// ---------------------------------------------------------------------------
// 卡片
// ---------------------------------------------------------------------------

/// 卡片底色：亮色纯白、暗色低层 surface（与书架 / 统计同款）。
Color _cardColor(ThemeData theme) => theme.brightness == Brightness.dark
    ? theme.colorScheme.surfaceContainerLow
    : Colors.white;

/// 累计阅读：头像 + 累计时长 + 已读完本数，点一下去统计页。
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.stats,
    required this.finishedCount,
    required this.onTap,
  });

  final ReadingStats stats;
  final int finishedCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    return PressableScale(
      onTap: onTap,
      child: Container(
        key: const ValueKey('home-overview-card'),
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: _cardColor(theme),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            _ReadingAvatar(scheme: scheme),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '累计阅读',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatTotalReadingDuration(stats.totalDurationMs)} · '
                    '$finishedCount 本',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 13.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: muted.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}

/// 累计阅读左侧的圆形头像（没有用户头像，用品牌渐变 + 书图标）。
class _ReadingAvatar extends StatelessWidget {
  const _ReadingAvatar({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, Colors.black, 0.28) ?? scheme.primary,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: const Icon(
        Icons.auto_stories_rounded,
        color: Colors.white,
        size: 26,
      ),
    );
  }
}

/// 继续阅读：横向卡片流（封面 + 书名 + 作者 + 进度）。
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.items,
    required this.onOpen,
    required this.onViewAll,
  });

  final List<ShelfItem> items;
  final ValueChanged<ShelfItem> onOpen;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const ValueKey('home-continue-card'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _cardColor(theme),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onViewAll,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '继续阅读',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const _EmptyRow(icon: Icons.auto_stories_outlined, text: '还没有正在读的书')
          else
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _ContinueTile(
                  item: items[i],
                  onTap: () => onOpen(items[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 继续阅读里的一本书（宽卡：封面 + 信息）。
class _ContinueTile extends StatelessWidget {
  const _ContinueTile({required this.item, required this.onTap});

  final ShelfItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final book = item.book;
    final author = book.author?.trim() ?? '';
    return PressableScale(
      onTap: onTap,
      child: SizedBox(
        width: 252,
        child: Row(
          children: [
            CoverThumb(
              path: book.coverPath,
              width: 68,
              height: 100,
              radius: 10,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 14,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    author.isEmpty ? '未知作者' : author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatPercent(item.percent),
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 今日目标：大圆弧进度 + 今日计时 + 开始阅读。
class _TodayGoalCard extends StatelessWidget {
  const _TodayGoalCard({
    required this.stats,
    required this.onOpenStats,
    required this.onEditGoal,
    required this.onStart,
  });

  final ReadingStats stats;
  final VoidCallback onOpenStats;
  final VoidCallback onEditGoal;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final goal = stats.dailyGoalMinutes;
    final goalText = goal <= 0 ? '（未设目标）' : '（目标 $goal 分钟）';
    return Container(
      key: const ValueKey('home-goal-card'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      decoration: BoxDecoration(
        color: _cardColor(theme),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '今日目标',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '查看统计',
                visualDensity: VisualDensity.compact,
                onPressed: onOpenStats,
                icon: Icon(
                  Icons.calendar_month_outlined,
                  size: 21,
                  color: scheme.onSurface,
                ),
              ),
              IconButton(
                tooltip: '调整目标',
                visualDensity: VisualDensity.compact,
                onPressed: onEditGoal,
                icon: Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          // 圆弧必须按正方形画：宽高不等会把半圆拉扁成椭圆。
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300, maxHeight: 300),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _GoalArcPainter(
                          progress: stats.todayGoalProgress,
                          trackColor: scheme.onSurface.withValues(alpha: 0.08),
                          progressColor: scheme.primary,
                          strokeWidth: 10,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '今日阅读进度',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          formatReadingClock(stats.todayDurationMs),
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 42,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: onEditGoal,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  goalText,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 13,
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 宽屏上按钮不跟着卡片拉满，居中保持 CTA 的正常比例。
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  key: const ValueKey('home-start-reading'),
                  onPressed: onStart,
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.onSurface,
                    foregroundColor: scheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('开始阅读'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 半圆弧进度（从左下经顶部到右下，共 240°）。
class _GoalArcPainter extends CustomPainter {
  const _GoalArcPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  /// 0..1。
  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  /// 起始角 150°（左下）。
  static const double _start = 150 * math.pi / 180;

  /// 扫过 240°（顶部到右下）。
  static const double _sweep = 240 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(rect, _start, _sweep, false, track);
    final value = progress.clamp(0.0, 1.0);
    if (value <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = progressColor;
    canvas.drawArc(rect, _start, _sweep * value, false, arc);
  }

  @override
  bool shouldRepaint(covariant _GoalArcPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// 今年读完的书：本年度已读完册数 / 年度目标 + 封面流。
class _YearFinishedCard extends StatelessWidget {
  const _YearFinishedCard({
    required this.books,
    required this.goal,
    required this.onOpen,
    required this.onOpenAll,
    required this.onEditGoal,
    required this.onOpenStats,
  });

  final List<ShelfItem> books;
  final int goal;
  final ValueChanged<ShelfItem> onOpen;
  final VoidCallback onOpenAll;
  final VoidCallback onEditGoal;
  final VoidCallback onOpenStats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const ValueKey('home-year-card'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: _cardColor(theme),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '今年读完的书',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                key: const ValueKey('home-year-goal'),
                onTap: onEditGoal,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    '${books.length} / $goal',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '查看年度统计',
                visualDensity: VisualDensity.compact,
                onPressed: onOpenStats,
                icon: Icon(
                  Icons.bar_chart_rounded,
                  size: 21,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (books.isEmpty)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: _EmptyRow(
                icon: Icons.emoji_events_outlined,
                text: '今年还没有读完的书',
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const coverWidth = 82.0;
                const gap = 10.0;
                final columns = math.max(
                  1,
                  ((constraints.maxWidth + gap) / (coverWidth + gap)).floor(),
                );
                // 默认最多三行，其余进「查看更多」页面。
                final maxCount = columns * 3;
                final shown = books.take(maxCount).toList(growable: false);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Wrap 会收缩到内容宽度，alignment.center 随之失效；
                    // 必须撑满卡片内宽，封面行（含不足整行的末行）才居中。
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: gap,
                        runSpacing: gap,
                        children: <Widget>[
                          for (final item in shown)
                            PressableScale(
                              onTap: () => onOpen(item),
                              child: CoverThumb(
                                path: item.book.coverPath,
                                width: coverWidth,
                                height: 122,
                                radius: 10,
                                shadow: true,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (books.length > maxCount)
                      Center(
                        child: TextButton(
                          key: const ValueKey('home-year-more'),
                          onPressed: onOpenAll,
                          child: const Text('查看更多'),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 通用小部件
// ---------------------------------------------------------------------------

/// 卡片里的空态行。
class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 64,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// 统计加载失败的重试视图（首页其它数据仍然可用）。
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: scheme.outline),
            const SizedBox(height: 10),
            Text(
              '首页数据加载失败',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
