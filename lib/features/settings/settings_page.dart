/// 设置页：外观（亮暗 / 主题色）、资源（字体 / 背景）、管理（标签 / 分类）、
/// 数据（同步 / 缓存）、关于（关于 / 开源协议）。
///
/// 只放「应用级」配置；阅读器内的排版（字号/行距/边距/翻页）在阅读页的
/// 「排版」面板里，避免同一项配置出现在两个地方。
library;

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart'
    show
        kAudioPath,
        kAuthorsPath,
        kBackgroundsPath,
        kBookReviewsPath,
        kCachePath,
        kCategoriesPath,
        kDuplicatesPath,
        kMyReadingPath,
        kNotesPath,
        kReedenImportPath,
        kTagsPath,
        kWeReadPath;
import '../reader/widgets/font_picker_sheet.dart';
import '../shelf/widgets/sync_sheet.dart';
import 'appearance_provider.dart';
import 'update_check.dart';
import 'reading_data_export.dart';
import 'reeden_import.dart';

/// 设置页。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = ref.watch(appAccentControllerProvider);
    final themeMode = ref.watch(appThemeModeControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        key: const PageStorageKey('settings-scroll'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _SectionLabel(text: '外观', theme: theme),
          Card(
            elevation: 0,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.brightness_6_outlined, size: 20),
                      const SizedBox(width: 12),
                      Text('显示模式', style: theme.textTheme.bodyMedium),
                      const Spacer(),
                      Text(
                        themeMode == AppThemeMode.system
                            ? '跟随系统'
                            : (theme.brightness == Brightness.dark
                                  ? '暗色'
                                  : '亮色'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // 只要一个切换按钮：按当前实际亮度在亮 / 暗之间切换。
                      Switch(
                        key: const ValueKey('settings-theme-mode'),
                        value: theme.brightness == Brightness.dark,
                        onChanged: (dark) => ref
                            .read(appThemeModeControllerProvider.notifier)
                            .set(dark ? AppThemeMode.dark : AppThemeMode.light),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('主题色', style: theme.textTheme.bodyMedium),
                          const Spacer(),
                          Text(
                            accent.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 14,
                        runSpacing: 10,
                        children: [
                          for (final option in AppAccent.values)
                            _AccentDot(
                              accent: option,
                              selected: option == accent,
                              onTap: () => ref
                                  .read(appAccentControllerProvider.notifier)
                                  .set(option),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '主色用于按钮、选中态、开关和统计图表',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel(text: '资源', theme: theme),
          Card(
            elevation: 0,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.font_download_outlined),
                  title: const Text('字体'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showFontPickerSheet(context),
                ),
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('背景'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(kBackgroundsPath),
                ),
                ListTile(
                  key: const ValueKey('settings-audio'),
                  leading: const Icon(Icons.library_music_outlined),
                  title: const Text('听书音频'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(kAudioPath),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel(text: '管理', theme: theme),
          Card(
            elevation: 0,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.auto_stories_outlined),
                  title: const Text('我的阅读'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(kMyReadingPath),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_note_outlined),
                  title: const Text('笔记回顾'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(kNotesPath),
                ),
                ListTile(
                  key: const ValueKey('settings-book-reviews'),
                  leading: const Icon(Icons.rate_review_outlined),
                  title: const Text('我的书评'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(kBookReviewsPath),
                ),
                ListTile(
                  leading: const Icon(Icons.sell_outlined),
                  title: const Text('标签'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(kTagsPath),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('分类'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(kCategoriesPath),
                ),
                ListTile(
                  key: const ValueKey('settings-authors'),
                  leading: const Icon(Icons.people_outline),
                  title: const Text('作者管理'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(kAuthorsPath),
                ),
                ListTile(
                  key: const ValueKey('settings-duplicate-books'),
                  leading: const Icon(Icons.content_copy_outlined),
                  title: const Text('重复书籍整理'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(kDuplicatesPath),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel(text: '数据', theme: theme),
          Card(
            elevation: 0,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_sync_outlined),
                  title: const Text('同步'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showSyncSheet(context),
                ),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('缓存'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(kCachePath),
                ),
                ListTile(
                  key: const ValueKey('settings-export-reading-data'),
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text('导出阅读数据'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => unawaited(exportReadingDataJson(context, ref)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel(text: '实验性功能', theme: theme),
          Card(
            elevation: 0,
            child: Column(
              children: [
                ListTile(
                  key: const ValueKey('settings-weread'),
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('微信读书'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(kWeReadPath),
                ),
                ListTile(
                  key: const ValueKey('settings-reeden-import'),
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('导入 Reeden 数据'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => unawaited(_pickReedenExport(context)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel(text: '关于', theme: theme),
          Card(
            elevation: 0,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.system_update_outlined),
                  title: const Text('检查更新'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => unawaited(checkForAppUpdate(context)),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于 QYReader'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showAbout(context),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('开源协议'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showLicenses(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _showAbout(BuildContext context) {
  showAboutDialog(
    context: context,
    applicationName: 'QYReader',
    applicationIcon: const Icon(Icons.menu_book_outlined, size: 36),
    applicationLegalese:
        '本地优先的 EPUB 阅读器\n'
        '书籍、进度、标注保存在本机，可选同步到自建对象存储。',
  );
}

void _showLicenses(BuildContext context) {
  showLicensePage(
    context: context,
    applicationName: 'QYReader',
    applicationLegalese: '本地优先的 EPUB 阅读器',
  );
}

/// 主题色圆点。
class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final AppAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: accent.label,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : Colors.transparent,
              width: 2,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, size: 18, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 选 Reeden 导出的 JSON，解析后进对比页（逐本勾选要更新的书）。
Future<void> _pickReedenExport(BuildContext context) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['json'],
    withData: true,
  );
  final bytes = picked?.files.single.bytes;
  if (bytes == null || bytes.isEmpty) return;
  final List<ReedenBookData> books;
  try {
    books = parseReedenExport(utf8.decode(bytes, allowMalformed: true));
  } on FormatException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('文件格式不对：${e.message}')));
    return;
  }
  if (books.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('文件里没有可导入的书籍')));
    return;
  }
  if (!context.mounted) return;
  unawaited(context.push(kReedenImportPath, extra: books));
}
