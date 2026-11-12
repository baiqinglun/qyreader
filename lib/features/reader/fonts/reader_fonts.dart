/// 自定义阅读字体：导入 / 注册 / 管理。
///
/// 字体文件落在应用支持目录 `fonts/`，元数据（id / 展示名 / 文件名）存
/// shared_preferences。注册走 `FontLoader`：运行时把字体塞进 Flutter 的
/// 字体集合，正文 `TextStyle(fontFamily: family)` 即可生效。
///
/// family 带 `qyfont_` 前缀，避免与系统字体或书籍自带字体撞名；
/// 空字符串表示系统默认字体（设置里不落 family）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

part 'reader_fonts.g.dart';

/// 一个已导入的字体。
class ReaderFont {
  const ReaderFont({
    required this.id,
    required this.name,
    required this.fileName,
  });

  /// 唯一 id（同时决定 family 名）。
  final String id;

  /// 展示名（默认取导入文件名，不含扩展名）。
  final String name;

  /// 字体目录内的文件名。
  final String fileName;

  /// Flutter 字体集合里的 family 名。
  String get family => 'qyfont_$id';

  /// 序列化为 manifest 条目。
  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id,
    'name': name,
    'file': fileName,
  };

  /// 从 manifest 条目还原；坏条目返回 null（不拖垮整个列表）。
  static ReaderFont? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final file = raw['file'];
    if (id is! String || id.isEmpty || id.length > 64) return null;
    if (name is! String || name.isEmpty || name.length > 200) return null;
    if (file is! String || file.isEmpty || file.length > 128) return null;
    // 只接受纯文件名：manifest 手改/旧版本残留不能把路径带到字体目录之外
    if (file.contains('/') || file.contains('\\') || file.contains('..')) {
      return null;
    }
    return ReaderFont(id: id, name: name, fileName: file);
  }
}

/// 字体导入失败（消息可直接展示给用户）。
class FontImportException implements Exception {
  /// 带用户可读消息构造。
  const FontImportException(this.message);

  /// 用户可读原因。
  final String message;

  @override
  String toString() => message;
}

/// 单个字体文件大小上限：中文字体通常 5~30 MB，超过 64 MB 基本是误选。
const int _kMaxFontBytes = 64 * 1024 * 1024;

/// 支持的字体扩展名（小写）；不支持返回 null。
///
/// WOFF/WOFF2 是网页压缩格式，Flutter 的 FontLoader 不认，直接排除。
String? supportedFontExtension(String path) {
  final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
  return const <String>{'ttf', 'otf', 'ttc'}.contains(ext) ? ext : null;
}

/// 文件头是否为可加载的 SFNT 字体（TrueType / OpenType / 集合）。
///
/// 只认文件内容：用户把 .ttf 的压缩包/图片改个后缀也能被拦住。
bool looksLikeSfnt(Uint8List bytes) {
  if (bytes.length < 12) return false;
  if (bytes[0] == 0x00 &&
      bytes[1] == 0x01 &&
      bytes[2] == 0x00 &&
      bytes[3] == 0x00) {
    return true; // TrueType
  }
  final tag = String.fromCharCodes(bytes.sublist(0, 4));
  return tag == 'OTTO' || tag == 'true' || tag == 'typ1' || tag == 'ttcf';
}

/// 解析 manifest（JSON）；任何坏条目逐条跳过。
List<ReaderFont> parseReaderFontManifest(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const <ReaderFont>[];
  }
  if (decoded is! Map) return const <ReaderFont>[];
  final list = decoded['fonts'];
  if (list is! List) return const <ReaderFont>[];
  final seen = <String>{};
  final out = <ReaderFont>[];
  for (final item in list) {
    final font = ReaderFont.fromMap(item);
    if (font == null || !seen.add(font.id)) continue;
    out.add(font);
  }
  return out;
}

/// 按 family 查找字体（找不到 = 已删除，调用方应回退系统字体）。
ReaderFont? findReaderFont(List<ReaderFont> fonts, String family) {
  for (final font in fonts) {
    if (font.family == family) return font;
  }
  return null;
}

/// 字体目录：`<应用支持目录>/fonts`。
Future<Directory> _fontsDir() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory(p.join(base.path, 'fonts'));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// 字体库控制器：manifest 读写 + 文件复制 + FontLoader 注册。
@Riverpod(keepAlive: true)
class ReaderFontsController extends _$ReaderFontsController {
  static const String _kKey = 'reader.fonts';

  /// manifest 恢复完成（阅读页首帧前等它，避免先用系统字体排一遍）。
  final _restored = Completer<void>();

  /// 已注册到 Flutter 字体集合的 family（进程内只需注册一次）。
  final Set<String> _loaded = <String>{};

  /// 注册中的 family（并发调用共用同一个 Future，避免重复 load）。
  final Map<String, Future<void>> _loading = <String, Future<void>>{};

  @override
  List<ReaderFont> build() {
    _restore();
    return const <ReaderFont>[];
  }

