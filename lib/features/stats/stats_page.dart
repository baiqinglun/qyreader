/// 统计页：日/周/月/年切换 + 周期汇总 + 时长分布 + 阅读内容明细。
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/motion.dart';
import '../../../domain/entities/reading_stats.dart';
import 'widgets/stats_period_header.dart';

/// 统计页。
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  ReadingStats? _overview;
  PeriodReadingStats? _period;
  StatsPeriod _granularity = StatsPeriod.day;
  DateTime _anchor = DateTime.now();
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final repo = await ref.read(statsRepositoryProvider.future);
      final overview = await repo.overview();
      final period = await repo.periodStats(_granularity, _anchor);
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _period = period;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _switchGranularity(StatsPeriod period) {
    if (period == _granularity) return;
    setState(() => _granularity = period);
    _load();
  }

  DateTime _shift(DateTime anchor, StatsPeriod period, int direction) {
    switch (period) {
      case StatsPeriod.day:
        return anchor.add(Duration(days: direction));
      case StatsPeriod.week:
        return anchor.add(Duration(days: 7 * direction));
      case StatsPeriod.month:
        return DateTime(anchor.year, anchor.month + direction, 1);
      case StatsPeriod.year:
        return DateTime(anchor.year + direction, 1, 1);
    }
  }

  void _movePeriod(int direction) {
    setState(() => _anchor = _shift(_anchor, _granularity, direction));
    _load();
  }

  void _goToday() {
    setState(() => _anchor = DateTime.now());
    _load();
  }

  /// 点击标题选日期：选中后跳到那一天（周/月/年按所在周期统计）。
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _anchor.isAfter(now) ? now : _anchor;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: '跳到日期',
    );
    if (picked == null || !mounted) return;
    setState(() => _anchor = picked);
    await _load();
  }

  bool _isToday(DateTime t) {
    final now = DateTime.now();
    return t.year == now.year && t.month == now.month && t.day == now.day;
  }

  Future<void> _editGoal() async {
    final current = _overview?.dailyGoalMinutes ?? 30;
    // 不用控制器：对话框退场动画期间还可能用到它。
    var value = '$current';
    final result = await showDialog<int>(
      context: context,
      animationStyle: kSmoothSheetAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('每日阅读目标'),
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
            onPressed: () {
              Navigator.of(ctx).pop(int.tryParse(value.trim()));
            },
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

  @override
  Widget build(BuildContext context) {
    final palette = _StatsPalette.of(context);
    final fg = palette.chromeForeground;
    final stats = _overview;
    final period = _period;

    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读统计'),
        actions: [
          IconButton(
            tooltip: '设置目标',
            onPressed: stats == null ? null : _editGoal,
            icon: const Icon(Icons.flag_outlined),
          ),
          const SizedBox(width: 4),
        ],
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: _error != null
          ? Center(
              child: Text('统计加载失败：$_error', style: TextStyle(color: fg)),
            )
          : stats == null || period == null
              ? Center(
                  child: CircularProgressIndicator(color: palette.accent),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _PeriodTabs(
                      selected: _granularity,
                      theme: palette,
                      onChanged: _switchGranularity,
                    ),
                    const SizedBox(height: 12),
                    StatsPeriodHeader(
                      period: period,
                      foreground: palette.chromeForeground,
                      accent: palette.accent,
                      onPrev: () => _movePeriod(-1),
                      onNext: period.canGoNext ? () => _movePeriod(1) : null,
                      onToday: period.canGoNext ? _goToday : null,
                      onPickDate: _pickDate,
                    ),
                    if (_granularity == StatsPeriod.day && _isToday(_anchor)) ...[
                      const SizedBox(height: 8),
                      _GoalCard(
                        stats: stats,
                        theme: palette,
                        onEdit: _editGoal,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _PeriodSummary(period: period, theme: palette),
                    const SizedBox(height: 20),
                    _SectionTitle(text: '时长分布', theme: palette),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 190,
                      child: period.hasData
                          ? _BucketChart(period: period, theme: palette)
                          : _EmptyChart(theme: palette),
                    ),
                    const SizedBox(height: 20),
                    _SectionTitle(text: '今年读过的书', theme: palette),
                    const SizedBox(height: 8),
                    _YearBooksCard(theme: palette),
                    const SizedBox(height: 20),
                    _SectionTitle(text: '阅读内容', theme: palette),
                    const SizedBox(height: 8),
                    _ReadingContentList(
                      books: period.books,
                      theme: palette,
                      onOpen: (bookId) async {
                        await context.push(readerPath(bookId));
                        if (mounted) await _load();
                      },
                    ),
                    const SizedBox(height: 20),
                    _CumulativeRow(stats: stats, theme: palette),
                    const SizedBox(height: 10),
                    Text(
                      '统计口径：周期来自阅读会话明细（前台时长）；'
                      '字数按翻页进度增量 × 全书字数估算',
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.45),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
    );
  }
}

/// 日/周/月/年切换。
class _PeriodTabs extends StatelessWidget {
  const _PeriodTabs({
    required this.selected,
    required this.theme,
    required this.onChanged,
  });

  final StatsPeriod selected;
  final _StatsPalette theme;
  final ValueChanged<StatsPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final fg = theme.chromeForeground;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        // 和其他页面的「分段胶囊」同款：浅色轨道 + 实心药丸。
        color: fg.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          for (final period in StatsPeriod.values)
            Expanded(
              child: Semantics(
                selected: period == selected,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onChanged(period),
                  child: AnimatedContainer(
                    duration: context.motion.quick,
                    curve: kSmoothCurve,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: period == selected
                          ? theme.chromeSurface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: period == selected
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      period.label,
                      style: TextStyle(
                        color: period == selected
                            ? theme.accent
                            : fg.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: period == selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 周期汇总卡片。
class _PeriodSummary extends StatelessWidget {
  const _PeriodSummary({required this.period, required this.theme});

  final PeriodReadingStats period;
  final _StatsPalette theme;

  @override
  Widget build(BuildContext context) {
    final avgMinutes = period.sessions <= 0
        ? 0
        : (period.durationMs / period.sessions / 60000).round();
    final topBook = period.books.isEmpty ? '暂无' : period.books.first.title;
    final items = <(String, String, String)>[
      (
        '阅读时长',
        _humanDuration(period.durationMs),
        '共 ${period.sessions} 段会话',
      ),
      (
        '阅读字数',
        _humanChars(period.charsRead),
        '${period.charsPerMinute.round()} 字/分',
      ),
      (
        '阅读书籍',
        '${period.books.length} 本',
        topBook,
      ),
      (
        '平均每次',
        '$avgMinutes 分钟',
        '单段会话',
      ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.9,
      children: [
        for (final (label, value, hint) in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: theme.chromeSurface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: theme.chromeForeground.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.chromeForeground,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.chromeForeground.withValues(alpha: 0.45),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 时长分布柱状图（桶由周期决定）。
class _BucketChart extends StatelessWidget {
  const _BucketChart({required this.period, required this.theme});

  final PeriodReadingStats period;
  final _StatsPalette theme;

  @override
  Widget build(BuildContext context) {
    final buckets = period.buckets;
    final fg = theme.chromeForeground;
    final maxMinutes = buckets
        .map((b) => b.minutes)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final labelStep = switch (period.period) {
      StatsPeriod.day => 3,
      StatsPeriod.week => 1,
      StatsPeriod.month => 5,
      StatsPeriod.year => 2,
    };
    return BarChart(
      BarChartData(
        maxY: (maxMinutes * 1.25).clamp(10, 100000).toDouble(),
        minY: 0,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxMinutes * 1.25 / 4).clamp(1, 100000),
          getDrawingHorizontalLine: (_) => FlLine(
            color: fg.withValues(alpha: 0.08),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= buckets.length) {
                  return const SizedBox.shrink();
                }
                if (i % labelStep != 0 && i != buckets.length - 1) {
                  return const SizedBox.shrink();
                }
                return Text(
                  buckets[i].label,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.5),
                    fontSize: 9,
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final bucket = buckets[group.x.toInt()];
              final label = period.period == StatsPeriod.day
                  ? '${bucket.label}:00'
                  : bucket.label;
              return BarTooltipItem(
                '$label\n${bucket.minutes} 分钟',
                TextStyle(color: fg, fontSize: 12),
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < buckets.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: buckets[i].minutes.toDouble(),
                  width: buckets.length > 20 ? 6 : 10,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
                  ),
                  color: buckets[i].minutes > 0
                      ? theme.accent
                      : fg.withValues(alpha: 0.12),
                ),
              ],
            ),
        ],
      ),
      duration: context.motion.standard,
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart({required this.theme});

  final _StatsPalette theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.chromeSurface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '这个周期还没有阅读记录',
        style: TextStyle(
          color: theme.chromeForeground.withValues(alpha: 0.5),
          fontSize: 12,
        ),
      ),
    );
  }
}

/// 阅读内容（按书籍聚合的时长与字数）。
class _ReadingContentList extends StatelessWidget {
  const _ReadingContentList({
    required this.books,
    required this.theme,
    required this.onOpen,
  });

  final List<BookReadingStat> books;
  final _StatsPalette theme;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.chromeSurface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '暂无阅读内容',
          style: TextStyle(
            color: theme.chromeForeground.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
      );
    }
    final maxMs = books.first.durationMs <= 0 ? 1 : books.first.durationMs;
    final fg = theme.chromeForeground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: theme.chromeSurface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          for (var i = 0; i < books.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: fg.withValues(alpha: 0.08),
              ),
            InkWell(
              onTap: books[i].exists ? () => onOpen(books[i].bookId) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          size: 15,
                          color: theme.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            books[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: fg, fontSize: 13),
                          ),
                        ),
                        Text(
                          _humanDuration(books[i].durationMs),
                          style: TextStyle(
                            color: fg.withValues(alpha: 0.75),
                            fontSize: 12,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (books[i].exists)
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: fg.withValues(alpha: 0.35),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: (books[i].durationMs / maxMs).clamp(0.0, 1.0),
                        minHeight: 4,
                        color: theme.accent,
                        backgroundColor: fg.withValues(alpha: 0.08),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_humanChars(books[i].charsRead)} · '
                      '${books[i].sessions} 段会话',
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.45),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 累计数据（跨周期）。
class _CumulativeRow extends StatelessWidget {
  const _CumulativeRow({required this.stats, required this.theme});

  final ReadingStats stats;
  final _StatsPalette theme;

  @override
  Widget build(BuildContext context) {
    final fg = theme.chromeForeground;
    final items = <(String, String)>[
      ('累计时长', _humanDuration(stats.totalDurationMs)),
      ('累计字数', _humanChars(stats.totalChars)),
      ('连续阅读', '${stats.streakDays} 天'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: theme.chromeSurface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          for (final (label, value) in items)
            Expanded(
              child: Column(
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.5),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, required this.theme});

  final String text;
  final _StatsPalette theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: theme.chromeForeground.withValues(alpha: 0.7),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// 今日目标环。
class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.stats,
    required this.theme,
    required this.onEdit,
  });

  final ReadingStats stats;
  final _StatsPalette theme;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final fg = theme.chromeForeground;
    final progress = stats.todayGoalProgress;
    final todayMin = stats.todayDurationMs ~/ 60000;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.chromeSurface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 76,
                  height: 76,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 7,
                    backgroundColor: fg.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation(theme.accent),
                  ),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: TextStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '今日已读 $todayMin 分钟',
                  style: TextStyle(
                    color: fg,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  stats.dailyGoalMinutes <= 0
                      ? '未设置每日目标'
                      : '目标 ${stats.dailyGoalMinutes} 分钟 · '
                          '${stats.todayChars} 字',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: onEdit,
                  child: Text(
                    '调整目标',
                    style: TextStyle(
                      color: theme.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _humanDuration(int ms) {
  final h = ms ~/ 3600000;
  final m = (ms % 3600000) ~/ 60000;
  if (h > 0) return '$h 小时 $m 分';
  return '$m 分钟';
}

String _humanChars(int chars) {
  if (chars >= 10000) {
    return '${(chars / 10000).toStringAsFixed(1)} 万字';
  }
  return '$chars 字';
}

/// 「今年读过的书」卡片：按本年度的阅读时长排序，给一个年度回顾入口。
class _YearBooksCard extends ConsumerStatefulWidget {
  const _YearBooksCard({required this.theme});

  final _StatsPalette theme;

  @override
  ConsumerState<_YearBooksCard> createState() => _YearBooksCardState();
}

class _YearBooksCardState extends ConsumerState<_YearBooksCard> {
  PeriodReadingStats? _year;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = await ref.read(statsRepositoryProvider.future);
      final now = DateTime.now();
      final data = await repo.periodStats(StatsPeriod.year, DateTime(now.year));
      if (!mounted) return;
      setState(() {
        _year = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final year = DateTime.now().year;
    final books = _year?.books ?? const <BookReadingStat>[];
    return Card(
      elevation: 0,
      color: theme.chromeSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_stories, size: 18, color: theme.accent),
                const SizedBox(width: 8),
                Text(
                  '$year 年 · ${books.length} 本',
                  style: TextStyle(
                    color: theme.chromeForeground,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loading)
              SizedBox(
                height: 60,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.accent,
                    ),
                  ),
                ),
              )
            else if (books.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '今年还没有读完的记录',
                  style: TextStyle(
                    color: theme.chromeForeground.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              )
            else
              // 横向卡片流：一眼扫过今年读过的书
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: books.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => _YearBookChip(
                    book: books[i],
                    theme: theme,
                    onTap: () => context.push(readerPath(books[i].bookId)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 单本年度书籍卡片。
class _YearBookChip extends StatelessWidget {
  const _YearBookChip({
    required this.book,
    required this.theme,
    required this.onTap,
  });

  final BookReadingStat book;
  final _StatsPalette theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final minutes = (book.durationMs / 60000).round();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 156,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.chromeForeground,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              minutes >= 60
                  ? '${(minutes / 60).toStringAsFixed(1)} 小时 · ${book.sessions} 次'
                  : '$minutes 分钟 · ${book.sessions} 次',
              style: TextStyle(
                color: theme.chromeForeground.withValues(alpha: 0.55),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 统计页配色：映射到 App 的 Material 主题（书架 / 设置页同款），
/// 不再用阅读主题——否则统计页会是米色纸面，跟其他页面不是一套皮肤。
class _StatsPalette {
  const _StatsPalette({
    required this.background,
    required this.chromeSurface,
    required this.chromeForeground,
    required this.foreground,
    required this.accent,
  });

  factory _StatsPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return _StatsPalette(
      background: theme.scaffoldBackgroundColor,
      chromeSurface: dark ? scheme.surfaceContainerLow : Colors.white,
      chromeForeground: scheme.onSurface,
      foreground: scheme.onSurface,
      accent: scheme.primary,
    );
  }

  /// 页面底色（与其它页面一致；Scaffold 默认就用它）。
  final Color background;

  /// 卡片 / 面板底色。
  final Color chromeSurface;

  /// 卡片上的主文字色。
  final Color chromeForeground;

  /// 正文文字色。
  final Color foreground;

  /// 主题主色（图表 / 选中态）。
  final Color accent;
}