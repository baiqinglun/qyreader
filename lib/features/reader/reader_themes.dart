/// 阅读主题库：默认主题 + 用户自定义主题。
///
/// 一个主题 = 纸面背景（含可选背景图）+ 字号 / 行距 / 段间距 / 页边距。
/// 内置主题只读；自定义主题可新增、编辑、删除，全部落 shared_preferences。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme/reading_theme.dart';
import 'reader_settings.dart';

part 'reader_themes.g.dart';

/// 一个阅读主题预设。
///
/// 自定义主题可以携带**整份排版快照**（`snapshot` = `ReadingSettings.toMap()`）：
/// 底色、正文、标题、页面、页眉页脚全在里面，应用时整体还原；在排版面板里
/// 改任何一项，都会写回当前自定义主题（v2.31.0）。内置主题没有快照，
/// 只切底色，不动用户已有的排版。
@immutable
class ReaderThemePreset {
  const ReaderThemePreset({
    required this.id,
    required this.name,
    required this.background,
    this.backgroundImage = '',
    this.fontSize = 18,
    this.lineHeight = 1.7,
    this.paragraphSpacing = 0.4,
    this.marginLeft = 16,
    this.marginRight = 16,
    this.marginTop = 12,
    this.marginBottom = 12,
    this.snapshot,
  });

  /// 稳定 id：`builtin:paper` / `custom:<微秒时间戳>`。
  final String id;

  /// 展示名。
  final String name;

  /// 纸面底色（同时决定 chrome 的明暗）。
  final ReadingTheme background;

  /// 自定义背景图路径；空 = 纯色。
  final String backgroundImage;

  /// 正文字号。
  final double fontSize;

  /// 行距倍数。
  final double lineHeight;

  /// 段间距（字号倍数）。
  final double paragraphSpacing;

  /// 左右上下边距。
  final double marginLeft;
  final double marginRight;
  final double marginTop;
  final double marginBottom;

  /// 整份排版快照（`ReadingSettings.toMap()`）；null = 只有底色/基础字号。
  ///
  /// 自定义主题从排版面板「+」复制当前设置时生成，之后面板里的每次调整都会
  /// 写回这里；应用主题时整体还原（正文/标题/页面/页眉页脚都在其中）。
  final Map<String, dynamic>? snapshot;

  /// 内置主题不可编辑/删除。
  bool get builtIn => id.startsWith('builtin:');

  /// 背景图是否可用（文件还在）。
  bool get hasImage => backgroundImage.isNotEmpty;

  ReaderThemePreset copyWith({
    String? id,
    String? name,
    ReadingTheme? background,
    String? backgroundImage,
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? marginLeft,
    double? marginRight,
    double? marginTop,
    double? marginBottom,
    Map<String, dynamic>? snapshot,
  }) {
    return ReaderThemePreset(
      id: id ?? this.id,
      name: name ?? this.name,
      background: background ?? this.background,
      backgroundImage: backgroundImage ?? this.backgroundImage,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      marginLeft: marginLeft ?? this.marginLeft,
      marginRight: marginRight ?? this.marginRight,
      marginTop: marginTop ?? this.marginTop,
      marginBottom: marginBottom ?? this.marginBottom,
      snapshot: snapshot ?? this.snapshot,
    );
  }

  /// 序列化（不含 builtIn，id 前缀决定）。
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'background': background.name,
        'backgroundImage': backgroundImage,
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'paragraphSpacing': paragraphSpacing,
        'marginLeft': marginLeft,
        'marginRight': marginRight,
        'marginTop': marginTop,
        'marginBottom': marginBottom,
        if (snapshot != null) 'snapshot': snapshot,
      };

  /// 反序列化；未知字段回退默认。
  factory ReaderThemePreset.fromJson(Map<String, dynamic> json) {
    double numOf(String key, double fallback, double min, double max) =>
        ((json[key] as num?)?.toDouble() ?? fallback).clamp(min, max);
    final background = ReadingTheme.values.firstWhere(
      (t) => t.name == json['background'],
      orElse: () => ReadingTheme.paper,
    );
    final rawSnapshot = json['snapshot'];
    final snapshot = rawSnapshot is Map
        ? Map<String, dynamic>.from(rawSnapshot)
        : null;
    return ReaderThemePreset(
      id: json['id'] is String ? json['id'] as String : 'custom:unknown',
      name: json['name'] is String ? json['name'] as String : '自定义主题',
      background: background,
      backgroundImage:
          json['backgroundImage'] is String ? json['backgroundImage'] as String : '',
      fontSize: numOf('fontSize', 18, 14, 28),
      lineHeight: numOf('lineHeight', 1.7, 1.2, 2.4),
      paragraphSpacing: numOf('paragraphSpacing', 0.4, 0, 2),
      marginLeft: numOf('marginLeft', 16, 0, 64),
      marginRight: numOf('marginRight', 16, 0, 64),
      marginTop: numOf('marginTop', 12, 0, 64),
      marginBottom: numOf('marginBottom', 12, 0, 64),
      snapshot: snapshot,
    );
  }

  /// 用当前阅读设置生成一个主题（复制当前主题为副本时用）。
  factory ReaderThemePreset.fromSettings({
    required String id,
    required String name,
    required ReadingSettings settings,
  }) {
    return ReaderThemePreset(
      id: id,
      name: name,
      background: settings.theme,
      backgroundImage: settings.backgroundImage,
      fontSize: settings.fontSize,
      lineHeight: settings.lineHeight,
      paragraphSpacing: settings.paragraphSpacing,
      marginLeft: settings.marginLeft,
      marginRight: settings.marginRight,
      marginTop: settings.marginTop,
      marginBottom: settings.marginBottom,
      snapshot: settings.toMap(),
    );
  }
}

