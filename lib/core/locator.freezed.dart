// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'locator.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Locator {

/// 格式版本，当前恒为 1。
 int get v;/// EPUB spine href / PDF 为 null / TXT 填 `txt`。
 String? get href;/// EPUB CFI 主定位，如 `epubcfi(/6/14!/4/2/2,/1:0,/1:120)`。
 String? get cfi;/// 兜底定位：章索引（0 基）。
 int? get chapterIndex;/// 兜底定位：章内字符偏移。
 int? get offset;/// 全书百分比 0..1，仅展示用，不参与定位。
 double? get percent;/// PDF 页码（1 基）。
 int? get page;/// PDF 页内横向比例 0..1。
 double? get x;/// PDF 页内纵向比例 0..1。
 double? get y;
/// Create a copy of Locator
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LocatorCopyWith<Locator> get copyWith => _$LocatorCopyWithImpl<Locator>(this as Locator, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Locator&&(identical(other.v, v) || other.v == v)&&(identical(other.href, href) || other.href == href)&&(identical(other.cfi, cfi) || other.cfi == cfi)&&(identical(other.chapterIndex, chapterIndex) || other.chapterIndex == chapterIndex)&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.percent, percent) || other.percent == percent)&&(identical(other.page, page) || other.page == page)&&(identical(other.x, x) || other.x == x)&&(identical(other.y, y) || other.y == y));
}


@override
int get hashCode => Object.hash(runtimeType,v,href,cfi,chapterIndex,offset,percent,page,x,y);

@override
String toString() {
  return 'Locator(v: $v, href: $href, cfi: $cfi, chapterIndex: $chapterIndex, offset: $offset, percent: $percent, page: $page, x: $x, y: $y)';
}


}

/// @nodoc
abstract mixin class $LocatorCopyWith<$Res>  {
  factory $LocatorCopyWith(Locator value, $Res Function(Locator) _then) = _$LocatorCopyWithImpl;
@useResult
$Res call({
 int v, String? href, String? cfi, int? chapterIndex, int? offset, double? percent, int? page, double? x, double? y
});




}
/// @nodoc
class _$LocatorCopyWithImpl<$Res>
    implements $LocatorCopyWith<$Res> {
  _$LocatorCopyWithImpl(this._self, this._then);

  final Locator _self;
  final $Res Function(Locator) _then;

/// Create a copy of Locator
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? v = null,Object? href = freezed,Object? cfi = freezed,Object? chapterIndex = freezed,Object? offset = freezed,Object? percent = freezed,Object? page = freezed,Object? x = freezed,Object? y = freezed,}) {
  return _then(_self.copyWith(
v: null == v ? _self.v : v // ignore: cast_nullable_to_non_nullable
as int,href: freezed == href ? _self.href : href // ignore: cast_nullable_to_non_nullable
as String?,cfi: freezed == cfi ? _self.cfi : cfi // ignore: cast_nullable_to_non_nullable
as String?,chapterIndex: freezed == chapterIndex ? _self.chapterIndex : chapterIndex // ignore: cast_nullable_to_non_nullable
as int?,offset: freezed == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int?,percent: freezed == percent ? _self.percent : percent // ignore: cast_nullable_to_non_nullable
as double?,page: freezed == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as int?,x: freezed == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as double?,y: freezed == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

}


/// Adds pattern-matching-related methods to [Locator].
extension LocatorPatterns on Locator {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Locator value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Locator() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Locator value)  $default,){
final _that = this;
switch (_that) {
case _Locator():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Locator value)?  $default,){
final _that = this;
switch (_that) {
case _Locator() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int v,  String? href,  String? cfi,  int? chapterIndex,  int? offset,  double? percent,  int? page,  double? x,  double? y)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Locator() when $default != null:
return $default(_that.v,_that.href,_that.cfi,_that.chapterIndex,_that.offset,_that.percent,_that.page,_that.x,_that.y);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int v,  String? href,  String? cfi,  int? chapterIndex,  int? offset,  double? percent,  int? page,  double? x,  double? y)  $default,) {final _that = this;
switch (_that) {
case _Locator():
return $default(_that.v,_that.href,_that.cfi,_that.chapterIndex,_that.offset,_that.percent,_that.page,_that.x,_that.y);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int v,  String? href,  String? cfi,  int? chapterIndex,  int? offset,  double? percent,  int? page,  double? x,  double? y)?  $default,) {final _that = this;
switch (_that) {
case _Locator() when $default != null:
return $default(_that.v,_that.href,_that.cfi,_that.chapterIndex,_that.offset,_that.percent,_that.page,_that.x,_that.y);case _:
  return null;

}
}

}

