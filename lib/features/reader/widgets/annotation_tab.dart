/// 标注列表：默认按**章节**分组（可折叠），可切换成按**颜色**分组。
///
/// 分组动机：一本书的标注往往散落在几十条，平铺列表很难定位「那一章划过
/// 的句子」；按章节分组 + 折叠，等于给标注加了一层目录。每条标注还能
/// 直接「添加想法」（笔记），不用先跳回正文。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/reading_theme.dart';
import '../../../core/locator.dart';
import '../../../domain/entities/annotation.dart';
import '../../../domain/entities/book.dart';
import '../../notes/annotation_share_sheet.dart';

/// 标注列表（按章节 / 按颜色，可折叠）。
class AnnotationTab extends StatefulWidget {
  const AnnotationTab({
    required this.theme,
    required this.chapters,
    required this.annotations,
    required this.onGotoAnnotation,
    required this.onDelete,
    required this.onEditNote,
    required this.onExport,
    this.unlocatedIds = const <String>{},
    this.onAutoLocate,
    this.onManualLocate,
    this.bookTitle = '',
    this.author = '',
    super.key,
  });

  /// 阅读主题。
  final ReadingTheme theme;

  /// 章节列表（分组标题用）。
  final List<BookChapter> chapters;

  /// 标注列表。
  final List<Annotation> annotations;

  /// 跳转到标注位置（不改变阅读进度，由阅读页挂起进度）。
  final void Function(String locatorJson) onGotoAnnotation;

  /// 删除标注。
  final void Function(String id) onDelete;

  /// 添加/编辑想法。
  final void Function(Annotation annotation) onEditNote;

  /// 导出 Markdown。
  final VoidCallback onExport;

  /// 当前书里对不上原文的标注 id（显示「未定位」与定位入口）。
  final Set<String> unlocatedIds;

  /// 自动查询定位（在书里搜原文）。
  final void Function(Annotation annotation)? onAutoLocate;

  /// 手动定位（进入阅读页手动选页）。
  final void Function(Annotation annotation)? onManualLocate;

  /// 书名 / 作者（卡片式分享用）。
  final String bookTitle;
  final String author;

  @override
  State<AnnotationTab> createState() => _AnnotationTabState();
}

class _AnnotationTabState extends State<AnnotationTab> {
  /// false = 按章节（默认）；true = 按颜色。
  bool _byColor = false;

  /// 标注类型筛选：null = 全部；underline = 划线；其余按高亮。
  AnnotationType? _typeFilter;

  /// 收起的组。
  final Set<String> _collapsed = {};

  Color get _fg => widget.theme.chromeForeground;

  /// 当前类型筛选下的标注。
  List<Annotation> get _visible => _typeFilter == null
      ? widget.annotations
      : widget.annotations
            .where(
              (a) => _typeFilter == AnnotationType.underline
                  ? a.type == AnnotationType.underline
                  : a.type != AnnotationType.underline,
            )
            .toList();

