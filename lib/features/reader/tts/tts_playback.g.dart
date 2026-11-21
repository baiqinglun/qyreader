// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tts_playback.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$ttsPlaybackHash() => r'99ad6b2c7f3446513fb65c85f1e932e810b79748';

/// 全局听书控制器（keepAlive 单例；退出阅读页后继续朗读）。
///
/// Copied from [TtsPlayback].
@ProviderFor(TtsPlayback)
final ttsPlaybackProvider =
    NotifierProvider<TtsPlayback, TtsPlaybackState>.internal(
      TtsPlayback.new,
      name: r'ttsPlaybackProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$ttsPlaybackHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$TtsPlayback = Notifier<TtsPlaybackState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