/// @nodoc


class _Locator implements Locator {
  const _Locator({this.v = 1, this.href, this.cfi, this.chapterIndex, this.offset, this.percent, this.page, this.x, this.y});
  

/// 格式版本，当前恒为 1。
@override@JsonKey() final  int v;
/// EPUB spine href / PDF 为 null / TXT 填 `txt`。
@override final  String? href;
/// EPUB CFI 主定位，如 `epubcfi(/6/14!/4/2/2,/1:0,/1:120)`。
@override final  String? cfi;
/// 兜底定位：章索引（0 基）。
@override final  int? chapterIndex;
/// 兜底定位：章内字符偏移。
@override final  int? offset;
/// 全书百分比 0..1，仅展示用，不参与定位。
@override final  double? percent;
/// PDF 页码（1 基）。
@override final  int? page;
/// PDF 页内横向比例 0..1。
@override final  double? x;
/// PDF 页内纵向比例 0..1。
@override final  double? y;

/// Create a copy of Locator
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LocatorCopyWith<_Locator> get copyWith => __$LocatorCopyWithImpl<_Locator>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Locator&&(identical(other.v, v) || other.v == v)&&(identical(other.href, href) || other.href == href)&&(identical(other.cfi, cfi) || other.cfi == cfi)&&(identical(other.chapterIndex, chapterIndex) || other.chapterIndex == chapterIndex)&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.percent, percent) || other.percent == percent)&&(identical(other.page, page) || other.page == page)&&(identical(other.x, x) || other.x == x)&&(identical(other.y, y) || other.y == y));
}


@override
int get hashCode => Object.hash(runtimeType,v,href,cfi,chapterIndex,offset,percent,page,x,y);

@override
String toString() {
  return 'Locator(v: $v, href: $href, cfi: $cfi, chapterIndex: $chapterIndex, offset: $offset, percent: $percent, page: $page, x: $x, y: $y)';
}


}

/// @nodoc
abstract mixin class _$LocatorCopyWith<$Res> implements $LocatorCopyWith<$Res> {
  factory _$LocatorCopyWith(_Locator value, $Res Function(_Locator) _then) = __$LocatorCopyWithImpl;
@override @useResult
$Res call({
 int v, String? href, String? cfi, int? chapterIndex, int? offset, double? percent, int? page, double? x, double? y
});




}
/// @nodoc
class __$LocatorCopyWithImpl<$Res>
    implements _$LocatorCopyWith<$Res> {
  __$LocatorCopyWithImpl(this._self, this._then);

  final _Locator _self;
  final $Res Function(_Locator) _then;

/// Create a copy of Locator
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? v = null,Object? href = freezed,Object? cfi = freezed,Object? chapterIndex = freezed,Object? offset = freezed,Object? percent = freezed,Object? page = freezed,Object? x = freezed,Object? y = freezed,}) {
  return _then(_Locator(
v: null == v ? _self.v : v // ignore: cast_nullable_to_non_nullable
as int,href: freezed == href ? _self.href : href // ignore: cast_nullable_to_non_nullable
as String?,cfi: freezed == cfi ? _self.cfi : cfi // ignore: cast_nullable_to_non_nullable
as String?,chapterIndex: freezed == chapterIndex ? _self.chapterIndex : chapterIndex // ignore: cast_nullable_to_non_nullable
as int?,offset: freezed == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int?,percent: freezed == percent ? _self.percent : percent // ignore: cast_nullable_to_non_nullable
as double?,page: freezed == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as int?,x: freezed == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as double?,y: freezed == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

// dart format on
