// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reader_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$readerControllerHash() => r'8acd384933f835efb8b72663f2a9633834d1f0a2';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

abstract class _$ReaderController
    extends BuildlessAutoDisposeNotifier<ReaderState> {
  late final String bookId;

  ReaderState build(String bookId);
}

/// 阅读器控制器（按 bookId family）。
///
/// Copied from [ReaderController].
@ProviderFor(ReaderController)
const readerControllerProvider = ReaderControllerFamily();

/// 阅读器控制器（按 bookId family）。
///
/// Copied from [ReaderController].
class ReaderControllerFamily extends Family<ReaderState> {
  /// 阅读器控制器（按 bookId family）。
  ///
  /// Copied from [ReaderController].
  const ReaderControllerFamily();

  /// 阅读器控制器（按 bookId family）。
  ///
  /// Copied from [ReaderController].
  ReaderControllerProvider call(String bookId) {
    return ReaderControllerProvider(bookId);
  }

  @override
  ReaderControllerProvider getProviderOverride(
    covariant ReaderControllerProvider provider,
  ) {
    return call(provider.bookId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'readerControllerProvider';
}

/// 阅读器控制器（按 bookId family）。
///
/// Copied from [ReaderController].
class ReaderControllerProvider
    extends AutoDisposeNotifierProviderImpl<ReaderController, ReaderState> {
  /// 阅读器控制器（按 bookId family）。
  ///
  /// Copied from [ReaderController].
  ReaderControllerProvider(String bookId)
    : this._internal(
        () => ReaderController()..bookId = bookId,
        from: readerControllerProvider,
        name: r'readerControllerProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$readerControllerHash,
        dependencies: ReaderControllerFamily._dependencies,
        allTransitiveDependencies:
            ReaderControllerFamily._allTransitiveDependencies,
        bookId: bookId,
      );

  ReaderControllerProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.bookId,
  }) : super.internal();

  final String bookId;

  @override
  ReaderState runNotifierBuild(covariant ReaderController notifier) {
    return notifier.build(bookId);
  }

  @override
  Override overrideWith(ReaderController Function() create) {
    return ProviderOverride(
      origin: this,
      override: ReaderControllerProvider._internal(
        () => create()..bookId = bookId,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        bookId: bookId,
      ),
    );
  }

  @override
  AutoDisposeNotifierProviderElement<ReaderController, ReaderState>
  createElement() {
    return _ReaderControllerProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ReaderControllerProvider && other.bookId == bookId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, bookId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ReaderControllerRef on AutoDisposeNotifierProviderRef<ReaderState> {
  /// The parameter `bookId` of this provider.
  String get bookId;
}

class _ReaderControllerProviderElement
    extends AutoDisposeNotifierProviderElement<ReaderController, ReaderState>
    with ReaderControllerRef {
  _ReaderControllerProviderElement(super.provider);

  @override
  String get bookId => (origin as ReaderControllerProvider).bookId;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
