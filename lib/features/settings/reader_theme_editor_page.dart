/// 阅读主题编辑页：名称 / 背景 / 背景图 / 字号 / 行距 / 段距 / 页边距。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/theme/reading_theme.dart';
import '../reader/reader_settings.dart';
import '../reader/reader_themes.dart';

/// 新建 / 编辑一个自定义阅读主题。
class ReaderThemeEditorPage extends ConsumerStatefulWidget {
  const ReaderThemeEditorPage({this.initial, super.key});

  /// null = 新建。
  final ReaderThemePreset? initial;

  @override
  ConsumerState<ReaderThemeEditorPage> createState() =>
      _ReaderThemeEditorPageState();
}

class _ReaderThemeEditorPageState extends ConsumerState<ReaderThemeEditorPage> {
  late final TextEditingController _name;
  late ReadingTheme _background;
  late String _image;
  late double _fontSize;
  late double _lineHeight;
  late double _paragraphSpacing;
  late double _marginLeft;
  late double _marginRight;
  late double _marginTop;
  late double _marginBottom;

  /// 本次新上传、尚未保存的图片；取消编辑时删掉，避免留垃圾。
  String? _pendingImage;

  @override
  void initState() {
    super.initState();
    final p0 = widget.initial;
    _name = TextEditingController(text: p0?.name ?? '我的主题');
    _background = p0?.background ?? ReadingTheme.paper;
    _image = p0?.backgroundImage ?? '';
    _fontSize = p0?.fontSize ?? 18;
    _lineHeight = p0?.lineHeight ?? 1.7;
    _paragraphSpacing = p0?.paragraphSpacing ?? 0.4;
    _marginLeft = p0?.marginLeft ?? 16;
    _marginRight = p0?.marginRight ?? 16;
    _marginTop = p0?.marginTop ?? 12;
    _marginBottom = p0?.marginBottom ?? 12;
  }

