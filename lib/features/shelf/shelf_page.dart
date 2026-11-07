/// 书架页：网格布局 + 空态 + 导入入口。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme/motion.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/skeleton.dart';
import '../../domain/entities/book.dart';
import 'shelf_controller.dart';
import 'widgets/book_card.dart';

/// 首页：书架。
class ShelfPage extends ConsumerWidget {
  const ShelfPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(shelfItemsProvider);
    final importing = ref.watch(importControllerProvider) is ImportLoading;

    ref.listen<ImportState>(importControllerProvider, (prev, next) {
      final messenger = ScaffoldMessenger.of(context);
      if (next case ImportDone(:final book)) {
        messenger.showSnackBar(
          SnackBar(content: Text('已导入《${book.title}》')),
        );
        ref.read(importControllerProvider.notifier).consume();
      } else if (next case ImportError(:final message)) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
        ref.read(importControllerProvider.notifier).consume();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        bottom: importing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: importing
            ? null
            : () =>
                ref.read(importControllerProvider.notifier).importFromPicker(),
        icon: const Icon(Icons.file_upload_outlined),
        label: const Text('导入书籍'),
      ),
      body: items.when(
        loading: () => const _SkeletonGrid(),
        error: (error, stack) => EmptyState(
          icon: Icons.error_outline,
          title: '书架加载失败',
          message: '$error',
        ),
        data: (list) => list.isEmpty
            ? EmptyState(
                icon: Icons.auto_stories_outlined,
                title: '书架空空如也',
                message: '导入一本 EPUB，开始阅读之旅',
                actionLabel: '选择 EPUB 文件',
                onAction: importing
                    ? null
                    : () => ref
                        .read(importControllerProvider.notifier)
                        .importFromPicker(),
              )
            : _BookGrid(items: list),
      ),
    );
  }
}

class _BookGrid extends ConsumerWidget {
  const _BookGrid({required this.items});

  final List<ShelfItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.72,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _AnimatedAppear(
          index: index,
          child: BookCard(
            item: items[index],
            onOpen: () => _openBook(context, ref, items[index].book.id),
          ),
        );
      },
    );
  }

  void _openBook(BuildContext context, WidgetRef ref, String bookId) {
    // 打开书：更新 last_opened_at（异步落库），并进入阅读器占位页。
    unawaited(
      ref.read(bookRepositoryProvider.future).then((r) => r.touchOpened(bookId)),
    );
    context.push(readerPath(bookId));
  }
}

class _AnimatedAppear extends StatelessWidget {
  const _AnimatedAppear({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    // 冷启动 stagger：每张 +20ms，封顶 300ms。
    final delayMs = (index * 20).clamp(0, 300);
    final total = motion.emphasized + Duration(milliseconds: delayMs);
    final beginFraction = delayMs / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(beginFraction, 1, curve: motion.enter),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.72,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: 9,
      itemBuilder: (context, index) => const SkeletonBox(
        width: double.infinity,
        height: double.infinity,
        borderRadius: 12,
      ),
    );
  }
}
