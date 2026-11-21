/// 底栏 Tab 定义：首页 / 书架 / 统计 / 设置。
///
/// 枚举顺序必须与 [kHomeTabs] 一一对应（`HomeTab.index` 直接当下标用）。
library;

import 'package:flutter/material.dart';

/// 底栏 Tab。
enum HomeTab {
  /// 首页（阅读概览）。
  home,

  /// 书架。
  shelf,

  /// 阅读统计。
  stats,

  /// 设置。
  settings,
}

/// 底栏四个 Tab 的图标 / 选中图标 / 文案。
const List<({IconData icon, IconData selected, String label})> kHomeTabs = [
  (icon: Icons.home_outlined, selected: Icons.home_rounded, label: '首页'),
  (icon: Icons.menu_book_outlined, selected: Icons.menu_book, label: '书架'),
  (icon: Icons.insights_outlined, selected: Icons.insights, label: '统计'),
  (icon: Icons.settings_outlined, selected: Icons.settings, label: '设置'),
];
