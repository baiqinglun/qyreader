// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'shelf_controller.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ImportState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImportState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ImportState()';
}


}

/// @nodoc
class $ImportStateCopyWith<$Res>  {
$ImportStateCopyWith(ImportState _, $Res Function(ImportState) __);
}


/// Adds pattern-matching-related methods to [ImportState].
extension ImportStatePatterns on ImportState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ImportIdle value)?  idle,TResult Function( ImportLoading value)?  loading,TResult Function( ImportDone value)?  done,TResult Function( ImportError value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ImportIdle() when idle != null:
return idle(_that);case ImportLoading() when loading != null:
return loading(_that);case ImportDone() when done != null:
return done(_that);case ImportError() when error != null:
return error(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ImportIdle value)  idle,required TResult Function( ImportLoading value)  loading,required TResult Function( ImportDone value)  done,required TResult Function( ImportError value)  error,}){
final _that = this;
switch (_that) {
case ImportIdle():
return idle(_that);case ImportLoading():
return loading(_that);case ImportDone():
return done(_that);case ImportError():
return error(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ImportIdle value)?  idle,TResult? Function( ImportLoading value)?  loading,TResult? Function( ImportDone value)?  done,TResult? Function( ImportError value)?  error,}){
final _that = this;
switch (_that) {
case ImportIdle() when idle != null:
return idle(_that);case ImportLoading() when loading != null:
return loading(_that);case ImportDone() when done != null:
return done(_that);case ImportError() when error != null:
return error(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function()?  loading,TResult Function( Book book)?  done,TResult Function( String message)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ImportIdle() when idle != null:
return idle();case ImportLoading() when loading != null:
return loading();case ImportDone() when done != null:
return done(_that.book);case ImportError() when error != null:
return error(_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function()  loading,required TResult Function( Book book)  done,required TResult Function( String message)  error,}) {final _that = this;
switch (_that) {
case ImportIdle():
return idle();case ImportLoading():
return loading();case ImportDone():
return done(_that.book);case ImportError():
return error(_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function()?  loading,TResult? Function( Book book)?  done,TResult? Function( String message)?  error,}) {final _that = this;
switch (_that) {
case ImportIdle() when idle != null:
return idle();case ImportLoading() when loading != null:
return loading();case ImportDone() when done != null:
return done(_that.book);case ImportError() when error != null:
return error(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class ImportIdle implements ImportState {
  const ImportIdle();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImportIdle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ImportState.idle()';
}


}




/// @nodoc


class ImportLoading implements ImportState {
  const ImportLoading();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImportLoading);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ImportState.loading()';
}


}




/// @nodoc


class ImportDone implements ImportState {
  const ImportDone(this.book);
  

 final  Book book;

/// Create a copy of ImportState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImportDoneCopyWith<ImportDone> get copyWith => _$ImportDoneCopyWithImpl<ImportDone>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImportDone&&(identical(other.book, book) || other.book == book));
}


@override
int get hashCode => Object.hash(runtimeType,book);

@override
String toString() {
  return 'ImportState.done(book: $book)';
}


}

/// @nodoc
abstract mixin class $ImportDoneCopyWith<$Res> implements $ImportStateCopyWith<$Res> {
  factory $ImportDoneCopyWith(ImportDone value, $Res Function(ImportDone) _then) = _$ImportDoneCopyWithImpl;
@useResult
$Res call({
 Book book
});


$BookCopyWith<$Res> get book;

}
/// @nodoc
class _$ImportDoneCopyWithImpl<$Res>
    implements $ImportDoneCopyWith<$Res> {
  _$ImportDoneCopyWithImpl(this._self, this._then);

  final ImportDone _self;
  final $Res Function(ImportDone) _then;

/// Create a copy of ImportState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? book = null,}) {
  return _then(ImportDone(
null == book ? _self.book : book // ignore: cast_nullable_to_non_nullable
as Book,
  ));
}

/// Create a copy of ImportState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BookCopyWith<$Res> get book {
  
  return $BookCopyWith<$Res>(_self.book, (value) {
    return _then(_self.copyWith(book: value));
  });
}
}

/// @nodoc


class ImportError implements ImportState {
  const ImportError(this.message);
  

 final  String message;

/// Create a copy of ImportState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImportErrorCopyWith<ImportError> get copyWith => _$ImportErrorCopyWithImpl<ImportError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImportError&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'ImportState.error(message: $message)';
}


}

/// @nodoc
abstract mixin class $ImportErrorCopyWith<$Res> implements $ImportStateCopyWith<$Res> {
  factory $ImportErrorCopyWith(ImportError value, $Res Function(ImportError) _then) = _$ImportErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$ImportErrorCopyWithImpl<$Res>
    implements $ImportErrorCopyWith<$Res> {
  _$ImportErrorCopyWithImpl(this._self, this._then);

  final ImportError _self;
  final $Res Function(ImportError) _then;

/// Create a copy of ImportState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(ImportError(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
