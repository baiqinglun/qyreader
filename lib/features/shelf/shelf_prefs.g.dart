// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shelf_prefs.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$recentShelfVisibleHash() =>
    r'23651343065e7a5258e32ac24db5b7ef7ed14be8';

/// 「最近在读」竖排架显隐（默认显示）。
///
/// Copied from [RecentShelfVisible].
@ProviderFor(RecentShelfVisible)
final recentShelfVisibleProvider =
    NotifierProvider<RecentShelfVisible, bool>.internal(
      RecentShelfVisible.new,
      name: r'recentShelfVisibleProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$recentShelfVisibleHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$RecentShelfVisible = Notifier<bool>;
String _$shelfViewModeControllerHash() =>
    r'c9ce561ead9db6b797b40e3bc2e0b10d0ec55a4a';

/// 书架展示形式（默认平铺）。
///
/// Copied from [ShelfViewModeController].
@ProviderFor(ShelfViewModeController)
final shelfViewModeControllerProvider =
    NotifierProvider<ShelfViewModeController, ShelfViewMode>.internal(
      ShelfViewModeController.new,
      name: r'shelfViewModeControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$shelfViewModeControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ShelfViewModeController = Notifier<ShelfViewMode>;
String _$shelfCategoryFilterHash() =>
    r'05d515c181e495db4834a40b93bd78e58e437747';

/// 书架分类筛选（'' = 书架首屏；分类名 = 正在看这个分类）。
///
/// Copied from [ShelfCategoryFilter].
@ProviderFor(ShelfCategoryFilter)
final shelfCategoryFilterProvider =
    NotifierProvider<ShelfCategoryFilter, String>.internal(
      ShelfCategoryFilter.new,
      name: r'shelfCategoryFilterProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$shelfCategoryFilterHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ShelfCategoryFilter = Notifier<String>;
String _$shelfPrefsControllerHash() =>
    r'2259c1ae2059b8f546ce8f6c05858a672f5fae74';

/// 书架外观偏好（默认值见 [ShelfPrefs]）。
///
/// 设置项都只有一个 key，逐项落盘；滑动圆角时不会一次写九个 key。
///
/// Copied from [ShelfPrefsController].
@ProviderFor(ShelfPrefsController)
final shelfPrefsControllerProvider =
    NotifierProvider<ShelfPrefsController, ShelfPrefs>.internal(
      ShelfPrefsController.new,
      name: r'shelfPrefsControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$shelfPrefsControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ShelfPrefsController = Notifier<ShelfPrefs>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