/// 内置主题（默认值与阅读设置的出厂值一致）。
const List<ReaderThemePreset> builtInReaderThemes = [
  ReaderThemePreset(
    id: 'builtin:paper',
    name: '纸',
    background: ReadingTheme.paper,
  ),
  ReaderThemePreset(
    id: 'builtin:white',
    name: '纯白',
    background: ReadingTheme.white,
  ),
  ReaderThemePreset(
    id: 'builtin:sepia',
    name: '羊皮',
    background: ReadingTheme.sepia,
  ),
  ReaderThemePreset(
    id: 'builtin:night',
    name: '夜间',
    background: ReadingTheme.night,
  ),
  ReaderThemePreset(
    id: 'builtin:black',
    name: '纯黑',
    background: ReadingTheme.black,
  ),
];

/// 主题库状态。
@immutable
class ReaderThemesState {
  const ReaderThemesState({
    this.custom = const [],
    this.activeId = 'builtin:paper',
  });

  /// 用户自定义主题。
  final List<ReaderThemePreset> custom;

  /// 当前应用的主题 id（仅用于列表勾选；改字号不会改它）。
  final String activeId;

  /// 内置 + 自定义。
  List<ReaderThemePreset> get all => [...builtInReaderThemes, ...custom];

  /// 当前主题（找不到时回退第一个内置）。
  ReaderThemePreset get active => all.firstWhere(
        (t) => t.id == activeId,
        orElse: () => builtInReaderThemes.first,
      );

  ReaderThemesState copyWith({
    List<ReaderThemePreset>? custom,
    String? activeId,
  }) {
    return ReaderThemesState(
      custom: custom ?? this.custom,
      activeId: activeId ?? this.activeId,
    );
  }
}

/// 主题库控制器。
@Riverpod(keepAlive: true)
class ReaderThemesController extends _$ReaderThemesController {
  static const String _kCustom = 'reader.customThemes';
  static const String _kActive = 'reader.activeThemeId';

  /// 写回防抖：拖动滑杆时每帧都会 patch 设置，攒一下再落盘。
  Timer? _writeBackTimer;

  /// 应用主题时置位，避免「apply → 设置变化 → 又写回主题」绕圈。
  bool _applying = false;

  /// 首次从 prefs 恢复的 future：所有写操作先等它，避免恢复晚到把刚存的主题
  /// 覆盖回空列表（构造后立即保存时的竞态）。
  Future<void>? _restoreFuture;

  Future<void> _ready() => _restoreFuture ?? Future<void>.value();

