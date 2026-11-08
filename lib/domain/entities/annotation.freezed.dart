// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'annotation.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Annotation {

/// uuid v4。
 String get id;/// 所属书籍。
 String get bookId;/// 类型。
 AnnotationType get type;/// 语义色。
 AnnotationColor get color;/// 起始位置 Locator JSON（EPUB: cfi 存的是选区范围 CFI，
/// 即 epub.js annotations API 直接可用的值）。
 String get locatorStart;/// 结束位置 Locator JSON（v1 与起始相同，预留点选区拆分）。
 String get locatorEnd;/// 划选原文冗余副本（列表/导出展示用）。
 String? get quotedText;/// 笔记正文。
 String? get note;/// 所在章 href（跳转兜底用）。
 String? get href;/// 所在章索引。
 int? get chapterIndex;/// 创建时间（epoch ms）。
 int get createdAt;/// 更新时间（epoch ms）。
 int get updatedAt;
/// Create a copy of Annotation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AnnotationCopyWith<Annotation> get copyWith => _$AnnotationCopyWithImpl<Annotation>(this as Annotation, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Annotation&&(identical(other.id, id) || other.id == id)&&(identical(other.bookId, bookId) || other.bookId == bookId)&&(identical(other.type, type) || other.type == type)&&(identical(other.color, color) || other.color == color)&&(identical(other.locatorStart, locatorStart) || other.locatorStart == locatorStart)&&(identical(other.locatorEnd, locatorEnd) || other.locatorEnd == locatorEnd)&&(identical(other.quotedText, quotedText) || other.quotedText == quotedText)&&(identical(other.note, note) || other.note == note)&&(identical(other.href, href) || other.href == href)&&(identical(other.chapterIndex, chapterIndex) || other.chapterIndex == chapterIndex)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,bookId,type,color,locatorStart,locatorEnd,quotedText,note,href,chapterIndex,createdAt,updatedAt);

