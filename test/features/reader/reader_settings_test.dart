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
        backgroundImage: '/tmp/bg.png',
        fontSize: 22,
        lineHeight: 2.0,
        marginLeft: 32,
        marginRight: 20,
        marginTop: 24,
        marginBottom: 8,
        flow: ReadingFlow.scrolled,
        pageTurnMode: PageTurnMode.cover,
        pageTurnSound: PageTurnSound.second,
        preciseTypesetting: true,
        fontFamily: 'qyfont_abc123',
      );
      final restored = readingSettingsFromMap(settings.toMap());
      expect(restored.theme, ReadingTheme.night);
      expect(restored.backgroundImage, '/tmp/bg.png');
      expect(restored.fontSize, 22);
      expect(restored.lineHeight, 2.0);
      expect(restored.marginLeft, 32);
      expect(restored.marginRight, 20);
      expect(restored.marginTop, 24);
      expect(restored.marginBottom, 8);
      expect(restored.flow, ReadingFlow.scrolled);
      expect(restored.pageTurnMode, PageTurnMode.cover);
      expect(restored.pageTurnSound, PageTurnSound.second);
      expect(restored.preciseTypesetting, isTrue);
      expect(restored.fontFamily, 'qyfont_abc123');
    });

    test('非法值逐字段兜底默认并夹紧范围', () {
      final restored = readingSettingsFromMap(<String, dynamic>{
        'theme': 'no-such-theme',
        'fontSize': 999,
        'lineHeight': -5,
        'marginTop': 999,
        'marginBottom': -1,
        'marginLeft': 12,
        'marginRight': 12,
        'flow': '???',
        'pageTurnMode': 42,
        'pageTurnSound': 'thunder',
      });
      expect(restored.theme, ReadingTheme.paper);
      expect(restored.fontSize, 28); // clamp 上限
      expect(restored.lineHeight, 1.2); // clamp 下限
      expect(restored.marginTop, 64); // clamp 上限
      expect(restored.marginBottom, 0); // clamp 下限
      expect(restored.marginLeft, 12);
      expect(restored.marginRight, 12);
      expect(restored.flow, ReadingFlow.paginated);
      expect(restored.pageTurnMode, PageTurnMode.slide);
      expect(restored.pageTurnSound, PageTurnSound.first);
    });

    test('旧版合成音效（paper / thin / thick）读成「音效一」', () {
      for (final old in ['paper', 'thin', 'thick']) {
        final restored = readingSettingsFromMap({'pageTurnSound': old});
        expect(restored.pageTurnSound, PageTurnSound.first);
      }
    });

    test('兼容 v1 单一 margin：迁移为左右边距', () {
      final restored = readingSettingsFromMap(<String, dynamic>{
        'margin': 24,
      });
      expect(restored.marginLeft, 24);
      expect(restored.marginRight, 24);
      expect(restored.marginTop, 12);
      expect(restored.marginBottom, 12);
    });

    test('样式载荷注入 WebView 用 JSON 可反解（边距走 Flutter padding）', () {
      const settings = ReadingSettings(
        theme: ReadingTheme.black,
        fontSize: 22,
        lineHeight: 1.8,
      );
      final payload = readerStylePayload(settings);
      expect(payload, contains('"background":"#000000"'));
      expect(payload, contains('"fontSize":22'));
      expect(payload, isNot(contains('margin')));
    });

    test('精排开关进样式载荷（渲染页据此决定是否保留书籍原样式）', () {
      const off = ReadingSettings();
      const on = ReadingSettings(preciseTypesetting: true);
      expect(readerStylePayload(off), contains('"precise":false'));
      expect(readerStylePayload(on), contains('"precise":true'));
    });

    test('精排默认关闭（默认统一排版：各家书观感一致）', () {
      expect(const ReadingSettings().preciseTypesetting, isFalse);
    });

    test('字体默认系统（空 family）；缺失/非字符串字段按系统字体兜底', () {
      expect(const ReadingSettings().fontFamily, '');
      expect(
        readingSettingsFromMap(<String, dynamic>{'fontFamily': 42}).fontFamily,
        '',
      );
      expect(
        readingSettingsFromMap(<String, dynamic>{'fontFamily': 'qyfont_x'})
            .fontFamily,
        'qyfont_x',
      );
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
