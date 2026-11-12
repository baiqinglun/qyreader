// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'reader_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ReadingSettings {

/// 阅读主题。
 ReadingTheme get theme;/// 自定义阅读背景图（应用内文件路径）；空 = 纯色纸面。
 String get backgroundImage;/// 正文字号（14..28）。
 double get fontSize;/// 行距倍数（1.2..2.4）。
 double get lineHeight;/// 左边距（0..64，不含系统安全区）。
 double get marginLeft;/// 右边距（0..64，不含系统安全区）。
 double get marginRight;/// 上边距（0..64，不含状态栏安全区）。
 double get marginTop;/// 下边距（0..64，不含导航栏安全区）。
 double get marginBottom;/// 排版流向。
 ReadingFlow get flow;/// 翻页动画模式。
 PageTurnMode get pageTurnMode;/// 翻页音效（默认书页；选「无」静音）。
 PageTurnSound get pageTurnSound;/// 精排：保留书籍自身的排版样式。
///
/// 关（默认）= 阅读器统一接管字号/行距/颜色，各家 EPUB 观感一致；
/// 开 = 只有主题底色参与，字号/行距/段落缩进/标题样式全部交给书籍
/// 自带的 CSS（"精排"）。适合排版讲究的书，也可能被粗糙的 CSS 弄乱，
/// 所以做成开关而不是默认开启。
 bool get preciseTypesetting;/// 底部进度条显示的是全书进度还是本章进度。
 ProgressScope get progressScope;/// 阅读字体：导入字体的 family 键（`qyfont_xxx`）；空 = 系统默认。
///
/// 存 family 而不是文件路径：字体文件由字体库统一管理（可删除/重导），
/// 设置里只记「用哪一个」。
 String get fontFamily;// ---------- 正文 ----------
/// 段间距（以字号为单位的倍数，0..2）。
 double get paragraphSpacing;/// 字间距（逻辑像素，-1..6）。
 double get letterSpacing;/// 正文加粗（等价于把字重抬到 700）。
 bool get bodyBold;/// 正文字重。
 BodyFontWeight get bodyWeight;/// 正文对齐。
 TextAlignMode get bodyAlign;/// 两端对齐（正文列尾对齐；居中/右对齐时以对齐设置为准）。
 bool get bodyJustify;/// 段落首行缩进。
 ParagraphIndent get bodyIndent;// ---------- 标题 ----------
/// 标题装饰样式。
 HeadingStyle get headingStyle;/// 标题字号（16..40）。
 double get headingFontSize;/// 标题加粗。
 bool get headingBold;/// 标题对齐。
 TextAlignMode get headingAlign;/// 标题上边距（逻辑像素）。
 double get headingMarginTop;/// 标题下边距（逻辑像素）。
 double get headingMarginBottom;// ---------- 页面 ----------
/// 单双页：开 = 每屏左右两页（书本摊开）。
 bool get doublePage;// ---------- 页眉 ----------
/// 页眉左槽内容。
 RunningContent get headerLeft;/// 页眉中槽内容。
 RunningContent get headerCenter;/// 页眉右槽内容。
 RunningContent get headerRight;/// 页眉字号（8..16，页脚同用）。
 double get headerFontSize;/// 页眉上边距。
 double get headerMarginTop;/// 页眉左边距。
 double get headerMarginLeft;/// 页眉右边距。
 double get headerMarginRight;// ---------- 页脚 ----------
/// 页脚左槽内容。
 RunningContent get footerLeft;/// 页脚中槽内容。
 RunningContent get footerCenter;/// 页脚右槽内容。
 RunningContent get footerRight;/// 页脚左边距。
 double get footerMarginLeft;/// 页脚右边距。
 double get footerMarginRight;/// 页脚下边距。
 double get footerMarginBottom;
/// Create a copy of ReadingSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadingSettingsCopyWith<ReadingSettings> get copyWith => _$ReadingSettingsCopyWithImpl<ReadingSettings>(this as ReadingSettings, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadingSettings&&(identical(other.theme, theme) || other.theme == theme)&&(identical(other.backgroundImage, backgroundImage) || other.backgroundImage == backgroundImage)&&(identical(other.fontSize, fontSize) || other.fontSize == fontSize)&&(identical(other.lineHeight, lineHeight) || other.lineHeight == lineHeight)&&(identical(other.marginLeft, marginLeft) || other.marginLeft == marginLeft)&&(identical(other.marginRight, marginRight) || other.marginRight == marginRight)&&(identical(other.marginTop, marginTop) || other.marginTop == marginTop)&&(identical(other.marginBottom, marginBottom) || other.marginBottom == marginBottom)&&(identical(other.flow, flow) || other.flow == flow)&&(identical(other.pageTurnMode, pageTurnMode) || other.pageTurnMode == pageTurnMode)&&(identical(other.pageTurnSound, pageTurnSound) || other.pageTurnSound == pageTurnSound)&&(identical(other.preciseTypesetting, preciseTypesetting) || other.preciseTypesetting == preciseTypesetting)&&(identical(other.progressScope, progressScope) || other.progressScope == progressScope)&&(identical(other.fontFamily, fontFamily) || other.fontFamily == fontFamily)&&(identical(other.paragraphSpacing, paragraphSpacing) || other.paragraphSpacing == paragraphSpacing)&&(identical(other.letterSpacing, letterSpacing) || other.letterSpacing == letterSpacing)&&(identical(other.bodyBold, bodyBold) || other.bodyBold == bodyBold)&&(identical(other.bodyWeight, bodyWeight) || other.bodyWeight == bodyWeight)&&(identical(other.bodyAlign, bodyAlign) || other.bodyAlign == bodyAlign)&&(identical(other.bodyJustify, bodyJustify) || other.bodyJustify == bodyJustify)&&(identical(other.bodyIndent, bodyIndent) || other.bodyIndent == bodyIndent)&&(identical(other.headingStyle, headingStyle) || other.headingStyle == headingStyle)&&(identical(other.headingFontSize, headingFontSize) || other.headingFontSize == headingFontSize)&&(identical(other.headingBold, headingBold) || other.headingBold == headingBold)&&(identical(other.headingAlign, headingAlign) || other.headingAlign == headingAlign)&&(identical(other.headingMarginTop, headingMarginTop) || other.headingMarginTop == headingMarginTop)&&(identical(other.headingMarginBottom, headingMarginBottom) || other.headingMarginBottom == headingMarginBottom)&&(identical(other.doublePage, doublePage) || other.doublePage == doublePage)&&(identical(other.headerLeft, headerLeft) || other.headerLeft == headerLeft)&&(identical(other.headerCenter, headerCenter) || other.headerCenter == headerCenter)&&(identical(other.headerRight, headerRight) || other.headerRight == headerRight)&&(identical(other.headerFontSize, headerFontSize) || other.headerFontSize == headerFontSize)&&(identical(other.headerMarginTop, headerMarginTop) || other.headerMarginTop == headerMarginTop)&&(identical(other.headerMarginLeft, headerMarginLeft) || other.headerMarginLeft == headerMarginLeft)&&(identical(other.headerMarginRight, headerMarginRight) || other.headerMarginRight == headerMarginRight)&&(identical(other.footerLeft, footerLeft) || other.footerLeft == footerLeft)&&(identical(other.footerCenter, footerCenter) || other.footerCenter == footerCenter)&&(identical(other.footerRight, footerRight) || other.footerRight == footerRight)&&(identical(other.footerMarginLeft, footerMarginLeft) || other.footerMarginLeft == footerMarginLeft)&&(identical(other.footerMarginRight, footerMarginRight) || other.footerMarginRight == footerMarginRight)&&(identical(other.footerMarginBottom, footerMarginBottom) || other.footerMarginBottom == footerMarginBottom));
}


