/// 听书背景音乐音频库：内置曲目 + 用户导入音频的管理。
///
/// 与自定义字体同一套结构：音频文件落在应用支持目录 `music/`，元数据
/// （id / 展示名 / 文件名）存 shared_preferences `reader.audio`；同步由
/// `AudioSync`（data/sync/audio_sync.dart）按内容 sha256 完成，与本控制
/// 器共用同一个 prefs key。
///
/// 内置曲目打包在 `assets/music/`，不进 manifest（不可删、不同步）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

part 'audio_library.g.dart';

/// 一条背景音乐曲目（内置或导入）。
class AudioTrack {
  const AudioTrack._({
    required this.id,
    required this.name,
    this.fileName,
    this.asset,
  });

  /// 内置曲目（打包在 assets/music/，随应用分发）。
  const AudioTrack.builtin({
    required String id,
    required String name,
    required String asset,
  }) : this._(id: id, name: name, asset: asset);

  /// 导入曲目（文件在音频目录里）。
  const AudioTrack.imported({
    required String id,
    required String name,
    required String fileName,
  }) : this._(id: id, name: name, fileName: fileName);

  /// 唯一 id（导入曲目同时决定文件名）。
  final String id;

  /// 展示名。
  final String name;

  /// 音频目录内的文件名（null = 内置曲目）。
  final String? fileName;

  /// 内置曲目的 asset 路径（导入曲目为 null）。
  final String? asset;

  /// 是否内置（内置不可删、不同步）。
  bool get isBuiltin => fileName == null;

  /// 播放源：内置走 asset，导入走本地文件路径。
  String? assetSourceKey() => asset == null
      ? null
      : (asset!.startsWith('assets/')
            ? asset!.substring('assets/'.length)
            : asset);

  /// 序列化为 manifest 条目（内置曲目不进 manifest）。
  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id,
    'name': name,
    'file': fileName,
  };

  /// 从 manifest 条目还原；坏条目返回 null（不拖垮整个列表）。
  static AudioTrack? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final file = raw['file'];
    if (id is! String || id.isEmpty || id.length > 64) return null;
    if (name is! String || name.isEmpty || name.length > 200) return null;
    if (file is! String || file.isEmpty || file.length > 128) return null;
    // 只接受纯文件名：manifest 手改/旧版本残留不能把路径带到音频目录之外
    if (file.contains('/') || file.contains('\\') || file.contains('..')) {
      return null;
    }
    return AudioTrack.imported(id: id, name: name, fileName: file);
  }
}

/// 内置背景音乐曲目（assets/music/，由 .zcode/gen_bgm.py 合成）。
const List<AudioTrack> kBuiltinAudioTracks = <AudioTrack>[
  AudioTrack.builtin(
    id: 'builtin-rain',
    name: '雨声',
    asset: 'assets/music/bgm-rain.mp3',
  ),
  AudioTrack.builtin(
    id: 'builtin-noise',
    name: '白噪音',
    asset: 'assets/music/bgm-noise.mp3',
  ),
  AudioTrack.builtin(
    id: 'builtin-melody',
    name: '轻音乐',
    asset: 'assets/music/bgm-melody.mp3',
  ),
];

/// 全部可选曲目：内置在前，导入在后。
List<AudioTrack> allAudioTracks(List<AudioTrack> imported) => <AudioTrack>[
  ...kBuiltinAudioTracks,
  ...imported,
];

/// 音频导入失败（消息可直接展示给用户）。
class AudioImportException implements Exception {
  /// 带用户可读消息构造。
  const AudioImportException(this.message);

  /// 用户可读原因。
  final String message;

  @override
  String toString() => message;
}

/// 单个音频文件大小上限：30 分钟的 mp3 大约 30 MB，超过 100 MB 基本是误选。
const int kMaxAudioBytes = 100 * 1024 * 1024;

/// 支持的音频扩展名（小写）；不支持返回 null。
String? supportedAudioExtension(String path) {
  final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
  return const <String>{
        'mp3',
        'm4a',
        'aac',
        'wav',
        'ogg',
        'flac',
        'opus',
      }.contains(ext)
      ? ext
      : null;
}

