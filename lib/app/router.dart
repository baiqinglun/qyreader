/// 应用路由（go_router）。
///
/// 手写路由声明，不使用 go_router_builder 代码生成
/// （其版本对本机 Dart SDK 有额外约束，M0 从简）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/book_detail/book_detail_page.dart';
import '../features/reader/reader_page.dart';
import '../features/reader/widgets/search_page.dart';
import '../features/home/home_shell.dart';
import '../features/settings/backgrounds_page.dart';
import '../features/settings/cache_center_page.dart';
import '../features/settings/category_manager_page.dart';
import '../features/settings/reader_theme_editor_page.dart';
import '../features/settings/reader_themes_page.dart';
import '../features/tags/tag_manager_page.dart';
import '../features/reader/reader_themes.dart';
import 'transitions/book_open_transition.dart';

/// 书架路由路径。
const String kShelfPath = '/';

/// 阅读器路由路径模板。
const String kReaderPath = '/reader/:bookId';

/// 阅读器内全书检索路由模板。
const String kReaderSearchPath = '/reader/:bookId/search';

/// 阅读统计页路径。
const String kStatsPath = '/stats';

/// 深链 `reader://book/{id}` 映射的路径。
const String kDeepLinkBookPath = '/book/:bookId';

/// 书籍详情/编辑页路由模板。
const String kBookDetailPath = '/book/:bookId/detail';

/// 标签管理页路径（设置 → 标签管理）。
const String kTagsPath = '/settings/tags';

/// 缓存中心路径（设置 → 数据 → 缓存：书籍 / 字体 / 背景）。
const String kCachePath = '/settings/cache';

/// 分类管理页路径（设置 → 管理 → 分类）。
const String kCategoriesPath = '/settings/categories';

/// 阅读背景管理页路径（设置 → 资源 → 背景）。
const String kBackgroundsPath = '/settings/backgrounds';

/// 阅读主题管理页路径。
const String kReaderThemesPath = '/settings/reader-themes';

/// 阅读主题编辑页路径（新建 / 编辑共用，编辑时经 extra 传预设）。
const String kReaderThemeEditPath = '/settings/reader-themes/edit';

/// 生成阅读器具体路径。
String readerPath(String bookId) => '/reader/$bookId';

/// 生成阅读器检索具体路径。
String readerSearchPath(String bookId) => '/reader/$bookId/search';

/// 生成书籍详情页具体路径。
String bookDetailPath(String bookId) => '/book/$bookId/detail';

/// 全局路由配置。
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: kShelfPath,
    // 文件管理器「打开方式」会把 file:// / content:// 当深链传给 Flutter；
    // 这类 URI 不是应用路由，统一回书架（文件本体经 qyreader/open 通道导入）。
    redirect: (context, state) {
      final scheme = state.uri.scheme;
      if (scheme == 'file' || scheme == 'content') return kShelfPath;
      return null;
    },
    routes: [
      // 主框架：书架 / 统计 / 设置三个 Tab
      GoRoute(path: kShelfPath, builder: (context, state) => const HomeShell()),
      GoRoute(
        path: kReaderPath,
        // 用 pageBuilder 而不是 builder：builder 固定生成 MaterialPage，
        // 拿不到「书封展开 / 合上」的自定义转场与动态 opaque。
        pageBuilder: (context, state) {
          final bookId = state.pathParameters['bookId'] ?? '';
          final launch = state.extra is BookLaunch
              ? state.extra as BookLaunch
              : null;
          return BookOpenPage<void>(
            key: state.pageKey,
            launch: launch,
            child: ReaderPage(bookId: bookId),
          );
        },
      ),
      GoRoute(
        path: kStatsPath,
        builder: (context, state) => const HomeShell(initialTab: HomeTab.stats),
      ),
      GoRoute(
        path: kReaderSearchPath,
        builder: (context, state) {
          final bookId = state.pathParameters['bookId'] ?? '';
          return BookSearchPage(bookId: bookId);
        },
      ),
      // 深链别名：reader://book/{id} 经 Android intent-filter 进入后
      // 由 Flutter 深链机制转成 /book/{id}
      GoRoute(
        path: kDeepLinkBookPath,
        builder: (context, state) {
          final bookId = state.pathParameters['bookId'] ?? '';
          return ReaderPage(bookId: bookId);
        },
      ),
      // 书籍详情/编辑页（书架长按菜单的「编辑信息」进入）
      GoRoute(
        path: kBookDetailPath,
        builder: (context, state) {
          final bookId = state.pathParameters['bookId'] ?? '';
          return BookDetailPage(bookId: bookId);
        },
      ),
      // 设置 → 标签管理
      GoRoute(
        path: kTagsPath,
        builder: (context, state) => const TagManagerPage(),
      ),
      // 设置 → 清除书籍缓存
      GoRoute(
        path: kCachePath,
        builder: (context, state) => const CacheCenterPage(),
      ),
      GoRoute(
        path: kCategoriesPath,
        builder: (context, state) => const CategoryManagerPage(),
      ),
      GoRoute(
        path: kBackgroundsPath,
        builder: (context, state) => const ReaderBackgroundsPage(),
      ),
      // 设置 → 阅读主题（默认 + 自定义主题管理）
      GoRoute(
        path: kReaderThemesPath,
        builder: (context, state) => const ReaderThemesPage(),
      ),
      // 新建 / 编辑阅读主题
      GoRoute(
        path: kReaderThemeEditPath,
        builder: (context, state) {
          final initial = state.extra is ReaderThemePreset
              ? state.extra! as ReaderThemePreset
              : null;
          return ReaderThemeEditorPage(initial: initial);
        },
      ),
    ],
  );
});
