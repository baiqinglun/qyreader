// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tag_library.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$tagSummariesHash() => r'e21c12804dbe14b1a1bbaec80150135843a398c1';

/// 全量标签摘要：书架用过的标签 + 标签库里的空标签。
///
/// 按使用数降序、名称升序排；标签管理页和编辑书籍的标签选择器共用。
///
/// Copied from [tagSummaries].
@ProviderFor(tagSummaries)
final tagSummariesProvider = AutoDisposeProvider<List<TagSummary>>.internal(
  tagSummaries,
  name: r'tagSummariesProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$tagSummariesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef TagSummariesRef = AutoDisposeProviderRef<List<TagSummary>>;
String _$tagLibraryControllerHash() =>
    r'dbff905e88ddccfe08d57e4031550d289703225a';

/// 手动维护的标签库（prefs key `tags.library`）。
///
/// Copied from [TagLibraryController].
@ProviderFor(TagLibraryController)
final tagLibraryControllerProvider =
    NotifierProvider<TagLibraryController, List<String>>.internal(
      TagLibraryController.new,
      name: r'tagLibraryControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$tagLibraryControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$TagLibraryController = Notifier<List<String>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
