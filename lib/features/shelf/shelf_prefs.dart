/// 书架外观偏好（本机）：圆角 / 每行格数 / 架板样式 / 列表行内容。
///
/// 纯 UI 偏好，只落 shared_preferences；不进数据库、不参与同步。
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'shelf_prefs.g.dart';

/// 书架展示形式（只管「书怎么排」，分类不走这里）。
enum ShelfViewMode {
  /// 平铺：网格卡片，封面 + 书名/作者/标签/评分/进度。
  grid('平铺'),

  /// 列表：一行一本，同样的信息横向排。
  list('列表'),

  /// 封面：只显示封面图。
  cover('封面');

  const ShelfViewMode(this.label);

  /// 展示名。
  final String label;
}

/// 书架每行格数（自动 = 按屏宽算）。
enum ShelfColumnCount {
  /// 按屏宽自动：手机 3 格，宽屏每格约 140dp 加列。
  auto('自动', 0),

  /// 固定 3 格。
  three('3', 3),

  /// 固定 4 格。
  four('4', 4),

  /// 固定 5 格。
  five('5', 5);

  const ShelfColumnCount(this.label, this.count);

  /// 选项展示名。
  final String label;

  /// 固定格数；0 = 自动。
  final int count;

  /// 当前偏好下的一行格数。
  int resolve(double width) {
    if (count > 0) return count;
    final fit = (width / 140).floor();
    return fit < 3 ? 3 : fit;
  }
}

/// 书架书籍排序字段。
enum ShelfSortField {
  /// 最近阅读（从没打开过的排最后）。
  lastOpened('最近阅读'),

  /// 导入时间。
  added('导入时间'),

  /// 书名。
  title('书名');

  const ShelfSortField(this.label);

  /// 展示名。
  final String label;
}

/// 网格每行书下面的架板样式。
enum ShelfPlankStyle {
  /// 不画架板（纯白底）。
  none('无'),

  /// 深胡桃木纹（默认）。
  wood('木纹'),

  /// 纯色板。
  solid('纯色');

  const ShelfPlankStyle(this.label);

  /// 展示名。
  final String label;
}

/// 书架外观偏好集合。
///
/// 默认值与产品定义一致：圆角 20、自动列数、木纹架板；列表四项默认关闭，
/// 简介/书评各 2 行。
class ShelfPrefs {
  /// 创建偏好。
  const ShelfPrefs({
    this.coverRadius = 20,
    this.columns = ShelfColumnCount.auto,
    this.plankStyle = ShelfPlankStyle.wood,
    this.sortField = ShelfSortField.lastOpened,
    this.sortAscending = false,
    this.showGridProgress = true,
    this.showRating = false,
    this.showTags = false,
    this.showDescription = false,
    this.descriptionLines = 2,
    this.showReview = false,
    this.reviewLines = 2,
  });

  /// 封面/卡片圆角（0..24）。
  final int coverRadius;

  /// 每行格数。
  final ShelfColumnCount columns;

  /// 架板样式。
  final ShelfPlankStyle plankStyle;

  /// 书籍排序字段。
  final ShelfSortField sortField;

  /// true = 升序；false = 降序。
  final bool sortAscending;

  /// 网格/封面模式是否在封面右上角显示圆形阅读进度。
  final bool showGridProgress;

  /// 列表行是否显示星级。
  final bool showRating;

  /// 列表行是否显示标签。
  final bool showTags;

  /// 列表行是否显示简介。
  final bool showDescription;

  /// 简介显示行数（1..4）。
  final int descriptionLines;

  /// 列表行是否显示书评。
  final bool showReview;

  /// 书评显示行数（1..4）。
  final int reviewLines;

  /// 复制并覆盖部分字段。
  ShelfPrefs copyWith({
    int? coverRadius,
    ShelfColumnCount? columns,
    ShelfPlankStyle? plankStyle,
    ShelfSortField? sortField,
    bool? sortAscending,
    bool? showGridProgress,
    bool? showRating,
    bool? showTags,
    bool? showDescription,
    int? descriptionLines,
    bool? showReview,
    int? reviewLines,
  }) {
    return ShelfPrefs(
      coverRadius: coverRadius ?? this.coverRadius,
      columns: columns ?? this.columns,
      plankStyle: plankStyle ?? this.plankStyle,
      sortField: sortField ?? this.sortField,
      sortAscending: sortAscending ?? this.sortAscending,
      showGridProgress: showGridProgress ?? this.showGridProgress,
      showRating: showRating ?? this.showRating,
      showTags: showTags ?? this.showTags,
      showDescription: showDescription ?? this.showDescription,
      descriptionLines: descriptionLines ?? this.descriptionLines,
      showReview: showReview ?? this.showReview,
      reviewLines: reviewLines ?? this.reviewLines,
    );
  }
}

