// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shelf_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$shelfItemsHash() => r'406784df65e8bd712601ef39206d6e784ecdc536';

/// 书架书籍流（未删除、按最近打开排序）。
///
/// Copied from [shelfItems].
@ProviderFor(shelfItems)
final shelfItemsProvider = AutoDisposeStreamProvider<List<ShelfItem>>.internal(
  shelfItems,
  name: r'shelfItemsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$shelfItemsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ShelfItemsRef = AutoDisposeStreamProviderRef<List<ShelfItem>>;
String _$importControllerHash() => r'c7b2d9b74a55e381b5b2f642a709ca7ac93390a6';

/// 导入控制器。
///
/// Copied from [ImportController].
@ProviderFor(ImportController)
final importControllerProvider =
    AutoDisposeNotifierProvider<ImportController, ImportState>.internal(
      ImportController.new,
      name: r'importControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$importControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ImportController = AutoDisposeNotifier<ImportState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