@override
int get hashCode => Object.hashAll([runtimeType,theme,backgroundImage,fontSize,lineHeight,marginLeft,marginRight,marginTop,marginBottom,flow,pageTurnMode,pageTurnSound,preciseTypesetting,progressScope,fontFamily,paragraphSpacing,letterSpacing,bodyBold,bodyWeight,bodyAlign,bodyJustify,bodyIndent,headingStyle,headingFontSize,headingBold,headingAlign,headingMarginTop,headingMarginBottom,doublePage,headerLeft,headerCenter,headerRight,headerFontSize,headerMarginTop,headerMarginLeft,headerMarginRight,footerLeft,footerCenter,footerRight,footerMarginLeft,footerMarginRight,footerMarginBottom]);

@override
String toString() {
  return 'ReadingSettings(theme: $theme, backgroundImage: $backgroundImage, fontSize: $fontSize, lineHeight: $lineHeight, marginLeft: $marginLeft, marginRight: $marginRight, marginTop: $marginTop, marginBottom: $marginBottom, flow: $flow, pageTurnMode: $pageTurnMode, pageTurnSound: $pageTurnSound, preciseTypesetting: $preciseTypesetting, progressScope: $progressScope, fontFamily: $fontFamily, paragraphSpacing: $paragraphSpacing, letterSpacing: $letterSpacing, bodyBold: $bodyBold, bodyWeight: $bodyWeight, bodyAlign: $bodyAlign, bodyJustify: $bodyJustify, bodyIndent: $bodyIndent, headingStyle: $headingStyle, headingFontSize: $headingFontSize, headingBold: $headingBold, headingAlign: $headingAlign, headingMarginTop: $headingMarginTop, headingMarginBottom: $headingMarginBottom, doublePage: $doublePage, headerLeft: $headerLeft, headerCenter: $headerCenter, headerRight: $headerRight, headerFontSize: $headerFontSize, headerMarginTop: $headerMarginTop, headerMarginLeft: $headerMarginLeft, headerMarginRight: $headerMarginRight, footerLeft: $footerLeft, footerCenter: $footerCenter, footerRight: $footerRight, footerMarginLeft: $footerMarginLeft, footerMarginRight: $footerMarginRight, footerMarginBottom: $footerMarginBottom)';
}


}

