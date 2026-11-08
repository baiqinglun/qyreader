/// 对象存储抽象（S3 语义子集）。
///
/// v1 先用 [LocalObjectStore]（本地目录模拟桶）；接入真实 S3（minio SDK）
/// 时实现同一接口即可替换，同步引擎不感知存储形态。
library;

/// 对象存储。
abstract interface class ObjectStore {
  /// 写入对象（同 key 覆盖）。
  Future<void> put(String key, List<int> bytes);

  /// 读取对象；不存在返回 null。
  Future<List<int>?> get(String key);

  /// 列举某前缀下的全部 key（递归）。
  Future<List<String>> list(String prefix);

  /// 删除对象（不存在视为成功）。
  Future<void> delete(String key);
}
