/// 书架设置底部弹窗：网格 / 列表两页。
///
/// 顶部是「分段胶囊」（浅色轨道 + 实心药丸，与排版面板同款）：
/// - 网格：封面圆角、单行数量、架板样式；
/// - 列表：星级 / 标签 / 简介（+行数）/ 书评（+行数）六个控件。
///
/// 所有偏好只落 shared_preferences（[ShelfPrefsController]），改动即时
/// 反映到弹窗后面的书架，关掉弹窗即完成。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/motion.dart';
import '../shelf_prefs.dart';

/// 弹出书架设置面板。
Future<void> showShelfSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: kSmoothSheetAnimation,
    // 拖拽条：明确「可下拉关闭」，也把标题区和系统导航隔开。
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const ShelfSettingsSheet(),
  );
}

/// 书架设置面板。
///
/// 顶部「网格 / 列表」页签同时是书架的展示形式开关：选中「列表」立即把书架
/// 切成列表，选中「网格」切回平铺（写入 `shelfViewModeControllerProvider`）。
class ShelfSettingsSheet extends ConsumerStatefulWidget {
  const ShelfSettingsSheet({super.key});

  @override
  ConsumerState<ShelfSettingsSheet> createState() => _ShelfSettingsSheetState();
}

class _ShelfSettingsSheetState extends ConsumerState<ShelfSettingsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  static int _indexOf(ShelfViewMode mode) => mode == ShelfViewMode.list ? 1 : 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: _indexOf(ref.read(shelfViewModeControllerProvider)),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// 选中页签 = 切换书架展示形式（点已选中的「网格」也能把封面模式切回网格）。
  void _selectMode(int index) {
    final mode = index == 1 ? ShelfViewMode.list : ShelfViewMode.grid;
    if (ref.read(shelfViewModeControllerProvider) != mode) {
      unawaited(ref.read(shelfViewModeControllerProvider.notifier).set(mode));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 书架模式若被别处改了（例如 prefs 恢复晚到），页签跟着走。
    ref.listen<ShelfViewMode>(shelfViewModeControllerProvider, (_, next) {
      final index = _indexOf(next);
      if (_tabs.index != index) _tabs.animateTo(index);
    });
    final prefs = ref.watch(shelfPrefsControllerProvider);
    final controller = ref.read(shelfPrefsControllerProvider.notifier);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = scheme.onSurface;
    final bg = scheme.surface;

    return SizedBox(
      height: 448,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Row(
                children: [
                  Icon(Icons.tune, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '书架设置',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            // 排序对所有展示形式生效，放在页签上方（网格/列表共用）。
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 12, 2),
              child: Row(
                children: [
                  Text(
                    '排序',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: fg.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<ShelfSortField>(
                        key: const ValueKey('shelf-sort-field'),
                        value: prefs.sortField,
                        isExpanded: true,
                        items: [
                          for (final field in ShelfSortField.values)
                            DropdownMenuItem<ShelfSortField>(
                              value: field,
                              child: Text(field.label),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          unawaited(controller.setSortField(value));
                        },
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('shelf-sort-direction'),
                    onPressed: () => unawaited(
                      controller.setSortAscending(!prefs.sortAscending),
                    ),
                    icon: Icon(
                      prefs.sortAscending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      size: 16,
                    ),
                    label: Text(prefs.sortAscending ? '升序' : '降序'),
                  ),
                ],
              ),
            ),
            // 分段胶囊：选中项是浮在浅色轨道上的实心药丸。
            Container(
              margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TabBar(
                controller: _tabs,
                onTap: _selectMode,
                labelColor: fg,
                unselectedLabelColor: fg.withValues(alpha: 0.55),
                indicator: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(fontSize: 12.5),
                labelPadding: EdgeInsets.zero,
                tabs: const [
                  Tab(text: '网格'),
                  Tab(text: '列表'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                // 只靠点页签切换：横向滑页会跟圆角滑杆抢手势。
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _tab(
                    children: [
                      _SliderRow(
                        sliderKey: const ValueKey('shelf-cover-radius'),
                        label: '封面圆角',
                        value: prefs.coverRadius.toDouble(),
                        min: 0,
                        max: ShelfPrefsController.maxCoverRadius.toDouble(),
                        divisions: ShelfPrefsController.maxCoverRadius,
                        display: '${prefs.coverRadius}',
                        onChanged: (value) =>
                            unawaited(controller.setCoverRadius(value.round())),
                      ),
                      _ChoiceRow<ShelfColumnCount>(
                        dropdownKey: const ValueKey('shelf-columns'),
                        label: '单行数量',
                        options: {
                          for (final option in ShelfColumnCount.values)
                            option: option.label,
                        },
                        selected: prefs.columns,
                        onSelect: (value) =>
                            unawaited(controller.setColumns(value)),
                      ),
                      _ChoiceRow<ShelfPlankStyle>(
                        dropdownKey: const ValueKey('shelf-plank-style'),
                        label: '架板样式',
                        options: {
                          for (final option in ShelfPlankStyle.values)
                            option: option.label,
                        },
                        selected: prefs.plankStyle,
                        onSelect: (value) =>
                            unawaited(controller.setPlankStyle(value)),
                      ),
                      _ToggleRow(
                        switchKey: const ValueKey('shelf-show-progress'),
                        label: '显示阅读进度',
                        value: prefs.showGridProgress,
                        onChanged: (value) =>
                            unawaited(controller.setShowGridProgress(value)),
                      ),
                    ],
                  ),
                  _tab(
                    children: [
                      _ToggleRow(
                        switchKey: const ValueKey('shelf-show-rating'),
                        label: '显示星级',
                        value: prefs.showRating,
                        onChanged: (value) =>
                            unawaited(controller.setShowRating(value)),
                      ),
                      _ToggleRow(
                        switchKey: const ValueKey('shelf-show-tags'),
                        label: '显示标签',
                        value: prefs.showTags,
                        onChanged: (value) =>
                            unawaited(controller.setShowTags(value)),
                      ),
                      _ToggleRow(
                        switchKey: const ValueKey('shelf-show-description'),
                        label: '显示简介',
                        value: prefs.showDescription,
                        onChanged: (value) =>
                            unawaited(controller.setShowDescription(value)),
                      ),
                      _SliderRow(
                        sliderKey: const ValueKey('shelf-description-lines'),
                        label: '简介行数',
                        value: prefs.descriptionLines.toDouble(),
                        min: 1,
                        max: ShelfPrefsController.maxTextLines.toDouble(),
                        divisions: ShelfPrefsController.maxTextLines - 1,
                        display: '${prefs.descriptionLines} 行',
                        onChanged: (value) => unawaited(
                          controller.setDescriptionLines(value.round()),
                        ),
                      ),
                      _ToggleRow(
                        switchKey: const ValueKey('shelf-show-review'),
                        label: '显示书评',
                        value: prefs.showReview,
                        onChanged: (value) =>
                            unawaited(controller.setShowReview(value)),
                      ),
                      _SliderRow(
                        sliderKey: const ValueKey('shelf-review-lines'),
                        label: '书评行数',
                        value: prefs.reviewLines.toDouble(),
                        min: 1,
                        max: ShelfPrefsController.maxTextLines.toDouble(),
                        divisions: ShelfPrefsController.maxTextLines - 1,
                        display: '${prefs.reviewLines} 行',
                        onChanged: (value) =>
                            unawaited(controller.setReviewLines(value.round())),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一个页签：整页可滚动，窄屏上六行也不会被裁掉。
  Widget _tab({required List<Widget> children}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: children,
    );
  }
}

/// 滑杆行：左标签 + 滑杆 + 右侧当前值。
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
    this.sliderKey,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;
  final Key? sliderKey;

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 13),
            ),
          ),
          Expanded(
            child: Slider(
              key: sliderKey,
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: display,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              display,
              textAlign: TextAlign.right,
              style: TextStyle(color: fg, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 开关行。
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.switchKey,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Key? switchKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.85),
                fontSize: 13,
              ),
            ),
          ),
          const Spacer(),
          Switch(
            key: switchKey,
            value: value,
            onChanged: onChanged,
            activeTrackColor: scheme.primary,
            activeColor: Colors.white,
          ),
        ],
      ),
    );
  }
}

/// 选项行：左侧标签，右侧下拉框（当前值 + 展开箭头）。
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.dropdownKey,
  });

  final String label;
  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onSelect;
  final Key? dropdownKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
    final valueStyle = TextStyle(color: fg, fontSize: 13.5);
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 13),
            ),
          ),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                key: dropdownKey,
                value: selected,
                isExpanded: true,
                isDense: true,
                alignment: Alignment.centerRight,
                borderRadius: BorderRadius.circular(14),
                dropdownColor: scheme.surface,
                focusColor: Colors.transparent,
                icon: Icon(
                  Icons.expand_more,
                  size: 18,
                  color: fg.withValues(alpha: 0.55),
                ),
                style: valueStyle,
                selectedItemBuilder: (context) => [
                  for (final entry in options.entries)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        entry.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: valueStyle.copyWith(
                          color: fg.withValues(alpha: 0.9),
                          fontWeight: entry.key == selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                ],
                items: [
                  for (final entry in options.entries)
                    DropdownMenuItem<T>(
                      value: entry.key,
                      child: Text(
                        entry.value,
                        style: valueStyle.copyWith(
                          fontWeight: entry.key == selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) onSelect(value);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
