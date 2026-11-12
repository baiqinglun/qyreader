/// 应用根组件。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/appearance_provider.dart';
import 'launch_reset.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// MaterialApp.router 装配。
class QyReaderApp extends ConsumerWidget {
  const QyReaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 主色可在设置页切换：这里 watch，改色后整个 App 立即换肤。
    final accent = ref.watch(appAccentControllerProvider);
    // 亮暗模式：书架右上角可以直接切，设置里默认跟随系统。
    final themeMode = ref.watch(appThemeModeControllerProvider);
    final router = ref.watch(routerProvider);
    // 点桌面图标重新进入时归位到书架（见 LaunchReset）。
    LaunchReset.bind(router);
    return MaterialApp.router(
      title: 'QYReader',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(accent.color),
      darkTheme: AppTheme.dark(accent.color),
      themeMode: themeMode.themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      locale: const Locale('zh'),
      routerConfig: router,
    );
  }
}
