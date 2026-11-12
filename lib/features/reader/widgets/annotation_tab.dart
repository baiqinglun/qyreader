/// 标注列表：默认按**章节**分组（可折叠），可切换成按**颜色**分组。
///
/// 分组动机：一本书的标注往往散落在几十条，平铺列表很难定位「那一章划过
/// 的句子」；按章节分组 + 折叠，等于给标注加了一层目录。每条标注还能
/// 直接「添加想法」（笔记），不用先跳回正文。
library;

import 'package:flutter/material.dart';

import '../../../app/theme/reading_theme.dart';
import '../../../core/locator.dart';
import '../../../domain/entities/annotation.dart';
import '../../../domain/entities/book.dart';

/// 标注列表（按章节 / 按颜色，可折叠）。
class AnnotationTab extends StatefulWidget {
  const AnnotationTab({
    required this.theme,
    required this.chapters,
    required this.annotations,
    required this.onGotoLocator,
    required this.onDelete,
    required this.onEditNote,
    required this.onExport,
    super.key,
  });

  /// 阅读主题。
  final ReadingTheme theme;

  /// 章节列表（分组标题用）。
  final List<BookChapter> chapters;

  /// 标注列表。
  final List<Annotation> annotations;

  /// 跳转到标注位置。
  final void Function(String locatorJson) onGotoLocator;

  /// 删除标注。
  final void Function(String id) onDelete;

  /// 添加/编辑想法。
  final void Function(Annotation annotation) onEditNote;

  /// 导出 Markdown。
  final VoidCallback onExport;

  @override
  State<AnnotationTab> createState() => _AnnotationTabState();
}

class _AnnotationTabState extends State<AnnotationTab> {
  /// false = 按章节（默认）；true = 按颜色。
  bool _byColor = false;

  /// 收起的组。
  final Set<String> _collapsed = {};

  Color get _fg => widget.theme.chromeForeground;

  static Color colorOf(Annotation a) => switch (a.color) {
        AnnotationColor.yellow => const Color(0xFFF7D774),
        AnnotationColor.green => const Color(0xFFA9D98B),
        AnnotationColor.blue => const Color(0xFF9CC3F5),
        AnnotationColor.rose => const Color(0xFFF2A9B8),
      };

  @override
  Widget build(BuildContext context) {
    final groups = _byColor ? _groupByColor() : _groupByChapter();
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Text(
            '共 ${widget.annotations.length} 条',
            style: TextStyle(color: _fg.withValues(alpha: 0.6), fontSize: 12),
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
          const Spacer(),
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

  Widget _tile(Annotation a) {
    final note = (a.note ?? '').trim();
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
        title: Text(
          (a.quotedText ?? '').trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: _fg, fontSize: 13, height: 1.4),
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
        trailing: IconButton(
          onPressed: () => widget.onEditNote(a),
          icon: Icon(
            note.isEmpty ? Icons.add_comment_outlined : Icons.edit_note,
            size: 18,
            color: _fg.withValues(alpha: 0.7),
          ),
          tooltip: note.isEmpty ? '添加想法' : '编辑想法',
        ),
        onTap: () => widget.onGotoLocator(a.locatorStart),
      ),
    );
  }

  List<_Group> _groupByChapter() {
    final map = <int, List<Annotation>>{};
    for (final a in widget.annotations) {
      final loc = locatorFromJson(a.locatorStart);
      final idx = loc?.chapterIndex ?? -1;
      map.putIfAbsent(idx, () => []).add(a);
    }
    final keys = map.keys.toList()..sort();
    return [
      for (final k in keys)
        _Group(
          key: '$k',
          label: _chapterLabel(k),
          items: map[k]!,
        ),
    ];
  }

  String _chapterLabel(int idx) {
    if (idx < 0 || idx >= widget.chapters.length) return '未定位';
    final title = widget.chapters[idx].title;
    if (title.isNotEmpty) return title;
    return '第 ${idx + 1} 章';
  }

  List<_Group> _groupByColor() {
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
      final items = widget.annotations.where((a) => a.color == c).toList();
      if (items.isEmpty) continue;
      groups.add(_Group(
        key: c.name,
        label: names[c] ?? c.name,
        items: items,
        color: colorOf(items.first),
      ));
    }
    return groups;
  }
}

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
