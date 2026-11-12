/// 排版面板（Aa）：主题 / 正文 / 标题 / 页面 / 页眉页脚。
///
/// 配置项多，按类分 Tab；每个 Tab 内部可滚动，常用项（字号/行距）不会被
/// 边距滑杆挤到屏幕外。页眉与页脚共用一套样式概念，合成一个页签分两段。
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/theme/reading_theme.dart';
import '../../settings/background_cache_view.dart' show listBackgroundFiles;
import '../fonts/reader_fonts.dart';
import '../page_turn_sound_player.dart';
import '../reader_settings.dart';
import '../reader_themes.dart';
import 'font_picker_sheet.dart';
import 'page_layout_editor.dart';

/// 排版设置面板（模态底部弹层）。
class TypesettingPanel extends ConsumerWidget {
  const TypesettingPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readingSettingsControllerProvider);
    final controller = ref.read(readingSettingsControllerProvider.notifier);
    final fg = settings.theme.chromeForeground;
    // 下拉菜单的底色：跟弹层同一块表面色，展开时不会闪出默认的白/黑。
    final bg = settings.theme.chromeSurface;
    // 字体名要查字体库：设置里只存 family，删除后自动显示「系统默认」
    final fonts = ref.watch(readerFontsControllerProvider);
    final fontName = findReaderFont(fonts, settings.fontFamily)?.name ?? '系统默认';
    final themesState = ref.watch(readerThemesControllerProvider);

    return DefaultTabController(
      length: 5,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 430,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: TabBar(
                  labelColor: fg,
                  unselectedLabelColor: fg.withValues(alpha: 0.55),
                  // 参考稿的「分段胶囊」：选中项是浮在浅色轨道上的实心药丸。
                  indicator: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(fontSize: 12),
                  labelPadding: EdgeInsets.zero,
                  tabs: const [
                    Tab(text: '主题'),
                    Tab(text: '正文'),
                    Tab(text: '标题'),
                    Tab(text: '页面'),
                    Tab(text: '页眉页脚'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    // ---------- 主题 ----------
                    // 每个主题就是一块「背景色 + 名称」：名称用该主题的字体色写，
                    // 不再用文字胶囊（v2.32.0）。加号复制当前主题，减号删除。
                    _tab(
                      children: [
                        Row(
                          children: [
                            Text(
                              '主题库',
                              style: TextStyle(
                                color: fg.withValues(alpha: 0.75),
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              key: const ValueKey('typeset-theme-add'),
                              tooltip: '复制当前主题为副本',
                              onPressed: () => _ThemeLibraryRow.addTheme(
                                context,
                                ref,
                              ),
                              icon: const Icon(
                                Icons.add_circle_outline,
                                size: 20,
                              ),
                              color: fg.withValues(alpha: 0.8),
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              key: const ValueKey('typeset-theme-remove'),
                              tooltip: themesState.active.builtIn
                                  ? '内置主题不可删除'
                                  : '删除当前主题',
                              onPressed: themesState.active.builtIn
                                  ? null
                                  : () => _ThemeLibraryRow.removeTheme(
                                        context,
                                        ref,
                                        themesState.active,
                                      ),
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 20,
                              ),
                              color: fg.withValues(
                                alpha: themesState.active.builtIn ? 0.25 : 0.7,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // 网格排列、多行显示；自定义主题长按可更换背景。
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final preset in themesState.all)
                              _ThemeTile(
                                key: ValueKey(
                                  'typeset-theme-chip-${preset.id}',
                                ),
                                preset: preset,
                                selected: preset.id == themesState.activeId,
                                onTap: () => ref
                                    .read(
                                      readerThemesControllerProvider.notifier,
                                    )
                                    .apply(preset),
                                onLongPress: preset.builtIn
                                    ? null
                                    : () => _ThemeLibraryRow.changeBackground(
                                          context,
                                          ref,
                                          preset,
                                        ),
                              ),
                          ],
                        ),
                        if (themesState.active.builtIn)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              '点「+」把当前排版复制成自定义主题，之后正文 / 标题 / '
                              '页面 / 页眉页脚的调整都会存进这份主题；'
                              '长按自定义主题可更换阅读背景。',
                              style: TextStyle(
                                color: fg.withValues(alpha: 0.5),
                                fontSize: 11.5,
                                height: 1.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    // ---------- 正文 ----------
                    _tab(
                      children: [
                        _FontRow(
                          label: fontName,
                          fg: fg,
                          onTap: () => showFontPickerSheet(context),
                        ),
                        _LiveSliderRow(
                          label: '字号',
                          fg: fg,
                          value: settings.fontSize,
                          min: 14,
                          max: 28,
                          divisions: 14,
                          display: settings.fontSize.round().toString(),
                          format: (v) => v.round().toString(),
                          onPreview: (v) => liveReaderTypesetPreview.value =
                              settings.copyWith(fontSize: v),
                          onCommit: (v) {
                            controller.patch(fontSize: v);
                            liveReaderTypesetPreview.value = null;
                          },
                        ),
                        _LiveSliderRow(
                          label: '行距',
                          fg: fg,
                          value: settings.lineHeight,
                          min: 1.2,
                          max: 2.4,
                          divisions: 12,
                          display: settings.lineHeight.toStringAsFixed(1),
                          onPreview: (v) => liveReaderTypesetPreview.value =
                              settings.copyWith(lineHeight: v),
                          onCommit: (v) {
                            controller.patch(lineHeight: v);
                            liveReaderTypesetPreview.value = null;
                          },
                        ),
                        _LiveSliderRow(
                          label: '段距',
                          fg: fg,
                          value: settings.paragraphSpacing,
                          min: 0,
                          max: 2,
                          divisions: 20,
                          display:
                              settings.paragraphSpacing.toStringAsFixed(1),
                          onPreview: (v) => liveReaderTypesetPreview.value =
                              settings.copyWith(paragraphSpacing: v),
                          onCommit: (v) {
                            controller.patch(paragraphSpacing: v);
                            liveReaderTypesetPreview.value = null;
                          },
                        ),
                        _LiveSliderRow(
                          label: '字距',
                          fg: fg,
                          value: settings.letterSpacing,
                          min: -1,
                          max: 6,
                          divisions: 14,
                          display: settings.letterSpacing.toStringAsFixed(1),
                          onPreview: (v) => liveReaderTypesetPreview.value =
                              settings.copyWith(letterSpacing: v),
                          onCommit: (v) {
                            controller.patch(letterSpacing: v);
                            liveReaderTypesetPreview.value = null;
                          },
                        ),
                        _SelectRow<BodyFontWeight>(
                          label: '字重',
                          fg: fg,
                          bg: bg,
                          options: {
                            for (final w in BodyFontWeight.values) w: w.label,
                          },
                          selected: settings.bodyWeight,
                          onSelect: (v) => controller.patch(bodyWeight: v),
                        ),
                        _SwitchRow(
                          label: '加粗',
                          hint: '正文整体加粗',
                          fg: fg,
                          accent: settings.theme.accent,
                          value: settings.bodyBold,
                          onChanged: (v) => controller.patch(bodyBold: v),
                        ),
                        _SelectRow<TextAlignMode>(
                          label: '对齐',
                          fg: fg,
                          bg: bg,
                          options: {
                            for (final a in TextAlignMode.values) a: a.label,
                          },
                          selected: settings.bodyAlign,
                          onSelect: (v) => controller.patch(bodyAlign: v),
                        ),
                        _SwitchRow(
                          label: '两端对齐',
                          hint: '正文右端也齐平（居中/右对齐时以对齐为准）',
                          fg: fg,
                          accent: settings.theme.accent,
                          value: settings.bodyJustify,
                          onChanged: (v) => controller.patch(bodyJustify: v),
                        ),
                        _SelectRow<ParagraphIndent>(
                          label: '段落缩进',
                          fg: fg,
                          bg: bg,
                          options: {
                            for (final i in ParagraphIndent.values) i: i.label,
                          },
                          selected: settings.bodyIndent,
                          onSelect: (v) => controller.patch(bodyIndent: v),
                        ),
                        const SizedBox(height: 4),
                        _SectionTitle('边距', fg: fg),
                        _MarginEntry(
                          key: const ValueKey('margin-entry-body'),
                          label: '正文边距',
                          value: '${settings.marginLeft.round()} / '
                              '${settings.marginTop.round()} / '
                              '${settings.marginRight.round()} / '
                              '${settings.marginBottom.round()}',
                          fg: fg,
                          onTap: () =>
                              Navigator.of(context).pop(MarginGroup.body),
                        ),
                      ],
                    ),
                    // ---------- 标题 ----------
                    _tab(
                      children: [
                        _SelectRow<HeadingStyle>(
                          label: '标题样式',
                          fg: fg,
                          bg: bg,
                          options: {
                            for (final h in HeadingStyle.values) h: h.label,
                          },
                          selected: settings.headingStyle,
                          onSelect: (v) => controller.patch(headingStyle: v),
                        ),
                        _StepperRow(
                          label: '字号',
                          value: settings.headingFontSize.round().toString(),
                          fg: fg,
                          onMinus: settings.headingFontSize > 16
                              ? () => controller.patch(
                                    headingFontSize: settings.headingFontSize - 1,
                                  )
                              : null,
                          onPlus: settings.headingFontSize < 40
                              ? () => controller.patch(
                                    headingFontSize: settings.headingFontSize + 1,
                                  )
                              : null,
                        ),
                        _SwitchRow(
                          label: '加粗',
                          hint: '标题文字加粗',
                          fg: fg,
                          accent: settings.theme.accent,
                          value: settings.headingBold,
                          onChanged: (v) => controller.patch(headingBold: v),
                        ),
                        _SelectRow<TextAlignMode>(
                          label: '对齐',
                          fg: fg,
                          bg: bg,
                          options: {
                            for (final a in TextAlignMode.values) a: a.label,
                          },
                          selected: settings.headingAlign,
                          onSelect: (v) => controller.patch(headingAlign: v),
                        ),
                        _ValueSlider(
                          label: '上边距',
                          value: settings.headingMarginTop,
                          fg: fg,
                          onCommit: (v) => controller.patch(headingMarginTop: v),
                        ),
                        _ValueSlider(
                          label: '下边距',
                          value: settings.headingMarginBottom,
                          fg: fg,
                          onCommit: (v) => controller.patch(headingMarginBottom: v),
                        ),
                      ],
                    ),
                    // ---------- 页面 ----------
                    _tab(
                      children: [
                        _SelectRow<bool>(
                          label: '单双页',
                          fg: fg,
                          bg: bg,
                          options: const {false: '单页', true: '双页'},
                          selected: settings.doublePage,
                          onSelect: (v) => controller.patch(doublePage: v),
                        ),
                        _SelectRow<PageTurnMode>(
                          label: '翻页',
                          fg: fg,
                          bg: bg,
                          options: {
                            for (final m in PageTurnMode.values) m: m.label,
                          },
                          selected: settings.pageTurnMode,
                          onSelect: (v) => controller.patch(pageTurnMode: v),
                        ),
                        _MarginEntry(
                          key: const ValueKey('page-layout-entry'),
                          label: '页面布局',
                          value: '九宫格点击区域',
                          fg: fg,
                          onTap: () => showPageLayoutEditor(context),
                        ),
                        _SelectRow<PageTurnSound>(
                          label: '音效',
                          fg: fg,
                          bg: bg,
                          options: {
                            for (final s in PageTurnSound.values) s: s.label,
                          },
                          selected: settings.pageTurnSound,
                          onSelect: (v) {
                            controller.patch(pageTurnSound: v);
                            // 选完立刻试听：不用关面板、翻一页才知道效果。
                            unawaited(PageTurnSoundPlayer.instance.play(v));
                          },
                        ),
                        _SelectRow<ProgressScope>(
                          label: '进度条',
                          fg: fg,
                          bg: bg,
                          options: {
                            for (final v in ProgressScope.values) v: v.label,
                          },
                          selected: settings.progressScope,
                          onSelect: (v) => controller.patch(progressScope: v),
                        ),
                        const SizedBox(height: 12),
                        // 「排版：分页/滚动」选择器已移除——原生阅读面只实现
                        // 了分页，滚动选了没反应，留着只会误导。
                        _SwitchRow(
                          label: '精排',
                          hint: settings.preciseTypesetting
                              ? '保留书籍原样式（字号/行距/缩进由书决定）'
                              : '统一字号行距，各家书观感一致',
                          fg: fg,
                          accent: settings.theme.accent,
                          value: settings.preciseTypesetting,
                          onChanged: (v) => controller.patch(preciseTypesetting: v),
                        ),
                      ],
                    ),
                    // ---------- 页眉页脚 ----------
                    _tab(
                      children: [
                        _SectionTitle('边距（在页面上拖动调节）', fg: fg),
                        _MarginEntry(
                          key: const ValueKey('margin-entry-body-2'),
                          label: '正文边距',
                          value: '${settings.marginLeft.round()} / '
                              '${settings.marginTop.round()} / '
                              '${settings.marginRight.round()} / '
                              '${settings.marginBottom.round()}',
                          fg: fg,
                          onTap: () =>
                              Navigator.of(context).pop(MarginGroup.body),
                        ),
                        _MarginEntry(
                          key: const ValueKey('margin-entry-header'),
                          label: '页眉边距',
                          value: '${settings.headerMarginLeft.round()} / '
                              '${settings.headerMarginTop.round()} / '
                              '${settings.headerMarginRight.round()}',
                          fg: fg,
                          onTap: () =>
                              Navigator.of(context).pop(MarginGroup.header),
                        ),
                        _MarginEntry(
                          key: const ValueKey('margin-entry-footer'),
                          label: '页脚边距',
                          value: '${settings.footerMarginLeft.round()} / '
                              '${settings.footerMarginBottom.round()} / '
                              '${settings.footerMarginRight.round()}',
                          fg: fg,
                          onTap: () =>
                              Navigator.of(context).pop(MarginGroup.footer),
                        ),
                        const SizedBox(height: 10),
                        _SectionTitle('页眉', fg: fg),
                        _RunningEditor(
                          fg: fg,
                          bg: bg,
                          left: settings.headerLeft,
                          center: settings.headerCenter,
                          right: settings.headerRight,
                          onLeft: (v) => controller.patch(headerLeft: v),
                          onCenter: (v) => controller.patch(headerCenter: v),
                          onRight: (v) => controller.patch(headerRight: v),
                        ),
                        const SizedBox(height: 6),
                        _StepperRow(
                          label: '字号',
                          value: settings.headerFontSize.round().toString(),
                          fg: fg,
                          onMinus: settings.headerFontSize > 8
                              ? () => controller.patch(
                                    headerFontSize: settings.headerFontSize - 1)
                              : null,
                          onPlus: settings.headerFontSize < 16
                              ? () => controller.patch(
                                    headerFontSize: settings.headerFontSize + 1)
                              : null,
                        ),
                        const SizedBox(height: 10),
                        _SectionTitle('页脚', fg: fg),
                        _RunningEditor(
                          fg: fg,
                          bg: bg,
                          left: settings.footerLeft,
                          center: settings.footerCenter,
                          right: settings.footerRight,
                          onLeft: (v) => controller.patch(footerLeft: v),
                          onCenter: (v) => controller.patch(footerCenter: v),
                          onRight: (v) => controller.patch(footerRight: v),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '页脚字号跟随页眉字号',
                          style: TextStyle(
                            color: fg.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 单个 Tab 的内容：统一内边距 + 可滚动（内容多时不会溢出）。
  Widget _tab({required List<Widget> children}) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
}

/// 页眉/页脚三槽内容编辑。
class _RunningEditor extends StatelessWidget {
  const _RunningEditor({
    required this.fg,
    required this.bg,
    required this.left,
    required this.center,
    required this.right,
    required this.onLeft,
    required this.onCenter,
    required this.onRight,
  });

  final Color fg;
  final Color bg;
  final RunningContent left;
  final RunningContent center;
  final RunningContent right;
  final ValueChanged<RunningContent> onLeft;
  final ValueChanged<RunningContent> onCenter;
  final ValueChanged<RunningContent> onRight;

  @override
  Widget build(BuildContext context) {
    final options = {for (final c in RunningContent.values) c: c.label};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SelectRow<RunningContent>(
          label: '左侧',
          fg: fg,
          bg: bg,
          options: options,
          selected: left,
          onSelect: onLeft,
        ),
        _SelectRow<RunningContent>(
          label: '中间',
          fg: fg,
          bg: bg,
          options: options,
          selected: center,
          onSelect: onCenter,
        ),
        _SelectRow<RunningContent>(
          label: '右侧',
          fg: fg,
          bg: bg,
          options: options,
          selected: right,
          onSelect: onRight,
        ),
      ],
    );
  }
}

/// 主题库的操作（排版面板的「+ / −」）。
///
/// 主题在界面上就是「一块背景色 + 用该主题字体色写的名称」，不再用文字胶囊。
class _ThemeLibraryRow {
  const _ThemeLibraryRow._();

  /// 「+」：把当前设置复制成新的自定义主题，并让用户改名字。
  static Future<void> addTheme(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(readerThemesControllerProvider.notifier);
    final preset = await controller.duplicateCurrent();
    if (!context.mounted) return;
    await showThemeRenameDialog(
      context,
      ref,
      id: preset.id,
      initialName: preset.name,
    );
    if (!context.mounted) return;
    final name = ref.read(readerThemesControllerProvider).active.name;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('已复制为「$name」，之后的排版调整会存进它')),
    );
  }

  /// 「−」：删除当前自定义主题（需确认），内置主题禁用。
  static Future<void> removeTheme(
    BuildContext context,
    WidgetRef ref,
    ReaderThemePreset active,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除主题'),
        content: Text('确定删除「${active.name}」吗？只删主题，阅读内容不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(readerThemesControllerProvider.notifier).delete(active.id);
  }

  /// 长按自定义主题：更换阅读背景（选图 / 背景库 / 清除）。
  static Future<void> changeBackground(
    BuildContext context,
    WidgetRef ref,
    ReaderThemePreset preset,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('修改名称'),
              subtitle: Text('当前：${preset.name}'),
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('更换背景图'),
              subtitle: const Text('从相册或文件里选一张图'),
              onTap: () => Navigator.of(ctx).pop('pick'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从背景库选择'),
              subtitle: const Text('用「设置 → 资源 → 背景」里已有的图片'),
              onTap: () => Navigator.of(ctx).pop('library'),
            ),
            if (preset.hasImage)
              ListTile(
                leading: const Icon(Icons.format_color_reset_outlined),
                title: const Text('清除背景'),
                subtitle: const Text('主题改回纯色背景'),
                onTap: () => Navigator.of(ctx).pop('clear'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final controller = ref.read(readerThemesControllerProvider.notifier);
    if (action == 'rename') {
      await showThemeRenameDialog(
        context,
        ref,
        id: preset.id,
        initialName: preset.name,
      );
      return;
    }
    if (action == 'clear') {
      await controller.save(
        preset.copyWith(backgroundImage: ''),
        applyNow: true,
      );
      return;
    }
    if (action == 'library') {
      final picked = await showBackgroundLibrarySheet(context);
      if (picked == null || picked.isEmpty) return;
      await controller.save(
        preset.copyWith(backgroundImage: picked),
        applyNow: true,
      );
      return;
    }
    // 选一张新图：复制进背景目录，再挂到主题上（同时进入背景库）。
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
        'bg-${DateTime.now().microsecondsSinceEpoch}$ext',
      );
      await File(source).copy(dest);
      await controller.save(
        preset.copyWith(backgroundImage: dest),
        applyNow: true,
      );
    } on Exception catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('背景图导入失败：$e')),
      );
    }
  }
}

/// 背景库选择弹层：列出本机背景目录里的图片，点一张返回路径。
Future<String?> showBackgroundLibrarySheet(BuildContext context) async {
  final files = await listBackgroundFiles();
  if (!context.mounted) return null;
  if (files.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('背景库还是空的：先在「设置 → 资源 → 背景」上传')),
    );
    return null;
  }
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  '选择背景图',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Flexible(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.72,
                      ),
                  itemCount: files.length,
                  itemBuilder: (_, index) {
                    final file = files[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => Navigator.of(ctx).pop(file.path),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          file,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: Color(0xFFE0E0E0)),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 主题名称编辑弹窗（排版面板里「+」之后直接改名）。
Future<void> showThemeRenameDialog(
  BuildContext context,
  WidgetRef ref, {
  required String id,
  required String initialName,
}) async {
  var name = initialName;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('主题名称'),
      content: TextFormField(
        key: const ValueKey('typeset-theme-name'),
        initialValue: initialName,
        autofocus: true,
        maxLength: 24,
        onChanged: (value) => name = value,
        decoration: const InputDecoration(labelText: '名称'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await ref.read(readerThemesControllerProvider.notifier).rename(id, name);
}
/// 主题块：背景色 / 背景图 + 名称（名称用该主题的字体色）。
class _ThemeTile extends ConsumerWidget {
  const _ThemeTile({
    required super.key,
    required this.preset,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final ReaderThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  /// 长按（自定义主题：更换阅读背景）。
  final VoidCallback? onLongPress;

  /// 主题实际纸色：自定义主题优先用快照里的底色（改过底色也准）。
  ReadingTheme get _paper {
    final snapshot = preset.snapshot;
    if (snapshot != null && snapshot['theme'] is String) {
      return ReadingTheme.values.firstWhere(
        (t) => t.name == snapshot['theme'],
        orElse: () => preset.background,
      );
    }
    return preset.background;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paper = _paper;
    final fg = paper.chromeForeground;
    final image = preset.hasImage ? preset.backgroundImage : '';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 100,
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: paper.background,
          image: image.isEmpty
              ? null
              : DecorationImage(
                  image: FileImage(File(image)),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    paper.background.withValues(alpha: 0.35),
                    BlendMode.srcOver,
                  ),
                ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? fg : fg.withValues(alpha: 0.18),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              preset.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                height: 1.25,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            Row(
              children: [
                if (preset.builtIn)
                  Icon(Icons.lock_outline, size: 10, color: fg.withValues(alpha: 0.5)),
                if (!preset.builtIn)
                  Icon(Icons.edit_outlined, size: 10, color: fg.withValues(alpha: 0.5)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
class _FontRow extends StatelessWidget {
  const _FontRow({
    required this.label,
    required this.fg,
    required this.onTap,
  });

  final String label;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(width: 64, child: Text('字体', style: TextStyle(color: fg))),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg.withValues(alpha: 0.75), fontSize: 14),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 20, color: fg.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.fg,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String value;
  final Color fg;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 13),
            ),
          ),
          IconButton(
            onPressed: onMinus,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.remove, color: fg),
          ),
          Expanded(
            child: Center(child: Text(value, style: TextStyle(color: fg))),
          ),
          IconButton(
            onPressed: onPlus,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add, color: fg),
          ),
        ],
      ),
    );
  }
}

/// 开关行（label + 说明 + Switch）。
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.hint,
    required this.fg,
    required this.accent,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final Color fg;

  /// 开关打开时的主题色（阅读主题的 accent）。
  final Color accent;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hint,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg.withValues(alpha: 0.55), fontSize: 11),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: accent,
            activeColor: Colors.white,
          ),
        ],
      ),
    );
  }
}