  static Color colorOf(Annotation a) => switch (a.color) {
    AnnotationColor.yellow => const Color(0xFFF7D774),
    AnnotationColor.green => const Color(0xFFA9D98B),
    AnnotationColor.blue => const Color(0xFF9CC3F5),
    AnnotationColor.rose => const Color(0xFFF2A9B8),
  };

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final groups = _byColor ? _groupByColor(visible) : _groupByChapter(visible);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    _typeFilter == null
                        ? '共 ${visible.length} 条'
                        : '共 ${visible.length}/${widget.annotations.length} 条',
                    style: TextStyle(
                      color: _fg.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ModeChip(
                    label: '按章节',
                    selected: !_byColor,
                    fg: _fg,
                    onTap: () => setState(() => _byColor = false),
                  ),
                  const SizedBox(width: 6),
                  _ModeChip(
                    label: '按颜色',
                    selected: _byColor,
                    fg: _fg,
                    onTap: () => setState(() => _byColor = true),
                  ),
                  const SizedBox(width: 6),
                  _TypeFilterChip(
                    value: _typeFilter,
                    fg: _fg,
                    onChanged: (value) => setState(() => _typeFilter = value),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: widget.annotations.isEmpty ? null : widget.onExport,
            icon: Icon(
              Icons.ios_share,
              size: 18,
              color: _fg.withValues(alpha: 0.8),
            ),
            tooltip: '导出 Markdown',
          ),
        ],
      ),
    );

    if (widget.annotations.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: Center(
              child: Text(
                '选中正文即可划线',
                style: TextStyle(color: _fg.withValues(alpha: 0.6)),
              ),
            ),
          ),
        ],
      );
    }

    if (visible.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: Center(
              child: Text(
                '没有该类型的标注',
                style: TextStyle(color: _fg.withValues(alpha: 0.6)),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final g in groups) ...[
                _groupHeader(g),
                if (!_collapsed.contains(g.key))
                  for (final a in g.items) _tile(a),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Widget _groupHeader(_Group g) {
    final collapsed = _collapsed.contains(g.key);
    return InkWell(
      onTap: () => setState(() {
        if (collapsed) {
          _collapsed.remove(g.key);
        } else {
          _collapsed.add(g.key);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Row(
          children: [
            if (g.color != null)
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: g.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Expanded(
              child: Text(
                g.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${g.items.length}',
              style: TextStyle(color: _fg.withValues(alpha: 0.5), fontSize: 12),
            ),
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 18,
              color: _fg.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  /// 卡片式分享一条标注（划线 / 高亮 / 笔记）。
  void _shareAnnotation(Annotation a) {
    final note = (a.note ?? '').trim();
    unawaited(
      showAnnotationShareSheet(
        context,
        AnnotationCardData(
          quote: (a.quotedText ?? '').trim(),
          note: note.isEmpty ? null : note,
          bookTitle: widget.bookTitle,
          author: widget.author,
          createdAt: a.createdAt,
          colorToken: a.color.token,
          kindLabel: a.type == AnnotationType.underline
              ? '划线'
              : a.type == AnnotationType.note
              ? '笔记'
              : '高亮',
        ),
      ),
    );
  }

  Widget _tile(Annotation a) {
    final note = (a.note ?? '').trim();
    final unlocated = widget.unlocatedIds.contains(a.id);
    final canLocate =
        unlocated &&
        (widget.onAutoLocate != null || widget.onManualLocate != null);
    return Dismissible(
      key: ValueKey(a.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.redAccent,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => widget.onDelete(a.id),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 4,
          height: 36,
          decoration: BoxDecoration(
            color: colorOf(a),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                (a.quotedText ?? '').trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _fg, fontSize: 13, height: 1.4),
              ),
            ),
            if (unlocated)
              Container(
                margin: const EdgeInsets.only(left: 6, top: 1),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFE08A2E).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '未定位',
                  style: TextStyle(
                    color: Color(0xFFB36A12),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        subtitle: note.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.format_quote,
                      size: 13,
                      color: _fg.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        note,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _fg.withValues(alpha: 0.75),
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _shareAnnotation(a),
              icon: Icon(
                Icons.ios_share_outlined,
                size: 17,
                color: _fg.withValues(alpha: 0.7),
              ),
              tooltip: '分享卡片',
            ),
            IconButton(
              onPressed: () => widget.onEditNote(a),
              icon: Icon(
                note.isEmpty ? Icons.add_comment_outlined : Icons.edit_note,
                size: 18,
                color: _fg.withValues(alpha: 0.7),
              ),
              tooltip: note.isEmpty ? '添加想法' : '编辑想法',
            ),
          ],
        ),
        // 未定位的笔记不在行尾挤第三个按钮：长按抬手弹「自动 / 手动定位」。
        onLongPress: canLocate ? () => _showLocateSheet(a) : null,
        onTap: () => widget.onGotoAnnotation(a.locatorStart),
      ),
    );
  }

  /// 未定位标注：弹「自动查询 / 手动定位」选择。
  Future<void> _showLocateSheet(Annotation a) async {
    final action = await showModalBottomSheet<_LocateAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '定位这条标注',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '「${(a.quotedText ?? '').trim()}」',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(
                        ctx,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              key: const ValueKey('annotation-auto-locate'),
              leading: const Icon(Icons.travel_explore),
              title: const Text('自动查询定位'),
              subtitle: const Text('在本书里搜索原文，找到后跳过去'),
              onTap: () => Navigator.of(ctx).pop(_LocateAction.auto),
            ),
            ListTile(
              key: const ValueKey('annotation-manual-locate'),
              leading: const Icon(Icons.my_location_outlined),
              title: const Text('手动定位'),
              subtitle: const Text('收起列表，翻到目标页后点「设为当前页」'),
              onTap: () => Navigator.of(ctx).pop(_LocateAction.manual),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _LocateAction.auto:
        widget.onAutoLocate?.call(a);
      case _LocateAction.manual:
        widget.onManualLocate?.call(a);
    }
  }

  List<_Group> _groupByChapter(List<Annotation> annotations) {
    final map = <int, List<Annotation>>{};
    for (final a in annotations) {
      final loc = locatorFromJson(a.locatorStart);
      // 对不上原文的标注归到「未定位」，不要按旧章号混进正常章节。
      final idx = widget.unlocatedIds.contains(a.id)
          ? -1
          : (loc?.chapterIndex ?? -1);
      map.putIfAbsent(idx, () => []).add(a);
    }
    final keys = map.keys.toList()..sort();
    return [
      for (final k in keys)
        _Group(key: '$k', label: _chapterLabel(k), items: map[k]!),
    ];
  }

  String _chapterLabel(int idx) {
    if (idx < 0 || idx >= widget.chapters.length) return '未定位';
    final title = widget.chapters[idx].title;
    if (title.isNotEmpty) return title;
    return '第 ${idx + 1} 章';
  }

  List<_Group> _groupByColor(List<Annotation> annotations) {
    const order = [
      AnnotationColor.yellow,
      AnnotationColor.green,
      AnnotationColor.blue,
      AnnotationColor.rose,
    ];
    const names = {
      AnnotationColor.yellow: '黄色',
      AnnotationColor.green: '绿色',
      AnnotationColor.blue: '蓝色',
      AnnotationColor.rose: '玫红',
    };
    final groups = <_Group>[];
    for (final c in order) {
      final items = annotations.where((a) => a.color == c).toList();
      if (items.isEmpty) continue;
      groups.add(
        _Group(
          key: c.name,
          label: names[c] ?? c.name,
          items: items,
          color: colorOf(items.first),
        ),
      );
    }
    return groups;
  }
}

/// 未定位标注的两种处理方式。
enum _LocateAction { auto, manual }

/// 一个分组（章节或颜色）。
class _Group {
  const _Group({
    required this.key,
    required this.label,
    required this.items,
    this.color,
  });

  final String key;
  final String label;
  final List<Annotation> items;
  final Color? color;
}

/// 类型筛选小胶囊（全部 / 高亮 / 划线）。
class _TypeFilterChip extends StatelessWidget {
  const _TypeFilterChip({
    required this.value,
    required this.fg,
    required this.onChanged,
  });

  final AnnotationType? value;
  final Color fg;
  final ValueChanged<AnnotationType?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value != null;
    final label = value == null
        ? '全部类型'
        : (value == AnnotationType.underline ? '划线' : '高亮');
    return PopupMenuButton<String>(
      key: const ValueKey('annotation-type-filter'),
      tooltip: '按类型筛选',
      initialValue: value == null
          ? 'all'
          : (value == AnnotationType.underline ? 'underline' : 'highlight'),
      onSelected: (raw) => onChanged(switch (raw) {
        'underline' => AnnotationType.underline,
        'highlight' => AnnotationType.highlight,
        _ => null,
      }),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'all', child: Text('全部类型')),
        PopupMenuItem(value: 'highlight', child: Text('高亮')),
        PopupMenuItem(value: 'underline', child: Text('划线')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? fg.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: fg.withValues(alpha: selected ? 0.4 : 0.18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: fg.withValues(alpha: selected ? 0.95 : 0.6),
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 1),
            Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: fg.withValues(alpha: selected ? 0.95 : 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分组方式小胶囊。
class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.fg,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? fg.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: fg.withValues(alpha: selected ? 0.4 : 0.18),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg.withValues(alpha: selected ? 0.95 : 0.6),
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
