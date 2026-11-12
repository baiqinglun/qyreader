/// 渲染页（reader.html）分栏几何不变量的回归守卫。
///
/// 这几条约束是踩过坑才定下来的，改动 reader.html 时必须一起守住：
///
/// 1. `renderTo` 必须显式 `gap: 0`。epub.js 默认按 floor(宽度/12)（取偶数）
///    算列距（正文区 361px → 30px），会给正文加 gap/2 内边距，页面右侧
///    留出一条空白带，且列边界与滚动步长 delta 不再重合。
/// 2. 章内页数的分母必须是真实列步长 `columnWidth`。用 columnWidth+gap
///    会把最后一列算丢（实测 8 页的章算成 7 页），于是「可视页是不是本章
///    末页」的判断出错，翻到章末前��页会误判隐藏层不是下一页而重新对齐，
///    表现为翻页卡住 / 骨架占位。
/// 3. 每页字数必须缓存且不能读 innerText——innerText 触发整章同步布局，
///    一次翻页要算四遍，长章节直接把 WebView 主线程占满（翻页卡顿）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late final String html;

  setUpAll(() {
    html = File('assets/reader/reader.html').readAsStringSync();
  });

  group('渲染页分栏几何', () {
    test('renderTo 显式 gap: 0（epub.js 默认列距会错位）', () {
      expect(html, contains('gap: 0'));
      // 不允许只依赖默认值：epub.js 在未传 gap 时按宽度自动算列距。
      final renderTo = html.substring(html.indexOf('renderTo('));
      final options = renderTo.substring(0, renderTo.indexOf(');'));
      expect(options, contains('gap: 0'));
    });

    test('章内页数分母用 columnWidth，不用 columnWidth+gap', () {
      expect(html, contains('var denom = layout.columnWidth || 0;'));
      expect(html, isNot(contains('(layout.columnWidth || 0) + (layout.gap || 0)')));
    });

    test('每页字数走缓存且不读 innerText（翻页卡顿主因）', () {
      expect(html, contains('charsPerPageCache'));
      expect(html, contains('charsPerPageOf'));
      // innerText 会触发整章同步布局；正文长度改用 textContent。
      // 只看代码行——注释里可以出现这个词。
      final code = html
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('innerText')));
      expect(code, contains('textContent'));
    });

    test('renderTo 用 100% 宽高（容器必须跟随 WebView，不能钉死 px）', () {
      // epub.js 会把分栏容器钉成固定 px 宽；WebView 尺寸变化后
      // stage.size() 读不到真实宽度，正文按旧宽排版、被裁掉右边一截
      // （实测右侧被裁 32px = 左右边距之和）。
      final renderTo = html.substring(html.indexOf('renderTo('));
      final options = renderTo.substring(0, renderTo.indexOf(');'));
      expect(options, contains("width: '100%'"));
      expect(options, contains("height: '100%'"));
      expect(options, isNot(contains('window.innerWidth + ')));
      // 重排走 updateLayout（没有「尺寸相同就忽略」的判断）
      expect(html, contains('syncLayoutToViewport'));
      expect(html, contains('mgr.updateLayout()'));
    });

    test('隐藏 iframe 与外层文档的滚动条（Android WebView 会画出来）', () {
      // epub.js 的分栏把整章横向铺在 iframe 里（iframe 宽 = 全部列宽，
      // 文档视口 = 一列宽），iframe 文档必然横向溢出。Android WebView 会
      // 画出横向滚动条 → 吃掉高度 → html 纵向溢出 → 再出纵向滚动条 →
      // 再吃掉宽度 → 正文可视宽度比容器窄一截（右边距比左边宽，不居中）。
      // 解法是只藏滚动条、不动 overflow（横向滚动能力必须保留）。
      final theme = html.substring(html.indexOf('function themeCss'));
      expect(theme.substring(0, 1200), contains('::-webkit-scrollbar'));
      expect(html, contains("display: 'none'"));
      // 外层文档同样要藏
      final style = html.substring(html.indexOf('<style>'));
      expect(style.substring(0, 1200), contains('webkit-scrollbar'));
      // 直接注入 iframe 文档（不依赖主题机制生效）
      expect(html, contains('__qyNoScrollbar'));
    });

    test('翻页只用容器 scrollLeft，不调 rendition.next/prev', () {
      // rendition.next()/prev() 在「末页」或容器暂时不可滚时会走 section
      // 切换 → manager.clear() 清空所有视图 → 整页空白，且新文档的点击
      // 监听还没挂上 → 整页点不动（真机实测卡死，只能退出重进）。
      // 章内翻页一律走 stepScrollPages（直接改 scrollLeft，最多滚不动）。
      expect(html, contains('function stepScrollPages'));
      final nextPage = html.substring(html.indexOf('function nextPage()'));
      final body = nextPage.substring(0, nextPage.indexOf('function prevPage()'));
      expect(body, isNot(contains('rendition.next()')));
      expect(body, contains('stepScrollPages'));
    });

    test('章末跳过空占位章节（否则停在空白页）', () {
      // 实测某 EPUB 的 spine 里混着空文件（text/xxxx.html，正文为空），
      // display() 到它只会得到一片空白。必须逐项往后找到有正文的章节。
      expect(html, contains('function gotoAdjacentChapter'));
      expect(html, contains('gotoAdjacentChapter(st.href, 1'));
      expect(html, contains('hasText'));
      expect(html, contains('t.length > 10'));
    });

    test('页码/总页数用容器几何 + round（亚像素取整会差一页）', () {
      // delta 一般是小数（实测 379.04），scrollLeft 只能取整像素；
      // floor 会把 2274（= 6×379.04 的取整）算成第 6 页而不是第 7 页，
      // 末页判错 → 继续 next() → 清空视图 → 白屏。
      expect(html, contains('function scrollGeom'));
      expect(html, contains('Math.round(c.scrollLeft / d) + 1'));
      expect(html, contains('Math.round(maxSl / d) + 1'));
      expect(html, isNot(contains('Math.floor(c.scrollLeft / d) + 1')));
    });

    test('新章节视图 0×0 时要显式撑开（否则整章空白）', () {
      // display() 到新章节后 views 可能是 [9:0]（iframe 0 宽），
      // epub.js 的 expand() 在 lockedWidth 未初始化时不会 reframe。
      expect(html, contains('!v.iframe.offsetWidth'));
      expect(html, contains("mgrLay.width + 'px'"));
    });

    test('样式表必须整体替换（registerCss），不能追加（registerRules）', () {
      // epub.js 的 themes.register(rules) 内部是 sheet.insertRule 追加，
      // 同一个 epubjs-inserted-css-reader 节点上会累积旧规则，
      // 旧的 !important 永远压着新规则 → 切主题/精排完全没反应（实测）。
      // 必须用 registerCss（addStylesheetCss → innerHTML = css）整体替换。
      expect(html, contains('themes.registerCss('));
      expect(html, contains('rulesToCss'));
      // registerRules 只允许作为「没有 registerCss 时」的兜底
      final apply = html.substring(html.indexOf('function applyThemeToRendition'));
      final body = apply.substring(0, apply.indexOf('function applyStyleToRendition'));
      expect(body.indexOf('registerCss'), lessThan(body.indexOf("themes.register('reader'")));
    });

    test('精排开启时保留书籍原样式（不覆盖字号/行距/字色）', () {
      // 精排 = 把排版交给书自带的 CSS。若仍然 !important 覆盖字号/行距/
      // 字色，开关就形同虚设（书的排版永远被压平）。
      final theme = html.substring(html.indexOf('function themeCss'));
      final body = theme.substring(0, theme.indexOf('return {', theme.indexOf('return {') + 1));
      expect(body, contains('style.precise === true'));
      // 精排分支里只允许底色与选区色出现，不允许 fontSize/lineHeight
      expect(body, isNot(contains('fontSize')));
      expect(body, isNot(contains('lineHeight')));
    });

    test('恢复进度按真实总页数夹紧（否则落到下一章）', () {
      // 保存的 page 可能来自旧字号（当时章尾页更多）；不夹紧就会多走几页，
      // 打开后直接跑到下一章（实测存 4/4、实际 3 页 → 落到下一章第 1 页）。
      expect(html, contains('want > g.total'));
      expect(html, contains('if (g && want < 1) want = 1;'));
    });

    test('恢复链也用 stepScrollPages，不用 rendition.next', () {
      // rendition.next() 到末页会切 section 并清空视图（白屏）。
      final disp = html.substring(html.indexOf('function displayLocator'));
      final body = disp.substring(0, disp.indexOf('function gotoLocator'));
      expect(body, isNot(contains('rendition.next()')));
      expect(body, contains('stepScrollPages'));
    });

    test('统一排版模式两端对齐（左对齐会让右端参差像"右边留白多"）', () {
      // 实测真机：WebView 与 body 都是 327px、无内边距，但 text-align:start
      // 时每行右端平均比左端多空 12px，看着像"页面不居中"。中文排版要两端
      // 对齐（精排模式不覆盖，交给书自己）。
      expect(html, contains("'text-align': 'justify !important'"));
      expect(html, contains('inter-ideograph'));
    });

    test('relocated / syncDone 走快通道，不刷 console', () {
      String callBefore(String marker) {
        final at = html.indexOf(marker);
        expect(at, greaterThan(0), reason: '未找到 $marker');
        final before = html.substring(0, at);
        final open = before.lastIndexOf('post(');
        final fast = before.lastIndexOf('postFast(');
        return fast > open ? 'postFast' : 'post';
      }

      expect(callBefore("type: 'relocated'"), 'postFast');
      expect(callBefore("type: 'syncDone'"), 'postFast');
    });
  });
}