/// 选择行：左侧标签，右侧下拉框（当前值 + 展开箭头）。
///
/// 选项型设置统一走这个控件。原先的 chip 墙在窄屏上要占两三行，
/// 一个页签里选项一多就变成「一堆小胶囊」，还看不出哪个是当前值。
class _SelectRow<T> extends StatelessWidget {
  const _SelectRow({
    required this.label,
    required this.fg,
    required this.bg,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final String label;
  final Color fg;

  /// 展开菜单的底色（跟弹层同一块表面色，避免闪出默认白/黑）。
  final Color bg;
  final Map<T, String> options;
  final T selected;
  final void Function(T value) onSelect;

  @override
  Widget build(BuildContext context) {
    final valueStyle = TextStyle(color: fg, fontSize: 13.5);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 13),
            ),
          ),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: selected,
                isExpanded: true,
                isDense: true,
                alignment: Alignment.centerRight,
                borderRadius: BorderRadius.circular(14),
                dropdownColor: bg,
                menuMaxHeight: 320,
                focusColor: Colors.transparent,
                icon: Icon(
                  Icons.expand_more,
                  size: 18,
                  color: fg.withValues(alpha: 0.55),
                ),
                style: valueStyle,
                selectedItemBuilder: (context) => [
                  for (final entry in options.entries)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        entry.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: valueStyle.copyWith(
                          color: fg.withValues(alpha: 0.9),
                          fontWeight: entry.key == selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                ],
                items: [
                  for (final entry in options.entries)
                    DropdownMenuItem<T>(
                      value: entry.key,
                      child: Text(
                        entry.value,
                        style: valueStyle.copyWith(
                          fontWeight: entry.key == selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) onSelect(value);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分组小标题（比设置行矮一档，用来分开「正文 / 页眉 / 页脚」几段）。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {required this.fg});

  final String text;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Text(
        text,
        style: TextStyle(
          color: fg.withValues(alpha: 0.55),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// 实时预览滑杆：拖动中只更新预览设置（阅读面只排当前页），松手提交。
class _LiveSliderRow extends StatefulWidget {
  const _LiveSliderRow({
    required this.label,
    required this.fg,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onPreview,
    required this.onCommit,
    this.format,
  });

  final String label;
  final Color fg;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onPreview;
  final ValueChanged<double> onCommit;

  /// 拖动中的数值格式（默认一位小数）。
  final String Function(double value)? format;

  @override
  State<_LiveSliderRow> createState() => _LiveSliderRowState();
}

class _LiveSliderRowState extends State<_LiveSliderRow> {
  late double _value = widget.value;
  bool _dragging = false;

  @override
  void didUpdateWidget(_LiveSliderRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.value != widget.value) {
      _value = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _value.clamp(widget.min, widget.max).toDouble();
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              widget.label,
              style: TextStyle(
                color: widget.fg.withValues(alpha: 0.85),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: v,
              min: widget.min,
              max: widget.max,
              divisions: widget.divisions,
              activeColor: widget.fg,
              onChangeStart: (x) {
                _dragging = true;
                widget.onPreview(x);
              },
              onChanged: (x) {
                setState(() => _value = x);
                widget.onPreview(x);
              },
              onChangeEnd: (x) {
                _dragging = false;
                widget.onCommit(x);
              },
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              _dragging
                  ? (widget.format?.call(v) ?? v.toStringAsFixed(1))
                  : widget.display,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.fg,
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 拖动时只改本地值、松手才提交的滑杆（避免每帧写 prefs + 重排）。
class _ValueSlider extends StatefulWidget {
  const _ValueSlider({
    required this.label,
    required this.value,
    required this.fg,
    required this.onCommit,
  });

  final String label;
  final double value;
  final Color fg;
  final ValueChanged<double> onCommit;

  static const double min = 0;
  static const double max = 64;

  @override
  State<_ValueSlider> createState() => _ValueSliderState();
}

class _ValueSliderState extends State<_ValueSlider> {
  late double _value = widget.value;
  bool _dragging = false;

  @override
  void didUpdateWidget(_ValueSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.value != widget.value) {
      _value = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _value.clamp(_ValueSlider.min, _ValueSlider.max).toDouble();
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              widget.label,
              style: TextStyle(
                color: widget.fg.withValues(alpha: 0.85),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: v,
              min: _ValueSlider.min,
              max: _ValueSlider.max,
              divisions: ((_ValueSlider.max - _ValueSlider.min) / 4).round(),
              activeColor: widget.fg,
              onChangeStart: (_) => _dragging = true,
              onChanged: (x) => setState(() => _value = x),
              onChangeEnd: (x) {
                _dragging = false;
                widget.onCommit(x);
              },
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              v.round().toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.fg,
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 边距入口行：点一下进入「在页面上拖动」的直调模式。
class _MarginEntry extends StatelessWidget {
  const _MarginEntry({
    required this.label,
    required this.value,
    required this.fg,
    required this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: fg.withValues(alpha: 0.85),
                fontSize: 13,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                color: fg.withValues(alpha: 0.5),
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: fg.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
