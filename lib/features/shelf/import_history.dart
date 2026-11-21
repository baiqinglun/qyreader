/// 导入记录：成功 / 重复 / 失败，持久化在 SharedPreferences。
///
/// 导入结果弹窗可以随手关掉，再从书架「⋯ → 导入记录」打开；只要用户没有
/// 点「清空记录」，记录跨重启保留。这里只存文件名与结果，不存原始路径。
library;

import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'import_history.g.dart';

/// 单次文件的导入结果。
enum ImportRecordStatus {
  /// 已加入书架。
  success('成功'),

  /// 内容重复，没有产生第二本。
  duplicate('重复'),

  /// 解析 / 格式 / 读写失败。
  failure('失败');

  const ImportRecordStatus(this.label);

  /// 中文展示名。
  final String label;

  /// 从名称恢复；未知值按失败处理。
  static ImportRecordStatus fromName(String? name) =>
      ImportRecordStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => ImportRecordStatus.failure,
      );
}

/// 一条导入记录。
class ImportRecord {
  /// 构造。
  const ImportRecord({
    required this.fileName,
    required this.title,
    required this.status,
    required this.message,
    required this.at,
  });

  /// 文件名（含扩展名）。
  final String fileName;

  /// 书名（成功时是入库书名，其余回退文件名）。
  final String title;

  /// 结果。
  final ImportRecordStatus status;

  /// 说明（重复 / 失败原因）。
  final String message;

  /// 时间（epoch ms）。
  final int at;

  /// 转 JSON。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'fileName': fileName,
    'title': title,
    'status': status.name,
    'message': message,
    'at': at,
  };

  /// 从 JSON 恢复（损坏字段回退默认值）。
  factory ImportRecord.fromJson(Map<String, dynamic> json) => ImportRecord(
    fileName: (json['fileName'] as String?)?.trim() ?? '未知文件',
    title: (json['title'] as String?)?.trim() ?? '',
    status: ImportRecordStatus.fromName(json['status'] as String?),
    message: (json['message'] as String?)?.trim() ?? '',
    at: (json['at'] as num?)?.toInt() ?? 0,
  );
}

/// 导入结果统计。
class ImportRecordSummary {
  /// 构造。
  const ImportRecordSummary({
    required this.success,
    required this.duplicate,
    required this.failure,
  });

  /// 成功数。
  final int success;

  /// 重复数。
  final int duplicate;

  /// 失败数。
  final int failure;

  /// 总条数。
  int get total => success + duplicate + failure;
}

/// 统计一组导入记录。
ImportRecordSummary importRecordSummary(List<ImportRecord> records) {
  var success = 0;
  var duplicate = 0;
  var failure = 0;
  for (final record in records) {
    switch (record.status) {
      case ImportRecordStatus.success:
        success++;
      case ImportRecordStatus.duplicate:
        duplicate++;
      case ImportRecordStatus.failure:
        failure++;
    }
  }
  return ImportRecordSummary(
    success: success,
    duplicate: duplicate,
    failure: failure,
  );
}

/// 记录列表最多保留多少条（防止 prefs 无限膨胀）。
const int kImportHistoryMax = 200;

/// prefs key。
const String kImportHistoryPrefsKey = 'import.history';

/// 解码记录列表；损坏输入回退空列表。
List<ImportRecord> decodeImportRecords(String? raw) {
  if (raw == null || raw.isEmpty) return const <ImportRecord>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <ImportRecord>[];
    final records = <ImportRecord>[];
    for (final item in decoded) {
      if (item is Map) {
        records.add(ImportRecord.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    records.sort((a, b) => b.at.compareTo(a.at));
    return records.length > kImportHistoryMax
        ? records.sublist(0, kImportHistoryMax)
        : records;
  } catch (_) {
    return const <ImportRecord>[];
  }
}

/// 编码记录列表。
String encodeImportRecords(List<ImportRecord> records) => jsonEncode(
  <Map<String, dynamic>>[for (final record in records) record.toJson()],
);

/// 导入记录仓储（keepAlive：导入控制器与弹窗共用一份状态）。
@Riverpod(keepAlive: true)
class ImportHistoryController extends _$ImportHistoryController {
  @override
  Future<List<ImportRecord>> build() async {
    final prefs = await SharedPreferences.getInstance();
    return decodeImportRecords(prefs.getString(kImportHistoryPrefsKey));
  }

  /// 追加一批记录（新的在前，最多 [kImportHistoryMax] 条）。
  Future<void> addAll(List<ImportRecord> records) async {
    if (records.isEmpty) return;
    final current = state.valueOrNull ?? await future;
    final next = <ImportRecord>[...records, ...current];
    final trimmed = next.length > kImportHistoryMax
        ? next.sublist(0, kImportHistoryMax)
        : next;
    state = AsyncData(trimmed);
    await _save(trimmed);
  }

  /// 清空全部记录（只清记录，不影响已导入的书）。
  Future<void> clear() async {
    state = const AsyncData(<ImportRecord>[]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kImportHistoryPrefsKey);
  }

  Future<void> _save(List<ImportRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kImportHistoryPrefsKey, encodeImportRecords(records));
  }
}