@override
String toString() {
  return 'Annotation(id: $id, bookId: $bookId, type: $type, color: $color, locatorStart: $locatorStart, locatorEnd: $locatorEnd, quotedText: $quotedText, note: $note, href: $href, chapterIndex: $chapterIndex, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $AnnotationCopyWith<$Res>  {
  factory $AnnotationCopyWith(Annotation value, $Res Function(Annotation) _then) = _$AnnotationCopyWithImpl;
@useResult
$Res call({
 String id, String bookId, AnnotationType type, AnnotationColor color, String locatorStart, String locatorEnd, String? quotedText, String? note, String? href, int? chapterIndex, int createdAt, int updatedAt
});




}
/// @nodoc
class _$AnnotationCopyWithImpl<$Res>
    implements $AnnotationCopyWith<$Res> {
  _$AnnotationCopyWithImpl(this._self, this._then);

  final Annotation _self;
  final $Res Function(Annotation) _then;

/// Create a copy of Annotation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? bookId = null,Object? type = null,Object? color = null,Object? locatorStart = null,Object? locatorEnd = null,Object? quotedText = freezed,Object? note = freezed,Object? href = freezed,Object? chapterIndex = freezed,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,bookId: null == bookId ? _self.bookId : bookId // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as AnnotationType,color: null == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as AnnotationColor,locatorStart: null == locatorStart ? _self.locatorStart : locatorStart // ignore: cast_nullable_to_non_nullable
as String,locatorEnd: null == locatorEnd ? _self.locatorEnd : locatorEnd // ignore: cast_nullable_to_non_nullable
as String,quotedText: freezed == quotedText ? _self.quotedText : quotedText // ignore: cast_nullable_to_non_nullable
as String?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,href: freezed == href ? _self.href : href // ignore: cast_nullable_to_non_nullable
as String?,chapterIndex: freezed == chapterIndex ? _self.chapterIndex : chapterIndex // ignore: cast_nullable_to_non_nullable
as int?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [Annotation].
extension AnnotationPatterns on Annotation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Annotation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Annotation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Annotation value)  $default,){
final _that = this;
switch (_that) {
case _Annotation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Annotation value)?  $default,){
final _that = this;
switch (_that) {
case _Annotation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String bookId,  AnnotationType type,  AnnotationColor color,  String locatorStart,  String locatorEnd,  String? quotedText,  String? note,  String? href,  int? chapterIndex,  int createdAt,  int updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Annotation() when $default != null:
return $default(_that.id,_that.bookId,_that.type,_that.color,_that.locatorStart,_that.locatorEnd,_that.quotedText,_that.note,_that.href,_that.chapterIndex,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String bookId,  AnnotationType type,  AnnotationColor color,  String locatorStart,  String locatorEnd,  String? quotedText,  String? note,  String? href,  int? chapterIndex,  int createdAt,  int updatedAt)  $default,) {final _that = this;
switch (_that) {
case _Annotation():
return $default(_that.id,_that.bookId,_that.type,_that.color,_that.locatorStart,_that.locatorEnd,_that.quotedText,_that.note,_that.href,_that.chapterIndex,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String bookId,  AnnotationType type,  AnnotationColor color,  String locatorStart,  String locatorEnd,  String? quotedText,  String? note,  String? href,  int? chapterIndex,  int createdAt,  int updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Annotation() when $default != null:
return $default(_that.id,_that.bookId,_that.type,_that.color,_that.locatorStart,_that.locatorEnd,_that.quotedText,_that.note,_that.href,_that.chapterIndex,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _Annotation implements Annotation {
  const _Annotation({required this.id, required this.bookId, required this.type, required this.color, required this.locatorStart, required this.locatorEnd, this.quotedText, this.note, this.href, this.chapterIndex, required this.createdAt, required this.updatedAt});
  

/// uuid v4。
@override final  String id;
/// 所属书籍。
@override final  String bookId;
/// 类型。
@override final  AnnotationType type;
/// 语义色。
@override final  AnnotationColor color;
/// 起始位置 Locator JSON（EPUB: cfi 存的是选区范围 CFI，
/// 即 epub.js annotations API 直接可用的值）。
@override final  String locatorStart;
/// 结束位置 Locator JSON（v1 与起始相同，预留点选区拆分）。
@override final  String locatorEnd;
/// 划选原文冗余副本（列表/导出展示用）。
@override final  String? quotedText;
/// 笔记正文。
@override final  String? note;
/// 所在章 href（跳转兜底用）。
@override final  String? href;
/// 所在章索引。
@override final  int? chapterIndex;
/// 创建时间（epoch ms）。
@override final  int createdAt;
/// 更新时间（epoch ms）。
@override final  int updatedAt;

/// Create a copy of Annotation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AnnotationCopyWith<_Annotation> get copyWith => __$AnnotationCopyWithImpl<_Annotation>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Annotation&&(identical(other.id, id) || other.id == id)&&(identical(other.bookId, bookId) || other.bookId == bookId)&&(identical(other.type, type) || other.type == type)&&(identical(other.color, color) || other.color == color)&&(identical(other.locatorStart, locatorStart) || other.locatorStart == locatorStart)&&(identical(other.locatorEnd, locatorEnd) || other.locatorEnd == locatorEnd)&&(identical(other.quotedText, quotedText) || other.quotedText == quotedText)&&(identical(other.note, note) || other.note == note)&&(identical(other.href, href) || other.href == href)&&(identical(other.chapterIndex, chapterIndex) || other.chapterIndex == chapterIndex)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,bookId,type,color,locatorStart,locatorEnd,quotedText,note,href,chapterIndex,createdAt,updatedAt);

@override
String toString() {
  return 'Annotation(id: $id, bookId: $bookId, type: $type, color: $color, locatorStart: $locatorStart, locatorEnd: $locatorEnd, quotedText: $quotedText, note: $note, href: $href, chapterIndex: $chapterIndex, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$AnnotationCopyWith<$Res> implements $AnnotationCopyWith<$Res> {
  factory _$AnnotationCopyWith(_Annotation value, $Res Function(_Annotation) _then) = __$AnnotationCopyWithImpl;
@override @useResult
$Res call({
 String id, String bookId, AnnotationType type, AnnotationColor color, String locatorStart, String locatorEnd, String? quotedText, String? note, String? href, int? chapterIndex, int createdAt, int updatedAt
});




}
/// @nodoc
class __$AnnotationCopyWithImpl<$Res>
    implements _$AnnotationCopyWith<$Res> {
  __$AnnotationCopyWithImpl(this._self, this._then);

  final _Annotation _self;
  final $Res Function(_Annotation) _then;

/// Create a copy of Annotation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? bookId = null,Object? type = null,Object? color = null,Object? locatorStart = null,Object? locatorEnd = null,Object? quotedText = freezed,Object? note = freezed,Object? href = freezed,Object? chapterIndex = freezed,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_Annotation(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,bookId: null == bookId ? _self.bookId : bookId // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as AnnotationType,color: null == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as AnnotationColor,locatorStart: null == locatorStart ? _self.locatorStart : locatorStart // ignore: cast_nullable_to_non_nullable
as String,locatorEnd: null == locatorEnd ? _self.locatorEnd : locatorEnd // ignore: cast_nullable_to_non_nullable
as String,quotedText: freezed == quotedText ? _self.quotedText : quotedText // ignore: cast_nullable_to_non_nullable
as String?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,href: freezed == href ? _self.href : href // ignore: cast_nullable_to_non_nullable
as String?,chapterIndex: freezed == chapterIndex ? _self.chapterIndex : chapterIndex // ignore: cast_nullable_to_non_nullable
as int?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
