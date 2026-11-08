// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'tts_settings.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TtsSettings {

/// 倍速 0.5..2.0（1.0 为正常语速）。
 double get rate;/// 音色名（flutter_tts voice.name）；null = 系统默认。
 String? get voiceName;/// 音色 locale（与 voiceName 配对，setVoice 需要）。
 String? get voiceLocale;/// 定时停止分钟数；0 = 不定时。
 int get timerMinutes;
/// Create a copy of TtsSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TtsSettingsCopyWith<TtsSettings> get copyWith => _$TtsSettingsCopyWithImpl<TtsSettings>(this as TtsSettings, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TtsSettings&&(identical(other.rate, rate) || other.rate == rate)&&(identical(other.voiceName, voiceName) || other.voiceName == voiceName)&&(identical(other.voiceLocale, voiceLocale) || other.voiceLocale == voiceLocale)&&(identical(other.timerMinutes, timerMinutes) || other.timerMinutes == timerMinutes));
}


@override
int get hashCode => Object.hash(runtimeType,rate,voiceName,voiceLocale,timerMinutes);

@override
String toString() {
  return 'TtsSettings(rate: $rate, voiceName: $voiceName, voiceLocale: $voiceLocale, timerMinutes: $timerMinutes)';
}


}

/// @nodoc
abstract mixin class $TtsSettingsCopyWith<$Res>  {
  factory $TtsSettingsCopyWith(TtsSettings value, $Res Function(TtsSettings) _then) = _$TtsSettingsCopyWithImpl;
@useResult
$Res call({
 double rate, String? voiceName, String? voiceLocale, int timerMinutes
});




}
/// @nodoc
class _$TtsSettingsCopyWithImpl<$Res>
    implements $TtsSettingsCopyWith<$Res> {
  _$TtsSettingsCopyWithImpl(this._self, this._then);

  final TtsSettings _self;
  final $Res Function(TtsSettings) _then;

/// Create a copy of TtsSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? rate = null,Object? voiceName = freezed,Object? voiceLocale = freezed,Object? timerMinutes = null,}) {
  return _then(_self.copyWith(
rate: null == rate ? _self.rate : rate // ignore: cast_nullable_to_non_nullable
as double,voiceName: freezed == voiceName ? _self.voiceName : voiceName // ignore: cast_nullable_to_non_nullable
as String?,voiceLocale: freezed == voiceLocale ? _self.voiceLocale : voiceLocale // ignore: cast_nullable_to_non_nullable
as String?,timerMinutes: null == timerMinutes ? _self.timerMinutes : timerMinutes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [TtsSettings].
extension TtsSettingsPatterns on TtsSettings {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TtsSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TtsSettings() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TtsSettings value)  $default,){
final _that = this;
switch (_that) {
case _TtsSettings():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TtsSettings value)?  $default,){
final _that = this;
switch (_that) {
case _TtsSettings() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( double rate,  String? voiceName,  String? voiceLocale,  int timerMinutes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TtsSettings() when $default != null:
return $default(_that.rate,_that.voiceName,_that.voiceLocale,_that.timerMinutes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( double rate,  String? voiceName,  String? voiceLocale,  int timerMinutes)  $default,) {final _that = this;
switch (_that) {
case _TtsSettings():
return $default(_that.rate,_that.voiceName,_that.voiceLocale,_that.timerMinutes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( double rate,  String? voiceName,  String? voiceLocale,  int timerMinutes)?  $default,) {final _that = this;
switch (_that) {
case _TtsSettings() when $default != null:
return $default(_that.rate,_that.voiceName,_that.voiceLocale,_that.timerMinutes);case _:
  return null;

}
}

}

/// @nodoc


class _TtsSettings implements TtsSettings {
  const _TtsSettings({this.rate = 1.0, this.voiceName, this.voiceLocale, this.timerMinutes = 0});
  

/// 倍速 0.5..2.0（1.0 为正常语速）。
@override@JsonKey() final  double rate;
/// 音色名（flutter_tts voice.name）；null = 系统默认。
@override final  String? voiceName;
/// 音色 locale（与 voiceName 配对，setVoice 需要）。
@override final  String? voiceLocale;
/// 定时停止分钟数；0 = 不定时。
@override@JsonKey() final  int timerMinutes;

/// Create a copy of TtsSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TtsSettingsCopyWith<_TtsSettings> get copyWith => __$TtsSettingsCopyWithImpl<_TtsSettings>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TtsSettings&&(identical(other.rate, rate) || other.rate == rate)&&(identical(other.voiceName, voiceName) || other.voiceName == voiceName)&&(identical(other.voiceLocale, voiceLocale) || other.voiceLocale == voiceLocale)&&(identical(other.timerMinutes, timerMinutes) || other.timerMinutes == timerMinutes));
}


@override
int get hashCode => Object.hash(runtimeType,rate,voiceName,voiceLocale,timerMinutes);

@override
String toString() {
  return 'TtsSettings(rate: $rate, voiceName: $voiceName, voiceLocale: $voiceLocale, timerMinutes: $timerMinutes)';
}


}

/// @nodoc
abstract mixin class _$TtsSettingsCopyWith<$Res> implements $TtsSettingsCopyWith<$Res> {
  factory _$TtsSettingsCopyWith(_TtsSettings value, $Res Function(_TtsSettings) _then) = __$TtsSettingsCopyWithImpl;
@override @useResult
$Res call({
 double rate, String? voiceName, String? voiceLocale, int timerMinutes
});




}
/// @nodoc
class __$TtsSettingsCopyWithImpl<$Res>
    implements _$TtsSettingsCopyWith<$Res> {
  __$TtsSettingsCopyWithImpl(this._self, this._then);

  final _TtsSettings _self;
  final $Res Function(_TtsSettings) _then;

/// Create a copy of TtsSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? rate = null,Object? voiceName = freezed,Object? voiceLocale = freezed,Object? timerMinutes = null,}) {
  return _then(_TtsSettings(
rate: null == rate ? _self.rate : rate // ignore: cast_nullable_to_non_nullable
as double,voiceName: freezed == voiceName ? _self.voiceName : voiceName // ignore: cast_nullable_to_non_nullable
as String?,voiceLocale: freezed == voiceLocale ? _self.voiceLocale : voiceLocale // ignore: cast_nullable_to_non_nullable
as String?,timerMinutes: null == timerMinutes ? _self.timerMinutes : timerMinutes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
