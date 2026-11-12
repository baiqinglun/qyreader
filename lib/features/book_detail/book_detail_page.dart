/// 书籍详情/编辑页。
///
/// 布局（黑白灰，参考「书详情页」的克制作法）：左上封面（按真书比例画，
/// 带书脊明暗与书页厚度），右上源信息；其下是**用书本身表示的阅读进度**
/// （一道细线≈若干页，读过的更深，当前位置插一枚书签，标出章节与页码）；
/// 再下是数据行与最近 14 天的每日阅读时长；之后是可编辑的标签 / 分类 /
/// 星级 / 书评 / 置顶（改动即存）；底部一个主按钮：从当前章节继续阅读。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart' show readerPath;
import '../../app/theme/motion.dart';
import '../../app/transitions/book_open_transition.dart'
    show BookLaunch, BookLaunchKind;
import '../../core/locator.dart' as locators;
import '../../domain/entities/annotation.dart';
import '../../domain/entities/book.dart';
import '../../domain/entities/reading_progress.dart';
import '../../domain/services/book_reviews.dart';
import '../shelf/shelf_controller.dart' show shelfCategories;
import '../shelf/widgets/book_actions_sheet.dart' show confirmDeleteBook;
import '../shelf/widgets/tag_capsule.dart';
import '../tags/tag_library.dart';
import '../tags/tag_picker_sheet.dart';

/// 全书页数估算用的每页字符数（与阅读器页眉页脚的估算口径同数量级）。
const int _kCharsPerPage = 750;

/// 每页阅读分钟数（估算「大约几天读完」用）。
const double _kMinutesPerPage = 1.5;

/// 编辑信息页的顶部页签。
enum _BookTabs {
  basic('基础信息'),
  tags('标签分类'),
  toc('目录'),
  review('书评'),
  notes('笔记');

  const _BookTabs(this.label);

  /// 展示名。
  final String label;

  /// TabBar 用的展示名列表。
  static List<String> get labels =>
      [for (final t in _BookTabs.values) t.label];
}

/// 书籍详情/编辑页。
class BookDetailPage extends ConsumerStatefulWidget {
  const BookDetailPage({required this.bookId, super.key});

  final String bookId;

