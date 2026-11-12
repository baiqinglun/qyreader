/// 阅读字体选择面板：系统默认 / 导入字体（含导入、删除）。
///
/// 面板自身从阅读设置里取主题色，阅读页排版面板与设置页共用同一入口。
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fonts/reader_fonts.dart';
import '../reader_settings.dart';
import '../../../app/theme/motion.dart';

/// 弹出字体选择面板。
Future<void> showFontPickerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: kSmoothSheetAnimation,
    backgroundColor: Colors.transparent,
    builder: (_) => const FontPickerSheet(),
  );
}

/// 字体选择面板。
class FontPickerSheet extends ConsumerStatefulWidget {
  const FontPickerSheet({super.key});

  @override
  ConsumerState<FontPickerSheet> createState() => _FontPickerSheetState();
}

class _FontPickerSheetState extends ConsumerState<FontPickerSheet> {
  /// 导入中（避免连点弹出多个文件选择器）。
  bool _busy = false;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<void> _selectSystem() async {
    await ref
        .read(readingSettingsControllerProvider.notifier)
        .setFontFamily('');
    if (mounted) unawaited(Navigator.of(context).maybePop());
  }

  Future<void> _select(ReaderFont font) async {
    try {
      await ref.read(readerFontsControllerProvider.notifier).ensureLoaded(font);
    } catch (_) {
      // 注册失败：不让设置指向一个排不出来的字体
      _toast('「${font.name}」加载失败，已保留系统字体');
      return;
    }
    await ref
        .read(readingSettingsControllerProvider.notifier)
        .setFontFamily(font.family);
    if (mounted) unawaited(Navigator.of(context).maybePop());
  }

  Future<void> _import() async {
    if (_busy) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf', 'ttc'],
      withData: false,
    );
    final path = (picked == null || picked.files.isEmpty)
        ? null
        : picked.files.first.path;
    if (path == null || !mounted) return; // 用户取消
    setState(() => _busy = true);
    try {
      final font = await ref
          .read(readerFontsControllerProvider.notifier)
          .importFromFile(path);
      await ref
          .read(readingSettingsControllerProvider.notifier)
          .setFontFamily(font.family);
      if (!mounted) return;
      _toast('已导入「${font.name}」并设为阅读字体');
      unawaited(Navigator.of(context).maybePop());
    } on FontImportException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(ReaderFont font) async {
    final ok = await showDialog<bool>(
      context: context,
      animationStyle: kSmoothSheetAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('删除字体'),
        content: Text('删除「${font.name}」？正在使用时会切回系统默认字体。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final settings = ref.read(readingSettingsControllerProvider);
    if (settings.fontFamily == font.family) {
      await ref
          .read(readingSettingsControllerProvider.notifier)
          .setFontFamily('');
    }
    await ref.read(readerFontsControllerProvider.notifier).deleteFont(font.id);
    _toast('已删除「${font.name}」');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readingSettingsControllerProvider);
    final fonts = ref.watch(readerFontsControllerProvider);
    final theme = settings.theme;
    final fg = theme.chromeForeground;
    // 字体被删除后设置里还留着 family：按「系统默认」展示，避免出现
    // 一个选不中任何一项的空状态。
    final selectedFamily = findReaderFont(fonts, settings.fontFamily) == null
        ? ''
        : settings.fontFamily;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        decoration: BoxDecoration(
          color: theme.chromeSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '阅读字体',
                      style: TextStyle(
                        color: fg,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: fg.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                children: [
                  _SystemFontTile(
                    fg: fg,
                    selected: selectedFamily.isEmpty,
                    onTap: _selectSystem,
                  ),
                  for (final font in fonts)
                    _FontTile(
                      key: ValueKey(font.id),
                      font: font,
                      fg: fg,
                      selected: selectedFamily == font.family,
                      onTap: () => _select(font),
                      onDelete: () => _delete(font),
                    ),
                  if (fonts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Text(
                        '导入 TTF / OTF / TTC 字体后，正文可以换用你喜欢的字体。'
                        '字体只保存在本机。',
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.55),
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: fg.withValues(alpha: 0.12)),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _busy ? null : _import,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor: fg,
                ),
                icon: _busy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: fg,
                        ),
                      )
                    : const Icon(Icons.file_open_outlined, size: 19),
                label: Text(_busy ? '导入中…' : '导入字体文件（TTF / OTF / TTC）'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 系统默认字体项。
class _SystemFontTile extends StatelessWidget {
  const _SystemFontTile({
    required this.fg,
    required this.selected,
    required this.onTap,
  });

  final Color fg;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TileFrame(
      fg: fg,
      selected: selected,
      onTap: onTap,
      trailing: null,
      title: '系统默认',
      preview: Text(
        '永字八法 · 山河入梦 Aa 123',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: fg, fontSize: 17),
      ),
    );
  }
}

/// 导入字体项：先注册再渲染预览（预览即实际排版结果）。
class _FontTile extends ConsumerWidget {
  const _FontTile({
    required this.font,
    required this.fg,
    required this.selected,
    required this.onTap,
    required this.onDelete,
    super.key,
  });

  final ReaderFont font;
  final Color fg;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(readerFontsControllerProvider.notifier);
    // 已注册的字体不要再给新的 Future：FutureBuilder 会先回到 waiting 一帧，
    // 预览就成了「加载中…」闪一下。null = 直接按就绪渲染。
    final ready = notifier.hasLoaded(font);
    final future = ready ? null : notifier.ensureLoaded(font);
    return FutureBuilder<void>(
      future: future,
      builder: (context, _) {
        final loaded = notifier.hasLoaded(font);
        final family = loaded ? font.family : null;
        return _TileFrame(
          fg: fg,
          selected: selected,
          onTap: onTap,
          trailing: IconButton(
            tooltip: '删除字体',
            onPressed: onDelete,
            icon: Icon(
              Icons.delete_outline,
              size: 20,
              color: fg.withValues(alpha: 0.55),
            ),
          ),
          title: font.name,
          preview: Text(
            loaded ? '永字八法 · 山河入梦 Aa 123' : '加载中…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: loaded ? fg : fg.withValues(alpha: 0.45),
              fontSize: 17,
              fontFamily: family,
            ),
          ),
        );
      },
    );
  }
}

/// 行内容（标题 + 字体预览 + 选中标记 + 尾部按钮）。
class _TileFrame extends StatelessWidget {
  const _TileFrame({
    required this.fg,
    required this.selected,
    required this.onTap,
    required this.title,
    required this.preview,
    required this.trailing,
  });

  final Color fg;
  final bool selected;
  final VoidCallback onTap;
  final String title;
  final Widget preview;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: fg,
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.check, size: 15, color: fg),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  preview,
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
