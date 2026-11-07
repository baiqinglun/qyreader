// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'book.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Book {

/// uuid v4。
 String get id;/// 书名。
 String get title;/// 作者。
 String? get author;/// 丛书名。
 String? get series;/// 丛书序号。
 double get seriesIndex;/// 语言（BCP-47）。
 String? get language;/// 简介。
 String? get description;/// 格式。
 BookFormat get format;/// 应用私有目录内的文件路径。
 String get filePath;/// 内容哈希（去重 + 同步校验）。
 String get fileSha256;/// 文件字节数。
 int get fileSize;/// 封面路径。
 String? get coverPath;/// 章节数。
 int get chapterCount;/// 全文字数（近似）。
 int get wordCount;/// 入库时间（epoch ms）。
 int get addedAt;/// 元数据更新时间（epoch ms）。
 int get updatedAt;/// 最近打开时间（epoch ms）。
 int? get lastOpenedAt;/// 是否读完。
 bool get isFinished;/// 是否归档。
 bool get isArchived;/// 墓碑（epoch ms），参与 LWW 合并。
 int? get deletedAt;/// 解析器原始元数据（JSON 字符串）。
 String? get metaJson;/// 最后写入的 HLC。
 String get hlc;/// 写入设备标识。
 String get deviceId;
/// Create a copy of Book
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BookCopyWith<Book> get copyWith => _$BookCopyWithImpl<Book>(this as Book, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Book&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.author, author) || other.author == author)&&(identical(other.series, series) || other.series == series)&&(identical(other.seriesIndex, seriesIndex) || other.seriesIndex == seriesIndex)&&(identical(other.language, language) || other.language == language)&&(identical(other.description, description) || other.description == description)&&(identical(other.format, format) || other.format == format)&&(identical(other.filePath, filePath) || other.filePath == filePath)&&(identical(other.fileSha256, fileSha256) || other.fileSha256 == fileSha256)&&(identical(other.fileSize, fileSize) || other.fileSize == fileSize)&&(identical(other.coverPath, coverPath) || other.coverPath == coverPath)&&(identical(other.chapterCount, chapterCount) || other.chapterCount == chapterCount)&&(identical(other.wordCount, wordCount) || other.wordCount == wordCount)&&(identical(other.addedAt, addedAt) || other.addedAt == addedAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.lastOpenedAt, lastOpenedAt) || other.lastOpenedAt == lastOpenedAt)&&(identical(other.isFinished, isFinished) || other.isFinished == isFinished)&&(identical(other.isArchived, isArchived) || other.isArchived == isArchived)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt)&&(identical(other.metaJson, metaJson) || other.metaJson == metaJson)&&(identical(other.hlc, hlc) || other.hlc == hlc)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId));
}


@override
int get hashCode => Object.hashAll([runtimeType,id,title,author,series,seriesIndex,language,description,format,filePath,fileSha256,fileSize,coverPath,chapterCount,wordCount,addedAt,updatedAt,lastOpenedAt,isFinished,isArchived,deletedAt,metaJson,hlc,deviceId]);

@override
String toString() {
  return 'Book(id: $id, title: $title, author: $author, series: $series, seriesIndex: $seriesIndex, language: $language, description: $description, format: $format, filePath: $filePath, fileSha256: $fileSha256, fileSize: $fileSize, coverPath: $coverPath, chapterCount: $chapterCount, wordCount: $wordCount, addedAt: $addedAt, updatedAt: $updatedAt, lastOpenedAt: $lastOpenedAt, isFinished: $isFinished, isArchived: $isArchived, deletedAt: $deletedAt, metaJson: $metaJson, hlc: $hlc, deviceId: $deviceId)';
}


}