  /// 等 manifest 读取完成。
  Future<void> waitRestored() => _restored.future;

  /// 同步拉回新字体后重新读 manifest（不重启也能在字体列表里看到）。
  ///
  /// 只以 prefs 为准：同步已经把下载到的条目合并进 `reader.fonts`。
  Future<void> reload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      state = raw == null ? const <ReaderFont>[] : parseReaderFontManifest(raw);
    } catch (_) {
      // 读取失败保持当前列表
    }
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw == null) return;
      // 读 prefs 期间用户已导入过字体（极少见）就别覆盖新状态
      if (state.isNotEmpty) return;
      state = parseReaderFontManifest(raw);
    } catch (_) {
      // 损坏的 manifest 按「无导入字体」处理
    } finally {
      if (!_restored.isCompleted) _restored.complete();
    }
  }

  /// 从文件导入字体并注册（文件选择由调用方负责）。
  ///
  /// 失败抛 [FontImportException]，消息可直接展示。
  Future<ReaderFont> importFromFile(String path) async {
    final ext = supportedFontExtension(path);
    if (ext == null) {
      throw const FontImportException('仅支持 TTF / OTF / TTC 字体文件');
    }
    final Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } catch (e) {
      throw FontImportException('读取字体文件失败：$e');
    }
    if (bytes.isEmpty) throw const FontImportException('字体文件为空');
    if (bytes.length > _kMaxFontBytes) {
      throw const FontImportException('字体文件超过 64 MB，无法导入');
    }
    if (!looksLikeSfnt(bytes)) {
      throw const FontImportException('文件内容不是有效的 TrueType/OpenType 字体');
    }

    final id = const Uuid().v4().replaceAll('-', '').substring(0, 10);
    final fileName = '$id.$ext';
    final dir = await _fontsDir();
    try {
      await File(p.join(dir.path, fileName)).writeAsBytes(bytes, flush: true);
    } catch (e) {
      throw FontImportException('保存字体文件失败：$e');
    }

    var name = p.basenameWithoutExtension(path).trim();
    if (name.isEmpty) name = '导入字体';
    if (name.length > 60) name = name.substring(0, 60);

    final font = ReaderFont(id: id, name: name, fileName: fileName);
    state = <ReaderFont>[...state, font];
    await _persist();
    // 先注册再返回：调用方紧接着会把它设为当前字体，必须已经能排字。
    // 注册失败（字体表损坏 / 引擎不支持该变体）就回滚，不留下排不出来的条目。
    try {
      await _register(font, bytes);
    } catch (_) {
      state = state.where((f) => f.id != id).toList(growable: false);
      await _persist();
      try {
        await File(p.join(dir.path, fileName)).delete();
      } catch (_) {}
      throw const FontImportException('这个字体无法被系统加载（文件可能已损坏）');
    }
    return font;
  }

  /// 删除字体（文件 + manifest）。已加载进引擎的字体无法卸载，
  /// 所以调用方要先把设置里指向它的 family 清掉。
  Future<void> deleteFont(String id) async {
    final font = findReaderFont(state, 'qyfont_$id');
    if (font == null) return;
    state = state.where((f) => f.id != id).toList(growable: false);
    await _persist();
    _loaded.remove(font.family);
    try {
      final dir = await _fontsDir();
      final file = File(p.join(dir.path, font.fileName));
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 文件已删/被占用：manifest 已更新，不影响使用
    }
  }

  /// 字体是否已处理过（注册成功，或文件缺失被跳过）。
  ///
  /// 阅读页据此决定能不能把 family 交给 TextStyle：没处理过就先用系统字体
  /// 排一遍，等注册完成再重排，避免引着一个还不存在的 family 出怪版面。
  bool hasLoaded(ReaderFont font) => _loaded.contains(font.family);

  /// 确保字体已注册（重复调用安全）。
  Future<void> ensureLoaded(ReaderFont font) {
    if (_loaded.contains(font.family)) return Future<void>.value();
    return _loading.putIfAbsent(font.family, () {
      return _load(font).whenComplete(() => _loading.remove(font.family));
    });
  }

  Future<void> _load(ReaderFont font) async {
    final dir = await _fontsDir();
    final file = File(p.join(dir.path, font.fileName));
    if (!await file.exists()) {
      // 文件被外部清掉：标记已处理，正文静默回退系统字体；
      // 不标记的话每次重建都会重读一次磁盘。
      _loaded.add(font.family);
      return;
    }
    final bytes = await file.readAsBytes();
    await _register(font, bytes);
  }

  Future<void> _register(ReaderFont font, Uint8List bytes) async {
    if (_loaded.contains(font.family)) return;
    final loader = FontLoader(font.family)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loaded.add(font.family);
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kKey,
        jsonEncode(<String, dynamic>{
          'v': 1,
          'fonts': state.map((f) => f.toMap()).toList(),
        }),
      );
    } catch (_) {
      // 落盘失败不影响本次使用；下次启动会丢失自定义字体
    }
  }
}
