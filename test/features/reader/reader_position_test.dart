/// 「打开书籍时不渲染整本书位置」的回归守卫。
///
/// 这条约束是 2026-11-10 定的：epub.js 的 `book.locations.generate(1600)`
/// 会把**整本书**渲染一遍来算位置（手机上几十秒，还和首屏渲染抢 WebView
/// 主线程，表现为打开书籍卡顿、打开后长时间掉帧）。改为：
/// - 位置一律用页级 pos（章索引 + 章内页比例），零渲染成本；
/// - 全书页数估算改用导入时解析出的全书字数（Dart 下发）；
/// - 退出阅读时再向渲染页要一次当前真实页位并落库。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qy_reader/core/locator.dart';
import 'package:qy_reader/features/reader/reader_controller.dart';

void main() {
  late final String html;

  setUpAll(() {
    html = File('assets/reader/reader.html').readAsStringSync();
  });

  /// 去掉注释（HTML 注释块 + 行注释），只看真实代码。
  ///
  /// 注释里可以出现这些词（说明「为什么不做」），所以断言必须只看代码。
  String codeOnly(String source) {
    final noHtml = source.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    return noHtml
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
  }

  group('渲染页：打开时不生成整本书位置', () {
    test('不再调用 locations.generate（那要把全书渲染一遍）', () {
      expect(codeOnly(html), isNot(contains('book.locations.generate')));
    });

    test('percent 缺失时用页级 pos 兜底', () {
      expect(
        codeOnly(html),
        contains('if (loc.percent == null && loc.pos != null) loc.percent = loc.pos;'),
      );
    });

    test('全书页数估算用 totalChars，不再依赖 locationsTotal', () {
      final code = codeOnly(html);
      expect(code, contains('var totalChars = 0;'));
      expect(code, contains('function setTotalChars(n)'));
      expect(code, contains('var bookChars = totalChars > 0'));
    });

    test('按页级位置跳转用 gotoPos（percent 就是 pos）', () {
      final code = codeOnly(html);
      expect(code, contains('function gotoPos(p)'));
      // 字符级百分比跳转与页级口径不一致，不能再用于进度滑杆。
      expect(code, contains('gotoPos'));
    });

    test('退出时能同步取到当前真实页位', () {
      final code = codeOnly(html);
      expect(code, contains('function currentLocatorJson()'));
      expect(code, contains('JSON.stringify(out)'));
    });
  });

  group('Dart 侧：百分比口径', () {
    test('percent 缺失时用 pos 兜底', () {
      expect(locatorPercent(const Locator(percent: 0.42)), 0.42);
      expect(locatorPercent(const Locator(pos: 0.31)), 0.31);
      // percent 在前：两者都有时以 percent 为准
      expect(locatorPercent(const Locator(percent: 0.1, pos: 0.9)), 0.1);
      expect(locatorPercent(const Locator()), isNull);
    });

    test('位置 JSON 往返保留 pos', () {
      final loc = const Locator(
        href: 'text/1.xhtml',
        chapterIndex: 3,
        pos: 0.25,
        page: 2,
        pages: 9,
      );
      final back = locatorFromJson(locatorToJson(loc));
      expect(back, isNotNull);
      expect(back!.pos, 0.25);
      expect(back.chapterIndex, 3);
      expect(back.page, 2);
    });
  });
}
