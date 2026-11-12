/// 阅读排版性能基准（模拟器 Profile 模式跑）。
///
/// 指标：
/// 1. 42k 字符章节的**首屏**耗时（pumpWidget 到首帧出现正文）；
/// 2. 模拟「拖动字号滑块 20 次」的帧耗时 P95；
/// 3. 拖动期间是否触发全章重排（应为 0）；
/// 4. 松手后全章分帧重排的耗时与帧 P95（不应长时间卡 UI）。
///
/// 运行：
/// flutter drive --profile -d emulator-5554 \
///   --driver=test_driver/integration_test.dart \
///   --target=integration_test/reader_perf_test.dart
library;

import 'dart:convert';

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

const int _targetChars = 42000;

/// 约 4.2 万字的章节（约 360 段，每 40 段一个小标题）。
NativeChapter _benchChapter() {
  const sentence = '在秋日午后的光线里，我数着归途上的每一片叶子，它们从枝头落下，'
      '像一封封没有寄出的信，落在无人经过的小径上，被风轻轻翻动。';
  final blocks = <ParsedBlock>[const ParsedBlock(text: '第一章 性能基准', level: 1)];
  var chars = 0;
  var i = 0;
  while (chars < _targetChars) {
    if (i > 0 && i % 40 == 0) {
      blocks.add(ParsedBlock(text: '第 ${i ~/ 40 + 1} 节', level: 2));
    }
    // 每段 1~3 句，约 60~180 字
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

class PerfHost extends StatefulWidget {
  const PerfHost({
    super.key,
    required this.chapters,
    required this.initialSettings,
  });

  final List<NativeChapter> chapters;
  final ReadingSettings initialSettings;

  @override
  State<PerfHost> createState() => PerfHostState();
}

class PerfHostState extends State<PerfHost> {
  late ReadingSettings _settings = widget.initialSettings;

  /// 与 app 相同的预览通道：拖动中不重建宿主、不落库。
  final ValueNotifier<ReadingSettings?> _preview = ValueNotifier(null);

  /// 模拟滑块 onChanged：只更新预览，不落库。
  void preview(ReadingSettings next) => _preview.value = next;

  /// 模拟滑块 onChangeEnd：提交并触发分帧全章重排。
  void commit(ReadingSettings next) {
    setState(() => _settings = next);
    _preview.value = null;
  }

  ReadingSettings? get currentPreview => _preview.value;

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NativeReaderView(
        chapters: widget.chapters,
        settings: _settings,
        previewListenable: _preview,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        theme: ReadingTheme.paper,
        initialChapterIndex: 0,
        initialOffset: 0,
        onPosition: (_) {},
        onCenterTap: () {},
      ),
    );
  }
}

