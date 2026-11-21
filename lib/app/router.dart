/// 应用路由（go_router）。
///
/// 手写路由声明，不使用 go_router_builder 代码生成
/// （其版本对本机 Dart SDK 有额外约束，M0 从简）。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/book_detail/book_detail_page.dart';
import '../features/my_reading/my_reading_page.dart';
import '../features/notes/notes_overview_page.dart';
import '../features/notes/notes_wander_page.dart';
import '../features/reader/reader_page.dart';
import '../features/reader/tts/tts_page.dart';
import '../features/reader/widgets/search_page.dart';
import '../features/home/home_shell.dart';
import '../features/home/home_tabs.dart';
import '../features/settings/audio_library_page.dart';
import '../features/settings/authors_page.dart';
import '../features/settings/backgrounds_page.dart';
import '../features/settings/cache_center_page.dart';
import '../features/settings/book_reviews_page.dart';
import '../features/settings/category_manager_page.dart';
import '../features/settings/duplicate_books_page.dart';
import '../features/settings/reeden_import.dart';
import '../features/settings/reeden_import_page.dart';
import '../features/settings/reader_theme_editor_page.dart';
import '../features/settings/reader_themes_page.dart';
import '../features/settings/weread/weread_page.dart';
import '../features/tags/tag_manager_page.dart';
import '../features/reader/reader_themes.dart';
import 'transitions/book_open_transition.dart';

/// 书架路由路径。
const String kShelfPath = '/';

/// 阅读器路由路径模板。
const String kReaderPath = '/reader/:bookId';

/// 阅读器内全书检索路由模板。
const String kReaderSearchPath = '/reader/:bookId/search';

/// 全屏听书页路由模板（extra 传 `TtsPageLaunch`）。
const String kReaderTtsPath = '/reader/:bookId/tts';

/// 阅读统计页路径。
const String kStatsPath = '/stats';

/// 书架 Tab 路径（桌面组件点「最近阅读」时直接落到书架）。
const String kShelfTabPath = '/shelf';

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

/// 重复书籍整理页路径（设置 → 管理 → 重复书籍整理）。
const String kDuplicatesPath = '/settings/duplicates';

/// 阅读背景管理页路径（设置 → 资源 → 背景）。
const String kBackgroundsPath = '/settings/backgrounds';

/// 听书音频管理页路径（设置 → 资源 → 听书音频）。
const String kAudioPath = '/settings/audio';

/// 我的书评页路径。
const String kBookReviewsPath = '/settings/book-reviews';

/// 作者管理页路径（设置 → 管理 → 作者管理）。
const String kAuthorsPath = '/settings/authors';

/// 作者书籍页路径（extra 传作者名，空字符串 = 未知作者）。
const String kAuthorBooksPath = '/settings/authors/books';

/// Reeden 数据导入对比页路径（extra 传解析后的书籍数组）。
const String kReedenImportPath = '/settings/reeden-import';

/// 阅读主题管理页路径。
const String kReaderThemesPath = '/settings/reader-themes';

/// 我的阅读（时间线 / 分享）路径。
const String kMyReadingPath = '/settings/my-reading';

/// 笔记回顾（按书汇总）路径。
const String kNotesPath = '/settings/notes';

/// 笔记漫游（卡片式回顾）路径。
const String kNotesWanderPath = '/settings/notes/wander';

/// 微信读书同步路径（设置 → 实验性功能）。
const String kWeReadPath = '/settings/weread';

/// 阅读主题编辑页路径（新建 / 编辑共用，编辑时经 extra 传预设）。
const String kReaderThemeEditPath = '/settings/reader-themes/edit';

/// 生成阅读器具体路径。
String readerPath(String bookId) => '/reader/$bookId';

/// 生成阅读器检索具体路径。
String readerSearchPath(String bookId) => '/reader/$bookId/search';

/// 生成全屏听书页具体路径。
String readerTtsPath(String bookId) => '/reader/$bookId/tts';

/// 生成书籍详情页具体路径。
String bookDetailPath(String bookId) => '/book/$bookId/detail';