/// @nodoc
abstract mixin class $BookCopyWith<$Res>  {
  factory $BookCopyWith(Book value, $Res Function(Book) _then) = _$BookCopyWithImpl;
@useResult
$Res call({
 String id, String title, String? author, String? series, double seriesIndex, String? language, String? description, BookFormat format, String filePath, String fileSha256, int fileSize, String? coverPath, int chapterCount, int wordCount, int addedAt, int updatedAt, int? lastOpenedAt, bool isFinished, bool isArchived, int? deletedAt, String? metaJson, String hlc, String deviceId
});




}
/// @nodoc
class _$BookCopyWithImpl<$Res>
    implements $BookCopyWith<$Res> {
  _$BookCopyWithImpl(this._self, this._then);

  final Book _self;
  final $Res Function(Book) _then;

/// Create a copy of Book
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? author = freezed,Object? series = freezed,Object? seriesIndex = null,Object? language = freezed,Object? description = freezed,Object? format = null,Object? filePath = null,Object? fileSha256 = null,Object? fileSize = null,Object? coverPath = freezed,Object? chapterCount = null,Object? wordCount = null,Object? addedAt = null,Object? updatedAt = null,Object? lastOpenedAt = freezed,Object? isFinished = null,Object? isArchived = null,Object? deletedAt = freezed,Object? metaJson = freezed,Object? hlc = null,Object? deviceId = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,author: freezed == author ? _self.author : author // ignore: cast_nullable_to_non_nullable
as String?,series: freezed == series ? _self.series : series // ignore: cast_nullable_to_non_nullable
as String?,seriesIndex: null == seriesIndex ? _self.seriesIndex : seriesIndex // ignore: cast_nullable_to_non_nullable
as double,language: freezed == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,format: null == format ? _self.format : format // ignore: cast_nullable_to_non_nullable
as BookFormat,filePath: null == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String,fileSha256: null == fileSha256 ? _self.fileSha256 : fileSha256 // ignore: cast_nullable_to_non_nullable
as String,fileSize: null == fileSize ? _self.fileSize : fileSize // ignore: cast_nullable_to_non_nullable
as int,coverPath: freezed == coverPath ? _self.coverPath : coverPath // ignore: cast_nullable_to_non_nullable
as String?,chapterCount: null == chapterCount ? _self.chapterCount : chapterCount // ignore: cast_nullable_to_non_nullable
as int,wordCount: null == wordCount ? _self.wordCount : wordCount // ignore: cast_nullable_to_non_nullable
as int,addedAt: null == addedAt ? _self.addedAt : addedAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,lastOpenedAt: freezed == lastOpenedAt ? _self.lastOpenedAt : lastOpenedAt // ignore: cast_nullable_to_non_nullable
as int?,isFinished: null == isFinished ? _self.isFinished : isFinished // ignore: cast_nullable_to_non_nullable
as bool,isArchived: null == isArchived ? _self.isArchived : isArchived // ignore: cast_nullable_to_non_nullable
as bool,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as int?,metaJson: freezed == metaJson ? _self.metaJson : metaJson // ignore: cast_nullable_to_non_nullable
as String?,hlc: null == hlc ? _self.hlc : hlc // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Book].
extension BookPatterns on Book {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Book value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Book() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Book value)  $default,){
final _that = this;
switch (_that) {
case _Book():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Book value)?  $default,){
final _that = this;
switch (_that) {
case _Book() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String? author,  String? series,  double seriesIndex,  String? language,  String? description,  BookFormat format,  String filePath,  String fileSha256,  int fileSize,  String? coverPath,  int chapterCount,  int wordCount,  int addedAt,  int updatedAt,  int? lastOpenedAt,  bool isFinished,  bool isArchived,  int? deletedAt,  String? metaJson,  String hlc,  String deviceId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Book() when $default != null:
return $default(_that.id,_that.title,_that.author,_that.series,_that.seriesIndex,_that.language,_that.description,_that.format,_that.filePath,_that.fileSha256,_that.fileSize,_that.coverPath,_that.chapterCount,_that.wordCount,_that.addedAt,_that.updatedAt,_that.lastOpenedAt,_that.isFinished,_that.isArchived,_that.deletedAt,_that.metaJson,_that.hlc,_that.deviceId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String? author,  String? series,  double seriesIndex,  String? language,  String? description,  BookFormat format,  String filePath,  String fileSha256,  int fileSize,  String? coverPath,  int chapterCount,  int wordCount,  int addedAt,  int updatedAt,  int? lastOpenedAt,  bool isFinished,  bool isArchived,  int? deletedAt,  String? metaJson,  String hlc,  String deviceId)  $default,) {final _that = this;
switch (_that) {
case _Book():
return $default(_that.id,_that.title,_that.author,_that.series,_that.seriesIndex,_that.language,_that.description,_that.format,_that.filePath,_that.fileSha256,_that.fileSize,_that.coverPath,_that.chapterCount,_that.wordCount,_that.addedAt,_that.updatedAt,_that.lastOpenedAt,_that.isFinished,_that.isArchived,_that.deletedAt,_that.metaJson,_that.hlc,_that.deviceId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String? author,  String? series,  double seriesIndex,  String? language,  String? description,  BookFormat format,  String filePath,  String fileSha256,  int fileSize,  String? coverPath,  int chapterCount,  int wordCount,  int addedAt,  int updatedAt,  int? lastOpenedAt,  bool isFinished,  bool isArchived,  int? deletedAt,  String? metaJson,  String hlc,  String deviceId)?  $default,) {final _that = this;
switch (_that) {
case _Book() when $default != null:
return $default(_that.id,_that.title,_that.author,_that.series,_that.seriesIndex,_that.language,_that.description,_that.format,_that.filePath,_that.fileSha256,_that.fileSize,_that.coverPath,_that.chapterCount,_that.wordCount,_that.addedAt,_that.updatedAt,_that.lastOpenedAt,_that.isFinished,_that.isArchived,_that.deletedAt,_that.metaJson,_that.hlc,_that.deviceId);case _:
  return null;

}
}

}

/// @nodoc


class _Book implements Book {
  const _Book({required this.id, required this.title, this.author, this.series, this.seriesIndex = 0, this.language, this.description, required this.format, required this.filePath, required this.fileSha256, required this.fileSize, this.coverPath, this.chapterCount = 0, this.wordCount = 0, required this.addedAt, required this.updatedAt, this.lastOpenedAt, this.isFinished = false, this.isArchived = false, this.deletedAt, this.metaJson, required this.hlc, required this.deviceId});
  

/// uuid v4。
@override final  String id;
/// 书名。
@override final  String title;
/// 作者。
@override final  String? author;
/// 丛书名。
@override final  String? series;
/// 丛书序号。
@override@JsonKey() final  double seriesIndex;
/// 语言（BCP-47）。
@override final  String? language;
/// 简介。
@override final  String? description;
/// 格式。
@override final  BookFormat format;
/// 应用私有目录内的文件路径。
@override final  String filePath;
/// 内容哈希（去重 + 同步校验）。
@override final  String fileSha256;
/// 文件字节数。
@override final  int fileSize;
/// 封面路径。
@override final  String? coverPath;
/// 章节数。
@override@JsonKey() final  int chapterCount;
/// 全文字数（近似）。
@override@JsonKey() final  int wordCount;
/// 入库时间（epoch ms）。
@override final  int addedAt;
/// 元数据更新时间（epoch ms）。
@override final  int updatedAt;
/// 最近打开时间（epoch ms）。
@override final  int? lastOpenedAt;
/// 是否读完。
@override@JsonKey() final  bool isFinished;
/// 是否归档。
@override@JsonKey() final  bool isArchived;
/// 墓碑（epoch ms），参与 LWW 合并。
@override final  int? deletedAt;
/// 解析器原始元数据（JSON 字符串）。
@override final  String? metaJson;
/// 最后写入的 HLC。
@override final  String hlc;
/// 写入设备标识。
@override final  String deviceId;

/// Create a copy of Book
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BookCopyWith<_Book> get copyWith => __$BookCopyWithImpl<_Book>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Book&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.author, author) || other.author == author)&&(identical(other.series, series) || other.series == series)&&(identical(other.seriesIndex, seriesIndex) || other.seriesIndex == seriesIndex)&&(identical(other.language, language) || other.language == language)&&(identical(other.description, description) || other.description == description)&&(identical(other.format, format) || other.format == format)&&(identical(other.filePath, filePath) || other.filePath == filePath)&&(identical(other.fileSha256, fileSha256) || other.fileSha256 == fileSha256)&&(identical(other.fileSize, fileSize) || other.fileSize == fileSize)&&(identical(other.coverPath, coverPath) || other.coverPath == coverPath)&&(identical(other.chapterCount, chapterCount) || other.chapterCount == chapterCount)&&(identical(other.wordCount, wordCount) || other.wordCount == wordCount)&&(identical(other.addedAt, addedAt) || other.addedAt == addedAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.lastOpenedAt, lastOpenedAt) || other.lastOpenedAt == lastOpenedAt)&&(identical(other.isFinished, isFinished) || other.isFinished == isFinished)&&(identical(other.isArchived, isArchived) || other.isArchived == isArchived)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt)&&(identical(other.metaJson, metaJson) || other.metaJson == metaJson)&&(identical(other.hlc, hlc) || other.hlc == hlc)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId));
}