List<int> _percentiles(List<int> micros) {
  if (micros.isEmpty) return [0, 0, 0];
  final sorted = [...micros]..sort();
  int at(double p) => sorted[((sorted.length - 1) * p).round()];
  return [at(0.50), at(0.95), sorted.last];
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('阅读排版性能基准', (tester) async {
    final chapter = _benchChapter();
    final hostKey = GlobalKey<PerfHostState>();

    // ---- 1) 首屏 ----
    NativeReaderViewState.debugPreviewCount = 0;
    final firstFrame = Stopwatch()..start();
    await tester.pumpWidget(MaterialApp(
      home: PerfHost(
        key: hostKey,
        chapters: [chapter],
        initialSettings: const ReadingSettings(fontSize: 18, lineHeight: 1.7),
      ),
    ));
    // 预览页在 post-frame 里算完，下一帧出现
    await tester.pump();
    final firstPreview = Stopwatch()..start();
    while (NativeReaderViewState.debugPreviewCount == 0 &&
        firstPreview.elapsedMilliseconds < 3000) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    await tester.pump(const Duration(milliseconds: 16));
    firstPreview.stop();
    firstFrame.stop();
    final firstScreenMs = firstFrame.elapsedMilliseconds;
    final firstPreviewMs = firstPreview.elapsedMilliseconds;
    final firstPreviewComputes = NativeReaderViewState.debugPreviewCount;
    final firstCompute = NativePaginator.debugComputeCount;

    // 等首次全章分帧重排完成
    final initialReflow = Stopwatch()..start();
    while (NativePaginator.debugComputeCount == firstCompute &&
        initialReflow.elapsedMilliseconds < 5000) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    initialReflow.stop();

    // ---- 2) 拖字号 20 次（onChanged 只排当前页）----
    final dragFrames = <int>[];
    final dragBuild = <int>[];
    final dragRaster = <int>[];
    final reflowFrames = <int>[];
    final idleFrames = <int>[];
    var collectingReflow = false;
    var collectingIdle = false;
    void collect(List<FrameTiming> timings) {
      for (final t in timings) {
        final us =
            t.buildDuration.inMicroseconds + t.rasterDuration.inMicroseconds;
        if (collectingIdle) {
          idleFrames.add(us);
        } else if (collectingReflow) {
          reflowFrames.add(us);
        } else {
          dragFrames.add(us);
          dragBuild.add(t.buildDuration.inMicroseconds);
          dragRaster.add(t.rasterDuration.inMicroseconds);
        }
      }
    }

    SchedulerBinding.instance.addTimingsCallback(collect);
    NativePaginator.debugComputeCount = 0;
    NativeReaderViewState.debugPreviewCount = 0;
    NativeReaderViewState.debugPreviewTotalUs = 0;
    NativeReaderViewState.debugPreviewLayoutUs = 0;
    final drag = Stopwatch()..start();

    const steps = 20;
    for (var i = 0; i < steps; i++) {
      final phase = i % 20;
      final size = phase < 10 ? 18.0 + phase : 28.0 - (phase - 10);
      hostKey.currentState!.preview(
        const ReadingSettings(lineHeight: 1.7).copyWith(fontSize: size),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 空闲帧基线（不做任何修改）
    collectingIdle = true;
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    collectingIdle = false;

    // 冲刷拖动期帧回调
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    drag.stop();
    final dragRecomputes = NativePaginator.debugComputeCount;

    // ---- 3) 松手：提交最后一次字号，全章分帧重排 ----
    collectingReflow = true;
    final lastSize = hostKey.currentState!.currentPreview?.fontSize ?? 18;
    final reflow = Stopwatch()..start();
    NativePaginator.debugComputeCount = 0;
    hostKey.currentState!.commit(
      const ReadingSettings(lineHeight: 1.7).copyWith(fontSize: lastSize),
    );
    while (NativePaginator.debugComputeCount == 0 &&
        reflow.elapsedMilliseconds < 10000) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    reflow.stop();
    // 冲刷重排期帧回调
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    SchedulerBinding.instance.removeTimingsCallback(collect);

    final dragStats = _percentiles(dragFrames);
    final dragBuildStats = _percentiles(dragBuild);
    final dragRasterStats = _percentiles(dragRaster);
    final reflowStats = _percentiles(reflowFrames);
    final idleStats = _percentiles(idleFrames);
    final result = <String, dynamic>{
      'chapterChars': chapter.text.length,
      'chapterParagraphs': chapter.paragraphs.length,
      'firstScreenMs': firstScreenMs,
      'firstPreviewMs': firstPreviewMs,
      'firstPreviewComputes': firstPreviewComputes,
      'firstScreenFullPagination': firstCompute,
      'initialFullReflowMs': initialReflow.elapsedMilliseconds,
      'dragTotalMs': drag.elapsedMilliseconds,
      'dragSteps': steps,
      'dragFrames': dragFrames.length,
      'dragFrameP50Ms': dragStats[0] / 1000.0,
      'dragFrameP95Ms': dragStats[1] / 1000.0,
      'dragFrameMaxMs': dragStats[2] / 1000.0,
      'dragBuildP95Ms': dragBuildStats[1] / 1000.0,
      'dragRasterP95Ms': dragRasterStats[1] / 1000.0,
      'idleFrames': idleFrames.length,
      'idleFrameP50Ms': idleStats[0] / 1000.0,
      'idleFrameP95Ms': idleStats[1] / 1000.0,
      'fullChapterRepaginationsDuringDrag': dragRecomputes,
      'previewPageComputes': NativeReaderViewState.debugPreviewCount,
      'previewAvgMs': NativeReaderViewState.debugPreviewCount == 0
          ? 0
          : NativeReaderViewState.debugPreviewTotalUs /
              NativeReaderViewState.debugPreviewCount /
              1000.0,
      'previewLayoutAvgMs': NativeReaderViewState.debugPreviewCount == 0
          ? 0
          : NativeReaderViewState.debugPreviewLayoutUs /
              NativeReaderViewState.debugPreviewCount /
              1000.0,
      'reflowMs': reflow.elapsedMilliseconds,
      'reflowFrames': reflowFrames.length,
      'reflowFrameP50Ms': reflowStats[0] / 1000.0,
      'reflowFrameP95Ms': reflowStats[1] / 1000.0,
      'reflowFrameMaxMs': reflowStats[2] / 1000.0,
      'devicePixelRatio': tester.view.devicePixelRatio,
      'screenSize':
          '${tester.view.physicalSize.width}x${tester.view.physicalSize.height}',
    };
    // ignore: avoid_print
    print('PERF_RESULT ${jsonEncode(result)}');
    binding.reportData = {'perf': result};
  });
}
