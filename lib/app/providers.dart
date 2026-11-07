/// 基础设施 provider：数据库、设备 id、HLC 时钟、书籍仓储。
///
/// 全部 keepAlive（应用级单例）；依赖链条：
/// deviceId(prefs) → hlcClock → bookRepository。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/db/app_database.dart';
import '../core/hlc.dart';
import '../data/repositories/book_repository_impl.dart';
import '../domain/repositories/book_repository.dart';

part 'providers.g.dart';

/// SharedPreferences 的 key：本设备 8 位 id。
const String _kDeviceIdKey = 'device.id';

/// 应用数据库单例。
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) => openAppDatabase();

/// 本设备 8 位标识（首次启动生成并持久化，HLC 时钟使用）。
@Riverpod(keepAlive: true)
Future<String> deviceId(Ref ref) async {
  final prefs = await SharedPreferences.getInstance();
  var id = prefs.getString(_kDeviceIdKey);
  if (id == null || id.length != 8) {
    id = const Uuid().v4().replaceAll('-', '').substring(0, 8);
    await prefs.setString(_kDeviceIdKey, id);
  }
  return id;
}

/// 混合逻辑时钟（同步时间戳全序）。
@Riverpod(keepAlive: true)
Future<HlcClock> hlcClock(Ref ref) async =>
    HlcClock(deviceId: await ref.watch(deviceIdProvider.future));

/// 书籍库根目录（书籍文件与封面落盘处）。
@Riverpod(keepAlive: true)
Future<Directory> libraryDirectory(Ref ref) async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory(p.join(docs.path, 'QYReader'));
}

/// 书籍仓储单例。
@Riverpod(keepAlive: true)
Future<BookRepository> bookRepository(Ref ref) async {
  return BookRepositoryImpl(
    db: ref.watch(appDatabaseProvider),
    hlcClock: await ref.watch(hlcClockProvider.future),
    deviceId: await ref.watch(deviceIdProvider.future),
    libraryDir: await ref.watch(libraryDirectoryProvider.future),
  );
}