@override
int get hashCode => Object.hashAll([runtimeType,id,title,author,series,seriesIndex,language,description,format,filePath,fileSha256,fileSize,coverPath,chapterCount,wordCount,addedAt,updatedAt,lastOpenedAt,isFinished,isArchived,deletedAt,metaJson,hlc,deviceId]);

@override
String toString() {
  return 'Book(id: $id, title: $title, author: $author, series: $series, seriesIndex: $seriesIndex, language: $language, description: $description, format: $format, filePath: $filePath, fileSha256: $fileSha256, fileSize: $fileSize, coverPath: $coverPath, chapterCount: $chapterCount, wordCount: $wordCount, addedAt: $addedAt, updatedAt: $updatedAt, lastOpenedAt: $lastOpenedAt, isFinished: $isFinished, isArchived: $isArchived, deletedAt: $deletedAt, metaJson: $metaJson, hlc: $hlc, deviceId: $deviceId)';
}


}

/// @nodoc
abstract mixin class _$BookCopyWith<$Res> implements $BookCopyWith<$Res> {
  factory _$BookCopyWith(_Book value, $Res Function(_Book) _then) = __$BookCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String? author, String? series, double seriesIndex, String? language, String? description, BookFormat format, String filePath, String fileSha256, int fileSize, String? coverPath, int chapterCount, int wordCount, int addedAt, int updatedAt, int? lastOpenedAt, bool isFinished, bool isArchived, int? deletedAt, String? metaJson, String hlc, String deviceId
});




}
/// @nodoc
class __$BookCopyWithImpl<$Res>
    implements _$BookCopyWith<$Res> {
  __$BookCopyWithImpl(this._self, this._then);

  final _Book _self;
  final $Res Function(_Book) _then;

/// Create a copy of Book
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? author = freezed,Object? series = freezed,Object? seriesIndex = null,Object? language = freezed,Object? description = freezed,Object? format = null,Object? filePath = null,Object? fileSha256 = null,Object? fileSize = null,Object? coverPath = freezed,Object? chapterCount = null,Object? wordCount = null,Object? addedAt = null,Object? updatedAt = null,Object? lastOpenedAt = freezed,Object? isFinished = null,Object? isArchived = null,Object? deletedAt = freezed,Object? metaJson = freezed,Object? hlc = null,Object? deviceId = null,}) {
  return _then(_Book(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,author: freezed == author ? _self.author : author // ignore: cast_nullable_to_non_nullable
as String?,series: freezed == series ? _self.series : series // ignore: cast_nullable_to_non_nullable
as String?,seriesIndex: null == seriesIndex ? _self.seriesIndex : seriesIndex // ignore: cast_nullable_to_non_nullable
as double,language: freezed == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,format: null == format ? _self.format : format // ignore: cast_nullable_to_non_nullable
as BookFormat,filePath: null == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String,fileSha256: null == fileSha256 ? _self.fileSha256 : fileSha256 // ignore: cast_nullable_to_non_nullable
as String,fileSize: null == fileSize ? _self.fileSize : fileSize // ignore: cast_nullable_to_non_nullable
as int,coverPath: freezed == coverPath ? _self.coverPath : coverPath // ignore: cast_nullable_to_non_nullable
as String?,chapterCount: null == chapterCount ? _self.chapterCount : chapterCount // ignore: cast_nullable_to_non_nullable
as int,wordCount: null == wordCount ? _self.wordCount : wordCount // ignore: cast_nullable_to_non_nullable
as int,addedAt: null == addedAt ? _self.addedAt : addedAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,lastOpenedAt: freezed == lastOpenedAt ? _self.lastOpenedAt : lastOpenedAt // ignore: cast_nullable_to_non_nullable
as int?,isFinished: null == isFinished ? _self.isFinished : isFinished // ignore: cast_nullable_to_non_nullable
as bool,isArchived: null == isArchived ? _self.isArchived : isArchived // ignore: cast_nullable_to_non_nullable
as bool,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as int?,metaJson: freezed == metaJson ? _self.metaJson : metaJson // ignore: cast_nullable_to_non_nullable
as String?,hlc: null == hlc ? _self.hlc : hlc // ignore: cast_nullable_to_non_nullable
as String,deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ShelfItem {

/// 书籍实体。
 Book get book;/// 当前阅读百分比 0..1。
 double get percent;
/// Create a copy of ShelfItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShelfItemCopyWith<ShelfItem> get copyWith => _$ShelfItemCopyWithImpl<ShelfItem>(this as ShelfItem, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShelfItem&&(identical(other.book, book) || other.book == book)&&(identical(other.percent, percent) || other.percent == percent));
}


@override
int get hashCode => Object.hash(runtimeType,book,percent);

@override
String toString() {
  return 'ShelfItem(book: $book, percent: $percent)';
}


}

/// @nodoc
abstract mixin class $ShelfItemCopyWith<$Res>  {
  factory $ShelfItemCopyWith(ShelfItem value, $Res Function(ShelfItem) _then) = _$ShelfItemCopyWithImpl;
@useResult
$Res call({
 Book book, double percent
});


$BookCopyWith<$Res> get book;

}
/// @nodoc
class _$ShelfItemCopyWithImpl<$Res>
    implements $ShelfItemCopyWith<$Res> {
  _$ShelfItemCopyWithImpl(this._self, this._then);

  final ShelfItem _self;
  final $Res Function(ShelfItem) _then;

/// Create a copy of ShelfItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? book = null,Object? percent = null,}) {
  return _then(_self.copyWith(
book: null == book ? _self.book : book // ignore: cast_nullable_to_non_nullable
as Book,percent: null == percent ? _self.percent : percent // ignore: cast_nullable_to_non_nullable
as double,
  ));
}
/// Create a copy of ShelfItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BookCopyWith<$Res> get book {
  
  return $BookCopyWith<$Res>(_self.book, (value) {
    return _then(_self.copyWith(book: value));
  });
}
}