/// 「最近在读」竖排架显隐（默认显示）。
@Riverpod(keepAlive: true)
class RecentShelfVisible extends _$RecentShelfVisible {
  static const String _kKey = 'shelf.recentShelfVisible';

  /// 用户是否已手动切换（prefs 恢复晚到时不能覆盖用户刚做的选择）。
  bool _userChanged = false;

  @override
  bool build() {
    _restore();
    return true;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_kKey);
      if (saved == null || _userChanged) return;
      state = saved;
    } catch (_) {
      // 读取失败按默认（显示）处理
    }
  }

  /// 设置显隐并落盘。
  Future<void> set(bool visible) async {
    _userChanged = true;
    if (state != visible) state = visible;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kKey, visible);
    } catch (_) {
      // 落盘失败：本次仍然生效
    }
  }
}


/// 书架展示形式（默认平铺）。
@Riverpod(keepAlive: true)
class ShelfViewModeController extends _$ShelfViewModeController {
  static const String _kKey = 'shelf.viewMode';

  /// 用户是否已手动切换（prefs 恢复晚到时不能覆盖用户刚做的选择）。
  bool _userChanged = false;

  @override
  ShelfViewMode build() {
    _restore();
    return ShelfViewMode.grid;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw == null || _userChanged) return;
      for (final mode in ShelfViewMode.values) {
        if (mode.name == raw) {
          state = mode;
          return;
        }
      }
    } catch (_) {
      // 读取失败按默认（平铺）处理
    }
  }

  /// 切换展示形式并落盘。
  Future<void> set(ShelfViewMode mode) async {
    _userChanged = true;
    if (state != mode) state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, mode.name);
    } catch (_) {
      // 落盘失败：本次仍然生效
    }
  }
}


/// 书架分类筛选（'' = 书架首屏；分类名 = 正在看这个分类）。
@Riverpod(keepAlive: true)
class ShelfCategoryFilter extends _$ShelfCategoryFilter {
  static const String _kKey = 'shelf.categoryFilter';

  /// 用户是否已手动切换（prefs 恢复晚到时不能覆盖用户刚做的选择）。
  bool _userChanged = false;

  @override
  String build() {
    _restore();
    return '';
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw == null || _userChanged) return;
      state = raw;
    } catch (_) {
      // 读取失败按「全部」处理
    }
  }

  /// 切换筛选并落盘。
  Future<void> set(String filter) async {
    _userChanged = true;
    if (state != filter) state = filter;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, filter);
    } catch (_) {
      // 落盘失败：本次仍然生效
    }
  }
}

/// 书架外观偏好（默认值见 [ShelfPrefs]）。
///
/// 设置项都只有一个 key，逐项落盘；滑动圆角时不会一次写九个 key。
@Riverpod(keepAlive: true)
class ShelfPrefsController extends _$ShelfPrefsController {
  static const String _kRadius = 'shelf.coverRadius';
  static const String _kColumns = 'shelf.columns';
  static const String _kPlankStyle = 'shelf.plankStyle';
  static const String _kSortField = 'shelf.sortField';
  static const String _kSortAsc = 'shelf.sortAsc';
  static const String _kShowGridProgress = 'shelf.grid.showProgress';
  static const String _kShowRating = 'shelf.list.showRating';
  static const String _kShowTags = 'shelf.list.showTags';
  static const String _kShowDescription = 'shelf.list.showDescription';
  static const String _kDescriptionLines = 'shelf.list.descriptionLines';
  static const String _kShowReview = 'shelf.list.showReview';
  static const String _kReviewLines = 'shelf.list.reviewLines';

  /// 圆角上限（滑杆 0..24）。
  static const int maxCoverRadius = 24;

  /// 圆角默认值。
  static const int defaultCoverRadius = 20;

  /// 文字行数上限。
  static const int maxTextLines = 4;

  /// 文字行数默认值。
  static const int defaultTextLines = 2;

  /// 用户是否已手动修改（prefs 恢复晚到时不能覆盖用户刚做的选择）。
  bool _userChanged = false;

