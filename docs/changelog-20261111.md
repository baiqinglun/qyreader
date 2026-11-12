# QYReader 变更记录归档（2026-11-11）

> 从 `AGENTS.md` §8 迁出，保持主文件精简。版本 2.10.1 – 2.21.0。
> 更细的实现说明见 `AGENTS.md` §7 与各版本的回归用例。

| 日期 | 版本 | 改动 | 产物 |
|---|---|---|---|
| 2026-11-11 | 2.10.1+52 | 新建 AGENTS.md，沉淀构建/版本/命名/分层规范 | — |
| 2026-11-11 | 2.10.2+53 | 跑通门禁并修 `integration_test` 未使用变量告警；补充环境与沙箱说明 | `qyreader/QYReader-v2.10.2-20261111-agents-md.apk` |
| 2026-11-11 | 2.10.3+54 | 修翻页方向：自建 `Viewport` 漏传 `axisDirection` 导致竖排；补横向翻页回归 | `qyreader/QYReader-v2.10.3-20261111-horizontal-turn.apk` |
| 2026-11-11 | 2.10.4+55 | 重做仿真翻页：纸角跟手折起 + 折边投影/折痕（`curl_geometry` / `curl_painter`） | `qyreader/QYReader-v2.10.4-20261111-corner-curl.apk` |
| 2026-11-11 | 2.10.5+56 | 打开/关闭书籍转场放慢：660/560ms → 1000/850ms | `qyreader/QYReader-v2.10.5-20261111-slower-book-open.apk` |
| 2026-11-11 | 2.10.6+57 | 排版面板重做：选项型设置全部改下拉框（44 行高 + 64 标签列） | `qyreader/QYReader-v2.10.6-20261111-typeset-dropdown.apk` |
| 2026-11-11 | 2.11.0+58 | 书架新增「分类」展示形式：一个分类一张卡，2×2 书位 | `qyreader/QYReader-v2.11.0-20261111-shelf-categories.apk` |
| 2026-11-11 | 2.11.1+59 | 分类从展示形式里拿掉，改成书架常驻分类条 `CategoryStrip` | `qyreader/QYReader-v2.11.1-20261111-category-strip.apk` |
| 2026-11-11 | 2.12.0+61 | 书架首屏重排：分类卡与书卡混排同一套格子（手机一行 3 格），点分类卡进分类 | `qyreader/QYReader-v2.12.0-20261111-shelf-flow.apk` |
| 2026-11-11 | 2.12.1+62 | 去掉点击/长按震动反馈（`PressableScale` 只保留缩放） | `qyreader/QYReader-v2.12.1-20261111-no-haptic.apk` |
| 2026-11-11 | 2.12.2+63 | 分类卡去掉卡面名称/本数；翻页效果「无」改成瞬间跳页 | `qyreader/QYReader-v2.12.2-20261111-shelf-clean-instant-turn.apk` |
| 2026-11-11 | 2.12.3+64 | EPUB 单文件多章按目录 `#锚点` 切章（《十扇窗》4 章恢复 16 章） | `qyreader/QYReader-v2.12.3-20261111-epub-anchor-chapters.apk` |
| 2026-11-11 | 2.12.4+65 | 选字只留自家菜单：压掉系统「复制 / 全选」浮层 | `qyreader/QYReader-v2.12.4-20261111-single-selection-menu.apk` |
| 2026-11-11 | 2.13.0+67 | 翻页音效 + 悬浮胶囊底栏与参考稿配色 + 书架搜索框 + 单字划线容差 + 慢快慢贝塞尔 | `qyreader/QYReader-v2.13.0-20261111-sound-nav-search.apk` |
| 2026-11-11 | 2.13.1+68 | 统计页换肤：映射 App Material 主题（白卡片 / 蓝图表） | `qyreader/QYReader-v2.13.1-20261111-stats-theme.apk` |
| 2026-11-11 | 2.13.2+69 | 修「划线后没有色块」：`nativeChapterForLocator` 优先按章索引定位 | `qyreader/QYReader-v2.13.2-20261111-highlight-fix.apk` |
| 2026-11-11 | 2.14.0+70 | 设置页升级为配置入口：主题色 / 阅读背景 / 字体管理 / 同步设置 / 缓存管理 | `qyreader/QYReader-v2.14.0-20261111-settings-hub.apk` |
| 2026-11-11 | 2.14.1+71 | 书架顶栏只留标题 + 搜索；同步归设置页、统计走底栏 | `qyreader/QYReader-v2.14.1-20261111-clean-shelf-header.apk` |
| 2026-11-11 | 2.14.2+72 | 底栏选中胶囊改成滑动指示器（`AnimatedPositioned` + 慢快慢曲线） | `qyreader/QYReader-v2.14.2-20261111-nav-pill-slide.apk` |
| 2026-11-11 | 2.14.3+73 | 退出阅读改成「缓慢合上书」：850 → 1100ms，书封全程浮现并缩回原位 | `qyreader/QYReader-v2.14.3-20261111-slow-close.apk` |
| 2026-11-11 | 2.14.4+74 | 导入收进书架「⋯」菜单，删掉悬浮导入按钮 | `qyreader/QYReader-v2.14.4-20261111-import-menu.apk` |
| 2026-11-11 | 2.14.5+75 | 合书动画提速一档：1100 → 900ms | `qyreader/QYReader-v2.14.5-20261111-close-900ms.apk` |
| 2026-11-11 | 2.14.6+76 | 退出时书封先「往前」抬 7% 再缩回书架原位 | `qyreader/QYReader-v2.14.6-20261111-close-lift.apk` |
| 2026-11-11 | 2.14.7+77 | 换用户提供的两个翻页音效（无 / 音效一 / 音效二），旧值自动映射 | `qyreader/QYReader-v2.14.7-20261111-turn-sounds-mp3.apk` |
| 2026-11-11 | 2.14.8+78 | 点桌面图标再启动时回到书架（`MainActivity` → `qyreader/launch`） | `qyreader/QYReader-v2.14.8-20261111-launch-to-shelf.apk` |
| 2026-11-11 | 2.15.0+79 | 同步存储支持阿里云 OSS（`pathStyle` 配置） | `qyreader/QYReader-v2.15.0-20261111-aliyun-oss.apk` |
| 2026-11-11 | 2.15.1+80 | 只保留阿里云 OSS；封面压到 512 JPEG 并独立存放；整库快照上传 | `qyreader/QYReader-v2.16.2-20261111-category-size.apk` |
| 2026-11-11 | 2.16.0+82 | 同步改成按书分片（`shards/<bookId>.json`），只传本次有写入的书 | `qyreader/QYReader-v2.16.2-20261111-category-size.apk` |
| 2026-11-11 | 2.16.2+84 | 分类卡与书卡同尺寸；移除本地桶后端；同步面板显示待同步书目与进度 | `qyreader/QYReader-v2.16.2-20261111-category-size.apk` |
| 2026-11-11 | 2.17.0+85 | 书架设置：圆角 / 列数 / 架板样式 / 列表四项开关，网格按行铺 + 木纹架板 | `qyreader/QYReader-v2.17.0-20261111-shelf-settings.apk` |
| 2026-11-11 | 2.17.1+86 | 书架设置页签变成真正的展示形式开关（网格 / 列表即时切换） | `qyreader/QYReader-v2.17.1-20261111-shelf-tab-mode.apk` |
| 2026-11-11 | 2.18.0+87 | 标签管理页（`/settings/tags`）+ 标签库选择器 + 批量改名/删除 | `qyreader/QYReader-v2.18.0-20261111-tag-manager.apk` |
| 2026-11-11 | 2.19.0+88 | 同步补齐书源与封面（本地有、云端缺则补传；缺失封面自动补回） | `qyreader/QYReader-v2.19.0-20261111-cloud-file-backup.apk` |
| 2026-11-11 | 2.20.0+89 | 清除书籍缓存页（`/settings/cache`）：先确保云端备份，只删本地书源 | `qyreader/QYReader-v2.20.0-20261111-cache-page.apk` |
| 2026-11-11 | 2.20.1+90 | 逻辑审查修复：`setPersonalization` null 语义、同步墓碑、弹窗 controller 生命周期等 | `qyreader/QYReader-v2.20.1-20261111-logic-fixes.apk` |
| 2026-11-11 | 2.20.2+91 | 修首次打开卡「正在打开…」：本地文件存在直接启动，跳过同步库初始化 | `qyreader/QYReader-v2.20.2-20261111-reader-boot-fix.apk` |
| 2026-11-11 | 2.20.3+92 | 修音效滞后：裁掉开头静音 + 预载式播放（`stop` + `resume`） | `qyreader/QYReader-v2.20.3-20261111-sound-latency.apk` |
| 2026-11-11 | 2.20.4+93 | 再修音效滞后：按响度峰值裁剪；翻页跨页即响，不等滚动结束 | `qyreader/QYReader-v2.20.4-20261111-sound-onset.apk` |
| 2026-11-11 | 2.20.5+94 | 音效一裁多了回退 0.15s（0.441s / 峰值约 190ms） | `qyreader/QYReader-v2.20.5-20261111-sound1-rollback.apk` |
| 2026-11-11 | 2.21.0+95 | 边距直调：正文/页眉/页脚边距改为页面上拖动数字（`MarginEditorOverlay`） | `qyreader/QYReader-v2.21.0-20261111-margin-editor.apk` |
