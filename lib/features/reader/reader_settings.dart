/// 阅读排版设置：主题 / 字号 / 行距 / 边距 / flow / 翻页模式。
///
/// 持久化到 shared_preferences（JSON）；不进 SQLite、不参与同步
/// （v1 设置为设备本地偏好）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme/reading_theme.dart';

part 'reader_settings.freezed.dart';
part 'reader_settings.g.dart';

/// 排版流向。
enum ReadingFlow {
  /// 分页（左右翻页）。
  paginated('分页'),

  /// 上下滚动。
  scrolled('滚动');

  const ReadingFlow(this.label);

  /// 展示名。
  final String label;
}

/// 翻页动画模式。
enum PageTurnMode {
  /// 滑动：双页同移。
  slide('滑动'),

  /// 覆盖：新页右入，旧页左移并压暗。
  cover('覆盖'),

  /// 无动画：瞬间切换。
  none('无'),

  /// 淡入：交叉淡入 + 2px 上移。
  fade('淡入'),

  /// 仿真：当前页沿左缘 3D 折叠翻起，下一页原样露出（无 WebView 截图，
  /// 以透视折叠 + 折线阴影近似仿真翻页）。
  curl('仿真'),

  /// 随手仿真：从手指落点开始折起，纸角跟着手指走，露出下一页；
  /// 手指离开后按拖动距离落定。
  freeCurl('随手仿真');

  const PageTurnMode(this.label);

  /// 展示名。
  final String label;
}

/// 翻页音效。
///
/// 资源在 `assets/sounds/`（用户提供的 mp3，约 20–40 KB）；
/// 播放走 `PageTurnSoundPlayer`（低延迟、可打断）。
enum PageTurnSound {
  /// 关闭。
  none('无', ''),

  /// 音效一（默认）。
  first('音效一', 'assets/sounds/page_turn_1.mp3'),

  /// 音效二。
  second('音效二', 'assets/sounds/page_turn_2.mp3');

  const PageTurnSound(this.label, this.asset);

  /// 展示名。
  final String label;

  /// 资源路径（相对工程根，`assets/` 开头）；[none] 为空。
  final String asset;
}

/// 进度条显示范围。
enum ProgressScope {
  /// 全书进度。
  book('全书'),

  /// 本章进度。
  chapter('本章');

  const ProgressScope(this.label);

  /// 展示名。
  final String label;
}

/// 正文/标题的对齐方式。
enum TextAlignMode {
  /// 默认（正文左对齐，标题居中）。
  auto('默认'),

  /// 左对齐。
  left('左'),

  /// 居中。
  center('居中'),

  /// 右对齐。
  right('右');

  const TextAlignMode(this.label);

  /// 展示名。
  final String label;
}

/// 首行缩进字数。
enum ParagraphIndent {
  /// 默认（两字）。
  auto('默认', 2),

  /// 无缩进。
  none('无', 0),

  /// 单字。
  one('单字', 1),

  /// 双字。
  two('双字', 2),

  /// 三字。
  three('三字', 3),

  /// 四字。
  four('四字', 4);

  const ParagraphIndent(this.label, this.chars);

  /// 展示名。
  final String label;

  /// 缩进的全角空格数。
  final int chars;
}

/// 正文字重。
enum BodyFontWeight {
  /// 细。
  light('细', 300),

  /// 常规。
  normal('常规', 400),

  /// 中等。
  medium('中等', 500),

  /// 半粗。
  semiBold('半粗', 600),

  /// 粗。
  bold('粗', 700),

  /// 特粗。
  black('特粗', 900);

  const BodyFontWeight(this.label, this.value);

  /// 展示名。
  final String label;

  /// Flutter 字重数值。
  final int value;
}

/// 标题装饰样式。
enum HeadingStyle {
  /// 默认（无装饰）。
  plain('默认'),

  /// 下划线。
  underline('下划线'),

  /// 浅色底纹。
  shade('底色'),

  /// 下划线 + 底色。
  underlineShade('下划线+底色');

  const HeadingStyle(this.label);

  /// 展示名。
  final String label;
}

/// 页眉/页脚槽位可显示的内容。
enum RunningContent {
  /// 不显示。
  none('无'),

  /// 当前时间（HH:mm）。
  time('时间'),

  /// 章节名。
  chapterName('章节名'),

  /// 章节进度百分比。
  chapterPercent('章节%'),

  /// 章节进度页数比。
  chapterPages('章节页'),

