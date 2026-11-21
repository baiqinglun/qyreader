/// 「我的阅读」数据整理：筛选、按年月分组、文案格式化。
///
/// 纯函数，页面与分享海报共用；阅读时长 / 字数来自 `StatsRepository.bookTotals()`。
library;

import '../../domain/entities/book.dart';
import '../../domain/entities/reading_stats.dart';

/// 顶部阅读状态筛选。
enum MyReadingFilter {
  all('全部'),
  reading('在读'),
  dropped('搁置'),
  finished('读完');

  const MyReadingFilter(this.label);

  /// 展示名。
  final String label;

  /// 该筛选是否收下这本书。
  bool accepts(Book book) => switch (this) {
    MyReadingFilter.all => true,
    MyReadingFilter.reading => book.readStatus == BookReadStatus.reading,
    MyReadingFilter.dropped => book.readStatus == BookReadStatus.dropped,
    MyReadingFilter.finished => book.readStatus == BookReadStatus.finished,
  };
}

/// 一本书在「我的阅读」里的展示数据。
class MyReadingBook {
  const MyReadingBook({
    required this.item,
    required this.durationMs,
    required this.charsRead,
    required this.date,
  });

  /// 书架条目（书籍 + 进度）。
  final ShelfItem item;

  /// 累计阅读时长（ms）。
  final int durationMs;

  /// 累计字符数。
  final int charsRead;

  /// 归属时间：最近打开时间，没打开过用元数据更新时间。
  final DateTime date;

  Book get book => item.book;

  /// 阅读状态。
  BookReadStatus get status => book.readStatus;
}

/// 年月分组。
class MyReadingMonth {
  MyReadingMonth({
    required this.year,
    required this.month,
    required this.books,
  });

  /// 年。
  final int year;

  /// 月（1..12）。
  final int month;

  /// 本月书目（按时间倒序）。
  final List<MyReadingBook> books;
}

/// 年分组。
class MyReadingYear {
  MyReadingYear({required this.year, required this.months});

  /// 年。
  final int year;

  /// 月份（按时间倒序）。
  final List<MyReadingMonth> months;

  /// 全年本数。
  int get count => months.fold(0, (sum, m) => sum + m.books.length);
}

/// 生成当前筛选 / 搜索下的书目，按时间倒序。
List<MyReadingBook> myReadingBooks({
  required List<ShelfItem> items,
  required Map<String, BookReadingTotal> totals,
  MyReadingFilter filter = MyReadingFilter.all,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  final books = <MyReadingBook>[];
  for (final item in items) {
    final book = item.book;
    if (!filter.accepts(book)) continue;
    if (q.isNotEmpty) {
      final title = book.title.toLowerCase();
      final author = (book.author ?? '').toLowerCase();
      if (!title.contains(q) && !author.contains(q)) continue;
    }
    final total = totals[book.id];
    final ms = book.lastOpenedAt ?? book.updatedAt;
    books.add(
      MyReadingBook(
        item: item,
        durationMs: total?.durationMs ?? 0,
        charsRead: total?.charsRead ?? 0,
        date: DateTime.fromMillisecondsSinceEpoch(ms > 0 ? ms : 0),
      ),
    );
  }
  books.sort((a, b) => b.date.compareTo(a.date));
  return books;
}

/// 按年 > 月分组。
List<MyReadingYear> groupMyReading(List<MyReadingBook> books) {
  final years = <int, Map<int, List<MyReadingBook>>>{};
  for (final book in books) {
    years
        .putIfAbsent(book.date.year, () => <int, List<MyReadingBook>>{})
        .putIfAbsent(book.date.month, () => <MyReadingBook>[])
        .add(book);
  }
  final out = <MyReadingYear>[];
  final yearKeys = years.keys.toList()..sort((a, b) => b.compareTo(a));
  for (final year in yearKeys) {
    final months = years[year]!;
    final monthKeys = months.keys.toList()..sort((a, b) => b.compareTo(a));
    out.add(
      MyReadingYear(
        year: year,
        months: [
          for (final month in monthKeys)
            MyReadingMonth(year: year, month: month, books: months[month]!),
        ],
      ),
    );
  }
  return out;
}

/// 卡片大标题：读完 / 搁置显示累计时长，其余显示读到百分之几。
String myReadingHeadline(MyReadingBook book) {
  switch (book.status) {
    case BookReadStatus.finished:
    case BookReadStatus.dropped:
      return formatReadingDuration(book.durationMs);
    case BookReadStatus.unread:
      if (book.item.percent > 0) return _percent(book.item.percent);
      return '未开始';
    case BookReadStatus.reading:
      return _percent(book.item.percent);
  }
}

String _percent(double percent) {
  final value = (percent.clamp(0.0, 1.0) * 100).toStringAsFixed(1);
  return '读到 ${value.endsWith('.0') ? value.substring(0, value.length - 2) : value}%';
}

/// 卡片副标题：开始阅读（字数 / 时长），或读完 / 搁置的年月。
String myReadingMeta(MyReadingBook book, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final ym = book.date.year == current.year
      ? '${book.date.month}月'
      : '${book.date.year}年${book.date.month}月';
  switch (book.status) {
    case BookReadStatus.finished:
      return '${book.date.year}年${book.date.month}月读完';
    case BookReadStatus.dropped:
      return '${book.date.year}年${book.date.month}月搁置';
    case BookReadStatus.unread:
      if (book.item.percent <= 0) return '$ym加入书架';
      return '$ym开始阅读 · ${formatReadingChars(book.charsRead)} · '
          '${formatReadingDuration(book.durationMs)}';
    case BookReadStatus.reading:
      return '$ym开始阅读 · ${formatReadingChars(book.charsRead)} · '
          '${formatReadingDuration(book.durationMs)}';
  }
}

/// 海报里的日期：`10.29`。
String myReadingMonthDay(DateTime date) =>
    '${date.month.toString().padLeft(2, '0')}.'
    '${date.day.toString().padLeft(2, '0')}';

/// 阅读时长：不足 1 分钟按秒，超过 1 小时带小时。
String formatReadingDuration(int ms) {
  final seconds = (ms / 1000).round();
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分钟';
}

/// 字数：1 万以上用「万」。
String formatReadingChars(int chars) {
  if (chars < 10000) return '$chars 字';
  final value = (chars / 10000).toStringAsFixed(1);
  final label = value.endsWith('.0')
      ? value.substring(0, value.length - 2)
      : value;
  return '$label 万字';
}
