// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'reading_progress.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ReadingProgressSnapshot {

/// 所属书籍 id。
 String get bookId;/// 当前位置（Locator JSON）。
 String get locator;/// 当前百分比 0..1。
 double get percent;/// 最远位置（Locator JSON）。
 String? get furthestLocator;/// 最远百分比，合并取 max 永不回退。
 double get furthestPercent;/// 更新时间（epoch ms）。
 int get updatedAt;
/// Create a copy of ReadingProgressSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadingProgressSnapshotCopyWith<ReadingProgressSnapshot> get copyWith => _$ReadingProgressSnapshotCopyWithImpl<ReadingProgressSnapshot>(this as ReadingProgressSnapshot, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadingProgressSnapshot&&(identical(other.bookId, bookId) || other.bookId == bookId)&&(identical(other.locator, locator) || other.locator == locator)&&(identical(other.percent, percent) || other.percent == percent)&&(identical(other.furthestLocator, furthestLocator) || other.furthestLocator == furthestLocator)&&(identical(other.furthestPercent, furthestPercent) || other.furthestPercent == furthestPercent)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hash(runtimeType,bookId,locator,percent,furthestLocator,furthestPercent,updatedAt);

@override
String toString() {
  return 'ReadingProgressSnapshot(bookId: $bookId, locator: $locator, percent: $percent, furthestLocator: $furthestLocator, furthestPercent: $furthestPercent, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $ReadingProgressSnapshotCopyWith<$Res>  {
  factory $ReadingProgressSnapshotCopyWith(ReadingProgressSnapshot value, $Res Function(ReadingProgressSnapshot) _then) = _$ReadingProgressSnapshotCopyWithImpl;
@useResult
$Res call({
 String bookId, String locator, double percent, String? furthestLocator, double furthestPercent, int updatedAt
});




}
/// @nodoc
class _$ReadingProgressSnapshotCopyWithImpl<$Res>
    implements $ReadingProgressSnapshotCopyWith<$Res> {
  _$ReadingProgressSnapshotCopyWithImpl(this._self, this._then);

  final ReadingProgressSnapshot _self;
  final $Res Function(ReadingProgressSnapshot) _then;

/// Create a copy of ReadingProgressSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? bookId = null,Object? locator = null,Object? percent = null,Object? furthestLocator = freezed,Object? furthestPercent = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
bookId: null == bookId ? _self.bookId : bookId // ignore: cast_nullable_to_non_nullable
as String,locator: null == locator ? _self.locator : locator // ignore: cast_nullable_to_non_nullable
as String,percent: null == percent ? _self.percent : percent // ignore: cast_nullable_to_non_nullable
as double,furthestLocator: freezed == furthestLocator ? _self.furthestLocator : furthestLocator // ignore: cast_nullable_to_non_nullable
as String?,furthestPercent: null == furthestPercent ? _self.furthestPercent : furthestPercent // ignore: cast_nullable_to_non_nullable
as double,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ReadingProgressSnapshot].
extension ReadingProgressSnapshotPatterns on ReadingProgressSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ReadingProgressSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ReadingProgressSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ReadingProgressSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _ReadingProgressSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ReadingProgressSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _ReadingProgressSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String bookId,  String locator,  double percent,  String? furthestLocator,  double furthestPercent,  int updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ReadingProgressSnapshot() when $default != null:
return $default(_that.bookId,_that.locator,_that.percent,_that.furthestLocator,_that.furthestPercent,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String bookId,  String locator,  double percent,  String? furthestLocator,  double furthestPercent,  int updatedAt)  $default,) {final _that = this;
switch (_that) {
case _ReadingProgressSnapshot():
return $default(_that.bookId,_that.locator,_that.percent,_that.furthestLocator,_that.furthestPercent,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String bookId,  String locator,  double percent,  String? furthestLocator,  double furthestPercent,  int updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _ReadingProgressSnapshot() when $default != null:
return $default(_that.bookId,_that.locator,_that.percent,_that.furthestLocator,_that.furthestPercent,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _ReadingProgressSnapshot implements ReadingProgressSnapshot {
  const _ReadingProgressSnapshot({required this.bookId, required this.locator, required this.percent, this.furthestLocator, this.furthestPercent = 0, required this.updatedAt});
  

/// 所属书籍 id。
@override final  String bookId;
/// 当前位置（Locator JSON）。
@override final  String locator;
/// 当前百分比 0..1。
@override final  double percent;
/// 最远位置（Locator JSON）。
@override final  String? furthestLocator;
/// 最远百分比，合并取 max 永不回退。
@override@JsonKey() final  double furthestPercent;
/// 更新时间（epoch ms）。
@override final  int updatedAt;

/// Create a copy of ReadingProgressSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ReadingProgressSnapshotCopyWith<_ReadingProgressSnapshot> get copyWith => __$ReadingProgressSnapshotCopyWithImpl<_ReadingProgressSnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ReadingProgressSnapshot&&(identical(other.bookId, bookId) || other.bookId == bookId)&&(identical(other.locator, locator) || other.locator == locator)&&(identical(other.percent, percent) || other.percent == percent)&&(identical(other.furthestLocator, furthestLocator) || other.furthestLocator == furthestLocator)&&(identical(other.furthestPercent, furthestPercent) || other.furthestPercent == furthestPercent)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hash(runtimeType,bookId,locator,percent,furthestLocator,furthestPercent,updatedAt);

@override
String toString() {
  return 'ReadingProgressSnapshot(bookId: $bookId, locator: $locator, percent: $percent, furthestLocator: $furthestLocator, furthestPercent: $furthestPercent, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$ReadingProgressSnapshotCopyWith<$Res> implements $ReadingProgressSnapshotCopyWith<$Res> {
  factory _$ReadingProgressSnapshotCopyWith(_ReadingProgressSnapshot value, $Res Function(_ReadingProgressSnapshot) _then) = __$ReadingProgressSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String bookId, String locator, double percent, String? furthestLocator, double furthestPercent, int updatedAt
});




}
/// @nodoc
class __$ReadingProgressSnapshotCopyWithImpl<$Res>
    implements _$ReadingProgressSnapshotCopyWith<$Res> {
  __$ReadingProgressSnapshotCopyWithImpl(this._self, this._then);

  final _ReadingProgressSnapshot _self;
  final $Res Function(_ReadingProgressSnapshot) _then;

/// Create a copy of ReadingProgressSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? bookId = null,Object? locator = null,Object? percent = null,Object? furthestLocator = freezed,Object? furthestPercent = null,Object? updatedAt = null,}) {
  return _then(_ReadingProgressSnapshot(
bookId: null == bookId ? _self.bookId : bookId // ignore: cast_nullable_to_non_nullable
as String,locator: null == locator ? _self.locator : locator // ignore: cast_nullable_to_non_nullable
as String,percent: null == percent ? _self.percent : percent // ignore: cast_nullable_to_non_nullable
as double,furthestLocator: freezed == furthestLocator ? _self.furthestLocator : furthestLocator // ignore: cast_nullable_to_non_nullable
as String?,furthestPercent: null == furthestPercent ? _self.furthestPercent : furthestPercent // ignore: cast_nullable_to_non_nullable
as double,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
