/// 阅读主题库：JSON 往返、内置主题、应用 / 新增 / 删除。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/features/reader/reader_settings.dart';
import 'package:qy_reader/features/reader/reader_themes.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('预设 JSON 往返，背景/字号/边距都保留', () {
    const preset = ReaderThemePreset(
      id: 'custom:1',
      name: '暖黄',
      background: ReadingTheme.sepia,
      backgroundImage: '/tmp/bg.jpg',
      fontSize: 20,
      lineHeight: 1.9,
      paragraphSpacing: 0.8,
      marginLeft: 24,
      marginRight: 22,
      marginTop: 18,
      marginBottom: 14,
    );
    final restored = ReaderThemePreset.fromJson(preset.toJson());
    expect(restored.id, 'custom:1');
    expect(restored.name, '暖黄');
    expect(restored.background, ReadingTheme.sepia);
    expect(restored.backgroundImage, '/tmp/bg.jpg');
    expect(restored.fontSize, 20);
    expect(restored.lineHeight, 1.9);
    expect(restored.paragraphSpacing, 0.8);
    expect(restored.marginLeft, 24);
    expect(restored.marginBottom, 14);
  });

  test('内置主题包含纯白，且不可编辑', () {
    expect(builtInReaderThemes.length, 5);
    final white =
        builtInReaderThemes.firstWhere((t) => t.background == ReadingTheme.white);
    expect(white.name, '纯白');
    expect(white.builtIn, isTrue);
  });

  test('应用主题会把背景/字号/行距/段距/边距写进阅读设置', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(readerThemesControllerProvider.notifier);

    await controller.apply(const ReaderThemePreset(
      id: 'custom:apply',
      name: '大字号',
      background: ReadingTheme.white,
      backgroundImage: '/tmp/none.png',
      fontSize: 24,
      lineHeight: 2.1,
      paragraphSpacing: 1.2,
      marginLeft: 30,
      marginRight: 28,
      marginTop: 20,
      marginBottom: 18,
    ));

    final settings = container.read(readingSettingsControllerProvider);
    expect(settings.theme, ReadingTheme.white);
    expect(settings.backgroundImage, '/tmp/none.png');
    expect(settings.fontSize, 24);
    expect(settings.lineHeight, 2.1);
    expect(settings.paragraphSpacing, 1.2);
    expect(settings.marginLeft, 30);
    expect(settings.marginRight, 28);
    expect(settings.marginTop, 20);
    expect(settings.marginBottom, 18);
    expect(container.read(readerThemesControllerProvider).activeId, 'custom:apply');
  });

  test('新增 / 删除自定义主题并落 prefs', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(readerThemesControllerProvider.notifier);

    const preset = ReaderThemePreset(
      id: 'custom:2',
      name: '我的主题',
      background: ReadingTheme.night,
      fontSize: 16,
    );
    await controller.save(preset, applyNow: false);
    expect(
      container.read(readerThemesControllerProvider).custom.map((t) => t.id),
      contains('custom:2'),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('reader.customThemes'), contains('我的主题'));

    await controller.delete('custom:2');
    expect(container.read(readerThemesControllerProvider).custom, isEmpty);
    expect(prefs.getString('reader.customThemes'), isNot(contains('我的主题')));
  });

  test('复制当前主题：生成带整份排版快照的副本并立即应用', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final settings = container.read(readingSettingsControllerProvider.notifier);
    await settings.waitRestored();
    await settings.patch(
      theme: ReadingTheme.sepia,
      fontSize: 21,
      headingStyle: HeadingStyle.underlineShade,
      headingFontSize: 26,
      headerLeft: RunningContent.chapterName,
      footerCenter: RunningContent.chapterPages,
      marginLeft: 30,
    );

    final controller = container.read(readerThemesControllerProvider.notifier);
    final preset = await controller.duplicateCurrent();

    expect(preset.builtIn, isFalse);
    expect(preset.name, contains('副本'));
    expect(preset.snapshot, isNotNull);
    expect(
      container.read(readerThemesControllerProvider).activeId,
      preset.id,
    );

    // 副本里带着刚才的排版：换回内置纸色后再应用，正文/标题/页眉页脚一起回来。
    await settings.patch(theme: ReadingTheme.white, fontSize: 16);
    await controller.apply(preset);
    final restored = container.read(readingSettingsControllerProvider);
    expect(restored.theme, ReadingTheme.sepia);
    expect(restored.fontSize, 21);
    expect(restored.headingStyle, HeadingStyle.underlineShade);
    expect(restored.headingFontSize, 26);
    expect(restored.headerLeft, RunningContent.chapterName);
    expect(restored.footerCenter, RunningContent.chapterPages);
    expect(restored.marginLeft, 30);
  });

  test('给带快照的主题换背景后，应用时阅读设置用的是新背景', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final settings = container.read(readingSettingsControllerProvider.notifier);
    await settings.waitRestored();
    final controller = container.read(readerThemesControllerProvider.notifier);
    final preset = await controller.duplicateCurrent();

    // 快照里记着当时的 backgroundImage（空），随后主题单独换背景。
    final withImage = preset.copyWith(backgroundImage: '/tmp/new-bg.jpg');
    await controller.save(withImage, applyNow: true);

    final applied = container.read(readingSettingsControllerProvider);
    expect(applied.backgroundImage, '/tmp/new-bg.jpg');

    // 再应用一次（快照仍然是旧值）也必须用主题当前的 backgroundImage。
    await settings.patch(backgroundImage: '');
    await controller.apply(withImage);
    expect(
      container.read(readingSettingsControllerProvider).backgroundImage,
      '/tmp/new-bg.jpg',
    );
  });

  test('自定义主题激活时，改排版会写回该主题（防抖后落盘）', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final settings = container.read(readingSettingsControllerProvider.notifier);
    await settings.waitRestored();
    final controller = container.read(readerThemesControllerProvider.notifier);
    final preset = await controller.duplicateCurrent();

    await settings.patch(fontSize: 24, headingStyle: HeadingStyle.shade);
    // 防抖 500ms 后写回
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final saved = container
        .read(readerThemesControllerProvider)
        .custom
        .firstWhere((t) => t.id == preset.id);
    expect(saved.snapshot?['fontSize'], 24);
    expect(saved.snapshot?['headingStyle'], HeadingStyle.shade.name);
  });

  test('重命名自定义主题', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(readerThemesControllerProvider.notifier);
    await controller.duplicateCurrent();
    final id = container.read(readerThemesControllerProvider).activeId;
    await controller.rename(id, '夜间加大');
    expect(controller.state.active.name, '夜间加大');
  });
}