/// Adds pattern-matching-related methods to [ShelfItem].
extension ShelfItemPatterns on ShelfItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShelfItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShelfItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShelfItem value)  $default,){
final _that = this;
switch (_that) {
case _ShelfItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShelfItem value)?  $default,){
final _that = this;
switch (_that) {
case _ShelfItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Book book,  double percent)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShelfItem() when $default != null:
return $default(_that.book,_that.percent);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Book book,  double percent)  $default,) {final _that = this;
switch (_that) {
case _ShelfItem():
return $default(_that.book,_that.percent);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Book book,  double percent)?  $default,) {final _that = this;
switch (_that) {
case _ShelfItem() when $default != null:
return $default(_that.book,_that.percent);case _:
  return null;

}
}

}

/// @nodoc


class _ShelfItem implements ShelfItem {
  const _ShelfItem({required this.book, this.percent = 0});
  

/// 书籍实体。
@override final  Book book;
/// 当前阅读百分比 0..1。
@override@JsonKey() final  double percent;

/// Create a copy of ShelfItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShelfItemCopyWith<_ShelfItem> get copyWith => __$ShelfItemCopyWithImpl<_ShelfItem>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShelfItem&&(identical(other.book, book) || other.book == book)&&(identical(other.percent, percent) || other.percent == percent));
}