  /// 全文进度百分比。
  bookPercent('全文%'),

  /// 全文进度页数比（全书页数为估算值）。
  bookPages('全文页'),

  /// 电池电量。
  battery('电量');

  const RunningContent(this.label);

  /// 展示名。
  final String label;
}

/// 排版设置集合。
@freezed
abstract class ReadingSettings with _$ReadingSettings {
  const factory ReadingSettings({
    /// 阅读主题。
    @Default(ReadingTheme.paper) ReadingTheme theme,

    /// 自定义阅读背景图（应用内文件路径）；空 = 纯色纸面。
    @Default('') String backgroundImage,

    /// 正文字号（14..28）。
    @Default(18.0) double fontSize,

    /// 行距倍数（1.2..2.4）。
    @Default(1.7) double lineHeight,

    /// 左边距（0..64，不含系统安全区）。
    @Default(16.0) double marginLeft,

    /// 右边距（0..64，不含系统安全区）。
    @Default(16.0) double marginRight,

    /// 上边距（0..64，不含状态栏安全区）。
    @Default(12.0) double marginTop,

    /// 下边距（0..64，不含导航栏安全区）。
    @Default(12.0) double marginBottom,

    /// 排版流向。
    @Default(ReadingFlow.paginated) ReadingFlow flow,

    /// 翻页动画模式。
    @Default(PageTurnMode.slide) PageTurnMode pageTurnMode,

    /// 翻页音效（默认书页；选「无」静音）。
    @Default(PageTurnSound.first) PageTurnSound pageTurnSound,

    /// 精排：保留书籍自身的排版样式。
    ///
    /// 关（默认）= 阅读器统一接管字号/行距/颜色，各家 EPUB 观感一致；
    /// 开 = 只有主题底色参与，字号/行距/段落缩进/标题样式全部交给书籍
    /// 自带的 CSS（"精排"）。适合排版讲究的书，也可能被粗糙的 CSS 弄乱，
    /// 所以做成开关而不是默认开启。
    @Default(false) bool preciseTypesetting,

    /// 底部进度条显示的是全书进度还是本章进度。
    @Default(ProgressScope.book) ProgressScope progressScope,

    /// 阅读字体：导入字体的 family 键（`qyfont_xxx`）；空 = 系统默认。
    ///
    /// 存 family 而不是文件路径：字体文件由字体库统一管理（可删除/重导），
    /// 设置里只记「用哪一个」。
    @Default('') String fontFamily,

    // ---------- 正文 ----------

    /// 段间距（以字号为单位的倍数，0..2）。
    @Default(0.4) double paragraphSpacing,

    /// 字间距（逻辑像素，-1..6）。
    @Default(0.0) double letterSpacing,

    /// 正文加粗（等价于把字重抬到 700）。
    @Default(false) bool bodyBold,

    /// 正文字重。
    @Default(BodyFontWeight.normal) BodyFontWeight bodyWeight,

    /// 正文对齐。
    @Default(TextAlignMode.auto) TextAlignMode bodyAlign,

    /// 两端对齐（正文列尾对齐；居中/右对齐时以对齐设置为准）。
    @Default(true) bool bodyJustify,

    /// 段落首行缩进。
    @Default(ParagraphIndent.auto) ParagraphIndent bodyIndent,

    // ---------- 标题 ----------

    /// 标题装饰样式。
    @Default(HeadingStyle.plain) HeadingStyle headingStyle,

    /// 标题字号（16..40）。
    @Default(24.0) double headingFontSize,

    /// 标题加粗。
    @Default(true) bool headingBold,

    /// 标题对齐。
    @Default(TextAlignMode.center) TextAlignMode headingAlign,

    /// 标题上边距（逻辑像素）。
    @Default(18.0) double headingMarginTop,

    /// 标题下边距（逻辑像素）。
    @Default(12.0) double headingMarginBottom,

    // ---------- 页面 ----------

    /// 单双页：开 = 每屏左右两页（书本摊开）。
    @Default(false) bool doublePage,

    // ---------- 页眉 ----------

    /// 页眉左槽内容。
    @Default(RunningContent.none) RunningContent headerLeft,

    /// 页眉中槽内容。
    @Default(RunningContent.none) RunningContent headerCenter,

    /// 页眉右槽内容。
    @Default(RunningContent.none) RunningContent headerRight,

    /// 页眉字号（8..16，页脚同用）。
    @Default(10.0) double headerFontSize,

    /// 页眉上边距。
    @Default(6.0) double headerMarginTop,

    /// 页眉左边距。
    @Default(16.0) double headerMarginLeft,

    /// 页眉右边距。
    @Default(16.0) double headerMarginRight,

    // ---------- 页脚 ----------

    /// 页脚左槽内容。
    @Default(RunningContent.none) RunningContent footerLeft,

    /// 页脚中槽内容。
    @Default(RunningContent.none) RunningContent footerCenter,

    /// 页脚右槽内容。
    @Default(RunningContent.none) RunningContent footerRight,

    /// 页脚左边距。
    @Default(16.0) double footerMarginLeft,

    /// 页脚右边距。
    @Default(16.0) double footerMarginRight,

    /// 页脚下边距。
    @Default(6.0) double footerMarginBottom,
  }) = _ReadingSettings;
}

