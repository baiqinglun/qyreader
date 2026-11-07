/// 初始 Locator 决策与排版设置单测。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/app/theme/reading_theme.dart';
import 'package:qy_reader/core/locator.dart';
import 'package:qy_reader/domain/entities/reading_progress.dart';
import 'package:qy_reader/features/reader/reader_controller.dart';
import 'package:qy_reader/features/reader/reader_settings.dart';

void main() {
  group('pickInitialLocator 恢复链', () {
    test('无进度 → null（从头读）', () {
      expect(pickInitialLocator(null), isNull);
    });

    test('当前 locator 可用 → 优先返回', () {
      final progress = ReadingProgressSnapshot(
        bookId: 'b1',
        locator: '{"v":1,"cfi":"epubcfi(/6/10)","percent":0.3}',
        percent: 0.3,
        furthestLocator: '{"v":1,"cfi":"epubcfi(/6/20)","percent":0.8}',
        furthestPercent: 0.8,
        updatedAt: 1,
      );
      final locator = pickInitialLocator(progress);
      expect(locator!.cfi, 'epubcfi(/6/10)');
    });

    test('当前 locator 损坏 → 回退最远 locator', () {
      final progress = ReadingProgressSnapshot(
        bookId: 'b1',
        locator: 'broken-json{',
        percent: 0.3,
        furthestLocator: '{"v":1,"cfi":"epubcfi(/6/20)","percent":0.8}',
        furthestPercent: 0.8,
        updatedAt: 1,
      );
      expect(pickInitialLocator(progress)!.cfi, 'epubcfi(/6/20)');
    });

    test('locator 全无定位字段 → 视为不可用', () {
      final progress = ReadingProgressSnapshot(
        bookId: 'b1',
        locator: '{"v":1}',
        percent: 0,
        updatedAt: 1,
      );
      expect(pickInitialLocator(progress), isNull);
    });
  });

  group('ReadingSettings 序列化', () {
    test('toMap / fromMap 往返一致', () {
      const settings = ReadingSettings(
        theme: ReadingTheme.night,
        fontSize: 22,
        lineHeight: 2.0,
        margin: 32,
        flow: ReadingFlow.scrolled,
        pageTurnMode: PageTurnMode.cover,
      );
      final restored = readingSettingsFromMap(settings.toMap());
      expect(restored.theme, ReadingTheme.night);
      expect(restored.fontSize, 22);
      expect(restored.lineHeight, 2.0);
      expect(restored.margin, 32);
      expect(restored.flow, ReadingFlow.scrolled);
      expect(restored.pageTurnMode, PageTurnMode.cover);
    });

    test('非法值逐字段兜底默认并夹紧范围', () {
      final restored = readingSettingsFromMap(<String, dynamic>{
        'theme': 'no-such-theme',
        'fontSize': 999,
        'lineHeight': -5,
        'margin': 12,
        'flow': '???',
        'pageTurnMode': 42,
      });
      expect(restored.theme, ReadingTheme.paper);
      expect(restored.fontSize, 28); // clamp 上限
      expect(restored.lineHeight, 1.2); // clamp 下限
      expect(restored.margin, 12);
      expect(restored.flow, ReadingFlow.paginated);
      expect(restored.pageTurnMode, PageTurnMode.slide);
    });

    test('样式载荷注入 WebView 用 JSON 可反解', () {
      const settings = ReadingSettings(theme: ReadingTheme.black);
      expect(readerStylePayload(settings), contains('"background":"#000000"'));
    });
  });

  group('Locator 降级链', () {
    test('损坏 JSON 返回 null；合法 JSON 正常解析', () {
      expect(locatorFromJson('{"v":1,"cfi":'), isNull);
      final loc = locatorFromJson('{"v":1,"percent":0.5}');
      expect(loc!.percent, 0.5);
    });
  });
}