  @override
  ShelfPrefs build() {
    _restore();
    return const ShelfPrefs();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_userChanged) return;
      final rawRadius =
          (prefs.getInt(_kRadius) ?? defaultCoverRadius).clamp(0, maxCoverRadius);
      final rawDescLines = (prefs.getInt(_kDescriptionLines) ?? defaultTextLines)
          .clamp(1, maxTextLines);
      final rawReviewLines = (prefs.getInt(_kReviewLines) ?? defaultTextLines)
          .clamp(1, maxTextLines);
      state = ShelfPrefs(
        coverRadius: rawRadius,
        columns: _enumByName(
              ShelfColumnCount.values,
              prefs.getString(_kColumns),
            ) ??
            ShelfColumnCount.auto,
        plankStyle: _enumByName(
              ShelfPlankStyle.values,
              prefs.getString(_kPlankStyle),
            ) ??
            ShelfPlankStyle.wood,
        sortField: _enumByName(
              ShelfSortField.values,
              prefs.getString(_kSortField),
            ) ??
            ShelfSortField.lastOpened,
        sortAscending: prefs.getBool(_kSortAsc) ?? false,
        showGridProgress: prefs.getBool(_kShowGridProgress) ?? true,
        showRating: prefs.getBool(_kShowRating) ?? false,
        showTags: prefs.getBool(_kShowTags) ?? false,
        showDescription: prefs.getBool(_kShowDescription) ?? false,
        descriptionLines: rawDescLines,
        showReview: prefs.getBool(_kShowReview) ?? false,
        reviewLines: rawReviewLines,
      );
    } catch (_) {
      // 读取失败按默认值处理
    }
  }

  /// 设置封面/卡片圆角。
  Future<void> setCoverRadius(int value) async {
    final v = value.clamp(0, maxCoverRadius);
    _userChanged = true;
    if (state.coverRadius != v) state = state.copyWith(coverRadius: v);
    await _write((p) => p.setInt(_kRadius, v));
  }

  /// 设置每行格数。
  Future<void> setColumns(ShelfColumnCount value) async {
    _userChanged = true;
    if (state.columns != value) state = state.copyWith(columns: value);
    await _write((p) => p.setString(_kColumns, value.name));
  }

  /// 设置架板样式。
  Future<void> setPlankStyle(ShelfPlankStyle value) async {
    _userChanged = true;
    if (state.plankStyle != value) state = state.copyWith(plankStyle: value);
    await _write((p) => p.setString(_kPlankStyle, value.name));
  }

  /// 设置排序字段。
  Future<void> setSortField(ShelfSortField value) async {
    _userChanged = true;
    if (state.sortField != value) state = state.copyWith(sortField: value);
    await _write((p) => p.setString(_kSortField, value.name));
  }

  /// 设置升序/降序。
  Future<void> setSortAscending(bool value) async {
    _userChanged = true;
    if (state.sortAscending != value) {
      state = state.copyWith(sortAscending: value);
    }
    await _write((p) => p.setBool(_kSortAsc, value));
  }

  /// 网格/封面是否显示封面右上角进度。
  Future<void> setShowGridProgress(bool value) async {
    _userChanged = true;
    if (state.showGridProgress != value) {
      state = state.copyWith(showGridProgress: value);
    }
    await _write((p) => p.setBool(_kShowGridProgress, value));
  }

  /// 列表行是否显示星级。
  Future<void> setShowRating(bool value) async {
    _userChanged = true;
    if (state.showRating != value) state = state.copyWith(showRating: value);
    await _write((p) => p.setBool(_kShowRating, value));
  }

  /// 列表行是否显示标签。
  Future<void> setShowTags(bool value) async {
    _userChanged = true;
    if (state.showTags != value) state = state.copyWith(showTags: value);
    await _write((p) => p.setBool(_kShowTags, value));
  }

  /// 列表行是否显示简介。
  Future<void> setShowDescription(bool value) async {
    _userChanged = true;
    if (state.showDescription != value) {
      state = state.copyWith(showDescription: value);
    }
    await _write((p) => p.setBool(_kShowDescription, value));
  }

  /// 简介显示行数。
  Future<void> setDescriptionLines(int value) async {
    final v = value.clamp(1, maxTextLines);
    _userChanged = true;
    if (state.descriptionLines != v) {
      state = state.copyWith(descriptionLines: v);
    }
    await _write((p) => p.setInt(_kDescriptionLines, v));
  }

  /// 列表行是否显示书评。
  Future<void> setShowReview(bool value) async {
    _userChanged = true;
    if (state.showReview != value) state = state.copyWith(showReview: value);
    await _write((p) => p.setBool(_kShowReview, value));
  }

  /// 书评显示行数。
  Future<void> setReviewLines(int value) async {
    final v = value.clamp(1, maxTextLines);
    _userChanged = true;
    if (state.reviewLines != v) state = state.copyWith(reviewLines: v);
    await _write((p) => p.setInt(_kReviewLines, v));
  }

  Future<void> _write(
    Future<bool> Function(SharedPreferences prefs) write,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await write(prefs);
    } catch (_) {
      // 落盘失败：本次仍然生效
    }
  }
}

/// 按枚举名取值；未知值返回 null（调用方回退默认）。
T? _enumByName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