@override
int get hashCode => Object.hash(runtimeType,book,percent);

@override
String toString() {
  return 'ShelfItem(book: $book, percent: $percent)';
}


}

/// @nodoc
abstract mixin class _$ShelfItemCopyWith<$Res> implements $ShelfItemCopyWith<$Res> {
  factory _$ShelfItemCopyWith(_ShelfItem value, $Res Function(_ShelfItem) _then) = __$ShelfItemCopyWithImpl;
@override @useResult
$Res call({
 Book book, double percent
});


@override $BookCopyWith<$Res> get book;

}
/// @nodoc
class __$ShelfItemCopyWithImpl<$Res>
    implements _$ShelfItemCopyWith<$Res> {
  __$ShelfItemCopyWithImpl(this._self, this._then);

  final _ShelfItem _self;
  final $Res Function(_ShelfItem) _then;

/// Create a copy of ShelfItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? book = null,Object? percent = null,}) {
  return _then(_ShelfItem(
book: null == book ? _self.book : book // ignore: cast_nullable_to_non_nullable
as Book,percent: null == percent ? _self.percent : percent // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

/// Create a copy of ShelfItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BookCopyWith<$Res> get book {
  
  return $BookCopyWith<$Res>(_self.book, (value) {
    return _then(_self.copyWith(book: value));
  });
}
}

// dart format on