  @override
  void dispose() {
    _name.dispose();
    final pending = _pendingImage;
    if (pending != null && pending != (widget.initial?.backgroundImage ?? '')) {
      // 未保存的新图：直接删。
      File(pending).delete().ignore();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    final source = picked?.files.single.path;
    if (source == null || source.isEmpty) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'QYReader', 'backgrounds'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext = p.extension(source).isEmpty
          ? '.jpg'
          : p.extension(source).toLowerCase();
      final dest = p.join(
        dir.path,
        'theme-${DateTime.now().microsecondsSinceEpoch}$ext',
      );
      await File(source).copy(dest);
      if (!mounted) {
        File(dest).delete().ignore();
        return;
      }
      // 替换掉本次之前未保存的图。
      final oldPending = _pendingImage;
      if (oldPending != null) File(oldPending).delete().ignore();
      setState(() {
        _image = dest;
        _pendingImage = dest;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('背景图导入失败：$e')));
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('给主题起个名字')));
      return;
    }
    // 自定义主题带整份排版快照：新建时以当前阅读设置为底，编辑时沿用原快照；
    // 编辑页改的这几项覆盖进去，其余（标题/页眉页脚等）保持不动。
    final baseSnapshot =
        widget.initial?.snapshot ??
        ref.read(readingSettingsControllerProvider).toMap();
    final snapshot = <String, dynamic>{
      ...baseSnapshot,
      'theme': _background.name,
      'backgroundImage': _image,
      'fontSize': _fontSize,
      'lineHeight': _lineHeight,
      'paragraphSpacing': _paragraphSpacing,
      'marginLeft': _marginLeft,
      'marginRight': _marginRight,
      'marginTop': _marginTop,
      'marginBottom': _marginBottom,
    };
    final preset = ReaderThemePreset(
      id:
          widget.initial?.id ??
          'custom:${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      background: _background,
      backgroundImage: _image,
      fontSize: _fontSize,
      lineHeight: _lineHeight,
      paragraphSpacing: _paragraphSpacing,
      marginLeft: _marginLeft,
      marginRight: _marginRight,
      marginTop: _marginTop,
      marginBottom: _marginBottom,
      snapshot: snapshot,
    );
    await ref.read(readerThemesControllerProvider.notifier).save(preset);
    _pendingImage = null;
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? '新建阅读主题' : '编辑阅读主题'),
        actions: [
          TextButton(
            key: const ValueKey('reader-theme-save'),
            onPressed: _save,
            child: const Text('保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Preview(
            name: _name.text.trim().isEmpty ? '主题预览' : _name.text.trim(),
            background: _background,
            image: _image,
            fontSize: _fontSize,
            lineHeight: _lineHeight,
            paragraphSpacing: _paragraphSpacing,
          ),
          const SizedBox(height: 16),
          const _Label('名称'),
          TextField(
            key: const ValueKey('reader-theme-name'),
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '例如：暖黄夜晚',
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const _Label('背景色'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final t in ReadingTheme.values)
                _BackgroundChoice(
                  theme: t,
                  selected: _background == t,
                  onTap: () => setState(() => _background = t),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('reader-theme-upload'),
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('上传背景图'),
                ),
              ),
              if (_image.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '移除背景图',
                  onPressed: () => setState(() {
                    _image = '';
                  }),
                  icon: const Icon(Icons.close),
                ),
              ],
            ],
          ),
          if (_image.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_image),
                width: double.infinity,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 120,
                  color: scheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: const Text('背景图已失效'),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const _Label('正文'),
          _Slider(
            label: '字号',
            value: _fontSize,
            min: 14,
            max: 28,
            display: '${_fontSize.round()}',
            onChanged: (v) => setState(() => _fontSize = v),
          ),
          _Slider(
            label: '行距',
            value: _lineHeight,
            min: 1.2,
            max: 2.4,
            display: _lineHeight.toStringAsFixed(1),
            onChanged: (v) => setState(() => _lineHeight = v),
          ),
          _Slider(
            label: '段间距',
            value: _paragraphSpacing,
            min: 0,
            max: 2,
            display: _paragraphSpacing.toStringAsFixed(1),
            onChanged: (v) => setState(() => _paragraphSpacing = v),
          ),
          const SizedBox(height: 20),
          const _Label('页边距'),
          _Slider(
            label: '左',
            value: _marginLeft,
            min: 0,
            max: 64,
            display: '${_marginLeft.round()}',
            onChanged: (v) => setState(() => _marginLeft = v),
          ),
          _Slider(
            label: '右',
            value: _marginRight,
            min: 0,
            max: 64,
            display: '${_marginRight.round()}',
            onChanged: (v) => setState(() => _marginRight = v),
          ),
          _Slider(
            label: '上',
            value: _marginTop,
            min: 0,
            max: 64,
            display: '${_marginTop.round()}',
            onChanged: (v) => setState(() => _marginTop = v),
          ),
          _Slider(
            label: '下',
            value: _marginBottom,
            min: 0,
            max: 64,
            display: '${_marginBottom.round()}',
            onChanged: (v) => setState(() => _marginBottom = v),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            display,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _BackgroundChoice extends StatelessWidget {
  const _BackgroundChoice({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final ReadingTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('reader-theme-bg-${theme.name}'),
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 72,
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 34,
              decoration: BoxDecoration(
                color: theme.background,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              ),
            ),
            const SizedBox(height: 4),
            Text(theme.label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.name,
    required this.background,
    required this.image,
    required this.fontSize,
    required this.lineHeight,
    required this.paragraphSpacing,
  });

  final String name;
  final ReadingTheme background;
  final String image;
  final double fontSize;
  final double lineHeight;
  final double paragraphSpacing;

  @override
  Widget build(BuildContext context) {
    final fg = background.foreground;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 170,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: background.background),
            if (image.isNotEmpty)
              Image.file(
                File(image),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            if (image.isNotEmpty)
              ColoredBox(color: background.background.withValues(alpha: 0.35)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '读书是一件安静的事，字句在纸面上慢慢展开。',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: fontSize,
                      height: lineHeight,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '行距 / 段距 / 边距会跟随主题生效',
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