  @override
  ConsumerState<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends ConsumerState<BookDetailPage>
    with TickerProviderStateMixin {
  Book? _book;
  List<BookChapter> _chapters = const [];
  ReadingProgressSnapshot? _progress;
  var _dailyMs = <String, int>{};
  var _suggestedTags = <String>[];
  var _suggestedShelves = <String>[];
  var _localCached = true;
  var _loading = true;

  /// 顶部 Tab：基础信息 / 标签分类 / 目录 / 书评 / 笔记。
  late final TabController _tab =
      TabController(length: _BookTabs.labels.length, vsync: this);

  /// 笔记列表（进入页面加载一次）。
  var _annotations = <Annotation>[];
  var _annotationsLoading = true;

  // 编辑态（从书初始化，改动即存）。
  var _rating = 0;
  var _tags = <String>{};
  String? _category;
  var _readStatus = BookReadStatus.unread;
  var _pinned = false;

  /// 书评（支持多条；改动即存，编码进 `books.review` 字段）。
  var _reviews = <String>[];

  @override
  void initState() {
    super.initState();
    _load();
    _loadAnnotations();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  /// 笔记/划线列表（笔记页签）。
  Future<void> _loadAnnotations() async {
    try {
      final repo = await ref.read(annotationRepositoryProvider.future);
      final items = await repo.listForBook(widget.bookId);
      if (!mounted) return;
      setState(() {
        _annotations = items;
        _annotationsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _annotationsLoading = false);
    }
  }

  Future<void> _load() async {
    final bookRepo = await ref.read(bookRepositoryProvider.future);
    final book = await bookRepo.getById(widget.bookId);
    if (!mounted) return;
    if (book == null) {
      setState(() => _loading = false);
      return;
    }
    final chapters = await bookRepo.getChapters(widget.bookId);
    if (!mounted) return;
    final progressRepo = await ref.read(progressRepositoryProvider.future);
    final progress = await progressRepo.getProgress(widget.bookId);
    if (!mounted) return;
    // 缓存状态 = 书源文件是否在本地（清除缓存后为 false，阅读时自动拉回）
    final localCached = await File(book.filePath).exists();
    if (!mounted) return;
    final statsRepo = await ref.read(statsRepositoryProvider.future);
    final daily = await statsRepo.bookDailyDurations(widget.bookId, days: 14);
    if (!mounted) return;
    // 建议标签：其他书用过的标签（书架全量）。
    final shelf = await bookRepo.watchShelf().first;
    if (!mounted) return;
    final others = <String>{
      for (final item in shelf)
        if (item.book.id != book.id) ...item.book.tags,
    };
    setState(() {
      _book = book;
      _chapters = chapters;
      _progress = progress;
      _dailyMs = daily;
      _localCached = localCached;
      _suggestedTags = others.toList()..sort();
      _suggestedShelves = shelfCategories(shelf);
      _rating = book.rating ?? 0;
      _tags = {...book.tags};
      _category = (book.category?.trim().isEmpty ?? true)
          ? null
          : book.category!.trim();
      _readStatus = book.readStatus;
      _pinned = book.pinnedAt != null;
      _reviews = decodeBookReviews(book.review);
      _loading = false;
    });
  }

  // ---- 编辑（改动即存） ----

  Future<void> _persist({
    int? rating,
    String? review,
    Set<String>? tags,
    String? category,
    BookReadStatus? readStatus,
  }) async {
    try {
      final repo = await ref.read(bookRepositoryProvider.future);
      await repo.setPersonalization(
        widget.bookId,
        rating: rating,
        review: review,
        tags: tags?.toList(),
        category: category,
        readStatus: readStatus,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    }
  }

  // ---- 元数据编辑（书名/作者） ----

  /// 编辑书名/作者：EPUB 的 dc:title 常与文件名一样脏，这里手动改，
  /// 改完即存（写 hlc + sync_ops，多设备同步）。
  Future<void> _editMetaDialog() async {
    final book = _book;
    if (book == null) return;
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    // 不用 TextEditingController：showDialog 返回时弹层还在退场动画里，
    // 立刻 dispose 会在动画帧里用到已销毁的 controller。
    var title = book.title;
    var author = book.author ?? '';
    final saved = await showDialog<bool>(
      context: context,
      animationStyle: kSmoothSheetAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑书名与作者'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: title,
              autofocus: true,
              maxLength: 120,
              style: TextStyle(color: fg),
              onChanged: (value) => title = value,
              decoration: const InputDecoration(
                labelText: '书名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: author,
              maxLength: 60,
              style: TextStyle(color: fg),
              onChanged: (value) => author = value,
              decoration: const InputDecoration(
                labelText: '作者（清空 = 无作者）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final newTitle = title.trim();
    final newAuthor = author.trim();
    if (saved != true || !mounted) return;
    final repo = await ref.read(bookRepositoryProvider.future);
    await repo.updateBookMeta(widget.bookId, title: newTitle, author: newAuthor);
    if (!mounted) return;
    setState(() {
      _book = book.copyWith(
        title: newTitle.isEmpty ? book.title : newTitle,
        author: newAuthor.isEmpty ? null : newAuthor,
      );
    });
  }

  void _setRating(int value) {
    setState(() {
      _rating = _rating == value ? 0 : value;
      _book = _book!.copyWith(rating: _rating == 0 ? null : _rating);
    });
    unawaited(_persist(rating: _rating));
  }

  void _addTag(String raw) {
    final tag = raw.trim();
    if (tag.isEmpty || _tags.length >= 12) return;
    final name = tag.length > 20 ? tag.substring(0, 20) : tag;
    setState(() {
      _tags.add(name);
      _book = _book!.copyWith(tags: _tags.toList());
    });
    // 写进本机标签库：以后从标签库选择器里还能直接选到。
    unawaited(ref.read(tagLibraryControllerProvider.notifier).add(name));
    unawaited(_persist(tags: _tags));
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
      _book = _book!.copyWith(tags: _tags.toList());
    });
    unawaited(_persist(tags: _tags));
  }

  /// 从全量标签库直接勾选（比手打快；改动仍然即存）。
  Future<void> _pickTagsFromLibrary(List<TagSummary> tags) async {
    await showTagPickerSheet(
      context,
      tags: tags,
      selected: _tags,
      onToggle: (tag) {
        if (_tags.contains(tag)) {
          _removeTag(tag);
        } else {
          _addTag(tag);
        }
      },
    );
  }

  void _setCategory(String? value) {
    setState(() {
      _category = value;
      _book = _book!.copyWith(category: value);
    });
    // null 表示「不改」，清空分类要显式传空串。
    unawaited(_persist(category: value ?? ''));
  }

  void _setReadStatus(BookReadStatus status) {
    if (status == _readStatus) return;
    setState(() {
      _readStatus = status;
      _book = _book!.copyWith(readStatus: status);
    });
    unawaited(_persist(readStatus: status));
  }

  void _setPinned(bool value) {
    setState(() {
      _pinned = value;
      _book = _book!.copyWith(pinnedAt: value ? DateTime.now().millisecondsSinceEpoch : null);
    });
    unawaited(
      ref.read(bookRepositoryProvider.future).then(
            (repo) => repo.setPinned(widget.bookId, value),
          ),
    );
  }

  /// 保存书评列表（编码进 `books.review` 字段）。
  void _saveReviews(List<String> reviews) {
    setState(() => _reviews = reviews);
    unawaited(_persist(review: encodeBookReviews(reviews)));
  }

  /// 新增 / 编辑一条书评；[index] 为 null = 新增。
  Future<void> _editReview({int? index}) async {
    final initial = index == null ? '' : _reviews[index];
    final controller = TextEditingController(text: initial);
    final saved = await showDialog<bool>(
      context: context,
      animationStyle: kSmoothSheetAnimation,
      builder: (ctx) => AlertDialog(
        title: Text(index == null ? '添加书评' : '编辑书评'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            key: const ValueKey('book-review-input'),
            controller: controller,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: '写下这本书给你的感受…',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved != true || !mounted) return;
    final text = controller.text.trim();
    final next = [..._reviews];
    if (text.isEmpty) {
      if (index != null) next.removeAt(index);
    } else if (index == null) {
      next.add(text);
    } else {
      next[index] = text;
    }
    _saveReviews(next);
  }

  // ---- 派生数据 ----

  /// 当前章索引（locator 里带；解析失败为 null）。
  int? get _chapterIndex {
    final p = _progress;
    if (p == null) return null;
    return locators.locatorFromJson(p.locator)?.chapterIndex;
  }

  double get _percent => _progress?.percent ?? 0;

  int get _estPages => _book == null
      ? 0
      : math.max(1, (_book!.wordCount / _kCharsPerPage).ceil());

  int get _estPage => _percent <= 0
      ? 0
      : (_percent * _estPages).round().clamp(1, _estPages);

  String get _chapterTitle {
    final idx = _chapterIndex;
    if (idx == null || idx < 0 || idx >= _chapters.length) return '';
    final t = _chapters[idx].title.trim();
    return t.length > 16 ? '${t.substring(0, 16)}…' : t;
  }

  String get _chapterLabel {
    final idx = _chapterIndex ?? 0;
    return '第${_cnNumber(idx + 1)}章';
  }

  /// 平均每天阅读分钟数（近 14 天里有阅读的天）。
  int get _avgMinutesPerDay {
    final active = _dailyMs.values.where((v) => v > 0).toList();
    if (active.isEmpty) return 0;
    final total = active.reduce((a, b) => a + b);
    return (total / active.length / 60000).round();
  }

  String get _totalDurationLabel {
    final minutes = _dailyMs.values.fold<int>(0, (a, b) => a + b) ~/ 60000;
    if (minutes < 60) return '$minutes 分钟';
    final h = minutes / 60;
    return '${h.toStringAsFixed(h < 10 ? 1 : 0)} 小时';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    final muted = fg.withValues(alpha: 0.55);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        scrolledUnderElevation: 0,
        title: const Text('书籍信息'),
        bottom: _loading || _book == null
            ? null
            : TabBar(
                controller: _tab,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.6),
                labelColor: fg,
                unselectedLabelColor: muted,
                indicatorColor: theme.colorScheme.primary,
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                tabs: [
                  for (final t in _BookTabs.values)
                    Tab(
                      key: ValueKey('book-tab-${t.name}'),
                      text: t.label,
                    ),
                ],
              ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _book == null
              ? Center(
                  child: Text('书籍不存在或已删除', style: TextStyle(color: muted)),
                )
              : TabBarView(
                  controller: _tab,
                  children: [
                    _basicTab(theme, fg, muted),
                    _tagsTab(theme, fg, muted),
                    _tocTab(theme, fg, muted),
                    _reviewTab(theme, fg, muted),
                    _notesTab(theme, fg, muted),
                  ],
                ),
      bottomNavigationBar: _loading || _book == null
          ? null
              : _buildBottomBar(theme, fg),
    );
  }

  /// 公共头部：封面 + 书名作者 + 进度/统计（五个页签共用）。
  Widget _bookHeader(ThemeData theme, Color fg, Color muted) {
    final book = _book!;
    final percent = _percent;
    final estPages = _estPages;
    final estPage = _estPage;
    final pagesLeft = math.max(0, estPages - estPage);
    final avgMin = _avgMinutesPerDay;

    final String summary;
    if (percent <= 0) {
      summary = '还没有阅读记录，可以从第一章开始。';
    } else {
      final where = _chapterTitle.isEmpty
          ? _chapterLabel
          : '「$_chapterTitle」';
      final remainPart = pagesLeft > 0 ? '还剩约 $pagesLeft 页' : '已经读到末尾';
      final estPart = avgMin > 0 && pagesLeft > 0
          ? '；按你最近平均每天读 $avgMin 分钟，'
              '大约 ${math.max(1, (pagesLeft * _kMinutesPerPage / avgMin).ceil())} 天读完'
          : '';
      summary = '读到$where，$remainPart$estPart。';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BookCover3D(path: book.coverPath, title: book.title),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _statusLine(),
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _editMetaDialog,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              book.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: fg,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Icon(
                              Icons.edit_outlined,
                              size: 15,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (book.author != null && book.author!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        book.author!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 10),
                  _SourceChips(
                    book: book,
                    muted: muted,
                    localCached: _localCached,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              (percent * 100).round().toString(),
              style: TextStyle(
                color: fg,
                fontSize: 34,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
            Text('%', style: TextStyle(color: muted, fontSize: 16)),
            const SizedBox(width: 10),
            Text('已读', style: TextStyle(color: muted, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 10),
        _BookEdgeProgress(
          percent: percent,
          chapterLabel: '$_chapterLabel · 约$estPage页',
          pages: estPages,
        ),
        const SizedBox(height: 12),
        Text(
          summary,
          style: TextStyle(
            color: fg.withValues(alpha: 0.8),
            fontSize: 13.5,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            _DataCard(
              value: '约$estPages',
              label: '总页数',
              fg: fg,
              muted: muted,
            ),
            const SizedBox(width: 10),
            _DataCard(
              value: '${book.chapterCount}',
              label: '章节',
              fg: fg,
              muted: muted,
            ),
            const SizedBox(width: 10),
            _DataCard(
              value: _totalDurationLabel,
              label: '累计时长',
              fg: fg,
              muted: muted,
            ),
          ],
        ),
      ],
    );
  }

  /// 基础信息页签：简介 + 最近 14 天每日时长。
  Widget _basicTab(ThemeData theme, Color fg, Color muted) {
    final book = _book!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _bookHeader(theme, fg, muted),
        if (book.description != null && book.description!.trim().isNotEmpty) ...[
          const SizedBox(height: 28),
          _sectionTitle('简介', fg),
          const SizedBox(height: 8),
          Text(
            book.description!.trim(),
            style: TextStyle(
              color: fg.withValues(alpha: 0.8),
              fontSize: 13.5,
              height: 1.6,
            ),
          ),
        ],
        const SizedBox(height: 28),
        _DailyBars(dailyMs: _dailyMs, muted: muted, fg: fg),
      ],
    );
  }

  /// 标签分类页签：标签 + 书架（分组） + 评分 + 置顶。
  Widget _tagsTab(ThemeData theme, Color fg, Color muted) {
    final libraryTags = ref.watch(tagSummariesProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        _sectionTitle('阅读状态', fg),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final status in BookReadStatus.values)
              ChoiceChip(
                key: ValueKey('book-status-${status.name}'),
                label: Text(status.label),
                selected: _readStatus == status,
                onSelected: (_) => _setReadStatus(status),
              ),
          ],
        ),
        const SizedBox(height: 22),
        _sectionTitle('标签', fg),
        const SizedBox(height: 8),
        _TagEditor(
          tags: _tags,
          suggestions:
              _suggestedTags.where((t) => !_tags.contains(t)).take(10).toList(),
          libraryCount: libraryTags.length,
          onAdd: _addTag,
          onRemove: _removeTag,
          onPickLibrary: () => unawaited(_pickTagsFromLibrary(libraryTags)),
        ),
        const SizedBox(height: 22),
        _sectionTitle('书架（分组）', fg),
        const SizedBox(height: 8),
        _CategoryEditor(
          category: _category,
          suggestions: _suggestedCategories(),
          onSelect: _setCategory,
        ),
        const SizedBox(height: 22),
        _sectionTitle('评分', fg),
        const SizedBox(height: 4),
        _RatingRow(rating: _rating, onRate: _setRating),
        const SizedBox(height: 14),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _pinned,
          activeTrackColor: theme.colorScheme.primary,
          onChanged: _setPinned,
          title: Text('在书架置顶', style: TextStyle(color: fg)),
          subtitle: Text(
            '置顶书籍始终排在最前面',
            style: TextStyle(color: muted, fontSize: 11),
          ),
        ),
      ],
    );
  }

  /// 目录页签：章节列表，点击跳到阅读器该章。
  Widget _tocTab(ThemeData theme, Color fg, Color muted) {
    if (_chapters.isEmpty) {
      return Center(
        child: Text('没有章节信息', style: TextStyle(color: muted)),
      );
    }
    final current = _chapterIndex;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: _chapters.length,
      itemBuilder: (context, index) {
        final chapter = _chapters[index];
        final isCurrent = index == current;
        return ListTile(
          key: ValueKey('book-toc-$index'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Text(
            _cnNumber(index + 1),
            style: TextStyle(
              color: isCurrent ? theme.colorScheme.primary : muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          title: Text(
            chapter.title.trim().isEmpty ? '第${_cnNumber(index + 1)}章' : chapter.title.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isCurrent ? theme.colorScheme.primary : fg,
              fontSize: 14,
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          onTap: () {
            unawaited(
              ref
                  .read(bookRepositoryProvider.future)
                  .then((r) => r.touchOpened(widget.bookId)),
            );
            context.push(
              readerPath(widget.bookId),
              extra: BookLaunch(
                bookId: widget.bookId,
                kind: BookLaunchKind.card,
                coverPath: _book?.coverPath,
                radius: 12,
              ),
            );
          },
        );
      },
    );
  }

  /// 书评页签：多条书评列表，可新增 / 编辑 / 删除（改动即存）。
  Widget _reviewTab(ThemeData theme, Color fg, Color muted) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _reviews.isEmpty ? '还没有书评' : '${_reviews.length} 条书评',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('book-review-add'),
              onPressed: () => unawaited(_editReview()),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加书评'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _reviews.length; i++)
          Container(
            key: ValueKey('book-review-$i'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _reviews[i],
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.9),
                    fontSize: 13.5,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => unawaited(_editReview(index: i)),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('编辑'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        final next = [..._reviews]..removeAt(i);
                        _saveReviews(next);
                      },
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('删除'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 笔记页签：这本书的划线与笔记。
  Widget _notesTab(ThemeData theme, Color fg, Color muted) {
    if (_annotationsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_annotations.isEmpty) {
      return Center(
        child: Text(
          '还没有笔记和划线\n阅读时长按选中文字即可添加',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, height: 1.7),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: _annotations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = _annotations[index];
        final quote = item.quotedText?.trim() ?? '';
        final note = item.note?.trim() ?? '';
        final date = DateTime.fromMillisecondsSinceEpoch(item.createdAt);
        final dateText =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        return Container(
          key: ValueKey('book-note-${item.id}'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _annotationColor(theme, item.color),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _annotationTypeLabel(item.type),
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                  const Spacer(),
                  Text(
                    dateText,
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ),
              if (quote.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  quote,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.85),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
              if (note.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  note,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Color _annotationColor(ThemeData theme, AnnotationColor color) {
    return switch (color) {
      AnnotationColor.yellow => const Color(0xFFE0A030),
      AnnotationColor.green => const Color(0xFF4CAF7D),
      AnnotationColor.blue => const Color(0xFF5B9BD5),
      AnnotationColor.rose => const Color(0xFFE57399),
    };
  }

  String _annotationTypeLabel(AnnotationType type) {
    return switch (type) {
      AnnotationType.highlight => '划线',
      AnnotationType.underline => '下划线',
      AnnotationType.note => '笔记',
    };
  }

  Widget _sectionTitle(String text, Color fg) => Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      );

  List<String> _suggestedCategories() {
    // 全量书架（当前书架由编辑器自行并入选中态）。
    return _suggestedShelves;
  }

  String _statusLine() {
    final book = _book!;
    final last = book.lastOpenedAt;
    if (book.isFinished) return '读完';
    if (last == null) return '未开始阅读';
    final d = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(last),
    );
    final when = d.inMinutes < 1
        ? '刚刚'
        : d.inHours < 1
            ? '${d.inMinutes} 分钟前'
            : d.inDays < 1
                ? '${d.inHours} 小时前'
                : d.inDays == 1
                    ? '昨天'
                    : '${d.inDays} 天前';
    return '在读 · $when';
  }

  Widget _buildBottomBar(ThemeData theme, Color fg) {
    final estPage = _estPage;
    final label = _percent > 0
        ? '从$_chapterLabel继续 · 约$estPage页'
        : '开始阅读';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Row(
          children: [
            IconButton.outlined(
              tooltip: '删除这本书',
              style: IconButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(
                  color: theme.colorScheme.error.withValues(alpha: 0.4),
                ),
              ),
              onPressed: () async {
                final deleted =
                    await confirmDeleteBook(context, ref, book: _book!);
                if (deleted && mounted) context.pop();
              },
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  unawaited(
                    ref
                        .read(bookRepositoryProvider.future)
                        .then((r) => r.touchOpened(widget.bookId)),
                  );
                  context.push(
                    readerPath(widget.bookId),
                    extra: BookLaunch(
                      bookId: widget.bookId,
                      kind: BookLaunchKind.card,
                      coverPath: _book?.coverPath,
                      radius: 12,
                    ),
                  );
                },
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// 数字转中文（章节标注用；大于 12 直接用数字）。
String _cnNumber(int n) {
  const cn = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
  if (n < cn.length) return cn[n];
  if (n <= 19) return '十${cn[n - 10]}';
  return '$n';
}

// ---- 头部封面：按真书比例画（书脊明暗 + 书页厚度 + 柔和投影） ----

class _BookCover3D extends StatelessWidget {
  const _BookCover3D({required this.path, required this.title});

  final String? path;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(3, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(2.5),
          right: Radius.circular(1.5),
        ),
        child: SizedBox(
          width: 92,
          height: 132,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    path == null
                        ? _placeholder(theme)
                        : Image.file(
                            File(path!),
                            fit: BoxFit.cover,
                            cacheWidth: 280,
                            errorBuilder: (_, __, ___) =>
                                _placeholder(theme),
                          ),
                    // 书脊明暗：左缘一道暗到透明的竖向明暗（表现装订侧）
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Color(0x5F000000),
                            Color(0x00000000),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 右侧书页厚度：一条浅色纸页，两道发丝线
              Container(
                width: 4,
                color: const Color(0xFFF4F1EA),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < 5; i++)
                      Container(
                        height: 0.6,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        color: const Color(0x33000000),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(ThemeData theme) => Container(
        color: const Color(0xFF3A3A3A),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: Text(
          title,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFDAD7D0),
            fontSize: 11,
            height: 1.4,
            letterSpacing: 1,
          ),
        ),
      );
}

// ---- 源信息芯片（格式 / 章节 / 字数 / 文件大小 / 导入时间） ----

class _SourceChips extends StatelessWidget {
  const _SourceChips({
    required this.book,
    required this.muted,
    required this.localCached,
  });

  final Book book;
  final Color muted;

  /// 书源文件是否在本地（清除缓存后为 false）。
  final bool localCached;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      book.format.name.toUpperCase(),
      if (book.language != null && book.language!.isNotEmpty)
        book.language!.toUpperCase(),
      '${book.chapterCount} 章',
      if (book.wordCount > 0) _words(book.wordCount),
      _size(book.fileSize),
      '导入于 ${_date(book.addedAt)}',
      localCached ? '本地缓存中' : '已清缓存 · 同步库保存',
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final t in parts)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: muted.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(t, style: TextStyle(color: muted, fontSize: 11)),
          ),
      ],
    );
  }

  static String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  static String _size(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }

  static String _words(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)} 万字';
    return '$n 字';
  }
}

// ---- 进度：书的侧面（一道细线≈8页，读过的更深，当前位置插书签） ----

class _BookEdgeProgress extends StatelessWidget {
  const _BookEdgeProgress({
    required this.percent,
    required this.chapterLabel,
    required this.pages,
  });

  final double percent;

  /// 书签标注文案（章节 · 页码）。
  final String chapterLabel;

  /// 估算总页数（右下角标注）。
  final int pages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    final muted = fg.withValues(alpha: 0.30);
    final read = fg.withValues(alpha: 0.82);
    const lines = 64;
    const ribbonColor = Color(0xFFB4574E);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final ribbonX = (percent.clamp(0.0, 1.0) * (w - 8) + 2)
            .clamp(10.0, w - 10)
            .toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 52,
              width: w,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _EdgeLinesPainter(
                        lines: lines,
                        read: read,
                        unread: muted,
                        readFraction: percent.clamp(0.0, 1.0),
                      ),
                    ),
                  ),
                  // 书签：缎带从线行里垂出来
                  Positioned(
                    left: ribbonX - 2.5,
                    top: 6,
                    child: CustomPaint(
                      size: const Size(5, 40),
                      painter: _RibbonPainter(color: ribbonColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('1', style: TextStyle(color: muted, fontSize: 11)),
                const Spacer(),
                Text(
                  chapterLabel,
                  style: TextStyle(
                    color: ribbonColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                Text(
                  '约 $pages 页',
                  style: TextStyle(
                    color: muted,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// 书侧面：一道细线 ≈ 总页数/lines 页；读过的更深。
class _EdgeLinesPainter extends CustomPainter {
  _EdgeLinesPainter({
    required this.lines,
    required this.read,
    required this.unread,
    required this.readFraction,
  });

  final int lines;
  final Color read;
  final Color unread;
  final double readFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / (lines - 1);
    final readX = size.width * readFraction;
    final readPaint = Paint()..color = read;
    final unreadPaint = Paint()..color = unread;
    for (var i = 0; i < lines; i++) {
      final x = i * step;
      final h = size.height * 0.62;
      // 轻微高低错落：真书页缘不是完全平的
      final y = (i.isEven ? 2.0 : 4.0) + size.height * 0.06;
      final p = x <= readX ? readPaint : unreadPaint;
      canvas.drawLine(Offset(x, y), Offset(x, y + h), p);
    }
  }

  @override
  bool shouldRepaint(_EdgeLinesPainter old) =>
      old.readFraction != readFraction ||
      old.lines != lines ||
      old.read != read ||
      old.unread != unread;
}

/// 书签缎带：竖条 + 底部燕尾缺口。
class _RibbonPainter extends CustomPainter {
  _RibbonPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height - 5)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.color != color;
}

// ---- 数据卡 ----

class _DataCard extends StatelessWidget {
  const _DataCard({
    required this.value,
    required this.label,
    required this.fg,
    required this.muted,
  });

  final String value;
  final String label;
  final Color fg;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: muted.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 19,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: muted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ---- 最近 14 天每日时长（迷你柱状，黑白灰） ----

class _DailyBars extends StatelessWidget {
  const _DailyBars({
    required this.dailyMs,
    required this.muted,
    required this.fg,
  });

  final Map<String, int> dailyMs;
  final Color muted;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    const days = 14;
    final now = DateTime.now();
    final values = <(DateTime, int)>[
      for (var i = days - 1; i >= 0; i--)
        (now.subtract(Duration(days: i)), 0),
    ];
    for (var i = 0; i < values.length; i++) {
      final d = values[i].$1;
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      values[i] = (d, dailyMs[key] ?? 0);
    }
    final maxMs = values.fold<int>(0, (a, b) => a + b.$2);

    String two(int v) => v.toString().padLeft(2, '0');
    String dayKey(DateTime d) =>
        '${d.month.toString().padLeft(2, '0')}-${two(d.day)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '最近 $days 天',
          style: TextStyle(
            color: fg,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 62,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (d, ms) in values)
                Expanded(
                  child: Tooltip(
                    message: ms > 0
                        ? '${dayKey(d)} · ${_minutesLabel(ms)}'
                        : '${dayKey(d)} · 未读',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: math.max(
                              2.0,
                              maxMs > 0 ? 52 * ms / maxMs : 0,
                            ),
                            decoration: BoxDecoration(
                              color: ms > 0
                                  ? fg.withValues(alpha: 0.75)
                                  : muted.withValues(alpha: 0.35),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              dayKey(values.first.$1),
              style: TextStyle(color: muted, fontSize: 10),
            ),
            Text(
              dayKey(values.last.$1),
              style: TextStyle(color: muted, fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }

  static String _minutesLabel(int ms) {
    final m = ms ~/ 60000;
    if (m < 1) return '不足 1 分钟';
    if (m < 60) return '$m 分钟';
    return '${(m / 60).toStringAsFixed(1)} 小时';
  }
}

// ---- 标签编辑（改动即存） ----

class _TagEditor extends StatefulWidget {
  const _TagEditor({
    required this.tags,
    required this.suggestions,
    required this.libraryCount,
    required this.onAdd,
    required this.onRemove,
    required this.onPickLibrary,
  });

  final Set<String> tags;
  final List<String> suggestions;

  /// 标签库全量条数（含当前书已选的标签）。
  final int libraryCount;
  final void Function(String) onAdd;
  final void Function(String) onRemove;

  /// 打开全量标签选择器。
  final VoidCallback onPickLibrary;

  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tags = widget.tags;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tags.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in tags)
                TagCapsule(
                  tag: tag,
                  selected: true,
                  onDeleted: () => widget.onRemove(tag),
                ),
            ],
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) {
                  widget.onAdd(v);
                  _ctrl.clear();
                },
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '输入新标签',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () {
                widget.onAdd(_ctrl.text);
                _ctrl.clear();
              },
              child: const Text('添加'),
            ),
          ],
        ),
        if (widget.libraryCount > 0) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: widget.onPickLibrary,
            icon: const Icon(Icons.sell_outlined, size: 18),
            label: Text('从标签库选择（${widget.libraryCount}）'),
          ),
        ],
        if (widget.suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final tag in widget.suggestions)
                TagCapsule(
                  showAdd: true,
                  tag: tag,
                  onTap: () => widget.onAdd(tag),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---- 分类编辑（改动即存） ----

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({
    required this.category,
    required this.suggestions,
    required this.onSelect,
  });

  final String? category;
  final List<String> suggestions;
  final void Function(String?) onSelect;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final options = <String>{
      ...widget.suggestions,
      if (category != null) category,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('无书架'),
              selected: category == null,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => widget.onSelect(null),
            ),
            for (final cat in options)
              ChoiceChip(
                label: Text(cat),
                selected: category == cat,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => widget.onSelect(cat),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) {
                  final t = v.trim();
                  if (t.isNotEmpty) {
                    widget.onSelect(t.length > 20 ? t.substring(0, 20) : t);
                  }
                  _ctrl.clear();
                },
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '新建书架',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---- 星级 ----

class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.rating, required this.onRate});

  final int rating;
  final void Function(int) onRate;

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            tooltip: '$i 星',
            onPressed: () => onRate(i),
            icon: Icon(
              i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 30,
              color: i <= rating
                  ? const Color(0xFFE0A030)
                  : fg.withValues(alpha: 0.4),
            ),
          ),
      ],
    );
  }
}