/// @nodoc
abstract mixin class $ReadingSettingsCopyWith<$Res>  {
  factory $ReadingSettingsCopyWith(ReadingSettings value, $Res Function(ReadingSettings) _then) = _$ReadingSettingsCopyWithImpl;
@useResult
$Res call({
 ReadingTheme theme, String backgroundImage, double fontSize, double lineHeight, double marginLeft, double marginRight, double marginTop, double marginBottom, ReadingFlow flow, PageTurnMode pageTurnMode, PageTurnSound pageTurnSound, bool preciseTypesetting, ProgressScope progressScope, String fontFamily, double paragraphSpacing, double letterSpacing, bool bodyBold, BodyFontWeight bodyWeight, TextAlignMode bodyAlign, bool bodyJustify, ParagraphIndent bodyIndent, HeadingStyle headingStyle, double headingFontSize, bool headingBold, TextAlignMode headingAlign, double headingMarginTop, double headingMarginBottom, bool doublePage, RunningContent headerLeft, RunningContent headerCenter, RunningContent headerRight, double headerFontSize, double headerMarginTop, double headerMarginLeft, double headerMarginRight, RunningContent footerLeft, RunningContent footerCenter, RunningContent footerRight, double footerMarginLeft, double footerMarginRight, double footerMarginBottom
});




}
/// @nodoc
class _$ReadingSettingsCopyWithImpl<$Res>
    implements $ReadingSettingsCopyWith<$Res> {
  _$ReadingSettingsCopyWithImpl(this._self, this._then);

  final ReadingSettings _self;
  final $Res Function(ReadingSettings) _then;

/// Create a copy of ReadingSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? theme = null,Object? backgroundImage = null,Object? fontSize = null,Object? lineHeight = null,Object? marginLeft = null,Object? marginRight = null,Object? marginTop = null,Object? marginBottom = null,Object? flow = null,Object? pageTurnMode = null,Object? pageTurnSound = null,Object? preciseTypesetting = null,Object? progressScope = null,Object? fontFamily = null,Object? paragraphSpacing = null,Object? letterSpacing = null,Object? bodyBold = null,Object? bodyWeight = null,Object? bodyAlign = null,Object? bodyJustify = null,Object? bodyIndent = null,Object? headingStyle = null,Object? headingFontSize = null,Object? headingBold = null,Object? headingAlign = null,Object? headingMarginTop = null,Object? headingMarginBottom = null,Object? doublePage = null,Object? headerLeft = null,Object? headerCenter = null,Object? headerRight = null,Object? headerFontSize = null,Object? headerMarginTop = null,Object? headerMarginLeft = null,Object? headerMarginRight = null,Object? footerLeft = null,Object? footerCenter = null,Object? footerRight = null,Object? footerMarginLeft = null,Object? footerMarginRight = null,Object? footerMarginBottom = null,}) {
  return _then(_self.copyWith(
theme: null == theme ? _self.theme : theme // ignore: cast_nullable_to_non_nullable
as ReadingTheme,backgroundImage: null == backgroundImage ? _self.backgroundImage : backgroundImage // ignore: cast_nullable_to_non_nullable
as String,fontSize: null == fontSize ? _self.fontSize : fontSize // ignore: cast_nullable_to_non_nullable
as double,lineHeight: null == lineHeight ? _self.lineHeight : lineHeight // ignore: cast_nullable_to_non_nullable
as double,marginLeft: null == marginLeft ? _self.marginLeft : marginLeft // ignore: cast_nullable_to_non_nullable
as double,marginRight: null == marginRight ? _self.marginRight : marginRight // ignore: cast_nullable_to_non_nullable
as double,marginTop: null == marginTop ? _self.marginTop : marginTop // ignore: cast_nullable_to_non_nullable
as double,marginBottom: null == marginBottom ? _self.marginBottom : marginBottom // ignore: cast_nullable_to_non_nullable
as double,flow: null == flow ? _self.flow : flow // ignore: cast_nullable_to_non_nullable
as ReadingFlow,pageTurnMode: null == pageTurnMode ? _self.pageTurnMode : pageTurnMode // ignore: cast_nullable_to_non_nullable
as PageTurnMode,pageTurnSound: null == pageTurnSound ? _self.pageTurnSound : pageTurnSound // ignore: cast_nullable_to_non_nullable
as PageTurnSound,preciseTypesetting: null == preciseTypesetting ? _self.preciseTypesetting : preciseTypesetting // ignore: cast_nullable_to_non_nullable
as bool,progressScope: null == progressScope ? _self.progressScope : progressScope // ignore: cast_nullable_to_non_nullable
as ProgressScope,fontFamily: null == fontFamily ? _self.fontFamily : fontFamily // ignore: cast_nullable_to_non_nullable
as String,paragraphSpacing: null == paragraphSpacing ? _self.paragraphSpacing : paragraphSpacing // ignore: cast_nullable_to_non_nullable
as double,letterSpacing: null == letterSpacing ? _self.letterSpacing : letterSpacing // ignore: cast_nullable_to_non_nullable
as double,bodyBold: null == bodyBold ? _self.bodyBold : bodyBold // ignore: cast_nullable_to_non_nullable
as bool,bodyWeight: null == bodyWeight ? _self.bodyWeight : bodyWeight // ignore: cast_nullable_to_non_nullable
as BodyFontWeight,bodyAlign: null == bodyAlign ? _self.bodyAlign : bodyAlign // ignore: cast_nullable_to_non_nullable
as TextAlignMode,bodyJustify: null == bodyJustify ? _self.bodyJustify : bodyJustify // ignore: cast_nullable_to_non_nullable
as bool,bodyIndent: null == bodyIndent ? _self.bodyIndent : bodyIndent // ignore: cast_nullable_to_non_nullable
as ParagraphIndent,headingStyle: null == headingStyle ? _self.headingStyle : headingStyle // ignore: cast_nullable_to_non_nullable
as HeadingStyle,headingFontSize: null == headingFontSize ? _self.headingFontSize : headingFontSize // ignore: cast_nullable_to_non_nullable
as double,headingBold: null == headingBold ? _self.headingBold : headingBold // ignore: cast_nullable_to_non_nullable
as bool,headingAlign: null == headingAlign ? _self.headingAlign : headingAlign // ignore: cast_nullable_to_non_nullable
as TextAlignMode,headingMarginTop: null == headingMarginTop ? _self.headingMarginTop : headingMarginTop // ignore: cast_nullable_to_non_nullable
as double,headingMarginBottom: null == headingMarginBottom ? _self.headingMarginBottom : headingMarginBottom // ignore: cast_nullable_to_non_nullable
as double,doublePage: null == doublePage ? _self.doublePage : doublePage // ignore: cast_nullable_to_non_nullable
as bool,headerLeft: null == headerLeft ? _self.headerLeft : headerLeft // ignore: cast_nullable_to_non_nullable
as RunningContent,headerCenter: null == headerCenter ? _self.headerCenter : headerCenter // ignore: cast_nullable_to_non_nullable
as RunningContent,headerRight: null == headerRight ? _self.headerRight : headerRight // ignore: cast_nullable_to_non_nullable
as RunningContent,headerFontSize: null == headerFontSize ? _self.headerFontSize : headerFontSize // ignore: cast_nullable_to_non_nullable
as double,headerMarginTop: null == headerMarginTop ? _self.headerMarginTop : headerMarginTop // ignore: cast_nullable_to_non_nullable
as double,headerMarginLeft: null == headerMarginLeft ? _self.headerMarginLeft : headerMarginLeft // ignore: cast_nullable_to_non_nullable
as double,headerMarginRight: null == headerMarginRight ? _self.headerMarginRight : headerMarginRight // ignore: cast_nullable_to_non_nullable
as double,footerLeft: null == footerLeft ? _self.footerLeft : footerLeft // ignore: cast_nullable_to_non_nullable
as RunningContent,footerCenter: null == footerCenter ? _self.footerCenter : footerCenter // ignore: cast_nullable_to_non_nullable
as RunningContent,footerRight: null == footerRight ? _self.footerRight : footerRight // ignore: cast_nullable_to_non_nullable
as RunningContent,footerMarginLeft: null == footerMarginLeft ? _self.footerMarginLeft : footerMarginLeft // ignore: cast_nullable_to_non_nullable
as double,footerMarginRight: null == footerMarginRight ? _self.footerMarginRight : footerMarginRight // ignore: cast_nullable_to_non_nullable
as double,footerMarginBottom: null == footerMarginBottom ? _self.footerMarginBottom : footerMarginBottom // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [ReadingSettings].
extension ReadingSettingsPatterns on ReadingSettings {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ReadingSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ReadingSettings() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ReadingSettings value)  $default,){
final _that = this;
switch (_that) {
case _ReadingSettings():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ReadingSettings value)?  $default,){
final _that = this;
switch (_that) {
case _ReadingSettings() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadingTheme theme,  String backgroundImage,  double fontSize,  double lineHeight,  double marginLeft,  double marginRight,  double marginTop,  double marginBottom,  ReadingFlow flow,  PageTurnMode pageTurnMode,  PageTurnSound pageTurnSound,  bool preciseTypesetting,  ProgressScope progressScope,  String fontFamily,  double paragraphSpacing,  double letterSpacing,  bool bodyBold,  BodyFontWeight bodyWeight,  TextAlignMode bodyAlign,  bool bodyJustify,  ParagraphIndent bodyIndent,  HeadingStyle headingStyle,  double headingFontSize,  bool headingBold,  TextAlignMode headingAlign,  double headingMarginTop,  double headingMarginBottom,  bool doublePage,  RunningContent headerLeft,  RunningContent headerCenter,  RunningContent headerRight,  double headerFontSize,  double headerMarginTop,  double headerMarginLeft,  double headerMarginRight,  RunningContent footerLeft,  RunningContent footerCenter,  RunningContent footerRight,  double footerMarginLeft,  double footerMarginRight,  double footerMarginBottom)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ReadingSettings() when $default != null:
return $default(_that.theme,_that.backgroundImage,_that.fontSize,_that.lineHeight,_that.marginLeft,_that.marginRight,_that.marginTop,_that.marginBottom,_that.flow,_that.pageTurnMode,_that.pageTurnSound,_that.preciseTypesetting,_that.progressScope,_that.fontFamily,_that.paragraphSpacing,_that.letterSpacing,_that.bodyBold,_that.bodyWeight,_that.bodyAlign,_that.bodyJustify,_that.bodyIndent,_that.headingStyle,_that.headingFontSize,_that.headingBold,_that.headingAlign,_that.headingMarginTop,_that.headingMarginBottom,_that.doublePage,_that.headerLeft,_that.headerCenter,_that.headerRight,_that.headerFontSize,_that.headerMarginTop,_that.headerMarginLeft,_that.headerMarginRight,_that.footerLeft,_that.footerCenter,_that.footerRight,_that.footerMarginLeft,_that.footerMarginRight,_that.footerMarginBottom);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadingTheme theme,  String backgroundImage,  double fontSize,  double lineHeight,  double marginLeft,  double marginRight,  double marginTop,  double marginBottom,  ReadingFlow flow,  PageTurnMode pageTurnMode,  PageTurnSound pageTurnSound,  bool preciseTypesetting,  ProgressScope progressScope,  String fontFamily,  double paragraphSpacing,  double letterSpacing,  bool bodyBold,  BodyFontWeight bodyWeight,  TextAlignMode bodyAlign,  bool bodyJustify,  ParagraphIndent bodyIndent,  HeadingStyle headingStyle,  double headingFontSize,  bool headingBold,  TextAlignMode headingAlign,  double headingMarginTop,  double headingMarginBottom,  bool doublePage,  RunningContent headerLeft,  RunningContent headerCenter,  RunningContent headerRight,  double headerFontSize,  double headerMarginTop,  double headerMarginLeft,  double headerMarginRight,  RunningContent footerLeft,  RunningContent footerCenter,  RunningContent footerRight,  double footerMarginLeft,  double footerMarginRight,  double footerMarginBottom)  $default,) {final _that = this;
switch (_that) {
case _ReadingSettings():
return $default(_that.theme,_that.backgroundImage,_that.fontSize,_that.lineHeight,_that.marginLeft,_that.marginRight,_that.marginTop,_that.marginBottom,_that.flow,_that.pageTurnMode,_that.pageTurnSound,_that.preciseTypesetting,_that.progressScope,_that.fontFamily,_that.paragraphSpacing,_that.letterSpacing,_that.bodyBold,_that.bodyWeight,_that.bodyAlign,_that.bodyJustify,_that.bodyIndent,_that.headingStyle,_that.headingFontSize,_that.headingBold,_that.headingAlign,_that.headingMarginTop,_that.headingMarginBottom,_that.doublePage,_that.headerLeft,_that.headerCenter,_that.headerRight,_that.headerFontSize,_that.headerMarginTop,_that.headerMarginLeft,_that.headerMarginRight,_that.footerLeft,_that.footerCenter,_that.footerRight,_that.footerMarginLeft,_that.footerMarginRight,_that.footerMarginBottom);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadingTheme theme,  String backgroundImage,  double fontSize,  double lineHeight,  double marginLeft,  double marginRight,  double marginTop,  double marginBottom,  ReadingFlow flow,  PageTurnMode pageTurnMode,  PageTurnSound pageTurnSound,  bool preciseTypesetting,  ProgressScope progressScope,  String fontFamily,  double paragraphSpacing,  double letterSpacing,  bool bodyBold,  BodyFontWeight bodyWeight,  TextAlignMode bodyAlign,  bool bodyJustify,  ParagraphIndent bodyIndent,  HeadingStyle headingStyle,  double headingFontSize,  bool headingBold,  TextAlignMode headingAlign,  double headingMarginTop,  double headingMarginBottom,  bool doublePage,  RunningContent headerLeft,  RunningContent headerCenter,  RunningContent headerRight,  double headerFontSize,  double headerMarginTop,  double headerMarginLeft,  double headerMarginRight,  RunningContent footerLeft,  RunningContent footerCenter,  RunningContent footerRight,  double footerMarginLeft,  double footerMarginRight,  double footerMarginBottom)?  $default,) {final _that = this;
switch (_that) {
case _ReadingSettings() when $default != null:
return $default(_that.theme,_that.backgroundImage,_that.fontSize,_that.lineHeight,_that.marginLeft,_that.marginRight,_that.marginTop,_that.marginBottom,_that.flow,_that.pageTurnMode,_that.pageTurnSound,_that.preciseTypesetting,_that.progressScope,_that.fontFamily,_that.paragraphSpacing,_that.letterSpacing,_that.bodyBold,_that.bodyWeight,_that.bodyAlign,_that.bodyJustify,_that.bodyIndent,_that.headingStyle,_that.headingFontSize,_that.headingBold,_that.headingAlign,_that.headingMarginTop,_that.headingMarginBottom,_that.doublePage,_that.headerLeft,_that.headerCenter,_that.headerRight,_that.headerFontSize,_that.headerMarginTop,_that.headerMarginLeft,_that.headerMarginRight,_that.footerLeft,_that.footerCenter,_that.footerRight,_that.footerMarginLeft,_that.footerMarginRight,_that.footerMarginBottom);case _:
  return null;

}
}

}

