/// 翻页动画性能基准（模拟器 Profile 模式跑）。
///
/// 指标：多页长章连续 fling 翻页期间每帧的 build/raster/total 耗时
/// P50/P95，以及翻页期间发生的全章重排次数。
///
/// 运行：
/// flutter drive --profile -d emulator-5554 \
///   --driver=test_driver/integration_test.dart \
///   --target=integration_test/reader_turn_perf_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/data/parsers/epub/epub_parser.dart';
import 'package:qy_reader/features/reader/native/native_chapter_source.dart';
import 'package:qy_reader/features/reader/native/native_paginator.dart';
import 'package:qy_reader/features/reader/native/native_reader_view.dart';
import 'package:qy_reader/features/reader/reader_settings.dart';

/// 约 2.4 万字的章节（>20 页，够连翻）。
NativeChapter _benchChapter() {
  const sentence = '在秋日午后的光线里，我数着归途上的每一片叶子，它们从枝头落下，'
      '像一封封没有寄出的信，落在无人经过的小径上，被风轻轻翻动。';
  final blocks = <ParsedBlock>[const ParsedBlock(text: '第一章 性能基准', level: 1)];
  var chars = 0;
  var i = 0;
  while (chars < 24000) {
    if (i > 0 && i % 30 == 0) {
      blocks.add(ParsedBlock(text: '第 ${i ~/ 30 + 1} 节', level: 2));
    }
    final text = List.filled(1 + i % 3, sentence).join();
    blocks.add(ParsedBlock(text: text));
    chars += text.length;
    i++;
  }
  return NativeChapter.fromBlocks(
    idx: 0,
    title: '第一章 性能基准',
    href: 'c1.xhtml',
    blocks: blocks,
    fallbackText: '',
  );
}

List<int> _percentiles(List<int> micros) {
  if (micros.isEmpty) return [0, 0, 0];
  final sorted = [...micros]..sort();
  int at(double p) => sorted[((sorted.length - 1) * p).round()];
  return [at(0.50), at(0.95), sorted.last];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('翻页性能基准', (tester) async {
    final chapter = _benchChapter();
    final hostKey = GlobalKey<State>();

    NativeReaderViewState.debugPreviewCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        key: hostKey,
        body: NativeReaderView(
          chapters: [chapter],
          settings: const ReadingSettings(fontSize: 18, lineHeight: 1.7),
          previewListenable: ValueNotifier(null),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          theme: ReadingTheme.paper,
          initialChapterIndex: 0,
          initialOffset: 0,
          onPosition: (_) {},
          onCenterTap: () {},
        ),
      ),
    ));
    // 等首屏 + 全章分页完成
    final wait = Stopwatch()..start();
    final firstCompute = NativePaginator.debugComputeCount;
    while (wait.elapsedMilliseconds < 8000) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 8));
      if (NativePaginator.debugComputeCount > firstCompute) break;
    }
    // 分页完成后等分帧重排收尾
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final total = <int>[];
    final builds = <int>[];
    final rasters = <int>[];
    var collecting = false;
    var turnIdx = -1;
    var frameIdx = -1;
    void collect(List<FrameTiming> timings) {
      if (!collecting) return;
      for (final t in timings) {
        builds.add(t.buildDuration.inMicroseconds);
        rasters.add(t.rasterDuration.inMicroseconds);
        total.add(
          t.buildDuration.inMicroseconds + t.rasterDuration.inMicroseconds,
        );
        if (t.buildDuration.inMicroseconds > 12000) {
          debugPrint(
            'TURN-SPIKE turn=$turnIdx f=$frameIdx '
            'build=${t.buildDuration.inMicroseconds} '
            'raster=${t.rasterDuration.inMicroseconds}',
          );
        }
      }
    }

    SchedulerBinding.instance.addTimingsCallback(collect);

    // 预热：翻过前几页，让哨兵章分页/相邻页构建都落到收集窗口之外
    Future<void> tapTurn() async {
      await tester.tapAt(tester.getCenter(find.byType(NativeReaderView)) +
          const Offset(150, 0));
    }

    for (var turn = 0; turn < 3; turn++) {
      await tapTurn();
      for (var f = 0; f < 26; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
    }

    // 只收集翻页动画期间的帧（fling 后 ~14 帧）；每轮结束后的空闲期
    // 让相邻页预构建，不进统计。
    collecting = true;
    for (var turn = 0; turn < 12; turn++) {
      turnIdx = turn;
      await tapTurn();
      for (var f = 0; f < 12; f++) {
        frameIdx = f;
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
      collecting = false;
      for (var f = 0; f < 16; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
      collecting = true;
    }
    collecting = false;
    SchedulerBinding.instance.removeTimingsCallback(collect);

    final pTotal = _percentiles(total);
    final pBuild = _percentiles(builds);
    final pRaster = _percentiles(rasters);
    debugPrint('TURN-PERF frames=${total.length}');
    debugPrint('TURN-PERF total  P50=${pTotal[0]} P95=${pTotal[1]} max=${pTotal[2]}');
    debugPrint('TURN-PERF build  P50=${pBuild[0]} P95=${pBuild[1]} max=${pBuild[2]}');
    debugPrint('TURN-PERF raster P50=${pRaster[0]} P95=${pRaster[1]} max=${pRaster[2]}');
    debugPrint(
      'TURN-PERF recomputes=${NativePaginator.debugComputeCount} '
      'previews=${NativeReaderViewState.debugPreviewCount}',
    );
  });
}