/// 全局路由观察者：阅读页用它感知「被其它页面盖住 / 回到最上层」，
/// 盖住时暂停阅读计时（搜索页 / 弹窗 / 底部面板都是 ModalRoute）。
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

/// 只观察页面路由，避免普通弹窗触发首页刷新。
final RouteObserver<PageRoute<dynamic>> pageRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

/// 全局路由配置。
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    observers: [routeObserver, pageRouteObserver],
    initialLocation: kShelfPath,
    // 文件管理器「打开方式」会把 file:// / content:// 当深链传给 Flutter；
    // 这类 URI 不是应用路由，统一回书架（文件本体经 qyreader/open 通道导入）。
    redirect: (context, state) {
      final scheme = state.uri.scheme;
      if (scheme == 'file' || scheme == 'content') return kShelfPath;
      return null;
    },
    routes: [
      // 主框架：首页 / 书架 / 统计 / 设置四个 Tab
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
            child: ReaderPage(
              bookId: bookId,
              initialLocatorJson: launch?.initialLocatorJson,
              holdProgress: launch?.holdProgress ?? false,
            ),
          );
        },
      ),
      GoRoute(
        path: kStatsPath,
        builder: (context, state) => const HomeShell(initialTab: HomeTab.stats),
      ),
      // 桌面组件（书架 / 最近阅读）点进来直接落到书架 Tab
      GoRoute(
        path: kShelfTabPath,
        builder: (context, state) => const HomeShell(initialTab: HomeTab.shelf),
      ),
      GoRoute(
        path: kReaderSearchPath,
        builder: (context, state) {
          final bookId = state.pathParameters['bookId'] ?? '';
          return BookSearchPage(bookId: bookId);
        },
      ),
      // 全屏听书页：控制器是全局单例（provider），页面自己取状态
      GoRoute(
        path: kReaderTtsPath,
        builder: (context, state) =>
            TtsPage(bookId: state.pathParameters['bookId'] ?? ''),
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
        path: kDuplicatesPath,
        builder: (context, state) => const DuplicateBooksPage(),
      ),
      GoRoute(
        path: kBackgroundsPath,
        builder: (context, state) => const ReaderBackgroundsPage(),
      ),
      // 设置 → 听书音频（背景音乐管理：内置 + 导入）
      GoRoute(
        path: kAudioPath,
        builder: (context, state) => const AudioLibraryPage(),
      ),
      // 设置 → 我的书评
      GoRoute(
        path: kBookReviewsPath,
        builder: (context, state) => const BookReviewsPage(),
      ),
      // 设置 → 作者管理
      GoRoute(
        path: kAuthorsPath,
        builder: (context, state) => const AuthorsPage(),
      ),
      // 某位作者名下的全部书籍（extra 传作者名，空字符串 = 未知作者）
      GoRoute(
        path: kAuthorBooksPath,
        builder: (context, state) {
          final extra = state.extra;
          return AuthorBooksPage(authorKey: extra is String ? extra : '');
        },
      ),
      // 设置 → 实验 → Reeden 数据导入对比（extra 传解析后的书籍数组）
      GoRoute(
        path: kReedenImportPath,
        builder: (context, state) =>
            ReedenImportPage(books: state.extra! as List<ReedenBookData>),
      ),
      // 设置 → 阅读主题（默认 + 自定义主题管理）
      GoRoute(
        path: kReaderThemesPath,
        builder: (context, state) => const ReaderThemesPage(),
      ),
      // 设置 → 我的阅读（时间线 / 分享海报）
      GoRoute(
        path: kMyReadingPath,
        builder: (context, state) => const MyReadingPage(),
      ),
      // 设置 → 笔记回顾
      GoRoute(
        path: kNotesPath,
        builder: (context, state) => const NotesOverviewPage(),
      ),
      // 设置 → 实验性功能 → 微信读书
      GoRoute(
        path: kWeReadPath,
        builder: (context, state) => const WeReadPage(),
      ),
      // 笔记漫游（可带书籍 id 只看某本书）
      GoRoute(
        path: kNotesWanderPath,
        builder: (context, state) => NotesWanderPage(
          initialBookId: state.extra is String ? state.extra! as String : null,
        ),
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
