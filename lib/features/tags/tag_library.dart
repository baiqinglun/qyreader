/// 标签库：跨书标签的并集 + 用户手动新增的空标签。
///
/// 标签本体仍存在每本书的 `books.tags` 里（参与同步）；这里只保存
/// 「标签管理页新增、暂时还没挂到书上」的标签，让选择器有稳定的全量列表。
/// 因此不需要新建数据库表，也不用做 schema 迁移。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/book.dart';
import '../shelf/shelf_controller.dart';

part 'tag_library.g.dart';

/// 标签名规范化：去首尾空白、限长 20；空名返回 null。
String? normalizeTagName(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return null;
  return v.length > 20 ? v.substring(0, 20) : v;
}

/// 标签摘要：名称 + 使用它的书数（0 = 标签库里新增、还没挂到书上）。
@immutable
class TagSummary {
  /// 创建摘要。
  const TagSummary({required this.name, required this.count});

  /// 标签名。
  final String name;

  /// 使用该标签的书籍数量。
  final int count;
}

/// 手动维护的标签库（prefs key `tags.library`）。
@Riverpod(keepAlive: true)
class TagLibraryController extends _$TagLibraryController {
  static const String _kKey = 'tags.library';

  /// 用户是否已手动修改（prefs 恢复晚到时不能覆盖用户刚做的选择）。
  bool _userChanged = false;

  @override
  List<String> build() {
    _restore();
    return const <String>[];
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_userChanged) return;
      state = _decode(prefs.getStringList(_kKey));
    } catch (_) {
      // 读取失败按空标签库处理
    }
  }

  /// 新增一个标签（已存在时忽略）。
  Future<void> add(String raw) async {
    final name = normalizeTagName(raw);
    if (name == null || state.contains(name)) return;
    await _set([...state, name]);
  }

  /// 重命名标签库里的标签（目标已存在时合并）。
  Future<void> rename(String from, String to) async {
    final name = normalizeTagName(to);
    if (name == null || name == from) return;
    final next = <String>[];
    for (final tag in state) {
      final value = tag == from ? name : tag;
      if (!next.contains(value)) next.add(value);
    }
    await _set(next);
  }

  /// 从标签库移除标签。
  Future<void> remove(String tag) async {
    if (!state.contains(tag)) return;
    await _set([
      for (final value in state)
        if (value != tag) value,
    ]);
  }

  Future<void> _set(List<String> next) async {
    _userChanged = true;
    state = List.unmodifiable(next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kKey, next);
    } catch (_) {
      // 落盘失败：本次仍然生效
    }
  }

  static List<String> _decode(List<String>? raw) {
    final out = <String>[];
    for (final item in raw ?? const <String>[]) {
      final name = normalizeTagName(item);
      if (name != null && !out.contains(name)) out.add(name);
    }
    return List.unmodifiable(out);
  }
}

/// 全量标签摘要：书架用过的标签 + 标签库里的空标签。
///
/// 按使用数降序、名称升序排；标签管理页和编辑书籍的标签选择器共用。
@riverpod
List<TagSummary> tagSummaries(Ref ref) {
  final library = ref.watch(tagLibraryControllerProvider);
  final items =
      ref.watch(shelfItemsProvider).valueOrNull ?? const <ShelfItem>[];
  final counts = <String, int>{};
  for (final item in items) {
    for (final raw in item.book.tags) {
      final name = normalizeTagName(raw);
      if (name == null) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }
  final names = <String>{...counts.keys, ...library};
  final list = <TagSummary>[
    for (final name in names) TagSummary(name: name, count: counts[name] ?? 0),
  ];
  list.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0 ? byCount : a.name.compareTo(b.name);
  });
  return List.unmodifiable(list);
}
