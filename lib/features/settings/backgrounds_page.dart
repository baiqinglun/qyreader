/// 阅读背景管理页（设置 → 资源 → 背景）。
///
/// 背景图属于自定义阅读主题；这里负责查看、逐张清理与一键清理本地图片。
/// 清除后对应主题变回纯色背景，排版设置保留。
library;

import 'package:flutter/material.dart';

import 'background_cache_view.dart';

/// 阅读背景页。
class ReaderBackgroundsPage extends StatelessWidget {
  /// 构造。
  const ReaderBackgroundsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('阅读背景')),
      body: const BackgroundCacheView(),
    );
  }
}
