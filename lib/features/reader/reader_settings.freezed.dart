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
 ReadingTheme get theme;/// 正文字号（14..28）。
 double get fontSize;/// 行距倍数（1.2..2.4）。
 double get lineHeight;/// 左右边距（0..48）。
 double get margin;/// 排版流向。
 ReadingFlow get flow;/// 翻页动画模式。
 PageTurnMode get pageTurnMode;
/// Create a copy of ReadingSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadingSettingsCopyWith<ReadingSettings> get copyWith => _$ReadingSettingsCopyWithImpl<ReadingSettings>(this as ReadingSettings, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadingSettings&&(identical(other.theme, theme) || other.theme == theme)&&(identical(other.fontSize, fontSize) || other.fontSize == fontSize)&&(identical(other.lineHeight, lineHeight) || other.lineHeight == lineHeight)&&(identical(other.margin, margin) || other.margin == margin)&&(identical(other.flow, flow) || other.flow == flow)&&(identical(other.pageTurnMode, pageTurnMode) || other.pageTurnMode == pageTurnMode));
}


@override
int get hashCode => Object.hash(runtimeType,theme,fontSize,lineHeight,margin,flow,pageTurnMode);

@override
String toString() {
  return 'ReadingSettings(theme: $theme, fontSize: $fontSize, lineHeight: $lineHeight, margin: $margin, flow: $flow, pageTurnMode: $pageTurnMode)';
}


}

/// @nodoc
abstract mixin class $ReadingSettingsCopyWith<$Res>  {
  factory $ReadingSettingsCopyWith(ReadingSettings value, $Res Function(ReadingSettings) _then) = _$ReadingSettingsCopyWithImpl;
@useResult
$Res call({
 ReadingTheme theme, double fontSize, double lineHeight, double margin, ReadingFlow flow, PageTurnMode pageTurnMode
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
@pragma('vm:prefer-inline') @override $Res call({Object? theme = null,Object? fontSize = null,Object? lineHeight = null,Object? margin = null,Object? flow = null,Object? pageTurnMode = null,}) {
  return _then(_self.copyWith(
theme: null == theme ? _self.theme : theme // ignore: cast_nullable_to_non_nullable
as ReadingTheme,fontSize: null == fontSize ? _self.fontSize : fontSize // ignore: cast_nullable_to_non_nullable
as double,lineHeight: null == lineHeight ? _self.lineHeight : lineHeight // ignore: cast_nullable_to_non_nullable
as double,margin: null == margin ? _self.margin : margin // ignore: cast_nullable_to_non_nullable
as double,flow: null == flow ? _self.flow : flow // ignore: cast_nullable_to_non_nullable
as ReadingFlow,pageTurnMode: null == pageTurnMode ? _self.pageTurnMode : pageTurnMode // ignore: cast_nullable_to_non_nullable
as PageTurnMode,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadingTheme theme,  double fontSize,  double lineHeight,  double margin,  ReadingFlow flow,  PageTurnMode pageTurnMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ReadingSettings() when $default != null:
return $default(_that.theme,_that.fontSize,_that.lineHeight,_that.margin,_that.flow,_that.pageTurnMode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadingTheme theme,  double fontSize,  double lineHeight,  double margin,  ReadingFlow flow,  PageTurnMode pageTurnMode)  $default,) {final _that = this;
switch (_that) {
case _ReadingSettings():
return $default(_that.theme,_that.fontSize,_that.lineHeight,_that.margin,_that.flow,_that.pageTurnMode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadingTheme theme,  double fontSize,  double lineHeight,  double margin,  ReadingFlow flow,  PageTurnMode pageTurnMode)?  $default,) {final _that = this;
switch (_that) {
case _ReadingSettings() when $default != null:
return $default(_that.theme,_that.fontSize,_that.lineHeight,_that.margin,_that.flow,_that.pageTurnMode);case _:
  return null;

}
}

}

/// @nodoc


class _ReadingSettings implements ReadingSettings {
  const _ReadingSettings({this.theme = ReadingTheme.paper, this.fontSize = 18.0, this.lineHeight = 1.7, this.margin = 16.0, this.flow = ReadingFlow.paginated, this.pageTurnMode = PageTurnMode.slide});
  

/// 阅读主题。
@override@JsonKey() final  ReadingTheme theme;
/// 正文字号（14..28）。
@override@JsonKey() final  double fontSize;
/// 行距倍数（1.2..2.4）。
@override@JsonKey() final  double lineHeight;
/// 左右边距（0..48）。
@override@JsonKey() final  double margin;
/// 排版流向。
@override@JsonKey() final  ReadingFlow flow;
/// 翻页动画模式。
@override@JsonKey() final  PageTurnMode pageTurnMode;

/// Create a copy of ReadingSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ReadingSettingsCopyWith<_ReadingSettings> get copyWith => __$ReadingSettingsCopyWithImpl<_ReadingSettings>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ReadingSettings&&(identical(other.theme, theme) || other.theme == theme)&&(identical(other.fontSize, fontSize) || other.fontSize == fontSize)&&(identical(other.lineHeight, lineHeight) || other.lineHeight == lineHeight)&&(identical(other.margin, margin) || other.margin == margin)&&(identical(other.flow, flow) || other.flow == flow)&&(identical(other.pageTurnMode, pageTurnMode) || other.pageTurnMode == pageTurnMode));
}


@override
int get hashCode => Object.hash(runtimeType,theme,fontSize,lineHeight,margin,flow,pageTurnMode);

@override
String toString() {
  return 'ReadingSettings(theme: $theme, fontSize: $fontSize, lineHeight: $lineHeight, margin: $margin, flow: $flow, pageTurnMode: $pageTurnMode)';
}


}

/// @nodoc
abstract mixin class _$ReadingSettingsCopyWith<$Res> implements $ReadingSettingsCopyWith<$Res> {
  factory _$ReadingSettingsCopyWith(_ReadingSettings value, $Res Function(_ReadingSettings) _then) = __$ReadingSettingsCopyWithImpl;
@override @useResult
$Res call({
 ReadingTheme theme, double fontSize, double lineHeight, double margin, ReadingFlow flow, PageTurnMode pageTurnMode
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
@override @pragma('vm:prefer-inline') $Res call({Object? theme = null,Object? fontSize = null,Object? lineHeight = null,Object? margin = null,Object? flow = null,Object? pageTurnMode = null,}) {
  return _then(_ReadingSettings(
theme: null == theme ? _self.theme : theme // ignore: cast_nullable_to_non_nullable
as ReadingTheme,fontSize: null == fontSize ? _self.fontSize : fontSize // ignore: cast_nullable_to_non_nullable
as double,lineHeight: null == lineHeight ? _self.lineHeight : lineHeight // ignore: cast_nullable_to_non_nullable
as double,margin: null == margin ? _self.margin : margin // ignore: cast_nullable_to_non_nullable
as double,flow: null == flow ? _self.flow : flow // ignore: cast_nullable_to_non_nullable
as ReadingFlow,pageTurnMode: null == pageTurnMode ? _self.pageTurnMode : pageTurnMode // ignore: cast_nullable_to_non_nullable
as PageTurnMode,
  ));
}


}

// dart format on
