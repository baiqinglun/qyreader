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
import '../data/repositories/annotation_repository_impl.dart';
import '../data/repositories/book_repository_impl.dart';
import '../data/repositories/progress_repository_impl.dart';
import '../data/repositories/search_repository_impl.dart';
import '../data/repositories/stats_repository_impl.dart';
import '../data/repositories/sync_repository_impl.dart';
import '../data/sync/local_object_store.dart';
import '../data/sync/s3_object_store.dart';
import '../data/sync/sync_backend_store.dart';
import '../domain/repositories/annotation_repository.dart';
import '../domain/repositories/book_repository.dart';
import '../domain/repositories/progress_repository.dart';
import '../domain/repositories/search_repository.dart';
import '../domain/repositories/stats_repository.dart';
import '../domain/repositories/sync_repository.dart';
import '../domain/sync/object_store.dart';

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

/// 阅读进度仓储单例。
@Riverpod(keepAlive: true)
Future<ProgressRepository> progressRepository(Ref ref) async {
  return ProgressRepositoryImpl(
    db: ref.watch(appDatabaseProvider),
    hlcClock: await ref.watch(hlcClockProvider.future),
    deviceId: await ref.watch(deviceIdProvider.future),
  );
}

/// 标注 + 书签仓储单例。
@Riverpod(keepAlive: true)
Future<AnnotationRepository> annotationRepository(Ref ref) async {
  return AnnotationRepositoryImpl(
    db: ref.watch(appDatabaseProvider),
    hlcClock: await ref.watch(hlcClockProvider.future),
    deviceId: await ref.watch(deviceIdProvider.future),
  );
}

/// 全书检索仓储单例。
@Riverpod(keepAlive: true)
Future<SearchRepository> searchRepository(Ref ref) async {
  return SearchRepositoryImpl(
    db: ref.watch(appDatabaseProvider),
    books: await ref.watch(bookRepositoryProvider.future),
  );
}

/// 同步空间 id（多设备填同一空间即互相同步；默认 local 单机空间）。
const String _kSyncSpaceKey = 'sync.spaceId';

/// 同步空间标识。
@Riverpod(keepAlive: true)
Future<String> syncSpaceId(Ref ref) async {
  final prefs = await SharedPreferences.getInstance();
  var id = prefs.getString(_kSyncSpaceKey);
  if (id == null || id.isEmpty) {
    id = 'local';
    await prefs.setString(_kSyncSpaceKey, id);
  }
  return id;
}

/// 同步后端配置存储（偏好 + 安全凭据）。
@Riverpod(keepAlive: true)
SyncBackendStore syncBackendStore(Ref ref) => SyncBackendStore();

/// 对象存储：按配置切本地桶 / S3（M6）；S3 配置不完整时回退本地桶。
@Riverpod(keepAlive: true)
Future<ObjectStore> objectStore(Ref ref) async {
  final store = ref.watch(syncBackendStoreProvider);
  final config = await store.loadConfig();
  final spaceId = await ref.watch(syncSpaceIdProvider.future);
  if (config.type == SyncBackendType.s3 && config.s3Complete) {
    final creds = await store.loadCredentials();
    if (creds.configured) {
      return S3ObjectStore(
        endPoint: config.endPoint,
        bucket: config.bucket,
        prefix: config.prefix,
        accessKey: creds.accessKey,
        secretKey: creds.secretKey,
        region: config.region,
        useSSL: config.useSSL,
        port: config.port,
      );
    }
  }
  final dir = await getApplicationSupportDirectory();
  return LocalObjectStore(
    Directory(p.join(dir.path, 'sync_store', spaceId)),
  );
}

/// 同步仓储单例。
@Riverpod(keepAlive: true)
Future<SyncRepository> syncRepository(Ref ref) async {
  return SyncRepositoryImpl(
    db: ref.watch(appDatabaseProvider),
    store: await ref.watch(objectStoreProvider.future),
    spaceId: await ref.watch(syncSpaceIdProvider.future),
    deviceId: await ref.watch(deviceIdProvider.future),
    libraryDir: await ref.watch(libraryDirectoryProvider.future),
    hlcClock: await ref.watch(hlcClockProvider.future),
  );
}

/// 阅读统计仓储单例。
@Riverpod(keepAlive: true)
Future<StatsRepository> statsRepository(Ref ref) async {
  return StatsRepositoryImpl(
    db: ref.watch(appDatabaseProvider),
    deviceId: await ref.watch(deviceIdProvider.future),
  );
}