/// 手写序列化（json_serializable 与 freezed 3 在 Dart 3.8 下不兼容）。
extension ReadingSettingsJson on ReadingSettings {
  /// 序列化为 JSON Map。
  Map<String, dynamic> toMap() => <String, dynamic>{
    'theme': theme.name,
    'backgroundImage': backgroundImage,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'marginLeft': marginLeft,
    'marginRight': marginRight,
    'marginTop': marginTop,
    'marginBottom': marginBottom,
    'flow': flow.name,
    'pageTurnMode': pageTurnMode.name,
    'pageTurnSound': pageTurnSound.name,
    'preciseTypesetting': preciseTypesetting,
    'progressScope': progressScope.name,
    'fontFamily': fontFamily,
    'paragraphSpacing': paragraphSpacing,
    'letterSpacing': letterSpacing,
    'bodyBold': bodyBold,
    'bodyWeight': bodyWeight.name,
    'bodyAlign': bodyAlign.name,
    'bodyJustify': bodyJustify,
    'bodyIndent': bodyIndent.name,
    'headingStyle': headingStyle.name,
    'headingFontSize': headingFontSize,
    'headingBold': headingBold,
    'headingAlign': headingAlign.name,
    'headingMarginTop': headingMarginTop,
    'headingMarginBottom': headingMarginBottom,
    'doublePage': doublePage,
    'headerLeft': headerLeft.name,
    'headerCenter': headerCenter.name,
    'headerRight': headerRight.name,
    'headerFontSize': headerFontSize,
    'headerMarginTop': headerMarginTop,
    'headerMarginLeft': headerMarginLeft,
    'headerMarginRight': headerMarginRight,
    'footerLeft': footerLeft.name,
    'footerCenter': footerCenter.name,
    'footerRight': footerRight.name,
    'footerMarginLeft': footerMarginLeft,
    'footerMarginRight': footerMarginRight,
    'footerMarginBottom': footerMarginBottom,
  };
}

