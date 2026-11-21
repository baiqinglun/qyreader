// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'my_reading_page.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$myReadingTotalsHash() => r'3d8732d6c4d935edee6dbdf1183b792272fed4c6';

/// 所有书的累计阅读数据（时长 / 字数）。
///
/// Copied from [myReadingTotals].
@ProviderFor(myReadingTotals)
final myReadingTotalsProvider =
    AutoDisposeFutureProvider<Map<String, BookReadingTotal>>.internal(
      myReadingTotals,
      name: r'myReadingTotalsProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$myReadingTotalsHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MyReadingTotalsRef =
    AutoDisposeFutureProviderRef<Map<String, BookReadingTotal>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