/// @nodoc


class _ReadingSettings implements ReadingSettings {
  const _ReadingSettings({this.theme = ReadingTheme.paper, this.backgroundImage = '', this.fontSize = 18.0, this.lineHeight = 1.7, this.marginLeft = 16.0, this.marginRight = 16.0, this.marginTop = 12.0, this.marginBottom = 12.0, this.flow = ReadingFlow.paginated, this.pageTurnMode = PageTurnMode.slide, this.pageTurnSound = PageTurnSound.first, this.preciseTypesetting = false, this.progressScope = ProgressScope.book, this.fontFamily = '', this.paragraphSpacing = 0.4, this.letterSpacing = 0.0, this.bodyBold = false, this.bodyWeight = BodyFontWeight.normal, this.bodyAlign = TextAlignMode.auto, this.bodyJustify = true, this.bodyIndent = ParagraphIndent.auto, this.headingStyle = HeadingStyle.plain, this.headingFontSize = 24.0, this.headingBold = true, this.headingAlign = TextAlignMode.center, this.headingMarginTop = 18.0, this.headingMarginBottom = 12.0, this.doublePage = false, this.headerLeft = RunningContent.none, this.headerCenter = RunningContent.none, this.headerRight = RunningContent.none, this.headerFontSize = 10.0, this.headerMarginTop = 6.0, this.headerMarginLeft = 16.0, this.headerMarginRight = 16.0, this.footerLeft = RunningContent.none, this.footerCenter = RunningContent.none, this.footerRight = RunningContent.none, this.footerMarginLeft = 16.0, this.footerMarginRight = 16.0, this.footerMarginBottom = 6.0});
  

/// 阅读主题。
@override@JsonKey() final  ReadingTheme theme;
/// 自定义阅读背景图（应用内文件路径）；空 = 纯色纸面。
@override@JsonKey() final  String backgroundImage;
/// 正文字号（14..28）。
@override@JsonKey() final  double fontSize;
/// 行距倍数（1.2..2.4）。
@override@JsonKey() final  double lineHeight;
/// 左边距（0..64，不含系统安全区）。
@override@JsonKey() final  double marginLeft;
/// 右边距（0..64，不含系统安全区）。
@override@JsonKey() final  double marginRight;
/// 上边距（0..64，不含状态栏安全区）。
@override@JsonKey() final  double marginTop;
/// 下边距（0..64，不含导航栏安全区）。
@override@JsonKey() final  double marginBottom;
/// 排版流向。
@override@JsonKey() final  ReadingFlow flow;
/// 翻页动画模式。
@override@JsonKey() final  PageTurnMode pageTurnMode;
/// 翻页音效（默认书页；选「无」静音）。
@override@JsonKey() final  PageTurnSound pageTurnSound;
/// 精排：保留书籍自身的排版样式。
///
/// 关（默认）= 阅读器统一接管字号/行距/颜色，各家 EPUB 观感一致；
/// 开 = 只有主题底色参与，字号/行距/段落缩进/标题样式全部交给书籍
/// 自带的 CSS（"精排"）。适合排版讲究的书，也可能被粗糙的 CSS 弄乱，
/// 所以做成开关而不是默认开启。
@override@JsonKey() final  bool preciseTypesetting;
/// 底部进度条显示的是全书进度还是本章进度。
@override@JsonKey() final  ProgressScope progressScope;
/// 阅读字体：导入字体的 family 键（`qyfont_xxx`）；空 = 系统默认。
///
/// 存 family 而不是文件路径：字体文件由字体库统一管理（可删除/重导），
/// 设置里只记「用哪一个」。
@override@JsonKey() final  String fontFamily;
// ---------- 正文 ----------
/// 段间距（以字号为单位的倍数，0..2）。
@override@JsonKey() final  double paragraphSpacing;
/// 字间距（逻辑像素，-1..6）。
@override@JsonKey() final  double letterSpacing;
/// 正文加粗（等价于把字重抬到 700）。
@override@JsonKey() final  bool bodyBold;
/// 正文字重。
@override@JsonKey() final  BodyFontWeight bodyWeight;
/// 正文对齐。
@override@JsonKey() final  TextAlignMode bodyAlign;
/// 两端对齐（正文列尾对齐；居中/右对齐时以对齐设置为准）。
@override@JsonKey() final  bool bodyJustify;
/// 段落首行缩进。
@override@JsonKey() final  ParagraphIndent bodyIndent;
// ---------- 标题 ----------
/// 标题装饰样式。
@override@JsonKey() final  HeadingStyle headingStyle;
/// 标题字号（16..40）。
@override@JsonKey() final  double headingFontSize;
/// 标题加粗。
@override@JsonKey() final  bool headingBold;
/// 标题对齐。
@override@JsonKey() final  TextAlignMode headingAlign;
/// 标题上边距（逻辑像素）。
@override@JsonKey() final  double headingMarginTop;
/// 标题下边距（逻辑像素）。
@override@JsonKey() final  double headingMarginBottom;
// ---------- 页面 ----------
/// 单双页：开 = 每屏左右两页（书本摊开）。
@override@JsonKey() final  bool doublePage;
// ---------- 页眉 ----------
/// 页眉左槽内容。
@override@JsonKey() final  RunningContent headerLeft;
/// 页眉中槽内容。
@override@JsonKey() final  RunningContent headerCenter;
/// 页眉右槽内容。
@override@JsonKey() final  RunningContent headerRight;
/// 页眉字号（8..16，页脚同用）。
@override@JsonKey() final  double headerFontSize;
/// 页眉上边距。
@override@JsonKey() final  double headerMarginTop;
/// 页眉左边距。
@override@JsonKey() final  double headerMarginLeft;
/// 页眉右边距。
@override@JsonKey() final  double headerMarginRight;
// ---------- 页脚 ----------
/// 页脚左槽内容。
@override@JsonKey() final  RunningContent footerLeft;
/// 页脚中槽内容。
@override@JsonKey() final  RunningContent footerCenter;
/// 页脚右槽内容。
@override@JsonKey() final  RunningContent footerRight;
/// 页脚左边距。
@override@JsonKey() final  double footerMarginLeft;
/// 页脚右边距。
@override@JsonKey() final  double footerMarginRight;
/// 页脚下边距。
@override@JsonKey() final  double footerMarginBottom;

/// Create a copy of ReadingSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ReadingSettingsCopyWith<_ReadingSettings> get copyWith => __$ReadingSettingsCopyWithImpl<_ReadingSettings>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ReadingSettings&&(identical(other.theme, theme) || other.theme == theme)&&(identical(other.backgroundImage, backgroundImage) || other.backgroundImage == backgroundImage)&&(identical(other.fontSize, fontSize) || other.fontSize == fontSize)&&(identical(other.lineHeight, lineHeight) || other.lineHeight == lineHeight)&&(identical(other.marginLeft, marginLeft) || other.marginLeft == marginLeft)&&(identical(other.marginRight, marginRight) || other.marginRight == marginRight)&&(identical(other.marginTop, marginTop) || other.marginTop == marginTop)&&(identical(other.marginBottom, marginBottom) || other.marginBottom == marginBottom)&&(identical(other.flow, flow) || other.flow == flow)&&(identical(other.pageTurnMode, pageTurnMode) || other.pageTurnMode == pageTurnMode)&&(identical(other.pageTurnSound, pageTurnSound) || other.pageTurnSound == pageTurnSound)&&(identical(other.preciseTypesetting, preciseTypesetting) || other.preciseTypesetting == preciseTypesetting)&&(identical(other.progressScope, progressScope) || other.progressScope == progressScope)&&(identical(other.fontFamily, fontFamily) || other.fontFamily == fontFamily)&&(identical(other.paragraphSpacing, paragraphSpacing) || other.paragraphSpacing == paragraphSpacing)&&(identical(other.letterSpacing, letterSpacing) || other.letterSpacing == letterSpacing)&&(identical(other.bodyBold, bodyBold) || other.bodyBold == bodyBold)&&(identical(other.bodyWeight, bodyWeight) || other.bodyWeight == bodyWeight)&&(identical(other.bodyAlign, bodyAlign) || other.bodyAlign == bodyAlign)&&(identical(other.bodyJustify, bodyJustify) || other.bodyJustify == bodyJustify)&&(identical(other.bodyIndent, bodyIndent) || other.bodyIndent == bodyIndent)&&(identical(other.headingStyle, headingStyle) || other.headingStyle == headingStyle)&&(identical(other.headingFontSize, headingFontSize) || other.headingFontSize == headingFontSize)&&(identical(other.headingBold, headingBold) || other.headingBold == headingBold)&&(identical(other.headingAlign, headingAlign) || other.headingAlign == headingAlign)&&(identical(other.headingMarginTop, headingMarginTop) || other.headingMarginTop == headingMarginTop)&&(identical(other.headingMarginBottom, headingMarginBottom) || other.headingMarginBottom == headingMarginBottom)&&(identical(other.doublePage, doublePage) || other.doublePage == doublePage)&&(identical(other.headerLeft, headerLeft) || other.headerLeft == headerLeft)&&(identical(other.headerCenter, headerCenter) || other.headerCenter == headerCenter)&&(identical(other.headerRight, headerRight) || other.headerRight == headerRight)&&(identical(other.headerFontSize, headerFontSize) || other.headerFontSize == headerFontSize)&&(identical(other.headerMarginTop, headerMarginTop) || other.headerMarginTop == headerMarginTop)&&(identical(other.headerMarginLeft, headerMarginLeft) || other.headerMarginLeft == headerMarginLeft)&&(identical(other.headerMarginRight, headerMarginRight) || other.headerMarginRight == headerMarginRight)&&(identical(other.footerLeft, footerLeft) || other.footerLeft == footerLeft)&&(identical(other.footerCenter, footerCenter) || other.footerCenter == footerCenter)&&(identical(other.footerRight, footerRight) || other.footerRight == footerRight)&&(identical(other.footerMarginLeft, footerMarginLeft) || other.footerMarginLeft == footerMarginLeft)&&(identical(other.footerMarginRight, footerMarginRight) || other.footerMarginRight == footerMarginRight)&&(identical(other.footerMarginBottom, footerMarginBottom) || other.footerMarginBottom == footerMarginBottom));
}


