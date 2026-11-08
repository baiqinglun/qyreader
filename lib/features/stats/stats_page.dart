/// 统计页：今日目标环 + 汇总卡片 + 近 14 天柱状图。
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/motion.dart';
import '../../../app/theme/reading_theme.dart';
import '../../../domain/entities/reading_stats.dart';

/// 统计页。
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  ReadingStats? _stats;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = await ref.read(statsRepositoryProvider.future);
      final stats = await repo.overview();
      if (!mounted) return;
      setState(() => _stats = stats);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _editGoal() async {
    final current = _stats?.dailyGoalMinutes ?? 30;
    final controller = TextEditingController(text: '$current');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('每日阅读目标'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
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
              final v = int.tryParse(controller.text.trim());
              Navigator.of(ctx).pop(v);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    final repo = await ref.read(statsRepositoryProvider.future);
    await repo.setDailyGoalMinutes(result);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final reading = dark ? ReadingTheme.night : ReadingTheme.paper;
    final fg = reading.chromeForeground;
    final stats = _stats;

    return Scaffold(
      backgroundColor: reading.background,
      appBar: AppBar(
        backgroundColor: reading.chromeSurface,
        foregroundColor: fg,
        title: const Text('阅读统计'),
        actions: [
          IconButton(
            tooltip: '设置目标',
            onPressed: stats == null ? null : _editGoal,
            icon: const Icon(Icons.flag_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _error != null
          ? Center(
              child: Text(
                '统计加载失败：$_error',
                style: TextStyle(color: fg),
              ),
            )
          : stats == null
              ? Center(
                  child: CircularProgressIndicator(color: reading.accent),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _GoalCard(
                      stats: stats,
                      theme: reading,
                      onEdit: _editGoal,
                    ),
                    const SizedBox(height: 12),
                    _SummaryGrid(stats: stats, theme: reading),
                    const SizedBox(height: 20),
                    Text(
                      '近 14 天',
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 200,
                      child: _MinutesBarChart(stats: stats, theme: reading),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '统计口径：前台阅读时长；字数按翻页进度增量 × 全书字数估算',
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

/// 今日目标环。
class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.stats,
    required this.theme,
    required this.onEdit,
  });

  final ReadingStats stats;
  final ReadingTheme theme;
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
        borderRadius: BorderRadius.circular(14),
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

/// 汇总卡片网格。
class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.stats, required this.theme});

  final ReadingStats stats;
  final ReadingTheme theme;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String, String)>[
      (
        '累计时长',
        _humanDuration(stats.totalDurationMs),
        '阅读 ${stats.totalDays} 天',
      ),
      (
        '累计字数',
        _humanChars(stats.totalChars),
        '速度 ${stats.charsPerMinute.round()} 字/分',
      ),
      (
        '连续阅读',
        '${stats.streakDays} 天',
        stats.streakDays >= 3 ? '保持住' : '今天也读一会儿',
      ),
      (
        '今日字数',
        _humanChars(stats.todayChars),
        '今日 ${stats.todayDurationMs ~/ 60000} 分钟',
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
              borderRadius: BorderRadius.circular(12),
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

  static String _humanDuration(int ms) {
    final h = ms ~/ 3600000;
    final m = (ms % 3600000) ~/ 60000;
    if (h > 0) return '$h 小时 $m 分';
    return '$m 分钟';
  }

  static String _humanChars(int chars) {
    if (chars >= 10000) {
      return '${(chars / 10000).toStringAsFixed(1)} 万字';
    }
    return '$chars 字';
  }
}

/// 近 N 天分钟柱状图。
class _MinutesBarChart extends StatelessWidget {
  const _MinutesBarChart({required this.stats, required this.theme});

  final ReadingStats stats;
  final ReadingTheme theme;

  @override
  Widget build(BuildContext context) {
    final days = stats.recentDays;
    final maxMinutes = days
        .map((d) => d.minutes)
        .fold<int>(stats.dailyGoalMinutes, (a, b) => a > b ? a : b);
    final fg = theme.chromeForeground;
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
                if (i < 0 || i >= days.length) {
                  return const SizedBox.shrink();
                }
                // 只显示首/中/尾三个日期，避免拥挤
                if (i != 0 && i != days.length ~/ 2 && i != days.length - 1) {
                  return const SizedBox.shrink();
                }
                final day = days[i].day;
                return Text(
                  '${day.substring(5, 7)}/${day.substring(8, 10)}',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.5),
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final d = days[group.x.toInt()];
              return BarTooltipItem(
                '${d.day}\n${d.minutes} 分钟',
                TextStyle(color: fg, fontSize: 12),
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: days[i].minutes.toDouble(),
                  width: 10,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
                  ),
                  color: days[i].minutes > 0
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
