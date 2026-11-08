// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$appDatabaseHash() => r'f285a3f7b13b6c6baf5a6b9c77b5d3379d6048ea';

/// 应用数据库单例。
///
/// Copied from [appDatabase].
@ProviderFor(appDatabase)
final appDatabaseProvider = Provider<AppDatabase>.internal(
  appDatabase,
  name: r'appDatabaseProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$appDatabaseHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AppDatabaseRef = ProviderRef<AppDatabase>;
String _$deviceIdHash() => r'd1ba14ffa8e6b0a52e5b72ff54dbc4101509bb2e';

/// 本设备 8 位标识（首次启动生成并持久化，HLC 时钟使用）。
///
/// Copied from [deviceId].
@ProviderFor(deviceId)
final deviceIdProvider = FutureProvider<String>.internal(
  deviceId,
  name: r'deviceIdProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$deviceIdHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DeviceIdRef = FutureProviderRef<String>;
String _$hlcClockHash() => r'ae33eb83139b7e1a129bd4c240a712053e6e91a3';

/// 混合逻辑时钟（同步时间戳全序）。
///
/// Copied from [hlcClock].
@ProviderFor(hlcClock)
final hlcClockProvider = FutureProvider<HlcClock>.internal(
  hlcClock,
  name: r'hlcClockProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$hlcClockHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef HlcClockRef = FutureProviderRef<HlcClock>;
String _$libraryDirectoryHash() => r'd223b2f7a8441774e7f1cf95855db1017a677ece';

/// 书籍库根目录（书籍文件与封面落盘处）。
///
/// Copied from [libraryDirectory].
@ProviderFor(libraryDirectory)
final libraryDirectoryProvider = FutureProvider<Directory>.internal(
  libraryDirectory,
  name: r'libraryDirectoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$libraryDirectoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef LibraryDirectoryRef = FutureProviderRef<Directory>;
String _$bookRepositoryHash() => r'14f9e9d5cce0bab1a105d381d21d7ae69fba2e57';

/// 书籍仓储单例。
///
/// Copied from [bookRepository].
@ProviderFor(bookRepository)
final bookRepositoryProvider = FutureProvider<BookRepository>.internal(
  bookRepository,
  name: r'bookRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$bookRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BookRepositoryRef = FutureProviderRef<BookRepository>;
String _$progressRepositoryHash() =>
    r'ac28f817d0c152103ab296a0e003212920f38099';

/// 阅读进度仓储单例。
///
/// Copied from [progressRepository].
@ProviderFor(progressRepository)
final progressRepositoryProvider = FutureProvider<ProgressRepository>.internal(
  progressRepository,
  name: r'progressRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$progressRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ProgressRepositoryRef = FutureProviderRef<ProgressRepository>;
String _$annotationRepositoryHash() =>
    r'0f3d99c05e8e9a7a0e07c610b1b2d2fc0194dff6';

/// 标注 + 书签仓储单例。
///
/// Copied from [annotationRepository].
@ProviderFor(annotationRepository)
final annotationRepositoryProvider =
    FutureProvider<AnnotationRepository>.internal(
      annotationRepository,
      name: r'annotationRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$annotationRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AnnotationRepositoryRef = FutureProviderRef<AnnotationRepository>;
String _$searchRepositoryHash() => r'a07d3cd82cb34f35215b2c1bf7bcbdc29b788eb4';

/// 全书检索仓储单例。
///
/// Copied from [searchRepository].
@ProviderFor(searchRepository)
final searchRepositoryProvider = FutureProvider<SearchRepository>.internal(
  searchRepository,
  name: r'searchRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$searchRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SearchRepositoryRef = FutureProviderRef<SearchRepository>;
String _$syncSpaceIdHash() => r'6077aba0b8f6a0b9faaa888f5e4a359d9f8ff0a9';

/// 同步空间标识。
///
/// Copied from [syncSpaceId].
@ProviderFor(syncSpaceId)
final syncSpaceIdProvider = FutureProvider<String>.internal(
  syncSpaceId,
  name: r'syncSpaceIdProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$syncSpaceIdHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SyncSpaceIdRef = FutureProviderRef<String>;
String _$syncBackendStoreHash() => r'a9d97fddff03530a9370a6e02472e175690f3e0b';

/// 同步后端配置存储（偏好 + 安全凭据）。
///
/// Copied from [syncBackendStore].
@ProviderFor(syncBackendStore)
final syncBackendStoreProvider = Provider<SyncBackendStore>.internal(
  syncBackendStore,
  name: r'syncBackendStoreProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$syncBackendStoreHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SyncBackendStoreRef = ProviderRef<SyncBackendStore>;
String _$objectStoreHash() => r'78a7190aab6d0c8ba4658ae710c805008a7ead2b';

/// 对象存储：按配置切本地桶 / S3（M6）；S3 配置不完整时回退本地桶。
///
/// Copied from [objectStore].
@ProviderFor(objectStore)
final objectStoreProvider = FutureProvider<ObjectStore>.internal(
  objectStore,
  name: r'objectStoreProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$objectStoreHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ObjectStoreRef = FutureProviderRef<ObjectStore>;
String _$syncRepositoryHash() => r'9d3c68bcf548ce8da877825e9c53d8081dc1a947';

/// 同步仓储单例。
///
/// Copied from [syncRepository].
@ProviderFor(syncRepository)
final syncRepositoryProvider = FutureProvider<SyncRepository>.internal(
  syncRepository,
  name: r'syncRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$syncRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SyncRepositoryRef = FutureProviderRef<SyncRepository>;
String _$statsRepositoryHash() => r'f1f78b43c74eccc54b81dcfceae48d3e588d89f3';

/// 阅读统计仓储单例。
///
/// Copied from [statsRepository].
@ProviderFor(statsRepository)
final statsRepositoryProvider = FutureProvider<StatsRepository>.internal(
  statsRepository,
  name: r'statsRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$statsRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef StatsRepositoryRef = FutureProviderRef<StatsRepository>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