  @override
  ReaderThemesState build() {
    // 当前是自定义主题时，排版面板里的任何改动都写回这份主题（v2.31.0）。
    ref.listen(readingSettingsControllerProvider, (previous, next) {
      if (_applying) return;
      final active = state.active;
      if (active.builtIn) return;
      _writeBackTimer?.cancel();
      _writeBackTimer = Timer(const Duration(milliseconds: 500), () {
        final current = state.active;
        if (current.builtIn) return;
        final settings = ref.read(readingSettingsControllerProvider);
        final updated = ReaderThemePreset.fromSettings(
          id: current.id,
          name: current.name,
          settings: settings,
        );
        unawaited(save(updated, applyNow: false));
      });
    });
    ref.onDispose(() => _writeBackTimer?.cancel());
    _restoreFuture = _restore();
    return const ReaderThemesState();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCustom);
      final custom = <ReaderThemePreset>[];
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              custom.add(ReaderThemePreset.fromJson(item));
            } else if (item is Map) {
              custom.add(
                ReaderThemePreset.fromJson(Map<String, dynamic>.from(item)),
              );
            }
          }
        }
      }
      final active = prefs.getString(_kActive) ?? 'builtin:paper';
      state = ReaderThemesState(custom: custom, activeId: active);
    } catch (_) {
      // 读取失败按内置主题处理
    }
  }

  /// 新建/覆盖一个自定义主题；[applyNow] 时立即应用到阅读设置。
  Future<void> save(ReaderThemePreset preset, {bool applyNow = true}) async {
    await _ready();
    final custom = [...state.custom];
    final index = custom.indexWhere((t) => t.id == preset.id);
    if (index >= 0) {
      custom[index] = preset;
    } else {
      custom.add(preset);
    }
    state = state.copyWith(custom: custom);
    await _writeCustom(custom);
    if (applyNow) await apply(preset);
  }

  /// 删除自定义主题；删的是当前主题时回退到「纸」。
  Future<void> delete(String id) async {
    await _ready();
    ReaderThemePreset? target;
    for (final t in state.custom) {
      if (t.id == id) {
        target = t;
        break;
      }
    }
    if (target == null) return;
    final deleted = target;
    final custom = state.custom.where((t) => t.id != id).toList();
    state = state.copyWith(custom: custom);
    await _writeCustom(custom);
    if (state.activeId == id) {
      await apply(builtInReaderThemes.first);
    }
    // 主题专属背景图一并清理；仍被其他主题引用则保留。
    if (deleted.backgroundImage.isNotEmpty &&
        !custom.any((t) => t.backgroundImage == deleted.backgroundImage)) {
      try {
        final file = File(deleted.backgroundImage);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // 图片删除失败不影响主题删除
      }
    }
  }

  /// 应用主题。
  ///
  /// 带快照的自定义主题：整份还原（底色、正文、标题、页面、页眉页脚）；
  /// 内置主题 / 旧主题：只切底色与基础字号、边距，不动其它排版项。
  Future<void> apply(ReaderThemePreset preset) async {
    await _ready();
    final controller = ref.read(readingSettingsControllerProvider.notifier);
    _applying = true;
    try {
      final snapshot = preset.snapshot;
      if (snapshot != null) {
        final restored = readingSettingsFromMap(
          Map<String, dynamic>.from(snapshot),
        );
        await controller.update(restored);
        // 快照里也存了当时的 backgroundImage：换过背景后必须用主题当前的
        // backgroundImage 覆盖，否则阅读页还显示旧背景（或旧图已删）。
        await controller.patch(backgroundImage: preset.backgroundImage);
      } else {
        await controller.patch(
          theme: preset.background,
          backgroundImage: preset.backgroundImage,
          fontSize: preset.fontSize,
          lineHeight: preset.lineHeight,
          paragraphSpacing: preset.paragraphSpacing,
          marginLeft: preset.marginLeft,
          marginRight: preset.marginRight,
          marginTop: preset.marginTop,
          marginBottom: preset.marginBottom,
        );
      }
    } finally {
      _applying = false;
    }
    state = state.copyWith(activeId: preset.id);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kActive, preset.id);
    } catch (_) {
      // 落盘失败：本次仍然生效
    }
  }

  /// 把「当前设置 + 当前主题」复制成一个新的自定义主题并立即应用。
  ///
  /// 排版面板的「+」走这里：新主题名 = 当前主题名 + 副本（重名自动加序号），
  /// 之后面板里的所有调整都会写回它。
  Future<ReaderThemePreset> duplicateCurrent() async {
    await ref.read(readingSettingsControllerProvider.notifier).waitRestored();
    final settings = ref.read(readingSettingsControllerProvider);
    final baseName = state.active.name;
    final name = _uniqueName('$baseName 副本');
    final preset = ReaderThemePreset.fromSettings(
      id: 'custom:${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      settings: settings,
    );
    await save(preset, applyNow: true);
    return preset;
  }

  /// 重命名自定义主题。
  Future<void> rename(String id, String name) async {
    await _ready();
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final index = state.custom.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final custom = [...state.custom];
    custom[index] = custom[index].copyWith(name: trimmed);
    state = state.copyWith(custom: custom);
    await _writeCustom(custom);
  }

  /// 主题名去重：`X` 已被占用时依次试 `X 2`、`X 3`…
  String _uniqueName(String base) {
    final used = {for (final t in state.all) t.name};
    if (!used.contains(base)) return base;
    var i = 2;
    while (used.contains('$base $i')) {
      i++;
    }
    return '$base $i';
  }

  Future<void> _writeCustom(List<ReaderThemePreset> custom) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kCustom,
        jsonEncode([for (final t in custom) t.toJson()]),
      );
    } catch (_) {
      // 落盘失败：本次仍然生效
    }
  }
}