/// 顶层反序列化；非法值逐字段兜底默认。
///
/// 兼容 v1 的单一 `margin` 字段（当时只作用于左右边距）。
ReadingSettings readingSettingsFromMap(Map<String, dynamic> json) {
  final legacyMargin = (json['margin'] as num?)?.toDouble();
  return ReadingSettings(
    theme: ReadingTheme.values.firstWhere(
      (t) => t.name == json['theme'],
      orElse: () => ReadingTheme.paper,
    ),
    backgroundImage: json['backgroundImage'] is String
        ? json['backgroundImage'] as String
        : '',
    fontSize: _clamp((json['fontSize'] as num?)?.toDouble(), 14, 28, 18),
    lineHeight: _clamp((json['lineHeight'] as num?)?.toDouble(), 1.2, 2.4, 1.7),
    marginLeft: _clamp(
      (json['marginLeft'] as num?)?.toDouble() ?? legacyMargin,
      0,
      64,
      16,
    ),
    marginRight: _clamp(
      (json['marginRight'] as num?)?.toDouble() ?? legacyMargin,
      0,
      64,
      16,
    ),
    marginTop: _clamp((json['marginTop'] as num?)?.toDouble(), 0, 64, 12),
    marginBottom: _clamp((json['marginBottom'] as num?)?.toDouble(), 0, 64, 12),
    flow: ReadingFlow.values.firstWhere(
      (f) => f.name == json['flow'],
      orElse: () => ReadingFlow.paginated,
    ),
    pageTurnMode: PageTurnMode.values.firstWhere(
      (m) => m.name == json['pageTurnMode'],
      orElse: () => PageTurnMode.slide,
    ),
    pageTurnSound: _pageTurnSoundOf(json['pageTurnSound']),
    preciseTypesetting: json['preciseTypesetting'] == true,
    progressScope: ProgressScope.values.firstWhere(
      (v) => v.name == json['progressScope'],
      orElse: () => ProgressScope.book,
    ),
    fontFamily: json['fontFamily'] is String
        ? json['fontFamily'] as String
        : '',
    paragraphSpacing:
        _clamp((json['paragraphSpacing'] as num?)?.toDouble(), 0, 2, 0.4),
    letterSpacing:
        _clamp((json['letterSpacing'] as num?)?.toDouble(), -1, 6, 0),
    bodyBold: json['bodyBold'] == true,
    bodyWeight: _enumOf(
        BodyFontWeight.values, json['bodyWeight'], BodyFontWeight.normal),
    bodyAlign:
        _enumOf(TextAlignMode.values, json['bodyAlign'], TextAlignMode.auto),
    bodyJustify: json['bodyJustify'] != false,
    bodyIndent: _enumOf(
        ParagraphIndent.values, json['bodyIndent'], ParagraphIndent.auto),
    headingStyle: _enumOf(
        HeadingStyle.values, json['headingStyle'], HeadingStyle.plain),
    headingFontSize:
        _clamp((json['headingFontSize'] as num?)?.toDouble(), 16, 40, 24),
    headingBold: json['headingBold'] != false,
    headingAlign: _enumOf(
        TextAlignMode.values, json['headingAlign'], TextAlignMode.center),
    headingMarginTop:
        _clamp((json['headingMarginTop'] as num?)?.toDouble(), 0, 64, 18),
    headingMarginBottom:
        _clamp((json['headingMarginBottom'] as num?)?.toDouble(), 0, 64, 12),
    doublePage: json['doublePage'] == true,
    headerLeft: _enumOf(
        RunningContent.values, json['headerLeft'], RunningContent.none),
    headerCenter: _enumOf(
        RunningContent.values, json['headerCenter'], RunningContent.none),
    headerRight: _enumOf(
        RunningContent.values, json['headerRight'], RunningContent.none),
    headerFontSize:
        _clamp((json['headerFontSize'] as num?)?.toDouble(), 8, 16, 10),
    headerMarginTop:
        _clamp((json['headerMarginTop'] as num?)?.toDouble(), 0, 64, 6),
    headerMarginLeft:
        _clamp((json['headerMarginLeft'] as num?)?.toDouble(), 0, 64, 16),
    headerMarginRight:
        _clamp((json['headerMarginRight'] as num?)?.toDouble(), 0, 64, 16),
    footerLeft: _enumOf(
        RunningContent.values, json['footerLeft'], RunningContent.none),
    footerCenter: _enumOf(
        RunningContent.values, json['footerCenter'], RunningContent.none),
    footerRight: _enumOf(
        RunningContent.values, json['footerRight'], RunningContent.none),
    footerMarginLeft:
        _clamp((json['footerMarginLeft'] as num?)?.toDouble(), 0, 64, 16),
    footerMarginRight:
        _clamp((json['footerMarginRight'] as num?)?.toDouble(), 0, 64, 16),
    footerMarginBottom:
        _clamp((json['footerMarginBottom'] as num?)?.toDouble(), 0, 64, 6),
  );
}

double _clamp(double? v, double min, double max, double fallback) {
  if (v == null) return fallback;
  return v.clamp(min, max);
}

/// 按枚举名解析；未知值回退默认。
T _enumOf<T extends Enum>(List<T> values, Object? raw, T fallback) {
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return fallback;
}

/// 翻页音效解析：旧版本的三档合成音效（paper / thin / thick）统一归到
/// 「音效一」，换音源后老用户的设置不会突然变回默认。
PageTurnSound _pageTurnSoundOf(Object? raw) {
  const legacy = {'paper', 'thin', 'thick'};
  if (raw is String && legacy.contains(raw)) return PageTurnSound.first;
  return _enumOf(PageTurnSound.values, raw, PageTurnSound.first);
}

/// 排版设置控制器：读写 shared_preferences。
@Riverpod(keepAlive: true)
class ReadingSettingsController extends _$ReadingSettingsController {
  static const String _kKey = 'reader.settings';

  /// 首次从 prefs 恢复完成（阅读页首帧前等它，避免字体等设置被晚到的
  /// 恢复值覆盖/闪一下默认值）。
  final _restored = Completer<void>();