/// 解析 manifest（JSON）；任何坏条目逐条跳过。
List<AudioTrack> parseAudioManifest(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const <AudioTrack>[];
  }
  if (decoded is! Map) return const <AudioTrack>[];
  final list = decoded['tracks'];
  if (list is! List) return const <AudioTrack>[];
  final seen = <String>{};
  final out = <AudioTrack>[];
  for (final item in list) {
    final track = AudioTrack.fromMap(item);
    if (track == null || !seen.add(track.id)) continue;
    out.add(track);
  }
  return out;
}

/// 按 id 查找曲目。
AudioTrack? findAudioTrack(List<AudioTrack> tracks, String id) {
  for (final track in tracks) {
    if (track.id == id) return track;
  }
  return null;
}

/// 音频目录：`<应用支持目录>/music`。
Future<Directory> audioLibraryDir() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory(p.join(base.path, 'music'));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// 音频库控制器：manifest 读写 + 文件复制（保持与字体库同构）。
@Riverpod(keepAlive: true)
class AudioLibraryController extends _$AudioLibraryController {
  static const String _kKey = 'reader.audio';

  @override
  List<AudioTrack> build() {
    _restore();
    return const <AudioTrack>[];
  }

  /// 同步拉回新音频后重新读 manifest（不重启也能在列表里看到）。
  Future<void> reload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      state = raw == null ? const <AudioTrack>[] : parseAudioManifest(raw);
    } catch (_) {
      // 读取失败保持当前列表
    }
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw == null) return;
      if (state.isNotEmpty) return;
      state = parseAudioManifest(raw);
    } catch (_) {
      // 损坏的 manifest 按「无导入音频」处理
    }
  }

  /// 从文件导入音频（文件选择由调用方负责）。
  ///
  /// 失败抛 [AudioImportException]，消息可直接展示。
  Future<AudioTrack> importFromFile(String path) async {
    final ext = supportedAudioExtension(path);
    if (ext == null) {
      throw const AudioImportException(
        '仅支持 mp3 / m4a / aac / wav / ogg / flac / opus 音频文件',
      );
    }
    final bytes = await _readFile(path);
    final id = const Uuid().v4().replaceAll('-', '').substring(0, 10);
    final fileName = '$id.$ext';
    final dir = await audioLibraryDir();
    try {
      await File(p.join(dir.path, fileName)).writeAsBytes(bytes, flush: true);
    } catch (e) {
      throw AudioImportException('保存音频文件失败：$e');
    }

    var name = p.basenameWithoutExtension(path).trim();
    if (name.isEmpty) name = '导入音频';
    if (name.length > 60) name = name.substring(0, 60);

    final track = AudioTrack.imported(id: id, name: name, fileName: fileName);
    state = <AudioTrack>[...state, track];
    await _persist();
    return track;
  }

  /// 删除导入的音频（文件 + manifest）。
  ///
  /// 正在把它当背景音乐的设备/会话由调用方负责切换设置。
  Future<void> deleteTrack(String id) async {
    AudioTrack? track;
    for (final t in state) {
      if (t.id == id) {
        track = t;
        break;
      }
    }
    if (track == null) return;
    state = state.where((t) => t.id != id).toList(growable: false);
    await _persist();
    try {
      final dir = await audioLibraryDir();
      final file = File(p.join(dir.path, track.fileName!));
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 文件已删/被占用：manifest 已更新，不影响使用
    }
  }

  Future<Uint8List> _readFile(String path) async {
    final Uint8List bytes;
    try {
      final file = File(path);
      final length = await file.length();
      if (length > kMaxAudioBytes) {
        throw const AudioImportException('音频文件超过 100 MB，无法导入');
      }
      bytes = await file.readAsBytes();
    } on AudioImportException {
      rethrow;
    } catch (e) {
      throw AudioImportException('读取音频文件失败：$e');
    }
    if (bytes.isEmpty) throw const AudioImportException('音频文件为空');
    return bytes;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kKey,
        jsonEncode(<String, dynamic>{
          'v': 1,
          'tracks': state.map((t) => t.toMap()).toList(),
        }),
      );
    } catch (_) {
      // 落盘失败不影响本次使用；下次启动会丢失导入记录
    }
  }
}
