/// 缓存中心：书籍 / 字体 / 背景三个页签，都能逐项或一键清除本地缓存。
///
/// 共同语义：**只删本机缓存，不动云端原数据**；书籍与字体在下次同步/打开时
/// 可重新下载；背景图只在本机（跟随自定义阅读主题），清除后主题回到纯色。
library;

import 'package:flutter/material.dart';

import 'background_cache_view.dart';
import 'cache_manager_page.dart' show BookCacheView;
import 'font_cache_view.dart';

/// 缓存中心页面。
class CacheCenterPage extends StatelessWidget {
  /// 构造。[initialTab] 可指定打开时的页签（0 书籍 / 1 字体 / 2 背景）。
  const CacheCenterPage({super.key, this.initialTab = 0});

  /// 初始页签下标。
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('缓存'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '书籍'),
              Tab(text: '字体'),
              Tab(text: '背景'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [BookCacheView(), FontCacheView(), BackgroundCacheView()],
        ),
      ),
    );
  }
}