  @override
  ReadingSettings build() {
    _restore();
    return const ReadingSettings();
  }

  /// 等首次恢复完成。
  Future<void> waitRestored() => _restored.future;

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw == null) return;
      state = readingSettingsFromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // 损坏的设置按默认值处理
    } finally {
      if (!_restored.isCompleted) _restored.complete();
    }
  }

  Future<void> update(ReadingSettings next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(next.toMap()));
  }

  /// 仅替换部分字段（面板快捷操作用）。
  Future<void> patch({
    ReadingTheme? theme,
    String? backgroundImage,
    double? fontSize,
    double? lineHeight,
    double? marginLeft,
    double? marginRight,
    double? marginTop,
    double? marginBottom,
    ReadingFlow? flow,
    PageTurnMode? pageTurnMode,
    PageTurnSound? pageTurnSound,
    bool? preciseTypesetting,
    ProgressScope? progressScope,
    double? paragraphSpacing,
    double? letterSpacing,
    bool? bodyBold,
    BodyFontWeight? bodyWeight,
    TextAlignMode? bodyAlign,
    bool? bodyJustify,
    ParagraphIndent? bodyIndent,
    HeadingStyle? headingStyle,
    double? headingFontSize,
    bool? headingBold,
    TextAlignMode? headingAlign,
    double? headingMarginTop,
    double? headingMarginBottom,
    bool? doublePage,
    RunningContent? headerLeft,
    RunningContent? headerCenter,
    RunningContent? headerRight,
    double? headerFontSize,
    double? headerMarginTop,
    double? headerMarginLeft,
    double? headerMarginRight,
    RunningContent? footerLeft,
    RunningContent? footerCenter,
    RunningContent? footerRight,
    double? footerMarginLeft,
    double? footerMarginRight,
    double? footerMarginBottom,
  }) async {
    // 逐项 copyWith：字段多，逐项合成既啰嗦又容易漏字段（漏一个就会
    // 把该项重置回默认值）。freezed 的 copyWith 对非空字段收非空参数，
    // 这里的参数都已判空，安全。
    var next = state;
    if (theme != null) next = next.copyWith(theme: theme);
    if (backgroundImage != null) {
      next = next.copyWith(backgroundImage: backgroundImage);
    }
    if (fontSize != null) next = next.copyWith(fontSize: fontSize);
    if (lineHeight != null) next = next.copyWith(lineHeight: lineHeight);
    if (marginLeft != null) next = next.copyWith(marginLeft: marginLeft);
    if (marginRight != null) next = next.copyWith(marginRight: marginRight);
    if (marginTop != null) next = next.copyWith(marginTop: marginTop);
    if (marginBottom != null) next = next.copyWith(marginBottom: marginBottom);
    if (flow != null) next = next.copyWith(flow: flow);
    if (pageTurnMode != null) next = next.copyWith(pageTurnMode: pageTurnMode);
    if (pageTurnSound != null) {
      next = next.copyWith(pageTurnSound: pageTurnSound);
    }
    if (preciseTypesetting != null) {
      next = next.copyWith(preciseTypesetting: preciseTypesetting);
    }
    if (progressScope != null) {
      next = next.copyWith(progressScope: progressScope);
    }
    if (paragraphSpacing != null) {
      next = next.copyWith(paragraphSpacing: paragraphSpacing);
    }
    if (letterSpacing != null) {
      next = next.copyWith(letterSpacing: letterSpacing);
    }
    if (bodyBold != null) next = next.copyWith(bodyBold: bodyBold);
    if (bodyWeight != null) next = next.copyWith(bodyWeight: bodyWeight);
    if (bodyAlign != null) next = next.copyWith(bodyAlign: bodyAlign);
    if (bodyJustify != null) next = next.copyWith(bodyJustify: bodyJustify);
    if (bodyIndent != null) next = next.copyWith(bodyIndent: bodyIndent);
    if (headingStyle != null) next = next.copyWith(headingStyle: headingStyle);
    if (headingFontSize != null) {
      next = next.copyWith(headingFontSize: headingFontSize);
    }
    if (headingBold != null) next = next.copyWith(headingBold: headingBold);
    if (headingAlign != null) {
      next = next.copyWith(headingAlign: headingAlign);
    }
    if (headingMarginTop != null) {
      next = next.copyWith(headingMarginTop: headingMarginTop);
    }
    if (headingMarginBottom != null) {
      next = next.copyWith(headingMarginBottom: headingMarginBottom);
    }
    if (doublePage != null) next = next.copyWith(doublePage: doublePage);
    if (headerLeft != null) next = next.copyWith(headerLeft: headerLeft);
    if (headerCenter != null) next = next.copyWith(headerCenter: headerCenter);
    if (headerRight != null) next = next.copyWith(headerRight: headerRight);
    if (headerFontSize != null) {
      next = next.copyWith(headerFontSize: headerFontSize);
    }
    if (headerMarginTop != null) {
      next = next.copyWith(headerMarginTop: headerMarginTop);
    }
    if (headerMarginLeft != null) {
      next = next.copyWith(headerMarginLeft: headerMarginLeft);
    }
    if (headerMarginRight != null) {
      next = next.copyWith(headerMarginRight: headerMarginRight);
    }
    if (footerLeft != null) next = next.copyWith(footerLeft: footerLeft);
    if (footerCenter != null) next = next.copyWith(footerCenter: footerCenter);
    if (footerRight != null) next = next.copyWith(footerRight: footerRight);
    if (footerMarginLeft != null) {
      next = next.copyWith(footerMarginLeft: footerMarginLeft);
    }
    if (footerMarginRight != null) {
      next = next.copyWith(footerMarginRight: footerMarginRight);
    }
    if (footerMarginBottom != null) {
      next = next.copyWith(footerMarginBottom: footerMarginBottom);
    }
    if (next == state) return;
    await update(next);
  }

  /// 设置阅读字体（空字符串 = 系统默认）。
  ///
  /// 单独一个方法而不是复用 [patch]：patch 的 `??` 合成无法表达
  /// 「显式切回系统字体（null/空）」。
  Future<void> setFontFamily(String family) async {
    if (state.fontFamily == family) return;
    await update(state.copyWith(fontFamily: family));
  }
}