@override
int get hashCode => Object.hashAll([runtimeType,theme,backgroundImage,fontSize,lineHeight,marginLeft,marginRight,marginTop,marginBottom,flow,pageTurnMode,pageTurnSound,preciseTypesetting,progressScope,fontFamily,paragraphSpacing,letterSpacing,bodyBold,bodyWeight,bodyAlign,bodyJustify,bodyIndent,headingStyle,headingFontSize,headingBold,headingAlign,headingMarginTop,headingMarginBottom,doublePage,headerLeft,headerCenter,headerRight,headerFontSize,headerMarginTop,headerMarginLeft,headerMarginRight,footerLeft,footerCenter,footerRight,footerMarginLeft,footerMarginRight,footerMarginBottom]);

@override
String toString() {
  return 'ReadingSettings(theme: $theme, backgroundImage: $backgroundImage, fontSize: $fontSize, lineHeight: $lineHeight, marginLeft: $marginLeft, marginRight: $marginRight, marginTop: $marginTop, marginBottom: $marginBottom, flow: $flow, pageTurnMode: $pageTurnMode, pageTurnSound: $pageTurnSound, preciseTypesetting: $preciseTypesetting, progressScope: $progressScope, fontFamily: $fontFamily, paragraphSpacing: $paragraphSpacing, letterSpacing: $letterSpacing, bodyBold: $bodyBold, bodyWeight: $bodyWeight, bodyAlign: $bodyAlign, bodyJustify: $bodyJustify, bodyIndent: $bodyIndent, headingStyle: $headingStyle, headingFontSize: $headingFontSize, headingBold: $headingBold, headingAlign: $headingAlign, headingMarginTop: $headingMarginTop, headingMarginBottom: $headingMarginBottom, doublePage: $doublePage, headerLeft: $headerLeft, headerCenter: $headerCenter, headerRight: $headerRight, headerFontSize: $headerFontSize, headerMarginTop: $headerMarginTop, headerMarginLeft: $headerMarginLeft, headerMarginRight: $headerMarginRight, footerLeft: $footerLeft, footerCenter: $footerCenter, footerRight: $footerRight, footerMarginLeft: $footerMarginLeft, footerMarginRight: $footerMarginRight, footerMarginBottom: $footerMarginBottom)';
}


}

