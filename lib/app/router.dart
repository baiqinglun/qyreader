/// 应用路由（go_router）。
///
/// 手写路由声明，不使用 go_router_builder 代码生成
/// （其版本对本机 Dart SDK 有额外约束，M0 从简）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/reader/reader_page.dart';
import '../features/reader/widgets/search_page.dart';
import '../features/stats/stats_page.dart';
import '../features/shelf/shelf_page.dart';

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

/// 生成阅读器具体路径。
String readerPath(String bookId) => '/reader/$bookId';

/// 生成阅读器检索具体路径。
String readerSearchPath(String bookId) => '/reader/$bookId/search';

/// 全局路由配置。
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: kShelfPath,
    routes: [
      GoRoute(
        path: kShelfPath,
        builder: (context, state) => const ShelfPage(),
      ),
      GoRoute(
        path: kReaderPath,
        builder: (context, state) {
          final bookId = state.pathParameters['bookId'] ?? '';
          return ReaderPage(bookId: bookId);
        },
      ),
      GoRoute(
        path: kStatsPath,
        builder: (context, state) => const StatsPage(),
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
    ],
  );
});
