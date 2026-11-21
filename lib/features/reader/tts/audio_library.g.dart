// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audio_library.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$audioLibraryControllerHash() =>
    r'a420b34ecc77df3c6363ec65a6049b7f4dcba5df';

/// 音频库控制器：manifest 读写 + 文件复制（保持与字体库同构）。
///
/// Copied from [AudioLibraryController].
@ProviderFor(AudioLibraryController)
final audioLibraryControllerProvider =
    NotifierProvider<AudioLibraryController, List<AudioTrack>>.internal(
      AudioLibraryController.new,
      name: r'audioLibraryControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$audioLibraryControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$AudioLibraryController = Notifier<List<AudioTrack>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