/// @nodoc
abstract mixin class _$ReadingSettingsCopyWith<$Res> implements $ReadingSettingsCopyWith<$Res> {
  factory _$ReadingSettingsCopyWith(_ReadingSettings value, $Res Function(_ReadingSettings) _then) = __$ReadingSettingsCopyWithImpl;
@override @useResult
$Res call({
 ReadingTheme theme, String backgroundImage, double fontSize, double lineHeight, double marginLeft, double marginRight, double marginTop, double marginBottom, ReadingFlow flow, PageTurnMode pageTurnMode, PageTurnSound pageTurnSound, bool preciseTypesetting, ProgressScope progressScope, String fontFamily, double paragraphSpacing, double letterSpacing, bool bodyBold, BodyFontWeight bodyWeight, TextAlignMode bodyAlign, bool bodyJustify, ParagraphIndent bodyIndent, HeadingStyle headingStyle, double headingFontSize, bool headingBold, TextAlignMode headingAlign, double headingMarginTop, double headingMarginBottom, bool doublePage, RunningContent headerLeft, RunningContent headerCenter, RunningContent headerRight, double headerFontSize, double headerMarginTop, double headerMarginLeft, double headerMarginRight, RunningContent footerLeft, RunningContent footerCenter, RunningContent footerRight, double footerMarginLeft, double footerMarginRight, double footerMarginBottom
});




}
/// @nodoc
class __$ReadingSettingsCopyWithImpl<$Res>
    implements _$ReadingSettingsCopyWith<$Res> {
  __$ReadingSettingsCopyWithImpl(this._self, this._then);

  final _ReadingSettings _self;
  final $Res Function(_ReadingSettings) _then;

/// Create a copy of ReadingSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? theme = null,Object? backgroundImage = null,Object? fontSize = null,Object? lineHeight = null,Object? marginLeft = null,Object? marginRight = null,Object? marginTop = null,Object? marginBottom = null,Object? flow = null,Object? pageTurnMode = null,Object? pageTurnSound = null,Object? preciseTypesetting = null,Object? progressScope = null,Object? fontFamily = null,Object? paragraphSpacing = null,Object? letterSpacing = null,Object? bodyBold = null,Object? bodyWeight = null,Object? bodyAlign = null,Object? bodyJustify = null,Object? bodyIndent = null,Object? headingStyle = null,Object? headingFontSize = null,Object? headingBold = null,Object? headingAlign = null,Object? headingMarginTop = null,Object? headingMarginBottom = null,Object? doublePage = null,Object? headerLeft = null,Object? headerCenter = null,Object? headerRight = null,Object? headerFontSize = null,Object? headerMarginTop = null,Object? headerMarginLeft = null,Object? headerMarginRight = null,Object? footerLeft = null,Object? footerCenter = null,Object? footerRight = null,Object? footerMarginLeft = null,Object? footerMarginRight = null,Object? footerMarginBottom = null,}) {
  return _then(_ReadingSettings(
theme: null == theme ? _self.theme : theme // ignore: cast_nullable_to_non_nullable
as ReadingTheme,backgroundImage: null == backgroundImage ? _self.backgroundImage : backgroundImage // ignore: cast_nullable_to_non_nullable
as String,fontSize: null == fontSize ? _self.fontSize : fontSize // ignore: cast_nullable_to_non_nullable
as double,lineHeight: null == lineHeight ? _self.lineHeight : lineHeight // ignore: cast_nullable_to_non_nullable
as double,marginLeft: null == marginLeft ? _self.marginLeft : marginLeft // ignore: cast_nullable_to_non_nullable
as double,marginRight: null == marginRight ? _self.marginRight : marginRight // ignore: cast_nullable_to_non_nullable
as double,marginTop: null == marginTop ? _self.marginTop : marginTop // ignore: cast_nullable_to_non_nullable
as double,marginBottom: null == marginBottom ? _self.marginBottom : marginBottom // ignore: cast_nullable_to_non_nullable
as double,flow: null == flow ? _self.flow : flow // ignore: cast_nullable_to_non_nullable
as ReadingFlow,pageTurnMode: null == pageTurnMode ? _self.pageTurnMode : pageTurnMode // ignore: cast_nullable_to_non_nullable
as PageTurnMode,pageTurnSound: null == pageTurnSound ? _self.pageTurnSound : pageTurnSound // ignore: cast_nullable_to_non_nullable
as PageTurnSound,preciseTypesetting: null == preciseTypesetting ? _self.preciseTypesetting : preciseTypesetting // ignore: cast_nullable_to_non_nullable
as bool,progressScope: null == progressScope ? _self.progressScope : progressScope // ignore: cast_nullable_to_non_nullable
as ProgressScope,fontFamily: null == fontFamily ? _self.fontFamily : fontFamily // ignore: cast_nullable_to_non_nullable
as String,paragraphSpacing: null == paragraphSpacing ? _self.paragraphSpacing : paragraphSpacing // ignore: cast_nullable_to_non_nullable
as double,letterSpacing: null == letterSpacing ? _self.letterSpacing : letterSpacing // ignore: cast_nullable_to_non_nullable
as double,bodyBold: null == bodyBold ? _self.bodyBold : bodyBold // ignore: cast_nullable_to_non_nullable
as bool,bodyWeight: null == bodyWeight ? _self.bodyWeight : bodyWeight // ignore: cast_nullable_to_non_nullable
as BodyFontWeight,bodyAlign: null == bodyAlign ? _self.bodyAlign : bodyAlign // ignore: cast_nullable_to_non_nullable
as TextAlignMode,bodyJustify: null == bodyJustify ? _self.bodyJustify : bodyJustify // ignore: cast_nullable_to_non_nullable
as bool,bodyIndent: null == bodyIndent ? _self.bodyIndent : bodyIndent // ignore: cast_nullable_to_non_nullable
as ParagraphIndent,headingStyle: null == headingStyle ? _self.headingStyle : headingStyle // ignore: cast_nullable_to_non_nullable
as HeadingStyle,headingFontSize: null == headingFontSize ? _self.headingFontSize : headingFontSize // ignore: cast_nullable_to_non_nullable
as double,headingBold: null == headingBold ? _self.headingBold : headingBold // ignore: cast_nullable_to_non_nullable
as bool,headingAlign: null == headingAlign ? _self.headingAlign : headingAlign // ignore: cast_nullable_to_non_nullable
as TextAlignMode,headingMarginTop: null == headingMarginTop ? _self.headingMarginTop : headingMarginTop // ignore: cast_nullable_to_non_nullable
as double,headingMarginBottom: null == headingMarginBottom ? _self.headingMarginBottom : headingMarginBottom // ignore: cast_nullable_to_non_nullable
as double,doublePage: null == doublePage ? _self.doublePage : doublePage // ignore: cast_nullable_to_non_nullable
as bool,headerLeft: null == headerLeft ? _self.headerLeft : headerLeft // ignore: cast_nullable_to_non_nullable
as RunningContent,headerCenter: null == headerCenter ? _self.headerCenter : headerCenter // ignore: cast_nullable_to_non_nullable
as RunningContent,headerRight: null == headerRight ? _self.headerRight : headerRight // ignore: cast_nullable_to_non_nullable
as RunningContent,headerFontSize: null == headerFontSize ? _self.headerFontSize : headerFontSize // ignore: cast_nullable_to_non_nullable
as double,headerMarginTop: null == headerMarginTop ? _self.headerMarginTop : headerMarginTop // ignore: cast_nullable_to_non_nullable
as double,headerMarginLeft: null == headerMarginLeft ? _self.headerMarginLeft : headerMarginLeft // ignore: cast_nullable_to_non_nullable
as double,headerMarginRight: null == headerMarginRight ? _self.headerMarginRight : headerMarginRight // ignore: cast_nullable_to_non_nullable
as double,footerLeft: null == footerLeft ? _self.footerLeft : footerLeft // ignore: cast_nullable_to_non_nullable
as RunningContent,footerCenter: null == footerCenter ? _self.footerCenter : footerCenter // ignore: cast_nullable_to_non_nullable
as RunningContent,footerRight: null == footerRight ? _self.footerRight : footerRight // ignore: cast_nullable_to_non_nullable
as RunningContent,footerMarginLeft: null == footerMarginLeft ? _self.footerMarginLeft : footerMarginLeft // ignore: cast_nullable_to_non_nullable
as double,footerMarginRight: null == footerMarginRight ? _self.footerMarginRight : footerMarginRight // ignore: cast_nullable_to_non_nullable
as double,footerMarginBottom: null == footerMarginBottom ? _self.footerMarginBottom : footerMarginBottom // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

// dart format on
