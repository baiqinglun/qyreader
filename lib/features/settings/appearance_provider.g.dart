// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'appearance_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$appAccentControllerHash() =>
    r'0dd25de7e3fa4ac4fbabd3802464518230e8d982';

/// 当前主题色（默认亮蓝）。
///
/// Copied from [AppAccentController].
@ProviderFor(AppAccentController)
final appAccentControllerProvider =
    NotifierProvider<AppAccentController, AppAccent>.internal(
      AppAccentController.new,
      name: r'appAccentControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$appAccentControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$AppAccentController = Notifier<AppAccent>;
String _$appThemeModeControllerHash() =>
    r'4534c0baf61235f535d39a74d04100e963298302';

/// 当前亮暗模式（书架右上角按钮 / 设置页共用，默认跟随系统）。
///
/// Copied from [AppThemeModeController].
@ProviderFor(AppThemeModeController)
final appThemeModeControllerProvider =
    NotifierProvider<AppThemeModeController, AppThemeMode>.internal(
      AppThemeModeController.new,
      name: r'appThemeModeControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$appThemeModeControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$AppThemeModeController = Notifier<AppThemeMode>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