/// 注入 WebView 的样式载荷（JSON 字符串）。
///
/// 边距不在这里：边距由 Flutter 外层 padding 实现（拖动时只改 padding，
/// 不触发排版；松手后 flushViewport 统一重排并回到原 CFI）。
String readerStylePayload(ReadingSettings s) => jsonEncode(<String, dynamic>{
  'theme': <String, String>{
    'background': _cssColor(s.theme.background),
    'foreground': _cssColor(s.theme.foreground),
    'accent': _cssColor(s.theme.accent),
  },
  'fontSize': s.fontSize.round(),
  'lineHeight': s.lineHeight,
  'flow': s.flow.name,
  'precise': s.preciseTypesetting,
});

/// 边距编辑分组（阅读页「边距」直调模式的三页）。
enum MarginGroup {
  /// 正文四边边距。
  body('正文'),

  /// 页眉上/左/右，以及页眉与正文之间的上边距。
  header('页眉'),

  /// 页脚下/左/右，以及正文与页脚之间的下边距。
  footer('页脚');

  const MarginGroup(this.label);

  /// 分组名（「正文」「页眉」「页脚」）。
  final String label;

  /// 工具栏标题（「正文边距」等）。
  String get title => '$label边距';
}

/// 边距编辑器拖动中的实时预览（null = 使用持久化设置）。
///
/// 与 [liveReaderTypesetPreview] 分开：边距预览会让阅读面按新尺寸重新
/// 分页预览当前页（只排当前章、当前页），字号/行距预览沿用原通道。
final ValueNotifier<ReadingSettings?> liveReaderMarginPreview =
    ValueNotifier<ReadingSettings?>(null);

/// 拖动排版滑杆（字号/行距/段距/字距）时的实时预览。
///
/// 用 ValueNotifier 而不是 Riverpod：拖动时只有阅读面的页面区域刷新，
/// 不重建整棵阅读页（也避免每帧一次完整页面绘制）。拖动中不落库、
/// 不触发全章重排；松手时提交到 [readingSettingsControllerProvider] 并清空。
final ValueNotifier<ReadingSettings?> liveReaderTypesetPreview =
    ValueNotifier<ReadingSettings?>(null);

/// 边距拖动中的实时预览（null = 使用持久化设置）。
///
/// 拖动只改 WebView 外层 padding（页面侧 60ms 插值），不做重排；
/// 松手后落库设置并 flushViewport 统一重排、回到原 CFI。
final liveReaderMarginsProvider = StateProvider<EdgeInsets?>((ref) => null);

String _cssColor(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
