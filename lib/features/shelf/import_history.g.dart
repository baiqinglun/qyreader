// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_history.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$importHistoryControllerHash() =>
    r'137a65a5ee645f540d879e7cfbd5da1172715805';

/// 导入记录仓储（keepAlive：导入控制器与弹窗共用一份状态）。
///
/// Copied from [ImportHistoryController].
@ProviderFor(ImportHistoryController)
final importHistoryControllerProvider =
    AsyncNotifierProvider<ImportHistoryController, List<ImportRecord>>.internal(
      ImportHistoryController.new,
      name: r'importHistoryControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$importHistoryControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ImportHistoryController = AsyncNotifier<List<ImportRecord>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
