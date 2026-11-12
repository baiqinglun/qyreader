# AGENTS.md · QYReader

> 给 AI 编码代理（以及人类协作者）的项目作业说明书。
> **每轮对话结束前必须更新本文件**：刷新 §2「当前状态」，并在 §8「对话变更记录」追加一行。

最后更新：2026-11-12

## 1. 项目速览

| 项 | 值 |
|---|---|
| 应用 | QYReader —— 本地优先的跨平台阅读器，Android 为验收平台 |
| 技术栈 | Flutter / Dart 3.8+、Riverpod 2、drift(SQLite)、go_router、freezed |
| 包名 / 显示名 | `com.qyreader.qy_reader` / `QYReader` |
| 当前版本 | `2.40.0+130`（versionName 2.40.0 / versionCode 130），定义在 `pubspec.yaml` |
| 数据库 | SQLite（drift），schema **v5**，唯一真相源，离线可用 |
| 工作区 | `D:\Github\QYReader` |
| 仓库 | 未初始化 git；`qyreader/`、`tools/`、`.zcode/` 已被 `.gitignore` 排除 |

功能面：书架（导入 / 分类 / 标签 / 最近在读）、EPUB 阅读器（Flutter 原生排版）、
4 色划线笔记、全书检索（FTS5 trigram）、TTS 朗读、S3/本地桶同步、阅读统计。
详细能力清单与真机截图见 `README.md`。

## 2. 当前状态

- 应用版本：`2.40.0+130`
- 数据库 schema：v5（books 含 rating / review / tags / pinned_at / category / read_status）
- 门禁：`flutter analyze` 0 issues、`flutter test` 413 项全绿（2026-11-12 验证）
- 最近一次构建：`qyreader/QYReader-v2.40.0-20261112-multiselect-delete-confirm.apk`（31.3 MB，正式签名）
- Windows 桌面版：`qyreader/QYReader-v2.40.0-20261112-windows-x64.zip`（15.7 MB，解压后运行 `qy_reader.exe`）
- 文档：`README.md` 已按 v2.40.0 重写（功能总览 / 下载 / 构建 / 签名 / 同步 / 架构 / 数据库 / 已知限制），
  6 张真机截图在 `docs/screenshots/1.jpg` – `6.jpg`
- 已知待办/限制：见 §7 与 `README.md`「已知限制」

## 3. 每轮对话的硬性动作

1. **改代码 → 跑门禁**：`flutter analyze` 必须 0 issues，`flutter test` 必须全绿。
2. **定版本号**：按 §4 规则递增，并同步改 `pubspec.yaml` 的 `version: x.y.z+build`。
3. **编译发布版 APK**：`flutter build apk --release`，复制到 `qyreader/`，按 §4 命名。
4. **更新本文件**：§2 当前状态 + §8 追加记录（日期 / 版本 / 改动 / 产物名）。

仅改动文档（含本文件）时：APK 内容不变，沿用当前版本号重新构建并覆盖同名产物，
在 §8 注明「仅文档更新，未递增版本」。

## 4. 版本号与产物命名

版本号三段：`主.次.修`，`versionCode`（`+` 后的构建号）每次构建 +1。

| 改动性质 | 递增位 | 示例 |
|---|---|---|
| 大逻辑 / 架构级重构、破坏性变更 | 第一位（x.0.0） | 2.10.1 → 3.0.0+53 |
| 新功能、新页面、新能力 | 第二位（x.y.0） | 2.10.1 → 2.11.0+53 |
| 小优化、Bug 修复、样式微调 | 第三位（x.y.z） | 2.10.1 → 2.10.2+53 |

APK 文件名：`qyreader/QYReader-v<版本>-<yyyyMMdd>-<主题>.apk`

- 主题用短横线小写英文，概括本次改动：`shelf-freeze-cache`、`book-cache-cloud`、`typeset-hf`。
- 同一天同一版本重出时：`-2`、`-hotfix` 等后缀，如 `QYReader-M1-20261108-2.apk`。
- `qyreader/` 是历史产物归档，**只增不改**，不要覆盖旧版本文件（同版本重出除外）。

## 5. 构建与验证（Windows / PowerShell）

环境：Flutter **3.32.0** / Dart **3.8.0**，SDK 位于 `D:\SoftData\flutter`（已加入 PATH）。
**构建必须在「完全权限」下执行**：`flutter.bat` 需要写 `%FLUTTER_ROOT%\bin\cache\flutter.bat.lock`，
pub 缓存与 Gradle 缓存也在工作区之外；在沙箱里跑会静默无限重试（无任何输出、不报错）而挂死。

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # 改了 drift / freezed / riverpod 注解后必跑
flutter analyze                                            # 0 issues
flutter test                                               # 全绿
flutter build apk --release

# 归档
$v = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([\d.]+)').Matches[0].Groups[1].Value
Copy-Item build\app\outputs\flutter-apk\app-release.apk "qyreader\QYReader-v$v-$(Get-Date -Format yyyyMMdd)-<主题>.apk"
```

- 构建产物：`build/app/outputs/flutter-apk/app-release.apk`。
- 签名：读 `android/key.properties`（alias `qyreader`，密钥 `android/qyreader-release.jks`）；
  文件缺失时自动回退 debug 签名，仍可侧载。两者均已 gitignore，**丢失后无法覆盖升级**，需自行备份。
- 验证签名：`apksigner verify --print-certs build\app\outputs\flutter-apk\app-release.apk`。
- **Windows 桌面版**（v2.31.0 起可出包给用户试同步）：
  ```powershell
  # flutter_tts 的 Windows 插件要求 nuget.exe 在 PATH 里（已放 tools\nuget\nuget.exe）
  $env:PATH = "$PWD\tools\nuget;" + $env:PATH
  flutter build windows --release
  # 整个 Release 目录（exe + dll + data/）一起打包，缺 data 会白屏
  Compress-Archive -Path "build\windows\x64\runner\Release\*" `
    -DestinationPath "qyreader\QYReader-v<版本>-<yyyyMMdd>-windows-x64.zip"
  ```
  运行数据：书库在 `我的文档\QYReader`（books/covers），数据库与 prefs 在
  `%APPDATA%\com.qyreader\qy_reader`（`qy_reader.sqlite3` 等）。桌面端阅读器走原生
  排版，不再依赖 `flutter_inappwebview`；`webview_flutter` 只服务旧链路，不要在任何
  Windows 路径上实例化它。
- 真机日志：`adb logcat | grep reader-diag`（阅读器全链路打点）。

## 6. 目录与分层

```
lib/
  app/        主题(theme)、路由(router)、providers、bootstrap、页面转场
  core/       HLC 时钟、Locator、drift 数据库与 DAO、通用组件
  data/       仓储实现、EPUB/纯文本解析、对象存储(local / S3)
  domain/     实体与仓储接口（页面层不依赖 data / core-db）
  features/
    home/     HomeShell（底部导航）
    shelf/    书架、导入、分类标签、最近在读、同步面板与存储设置
    tags/     标签库（prefs）、标签管理页、编辑书籍的标签选择器
    reader/   阅读器（NativeReaderView 原生排版为主、桥、标注、TTS）、检索页
    stats/    阅读统计（fl_chart）
    settings/ 设置页
assets/reader/  reader.html + epub.js / jszip（旧 WebView 渲染链，当前未启用）
test/            单元/组件测试（对应 lib 同路径）
integration_test/ 性能测试（翻页、阅读）
tools/           vm_dump / devtools_eval 诊断脚本（本地工具，勿入库）
qyreader/        APK 归档目录
```

约定：`features` 通过 Riverpod provider 拿 `domain` 接口；实现放 `data`；
不要从页面层直连 DAO 或数据库。

## 7. 规范与已知坑

- 注释、UI 文案一律中文；代码风格受 `analysis_options.yaml` 约束：
  `prefer_single_quotes`、`always_declare_return_types`、`unawaited_futures`。
- 生成代码（`*.g.dart`、`*.freezed.dart`）在库内；改注解后必须重跑 build_runner。
- drift 迁移纪律：按 `schemaVersion` 增量 `addColumn`，**不删表重建**；
  唯一例外是派生表 `book_fts`（可由书籍文件重建）。
- `fl_chart` 锁 **0.69.2**（1.x 需 vector_math 2.2，与 Flutter 3.32 的 2.1.4 冲突）。
- `minSdk 24`（flutter_tts 要求）、`compileSdk >= 36`（flutter_secure_storage 要求）。
- `packaging { jniLibs { useLegacyPackaging = true } }` 用于压缩 .so、控制包体。
- **Windows 桌面版（v2.31.0 起）**：阅读器走原生排版，`flutter_inappwebview` 已从依赖里移除；`webview_flutter` 只服务已旁路的旧链路，不要在 Windows 路径实例化。构建需要 `nuget.exe`（见 §5），运行数据见 §5。**v2.32.1 起删掉了 `_boot` 里「Windows 直接锁死阅读器」的旧 WebView 门槛**：桌面端现在能正常进正文，不要把这个 `Platform.isWindows` 早退加回来。
- 构建时会出现 NDK 版本提示：项目 `ndkVersion` 26.3.11579264，插件要求 27.0.12077973。
  仅警告、不影响产物；要消除需在 `android/app/build.gradle.kts` 显式 `ndkVersion = "27.0.12077973"`。
- **同步存储**：本地桶 / S3 兼容（阿里云 OSS / AWS S3 / R2 / MinIO），实现走 minio SDK
  （`data/sync/s3_object_store.dart`），配置在「设置 → 同步设置 → 存储」。
  **阿里云 OSS 必须关掉「路径风格」**：`SyncBackendConfig.pathStyle=false` 时请求走
  `桶名.端点`（OSS/R2 只认虚拟主机风格），区域填 `oss-cn-<地区>`（如 `oss-cn-hangzhou`）；
  MinIO 保持路径风格（默认 true）。设置页只保留 OSS 一种（无服务商选择、无风格开关），切到 OSS 自动填杭州端点/地域。
  凭据只存 `flutter_secure_storage`，无端到端加密。
  回归用例：`test/data/sync/sync_backend_config_test.dart`（含旧配置 pathStyle 兜底）。
- **同步补齐书籍与封面（v2.19.0）**：每次 `syncNow` 在推送/拉取分片后列举云端
  `spaces/<space>/books/` 与 `spaces/<space>/covers/`，把「本地有、云端没有」的
  书源文件与封面补传；本地文件已清缓存则跳过（下次阅读会从云端拉回）。
  书源按 sha256 内容寻址（`books/<sha>.epub`），封面按书 id（`covers/<bookId>.jpg`）。
  拉取侧：从云端新建书时下载封面；每次同步用 `_restoreLocalCovers` 把本地缺失的
  封面补回。`SyncResult` 增加 `backedUpFiles` / `backedUpBytes` / `backupError`，
  同步面板提示「已补齐 N 个本地文件（KB）」。
  回归用例：`sync_repository_impl_test.dart` 的「本地有书源与封面、云端缺失时同步会
  补齐上传」「本地封面文件丢失时，同步会从云端补回」。
- **同步拉取是增量的（v2.29.2）**：`ObjectStore.listDetailed` 返回 key + 服务端
  修改时间；`_pull()` 维护水位线 `sync.lastPullAt`（状态表），只下载比
  「水位线 − 10 分钟」新的 op，水位线只按**成功下载**的对象推进；下载失败的
  op 不推水位线，下次同步会重试。opId 幂等比对用 `_knownOpIds()` 一次读全量
  Set（不要再写逐条 `_hasOp` 查询）。别改回「列举全部 → 全量下载 → 逐条跳过」：
  500 多条历史 op 每次同步都会被重新拉一遍。回归：
  `sync_repository_impl_test.dart` 的「增量拉取：水位线之前的旧 op 不再重复下载」。
- **分片拉取也走增量（v2.33.1）**：`_pullShards` 原来每次下载 `shards/` 下所有书
  的分片再逐本比 `updated_at`，所以「只读了一本书」也会把其他书的进度/笔记刷一遍，
  同步面板还逐本报「正在同步《某书》」。现在用 `ObjectStore.listDetailed` 的
  mtime + 水位线 `sync.lastShardPullAt`（分片与水位线都来自服务端时间，所以**不做**
  10 分钟回看，只 `> watermark`），只下载上次同步之后被改写的分片；水位线只按成功
  下载的对象推进；进度只在「真的要写入本地」时才报。回归：
  `sync_repository_impl_test.dart` 的「分片增量：上次同步之后没改过的书不再下载分片」
  （用 `LocalObjectStore.readKeys` 断言只读了变化的那本）。
- **字体也参与同步（v2.34.0）**：自定义阅读字体原来只在本机（应用支持目录
  `fonts/` + prefs `reader.fonts`），换设备要重新导入。现在 `syncNow` 最后一步
  调 `data/sync/font_sync.dart` 的 `FontSync`：字体文件按 sha256 传
  `spaces/<空间>/fonts/font-<sha>.<ext>`，清单写
  `spaces/<空间>/fonts/manifest.json`（`{id,name,sha256,ext}`）；拉取侧按 sha256
  去重，云端有、本机没有的字体下载到 `fonts/` 并合并进 prefs `reader.fonts`。
  语义是**并集**：本机删字体不会删其他设备（字体是小体积个人资产）。同步面板
  完成后会 `ReaderFontsController.reload()`，不用重启就能在字体列表里看到；
  `SyncResult.fontsSynced` 给面板显示「已同步 N 个字体」。回归：
  `test/data/sync/font_sync_test.dart`（上传→另一台设备拉取、sha256 去重）。
- **书籍按需下载（v2.30.0）**：新设备同步**不再下载书源文件**——`_mergeBook` 本地
  没有这本书时只落书籍行（`file_path` 用 `_plannedBookPath` 的本机计划路径）+ 封面，
  不读桶里的 epub、也不解析章节；`chapters` 随书分片同步（`BookShard.applyChapters`，
  书籍元数据已最新、本地缺章节时只补目录），所以新设备一同步就有目录与章数。
  `_normalizeCloudBookPaths()` 在每次 `syncNow` 的拉取之后跑：把别的设备带来的
  `file_path` 改写成「本机文件不在时的计划路径」，首次打开才能落到对的地方。
  首次打开**先问用户**（v2.33.0，`widgets/cloud_download_dialog.dart`）：
  `ReaderPage._restoreThenBoot` 用 `isBookFileLocal` 判断，本地没有就弹
  「《书名》还没有下载到本地（约 X MB）…取消 / 下载」，同意后才
  `ensureBookFileLocal`（期间显示「正在下载《书名》的书籍…」）；取消或下载失败
  直接退出阅读页，**不要再偷偷下载**。`restoreBookFileIfNeeded` 只留给不需要
  确认的场景 / 单测。
  回归：`sync_repository_impl_test.dart` 的「新设备同步只拉书籍元数据，书源文件
  按需下载」、`cloud_download_dialog_test.dart`。
- **阅读器只有原生实现**：`reader_page.dart` 的 `_useNative()` 恒为 `true`，
  WebView + epub.js 渲染链（`reader_bridge.dart` / `reader_asset_server.dart` /
  `assets/reader/reader.html`）仍在库里但已被旁路（`README.md`「已知限制」已注明）。
- **打开书籍卡在「正在打开…」（v2.20.2）**：`_restoreThenBoot` 原来无条件先构造
  `syncRepositoryProvider`（会读 OSS 配置 + 安全存储），冷启动首次可能很慢，
  结果正文启动被同步库初始化卡住；本地书源明明存在却一直转圈，退出再开又好了
  （provider 已缓存）。现在 `restoreBookFileIfNeeded`（`features/reader/reader_boot.dart`）
  **先查本地书源文件，存在就直接启动**，只有文件缺失（清过缓存）才走同步库；
  同步恢复最多 5s / 整体 20s，`_boot` 再加 25s 兜底，任何一步超时都走诊断面板而不是
  无限 loading。原生模式同时跳过只给 WebView 用的 `ReaderAssetServer`
  （不再把整本书读进内存 + 起本地 HTTP 服务）。
  回归：`test/features/reader/reader_boot_test.dart`（本地文件存在不碰同步库 /
  缺失才恢复 / 恢复卡住会超时）。
- **首次打开不卡 / 章节缓存（v2.22.1）**：`_boot` 现在在 `_controller.init()` 拿到书之后
  **立刻** `_booted = true`，正文先挂出来；统计/标注/字体/音效都挪到
  `_finishBoot`，各自 4~5s 超时、失败只记诊断，不再拖住「正在打开…」。
  `nativeChaptersProvider` 的 family key 从 `Book` 改成 `NativeChaptersKey`
  （id/路径/sha256/大小/格式），`touchOpened` 改 `lastOpenedAt` 不会让每次打开重新解析；
  解析加 60s 超时，失败界面带「重新加载」；启动超时的诊断面板也加了「重新加载」。
  回归：`native_plain_reader_test.dart` 的「章节缓存 key 只认书源文件」、
  `launch_reset_test.dart`；`flutter test` 335 项。
- 会话若跑在 workspace-write 沙箱下，`pwsh` 只能写工作区根目录，`lib/`、`qyreader/` 等子目录会
  报「access denied」（文件工具不受此限）。本机已把 `D:\Github\QYReader` 的目录权限补齐，
  修复记录在 `.zcode/acl-reports/`；仍失败就切「完全权限」。
- **退出阅读（合上书）**：`BookOpenRoute.closeDuration = 900ms`（850 → 1100 → 900，
  两次用户反馈：先要慢、再要快一点）。反向动画走 `BookOpenTransition` 的 closing
  分支：整段收缩用 `easeInOutCubic`，书封 alpha 从 0 **线性**升到 1，
  并且先朝观众「抬」一下——`coverScale = 1 + 0.07 * sin(π · clamp(1.6·(1-v)))`，
  带一层浮起的投影（`book-open-cover-lift`），然后缩回
  `BookCoverRegistry` 里书架那一格的实时矩形（拿不到才用 `launch.rect`）。
  打开仍 1000ms、前半程撑满后半程溶解，不抬。回归用例：
  `test/app/book_open_transition_test.dart` 的「退出刚开始书封就浮现，一路缩回书架原位」
  （中途 `getMaxScaleOnAxis() > 1`、落点回到 1）。
- **仿真翻页（curl，v2.21.1 重做）**：不再截图、不再镜像整页正文。当前页钉住，
  下一页从折线右侧滑入；折线 `x = W - progress·W` 随拖动扫过整页，叠加层
  （`CurlTurnPainter`，画在滚动区外）在折线左侧画一条 **46px 纸色卷边**：
  外缘微微弯曲、折线处压一道投影 + 折痕，像纸页右缘卷起来。
  旧实现的两个问题：① 每一页没有不透明底，旧页被钉住时新页盖上来会**透出两页
  文字**（用户截图里的满屏重影）；② 折角三角只掀开右下角，拖动大半屏页面仍是
  整块不动。现在 `_spreadFrame` 给每个翻页单元加 `ColoredBox(theme.background)`
  不透明白底，卷边只做视觉、不铺整页纸背，翻页面积随拖动线性增加。
  几何在 `curl_geometry.dart`（纯数据、可单测），绘制在 `curl_painter.dart`；
  回翻（往右拖）仍走覆盖式、不画卷边。
  视觉自检：`flutter test .zcode/curl_reader_preview_test.dart` →
  `.zcode/curl-reader-preview/*.png`。回归：`curl_geometry_test.dart`、
  `native_reader_view_test.dart`（拖动出层 / 松手收层 / 每页不透明白底）。
- **随手仿真（v2.22.0）**：`PageTurnMode.freeCurl`（面板「翻页方式」里的「随手仿真」）。
  几何在 `free_curl_geometry.dart`：纸角 C 折到手指 F，折线 = CF 的垂直平分线，
  C 一侧的多边形是掀开的洞（露出下一页），镜像到 F 一侧就是纸背；手指拖到哪，
  纸角跟到哪。视觉在 `free_curl_overlay.dart`：**不截整页图**，直接用真实页面
  widget 现场裁剪——下一页垫底、当前页挖掉纸角、当前页关于折线镜像后裁进纸背，
  所以纸背上的字天然是镜像的（与参考稿一致）。`NativeReaderView` 的 Listener 在
  pointer down 记落点，横向移动超过 8px 才判断方向（左 = 下一页，右 = 上一页），
  现场构建 old/new 两页盖在滚动区上；覆盖层 `IgnorePointer` + `ExcludeSemantics`。
  **v2.26.1 起由它完全接管拖动**：freeCurl 模式下 Scrollable 始终
  `NeverScrollableScrollPhysics`，**v2.26.2 起纸角取右/左边缘与落点同高的点**（不再吸附上/下角）；
  松手按 18% 页宽决定翻页/弹回，用 190ms 收尾动画（翻页时允许手指越过页框、
  折线扫出整页）后再 `jumpToPage`，不会出现「拖到一半变成滑动」或松手突跳。
  点击左右三分之一也走 `jumpTo`，**直接到下一页/上一页，不做 220ms 滑动**。
  回归：`free_curl_geometry_test.dart`（折线/洞/纸背/等距镜像/边界）、
  `native_reader_view_test.dart` 的「随手仿真：拖起时盖出折页层，松手收起」
  「从右侧中间起手，纸角在落点高度，松手翻页」。
  视觉自检：`flutter test .zcode/free_curl_preview_test.dart` →
  `.zcode/free-curl-preview/*.png`。
- **页面布局（v2.28.0）**：排版面板 → 页面页签 →「页面布局」打开全屏九宫格编辑器
  （`widgets/page_layout_editor.dart`）。9 个区域分别设「上一页 / 菜单 / 下一页」；
  页眉/页脚左右 4 个区域可「跟随九宫格」或固定动作。配置由
  `features/reader/page_layout.dart` 的 `PageLayoutController` 保存到 prefs
  `reader.pageLayout`，`ReaderPage` watch 后传给 `NativeReaderView`；点击先用
  `PageLayoutSettings.actionAt` 解析页眉/页脚带与九宫格，再执行翻页/菜单；划线点击
  仍优先。滑动翻页在所有翻页效果下都保留（「无」点击瞬间跳页但可拖动；
  「随手仿真」下是跟手折页）。回归：`page_layout_test.dart`、
  `native_reader_view_test.dart` 的「页面布局：中间区域设为下一页」「翻页效果「无」
  也能拖动滑动翻页」。
- **翻页效果「无」= 瞬间跳页**：`NativeReaderView._animateTo` 在 `PageTurnMode.none` 下
  走 `_pc.jumpTo(target)`，不要 220ms 的 `animateTo`（用户明确「瞬间出来，没有过渡动画」）；
  **滑动翻页始终可用**：none 模式也用 `PageScrollPhysics`，不要再禁拖；只有点击才是瞬间跳页。
  回归用例：`test/features/reader/native_reader_view_test.dart` 的「翻页效果「无」」。
- **排版面板（Aa）**：选项型设置统一用 `_SelectRow`（左标签 + 右对齐当前值 + 下拉箭头），
  不要再用 chip 墙；行高 44、标签列 64 是全面板的基准，新加的设置行照这个走。
  数值用 `_LiveSliderRow`（拖动只预览、松手提交）/ `_ValueSlider`，开关用 `_SwitchRow`。
  页签是参考稿的「分段胶囊」（浅色轨道 + 实心药丸，v2.13.0），开关打开色用阅读主题
  `accent`（`_SwitchRow.accent`）。**边距不再用滑杆**：正文/页眉/页脚三组边距都改成
  「在页面上拖动调节」入口（v2.21.0，`_MarginEntry` → 返回 `MarginGroup` 给阅读页），
  页眉页脚内容/字号与页脚字号提示仍在这个页签里。
  主题底色保留色块选择（5 个色块比下拉直观）。面板预览：
  `flutter test .zcode/typeset_preview_test.dart` → `.zcode/typeset-preview/*.png`（测试字体无中文，只看版式）。
- **边距直调（v2.21.0，参考稿三页）**：`features/reader/widgets/margin_editor_overlay.dart`
  的 `MarginEditorOverlay`，从排版面板的「正文边距 / 页眉边距 / 页脚边距」入口进入，
  直接盖在阅读页上：
  - 正文页：正文四边细框 + 上/下/左/右四个数字；页眉页：页眉文字带 + 上/左/右
    数字，带底再放一个「正文上边距」数字；页脚页：页脚文字带 + 下/左/右数字，
    带顶放一个「正文下边距」数字（对应截图里 4/27、20/28 两个数字的结构）。
  - 数字在框外侧，点选后变成 `− 数字 +`，可拖动也可步进 1px（0..64）；拖动方向与
    边距增减的符号按每条边不同（`_dragSign`）。中间悬浮条：分组下拉、复位该组
    默认值、眼睛（隐藏参考框/数字）、勾选完成。
  - 流畅性：拖动只更新 `liveReaderMarginPreview`（ValueNotifier）与
    `liveReaderMarginsProvider`（左右边距走外层 padding），`NativeReaderView`
    新增 `marginPreviewListenable`，监听后 setState 重算版心并只预览当前页
    （`_schedulePreview`），松手/步进才 `patch` 落库；不触发全章重排。
    返回键先退边距编辑（PopScope），再退阅读器。
  - 视觉自检：`flutter test .zcode/margin_editor_preview_test.dart`
    → `.zcode/margin-editor-preview/{body,header,footer}.png`。回归：
    `test/features/reader/margin_editor_overlay_test.dart`（三页数值、步进提交、
    复位、眼睛、勾选）。
- **主题 = 整份排版快照（v2.31.0）**：`ReaderThemePreset.snapshot` 存
  `ReadingSettings.toMap()`（底色、正文、标题、页面、页眉页脚全在内）。排版面板
  「主题」页签顶部是一行**主题色块**（背景色 + 用该主题字体色写的名称） + `+` / `−`（v2.32.0 去掉了文字胶囊与单独的 5 色色块行）：
  `+`（key `typeset-theme-add`）调 `ReaderThemesController.duplicateCurrent()`
  把当前设置复制成 `「<当前主题名> 副本」`（重名自动加序号）并立即应用，随后弹
  `showThemeRenameDialog`（key `typeset-theme-name`）；`−`（`typeset-theme-remove`）
  删当前自定义主题，内置主题时禁用。带快照的主题 `apply()` 走
  `readingSettingsFromMap` 整份还原，内置主题只切底色 + 基础字号/边距（不破坏
  已有排版）。自定义主题激活时，`build()` 里的 `ref.listen` 监听阅读设置，
  500ms 防抖后把整份设置写回该主题（`fromSettings`）——所以面板里改正文/标题/
  页面/页眉页脚都直接算这份主题的。所有写操作先 `await _ready()`（等
  `_restore()` 完成），避免首次从 prefs 恢复时把刚保存的主题覆盖成空。
  回归：`reader_themes_test.dart`（副本快照往返、写回、重命名）、
  `typesetting_panel_test.dart`（加号复制 + 改名、减号删除）。
- **同步进度带书名 + 数据类型（v2.33.0）**：`SyncProgress(label, done, total)`
  的 label 由各阶段自己拼，统一成「正在<动作>《书名》的<数据类型>」，数据类型走
  `_entityLabel`：book=书籍信息 / progress=阅读进度 / annotation=笔记 / bookmark=书签。
  `_push` 报「正在上传《X》的阅读进度」等；`_pull` 报「正在同步《X》的笔记」等
  （远端 op 里有 title 优先用，新设备本地还没建书也能显示）；`_pullShards` /
  `_uploadShards` 报「正在同步 / 上传《X》的阅读数据」；`_backupLocalBlobs` 报
  「正在上传《X》的书籍」「正在上传《X》的封面」；`_restoreLocalCovers` 报
  「正在同步《X》的封面」；开头是「正在准备同步」。书名走 `_bookTitle`（一次同步内
  缓存）/ `_titleOfRemoteOp`。同步面板显示「label（done/total）」+ 进度条。
  回归：`sync_repository_impl_test.dart` 的「同步进度会报出正在同步的书名」、
  `cloud_download_dialog_test.dart`。
- **书架：分类和书混排在同一套格子里**。展示形式只有平铺 / 列表 / 封面三种
  （`ShelfViewMode`），别再往枚举里加「分类」——分类是书架本身的内容，和展示形式不同级。
  首屏由 `shelfCells()`（`shelf_controller.dart`）排成一条 `List<ShelfCell>`：**分类格在前
  （按名字排序），没有分类的书散落在后**；有分类的书只出现在分类格（点开分类才看得到），
  不单独占格。`ShelfFlow`（`widgets/shelf_flow.dart`）按展示形式铺这条格子：
  平铺 `CategoryCard` / `BookCard`，封面 `CategoryCard` / `BookCoverTile`，列表 `CategoryListTile` / `BookListTile`。
  网格一行几格由 `shelfColumns(宽 - 32, columns: prefs.columns)` 算：默认自动（**手机上 3 格**，
  宽屏按每格约 140dp 自动加列），书架设置里可固定 3/4/5 格。网格按「行」铺
  （`SliverList` + 每行一个 `Row`），不再用 `SliverGrid`：一行书下面要压一条横贯
  整行的架板（`ShelfPlank`），`SliverGrid` 的 12dp 列间距会把木板切断。
  别改回 `MaxCrossAxisExtent`（那在手机上只有 2 格）。
  点分类卡 = 把 `shelfCategoryFilterProvider` 设成分类名，AppBar 换成分类名 + 返回箭头，
  只摆这个分类的书；系统返回键走 `PopScope` 先回首屏。
  分类卡：2×2 书位摆前 4 本封面，空位摆「空白书」（书脊剪影）；**卡面不写分类名和本数**
  （用户要求，v2.12.2 去掉），名称只作读屏标签，点进分类后由 AppBar 标题交代。
  书位按书的比例（0.72）算，格子不够高时才压扁，别改回纯 Expanded 等分。
  预览：`flutter test .zcode/category_preview_test.dart` → `.zcode/category-preview/shelf-flow.png`
  （测试环境里 `Image.file` 加载不出封面，也别在预览脚本里用 `precacheImage`——它在 fake async 里不返回，会挂死）。
  布局回归在 `test/features/shelf/shelf_page_layout_test.dart`（分类在前、一行 3 格、点卡进分类再返回）。
- **书架顶栏只留标题 + 搜索 + 「⋯」**（v2.14.1 去掉同步/统计/展示方式，v2.14.4
  把导入收进右上角菜单，v2.17.0 菜单里加「书架设置」）：`PopupMenuButton` 里是
  「多选」「书架设置」「导入书籍」，**不再有悬浮导入按钮**（`FloatingActionButton` 已删，
  别加回来）。导入中菜单项禁用并显示小菊花，进度条仍挂在搜索框上方。同步去
  「设置 → 同步设置」，统计走底栏 Tab；`ShelfViewMode` 的切换入口就是书架设置
  顶部的「网格 / 列表」页签（v2.17.1），实际模式仍取
  `shelfViewModeControllerProvider` 里持久化的值（默认平铺）。
- **书架右上角：快捷同步 + 亮暗切换（v2.35.0）**：AppBar 右侧在「⋯」之前多了两个
  IconButton（多选时整排隐藏）：
  ① `shelf-sync-button`（key）点一下**直接**跑 `syncNow`，不打开面板；同步中图标换成
  18px 小菊花并禁用，结束后 SnackBar 用 `syncResultSummary(result)`
  （`widgets/sync_sheet.dart` 顶层函数，同步面板也用同一句）报结果，并顺手
  `ReaderFontsController.reload()`；② `shelf-theme-mode-button` 按当前
  `Theme.of(context).brightness` 在亮 / 暗之间切换。
  亮暗模式存在 `features/settings/appearance_provider.dart` 的
  `AppThemeModeController`（prefs `app.themeMode`，`AppThemeMode.system/light/dark`，
  默认跟随系统，`set()` 落盘，`toggle(brightness)` 供按钮用），`app.dart` watch 后传
  `MaterialApp.router(themeMode:)`。回归：`shelf_page_layout_test.dart` 的「右上角有直接
  同步按钮与亮暗切换按钮…」、`sync_result_summary_test.dart`。
- **「最近在读」不显示刚读的书（v2.34.1）**：`ReaderPage.dispose` 里原来用
  `ref.read(bookRepositoryProvider.future)` 去 `flushOpened`，但 widget 卸载后
  Riverpod 会抛 `Bad state: Cannot use "ref" after the widget was disposed.`，
  flush 被静默丢掉 → `lastOpenedAt` 永远不落库，书架顶部「最近在读」一行永远
  空着（`recentlyReadItems` 只收录 `lastOpenedAt != null` 的书）。现在在
  `initState` 里先拿住 `Future<BookRepository> _bookRepoFuture`，
  `_flushOpened()` 只用它；并在 `didChangeAppLifecycleState` 的
  paused / hidden / detached 时也 flush（桌面端直接关窗口、进程被回收也能记上）。
  **规矩：`dispose` / 生命周期回调里不要再 `ref.read`。** 回归：
  `book_repository_impl_test.dart` 的「touchOpened 只在 flushOpened 时落库（最近在读依赖它）」。
- **书架最近/进度/返回（v2.23.0）**：① 「最近在读」竖排架排序改成**置顶优先**
  （pinnedAt 降序），再按 lastOpenedAt 降序；刚打开的书在最上面，但不会压过置顶书。
  ② 网格模式**只显示封面 + 右上角圆形进度**（名称/作者/评分/标签/置顶角标全部不出现在网格里）；封面模式仍只显示封面、不显示进度。进度角标是 `BookProgressBadge`：
  圆环 + 百分比，深色半透明底保证浅色封面可读；网格卡片底部的线性进度条移除，
  列表行仍保留原来的进度条 + 百分比。书架设置 → 网格页新增「显示阅读进度」开关
  （`ShelfPrefs.showGridProgress`，prefs key `shelf.grid.showProgress`，默认开）。
  ③ 从分类里打开书：退出阅读器后**保留分类筛选**，回到该分类页（v2.26.4 按用户要求
  从「直接回书架首屏」改回）；从分类卡本身返回仍回首屏。
  回归：`recently_read_test.dart`（置顶优先）、`shelf_view_mode_test.dart`（圆形进度/
  未读不画）、`shelf_page_layout_test.dart`（网格进度 / 开关关闭）、`shelf_prefs_test.dart`。
- **标注弹窗 / 书签 / 阅读主题（v2.24.0）**：
  ① 点已有划线 → 屏幕中间 `AnnotationEditDialog`（不再是底部弹层）：原文、四色、想法
  长输入（4~8 行）、删除标注 / 取消 / 保存。保存时颜色变了走 `setColor` + 双池重挂
  highlight，想法变了走 `setNote`；删除走 `repo.remove` + 移除绘制。
  ② **书签修复**：原生排版 locator 没有 CFI，旧 `_toggleBookmark` 只认 `locator.cfi`，
  所以点书签没反应。新增 `bookmarkKeyFor(locator)`（CFI 优先；原生用 href + 章索引 +
  章内页 + 偏移），书签开关和顶栏图标态都改用它；位置还没回报时用
  `initialLocator` 兜底。
  ③ `ReadingTheme.white` 新增「纯白」纸面（白底、深色文字），阅读主题从 4 个变 5 个。
  ④ 阅读主题库：`features/reader/reader_themes.dart` 的 `ReaderThemePreset`
  （背景色 / 背景图 / 字号 / 行距 / 段间距 / 四边页边距）+ `ReaderThemesController`
  （prefs `reader.customThemes` / `reader.activeThemeId`）。内置 5 个默认主题只读；
  自定义主题可新增 / 编辑 / 删除，保存后立即应用；应用主题 = patch
  `ReadingSettings`（含新字段 `backgroundImage`）。设置 →「阅读主题」→
  `/settings/reader-themes`；编辑页 `/settings/reader-themes/edit`。背景图用
  `file_picker` 选图后复制到 `QYReader/backgrounds/`，`NativeReaderView` 的
  `_PageBackground` 把图铺满纸面并叠 35% 纸色蒙层保证正文可读。
  ⑤ 设置页重组：外观（主题色）/ 阅读（阅读主题、字体管理、排版说明、每日目标）/
  书架与标注（书架设置、标签管理）/ 同步与存储 / 关于。
  回归：`annotation_dialog_test.dart`、`reader_bookmark_test.dart`、
  `reading_theme_test.dart`、`reader_themes_test.dart`、`reader_themes_page_test.dart`、
  `native_reader_view_test.dart`（背景图）、`reader_settings_test.dart`（背景图往返）。
- **书架排序 / 统计日期（v2.25.0）**：
  ① 书架设置弹窗顶部新增「排序」：字段 = 最近阅读 / 导入时间 / 书名，方向 = 升序 /
  降序（按钮显示箭头 + 文案）。`ShelfSortField` 与 `sortAscending` 落 prefs
  （`shelf.sortField` / `shelf.sortAsc`，默认最近阅读 + 降序）。
  `sortShelfItems()`（`shelf_controller.dart`）先按置顶（pinnedAt 降序），再按所选
  字段排序、方向反转；字段相等时按仓库原始顺序稳定排列。排序对分类里的书、
  没有分类的书、搜索结果都生效；「最近在读」竖排架仍按最近打开单独排。
  ② 统计页周期标题抽成 `features/stats/widgets/stats_period_header.dart`：左右各
  预留等宽（右侧有「今天」时两侧都是 96），标题真正居中；点标题打开
  `showDatePicker`（1900/2000 至今），选中后跳到该日期所在周期，日/周/月/年都适用。
  回归：`shelf_sort_test.dart`、`shelf_prefs_test.dart`、`shelf_settings_test.dart`、
  `stats_period_header_test.dart`。
- **书架设置（v2.17.0 / 2.17.1）**：`ShelfPrefs` + `shelfPrefsControllerProvider`
  （`features/shelf/shelf_prefs.dart`），全部只落 shared_preferences，不进库、不同步。
  prefs key：`shelf.coverRadius` / `shelf.columns` / `shelf.plankStyle` /
  `shelf.sortField` / `shelf.sortAsc` /
  `shelf.list.showRating|showTags|showDescription|descriptionLines|showReview|reviewLines`。
  默认：圆角 20、自动列数、木纹架板；列表四项开关默认关、行数各 2。恢复时圆角夹
  0..24、行数夹 1..4，未知枚举回退默认（settings 里改完全局实时生效）。
  入口在书架「⋯」→「书架设置」，弹窗 `widgets/shelf_settings_sheet.dart`：顶部
  「网格 / 列表」分段胶囊；**选中页签会同步切换书架展示形式**（v2.17.1：`TabBar.onTap`
  写 `shelfViewModeControllerProvider`；打开时按当前模式定位初始页，外部模式变化用
  `ref.listen` 把页签动画过去）；网格页 = 圆角滑杆 + 单行数量 + 架板样式，列表页 =
  星级 / 标签 / 简介+行数 / 书评+行数 六个控件。列表开关只作用 `BookListTile`
  （网格卡片保持常显）；关掉后不插入占位，行高自然收紧。
  架板 `widgets/shelf_plank.dart`：木纹 = 深胡桃竖向渐变 + 6 条确定性横纹 + 板沿高光/投影，
  纯色 = 单色板。`ShelfFlow` 把网格按「行」铺（`SliverList` + `Row`），每行下面压一条
  `ShelfPlank`；**`Column` 必须 `crossAxisAlignment: stretch`**，否则木板只有高没有宽
  （踩过：宽度 0，截图里完全看不见）。
  视觉自检：`flutter test .zcode/shelf_settings_preview_test.dart`
  → `.zcode/shelf-settings-preview/*.png`。回归：`test/features/shelf/shelf_prefs_test.dart`、
  `shelf_settings_test.dart`（弹窗控件/架板宽度/圆角透传/列表开关/行高收紧）。
- **标签管理（v2.18.0）**：标签本体仍在每本书的 `books.tags` 里（跟随书籍同步）；
  另有本机标签库 `TagLibraryController`（prefs key `tags.library`）保存「新增但还没挂书」
  的标签。`tagSummariesProvider` = 书架用过的标签 ∪ 标签库，按使用数降序、同数按名字；
  没人用的标签也显示（count 0）。页面 `features/tags/tag_manager_page.dart`：
  设置 → 书架 →「标签管理」，路由 `/settings/tags`；搜索框 + 大号胶囊
  （`TagCapsule(large: true)`，计数在右）+ 右上角「+」新建；点胶囊弹出改名/删除，
  删除要二次确认。重命名/删除走 `BookRepository.renameTag/deleteTag`：只改未删除书籍、
  每本追加 sync_op，目标名已存在时同书内合并去重；操作后同步更新标签库。
  编辑书籍的标签区新增「从标签库选择（N）」→ `features/tags/tag_picker_sheet.dart`：
  搜索 + 多选（点击即存，最多 12 个）；手动输入的新标签也会写进标签库。
  `TagCapsule` 保持默认尺寸给卡片用，`large` 只给管理页。
  视觉自检：`flutter test .zcode/tag_manager_preview_test.dart`
  → `.zcode/tag-manager-preview/*.png`。回归：`test/features/tags/*`、
  `book_personalization_test.dart` 的批量重命名/删除用例。
- **清除书籍缓存（v2.20.0）**：设置 → 同步与存储 →「清除书籍缓存」进入
  `/settings/cache`（`features/settings/cache_manager_page.dart`）。只列本地有书源
  文件的书籍（封面缩略图 + 占用大小），支持逐本 / 全部清除。清除走
  `SyncRepository.clearLocalBookCache`：先确保云端有书源备份（没有就拒绝），再删本地
  书源文件；**封面、数据库记录、云端书源/封面都不动**，下次打开由
  `ensureBookFileLocal` 自动拉回。`ObjectStore` 新增 `exists()`（S3 用 statObject），
  校验备份不再下载整本书。
  删除书籍时才清云端：`confirmDeleteBook` 调 `deleteCloudBook` 立即删书源/封面/分片；
  墓碑 payload 带 `fileSha256`，`_push` 推送删除 op 后再清一次（幂等重试）。
  `_uploadShards` 跳过已删除的书，避免清掉后又传回空分片。
  回归：`test/features/settings/cache_manager_page_test.dart`、`sync_repository_impl_test.dart`
  的「清除缓存只删本地书源…」「删除书籍时云端书源、封面与分片一起删除」。
- **逻辑审查修复（v2.20.1）**：① `BookRepository.setPersonalization` 的 `null` 参数
  改为「该字段不改」，只有显式 0 / 空串 / 空列表才清除；详情页改评分/标签/书评/分类、
  书架「移动」不会再顺手清空其他字段（清空分类改传 `''`）。
  ② 同步墓碑真正生效：`_mergeBook` 识别 `{id, deletedAt}` 最小 payload，按 HLC
  删除本地书 + 关联行 + 文件/封面 + `book_fts` 行，另一台设备删除后本机也会移除。
  ③ 弹窗输入不在退场动画期间 `dispose` controller：书名/作者、每日目标改用
  `TextFormField`，标签/分类编辑器改 Stateful 持有 controller。
  ④ 缓存页「全部清除」单本失败不再中断整批；⑤ 删除书时清 FTS 派生行。
  回归：`book_personalization_test.dart` 的「只更新一个字段时其他字段保持」、
  `sync_repository_impl_test.dart` 的「删除墓碑传播」。
- **点按不加触感反馈**：`PressableScale`（`core/widgets/pressable_scale.dart`）只做按压缩放，
  不调 `HapticFeedback`（v2.12.1 按用户要求去掉点击/长按震动）；新组件也别再单独加震动。
  回归用例：`test/core/widgets/pressable_scale_test.dart`。
- **EPUB 单文件多章靠目录锚点切**：calibre / pdftohtml 会把整本书塞进几个
  `index_split_00x.html`，目录（NCX/nav）用 `#p12` 指向段首。`parseEpub` 的
  `_splitByAnchors` 用目录里的**真实锚点**切正文块（不按标题猜），`<a id>`
  藏在段首或独占一段都能定位；下一份文档开头（第一个锚点之前）续到上一章，
  正文不丢不重。实测《十扇窗》原来 16 个目录条目只剩 4 章，修好后 16 章齐全。
  解析在打开书时重跑（`nativeChaptersProvider`），所以解析器修好后旧书**重开即可**，
  不必重新导入；书架 DB 里的 chapters 行是导入时写的，可能仍是旧粒度（只影响
  书详情里的章数）。
  回归用例：`test/data/parsers/epub_anchor_chapters_test.dart`；
  真实样本自检：`flutter test .zcode/epub_anchor_check_test.dart`。
- **标注 locator 必须按章索引定位**：切章修复后多章共用同一个 href
  （`index_split_001.html` 里有第四章/五章/六章），`nativeChapterForLocator`
  优先用 `chapterIndex`（与 href 对得上时），旧数据才退回 href 的第一章。
  只按 href 找会把新划线的偏移算到同文件第一章上——表现为「划线后没有色块」
  （v2.13.2 修）。回归用例：`test/features/reader/native_chapter_source_test.dart`。
  目录跳转（`_gotoLocatorJson`）也走这个函数。
- **选字只留自家菜单**：`NativeReaderView` 正文的 `SelectableText.rich` 用
  `contextMenuBuilder` 返回空盒子，压掉系统自带的「复制 / 全选」浮层——阅读页
  已经有四色划线 `SelectionMenu`，两套弹窗会叠在一起（v2.12.4 用户反馈）。
  选区手柄照常保留（要拖范围），菜单由 `onSelectionChanged` 收口。
  回归用例：`test/features/reader/native_reader_view_test.dart` 的「选中文字不弹系统菜单」。
- **单字划线也要点得中**：`_markAtInRun` 先按命中框精确判，再按「离最近划线
  ≤ `_markHitSlop`(20px)」兜底——一个字的划线只有约 18px 宽，手指点偏一点原来
  会没反应（v2.13.0 用户反馈）；同一行相邻划线取最近的。回归用例：
  `native_reader_view_test.dart` 的「单个字划线：点偏一点也能打开笔记」。
- **翻页音效**：`PageTurnSound`（无 / 音效一 / 音效二）存在 `ReadingSettings` 里，
  资源是用户提供的 `assets/sounds/page_turn_1.mp3` / `page_turn_2.mp3`（v2.14.7 起，
  旧的合成 WAV 与 `.zcode/gen_page_turn_sounds.py` 已废弃，不要再生成）。
  **素材做过三轮延迟裁剪**：v2.20.3 裁掉开头静音（143ms / 79ms）；v2.20.4 发现
  素材是**渐强**的（响度峰值分别在 360ms / 460ms），按峰值对齐裁剪；v2.20.5 用户
  反馈音效一裁多了，回退 0.15s。当前长度：音效一 0.441s（峰值约 190ms）、音效二
  0.411s（峰值约 50ms）。以后替换素材必须确认「开头就是冲击声」，否则听感仍会
  滞后（MP3 编码器本身约 30ms 延迟是格式固有的）。
  旧设置里的 `paper` / `thin` / `thick` 在 `_pageTurnSoundOf` 里统一映射到「音效一」。
  播放统一走 `PageTurnSoundPlayer`：**预载式低延迟**（v2.20.3）——音源只在预载时
  `setSource` 一次（SoundPool 完成解码），翻页只走 `stop` + `resume` 两个通道调用，
  不再每次 `play(AssetSource)` 重新装载并等 prepared 事件；注意 SoundPool 的
  `resume` 只续播当前流，连续重播必须先 `stop` 清流 id。阅读页 `_boot` 里预载
  当前音效；`mixWithOthers` 不抢音频焦点 + 失败静默。
  **触发时机（v2.20.4）**：`NativeReaderView._onScrollPageChanged` 在页索引跨过
  目标页时立即 `_playTurnSound()`，不再等 `ScrollEnd`（旧逻辑要等完 220ms 翻页
  动画/回弹收尾，实测「慢半拍 0.5s」的主因）。目录 / 续读 / TTS 跳页用
  `_suppressTurnSound` 静音；`PageTurnMode.none` 的瞬间跳页也会响。
  面板里在下拉框里选音效会立即试听。
- **慢快慢贝塞尔**：`kSmoothCurve = Cubic(0.65, 0, 0.35, 1)`（`app/theme/motion.dart`）。
  页面转场用 `SmoothPageTransitionsBuilder`（`app_theme.dart`，纯 Fade/Slide，
  **不能用 SnapshotWidget 类转场**，原因见主题注释）；所有底部弹层/对话框传
  `sheetAnimationStyle` / `animationStyle: kSmoothSheetAnimation`。别散写 `easeOutCubic`。
- **底栏与配色**：底栏是 `FloatingNavBar`（`features/home/widgets/floating_nav_bar.dart`）：
  悬浮胶囊、白底 66 高、圆角 33、选中项套浅色胶囊 + primary 图标文字（参考稿，
  v2.13.0）。**选中胶囊是滑动的**（v2.14.2）：`LayoutBuilder` 算出每格宽度，
  `AnimatedPositioned` 用 `kSmoothCurve` 在格与格之间滑动，别改回「每项各自
  AnimatedContainer 原地淡入」。主题 seed 换成参考稿亮蓝 `#1E7BFF`，亮色页面底色
  `#F3F4F9`，卡片白底 20 圆角无描边、AppBar 透明无阴影。别再改回 `NavigationBar`。
  回归用例：`test/features/home/floating_nav_bar_test.dart`（胶囊中途位置 + 落点）。
- **统计页跟其他页面同一套皮肤**：`stats_page.dart` 的 `_StatsPalette` 把页面底 /
  卡片 / 文字 / 主色映射到 `Theme.of(context)`（白卡片、20 圆角、蓝色图表），
  **不要再用 `ReadingTheme`**（那是阅读页的纸面配色，v2.13.1 之前统计页是米色底，
  跟书架/设置不一致）。周期切换用同款「分段胶囊」。
- **书架搜索与筛选**：AppBar 底部常驻书名搜索框，右侧紧跟筛选按钮（有筛选时角标
  高亮）。筛选条件 = 最低星级（不限 / 1~5 星+）+ 标签多选（命中任意一个）+ 阅读状态
  （v2.37.0，未读 / 在读 / 已读 / 弃读，命中任意一个），由
  `features/shelf/shelf_filter.dart` 的 `ShelfFilter` 表达，弹层是
  `widgets/shelf_filter_sheet.dart`。搜索和筛选叠加：先按当前分类取书，再按书名 +
  星级 + 标签 + 状态过滤；任一条件生效时压平成书格（不摆分类、不摆「最近在读」），
  空结果显示「没有符合筛选条件的书」并可一键清除筛选。搜索词与筛选条件只存页面
  state，不进 prefs。回归：`shelf_page_layout_test.dart` 的「搜索书名」「筛选：星级 + 标签，
  并在筛选范围内搜索」、`shelf_filter_test.dart`（含阅读状态用例）。
- **阅读状态（v2.37.0）**：`BookReadStatus`（unread / reading / finished / dropped，
  `domain/entities/book.dart`，带中文 `label`）存在 `books.read_status`（schema v5，
  迁移只 `addColumn`）。设置入口在书籍详情 →「标签分类」页签顶部的四个 ChoiceChip
  （key `book-status-<name>`），改动走 `setPersonalization(readStatus:)`，与
  评分/标签/分类同口径（写 HLC + sync_ops，多设备同步）；`bookToJson` 只在非
  unread 时写 `readStatus`，旧 payload 缺字段按 unread 处理。旧布尔字段
  `isFinished` 保留但不再用于状态判断。
- **书架多选 / 批量操作（v2.27.0，v2.40.0 收敛范围）**：入口在书架「⋯」→「多选」；进入后 AppBar 变成
  「已选择 N 本」+ 关闭按钮，搜索/筛选条收起，底部出现删除 / 加标签 / 分组三个动作。
  **多选只选当前目录**：书架首屏（根目录）只铺没有分类的书（`rootShelfItems`），
  分类里只铺该分类的书；分类卡在多选时有分类书时也不再出现，点书或长按切换选中；
  卡片左上角勾选角标、列表选中项带浅色底；系统返回键先退出多选。
  批量删除先确认「取消 / 删除书籍 / 删除全部」，选「删除全部」还会再弹一次
  「危险操作」二次确认；逐本 `deleteBook` 并清理云端书源；批量加标签弹层支持勾选
  已有标签 + 逗号分隔新标签，逐本合并去重后 `setPersonalization(tags:)`，新标签
  同时写入标签库；批量分组支持已有分组 / 新建 / 移出，逐本
  `setPersonalization(category:)`。弹层在 `widgets/batch_actions.dart`，卡片通过
  `selectionMode / selected / onSelect` 支持多选。
  回归：`shelf_page_layout_test.dart` 的「多选：根目录只选没有分类的书…」
  「分类里多选只选该分类的书」、`batch_actions_test.dart`（标签解析 / 新建分组 /
  删除二次确认）。
- **页眉/页脚边距是绝对边距（v2.38.3 起）**：`_runningHeight` 与
  `_pageContent` 只用 `settings.headerMarginTop` / `settings.footerMarginBottom`，
  **不再叠加系统安全区**（用户要求「不考虑安全区」）。改这里必须同步改
  `_pageContent` 里页眉/页脚的 Padding，否则文字位置和分页高度对不上；
  边距直调覆盖层（`MarginEditorOverlay`）也不再有 `safeTop/safeBottom`，
  几何直接用边距从 0 / size.height 起算。
- **设置页是配置入口**（v2.36.0 重排为五组，v2.36.1 精简）：外观（显示模式 /
  主题色）/ 资源（字体 / 背景）/ 管理（标签 / 分类）/ 数据（同步 / 缓存）/ 关于
  （关于 QYReader / 开源协议）。页面结构改动时保持这五组，别再零散堆 ListTile。
  v2.36.1 按用户要求删掉了「阅读主题」「每日阅读目标」「书架设置」「临时文件与图片」
  「数据存储」入口：阅读主题走阅读页排版面板，书架设置在书架「⋯」里，每日目标
  暂不再提供界面入口（`statsRepository.setDailyGoalMinutes` 仍保留）。
  - 显示模式：单个开关（v2.36.2 起不再用三段选择）：`AppThemeMode`（system /
    light / dark，prefs `app.themeMode`）+
    `AppThemeModeController`，`app.dart` 把它传给 `MaterialApp.router(themeMode:)`；
    书架右上角按钮也调同一个 controller（见 v2.35.0）。
  - 主题色：`AppAccent` 6 色（prefs `app.accent`），`QyReaderApp` watch 后传给
    `AppTheme.light/dark(seed)`；阅读主题是另一套（`ReadingTheme` /
    `ReaderThemePreset`），跟 App 主题色互不影响。
  - 主题网格（v2.38.0）：排版面板「主题」页签从横向单行改成 `Wrap` 网格
    （每块 100×64、自动多行），右上角 + / − 仍然复制 / 删除；长按自定义主题
    弹出「修改名称 / 更换背景图 / 从背景库选择 / 清除背景」；内置主题只能点选（带锁）。
  - 资源 → 背景：`ReaderBackgroundsPage`（`/settings/backgrounds`）里的
    `BackgroundCacheView`，列的是背景目录里的全部图片（不只是被主题引用的），
    可逐张 / 一键清除；清除 = 删图片 + 把引用它的主题 `backgroundImage` 置空
    （变回纯色），排版设置保留；「上传背景」只把图片放进背景库，**不会新建主题**
    （v2.38.1 起；主题是主题、背景是背景，一个背景可被多个主题共用）。
    主题在排版面板长按「更换背景 / 从背景库选择」来选用；背景随同步上传云端
    （见 v2.38.0 的 `BackgroundSync`）。
  - 管理 → 分类：`CategoryManagerPage`（`/settings/categories`）列出书架上出现过的
    分类与本数，支持改名（逐本 `setPersonalization(category:)`）与删除（清空分类，
    不删书）；分类没有独立实体，来自 `books.category`。
  - 数据 → 缓存：`CacheCenterPage`（`/settings/cache`）三个页签：
    书籍（`BookCacheView`，原「清除书籍缓存」）/ 字体（`FontCacheView`）/
    背景（`BackgroundCacheView`）。语义统一为「只清本地，云端原数据保留」；
    书籍下次打开自动拉回，字体与背景下次同步按 sha256 重新下载（主题背景被清则回纯色）。
  - 关于 → 开源协议走 Flutter 自带 `showLicensePage`，关于走 `showAboutDialog`。
- **背景图参与同步（v2.38.0）**：`data/sync/background_sync.dart` 的 `BackgroundSync`
  把 `<文档>/QYReader/backgrounds/` 里的图片按 sha256 传
  `spaces/<空间>/backgrounds/bg-<sha>.<ext>`，清单
  `spaces/<空间>/backgrounds/manifest.json` 记录 `{sha256, fileName, ext}`；拉取侧
  按 sha256 去重，云端有、本机没有的图片下载回背景目录（重名加 `-2` 等后缀）。
  语义是并集：本机删背景不删云端，下次同步会拉回来。`syncNow` 在字体之后调用，
  `SyncResult.backgroundsSynced` 给同步面板显示「同步 N 张背景」。
  回归：`test/data/sync/background_sync_test.dart`（上传→另一台设备拉取、二次同步
  不重复上传）。
- **点桌面图标：阅读中保持阅读页，其它页回书架**（v2.22.1 调整）：`launchMode=singleTop`，
  进程还活着时点图标 Android 走 `onNewIntent`；`MainActivity` 发 `qyreader/launch`，
  `app/launch_reset.dart` 先查 `activeReaderBookSync()/activeReaderBook()`：
  **正在阅读就忽略归位**（切后台再回来不合书），不在阅读页才 `router.go('/')`。
  阅读标记在 `ReaderPage.initState` 同步写内存 + prefs，`dispose` 清掉。
  冷启动本来就从 `/` 起；深链 / 文件「打开方式」（VIEW/SEND）不触发归位。
  回归用例：`test/app/launch_reset_test.dart`（阅读中不掉书 / 退出后才回书架）。
- 阅读器诊断：顶栏 🐛 打开诊断面板；debug 构建可用
  `adb forward tcp:9222 localabstract:webview_devtools_remote_<pid>` 配合 `tools/devtools_eval.dart`。
- **自建 `Viewport` 必须显式传 `axisDirection`**：它默认是 `AxisDirection.down`，与
  `Scrollable(axisDirection: right)` 不一致时页面会竖排——手指左右滑、内容上下翻
  （v2.10.3 修的正是这个）。回归用例在 `test/features/reader/native_reader_view_test.dart`
  的「翻页沿横轴：视口主轴右向，横滑前进、竖滑不换页」。

## 8. 对话变更记录

更早的 2026-11-11 记录（2.10.1 – 2.20.5）已迁到 [`docs/changelog-20261111.md`](docs/changelog-20261111.md)。

更早的 2026-11-12 记录（2.21.1 – 2.33.1）见 [`docs/changelog-20261112.md`](docs/changelog-20261112.md)。

| 日期 | 版本 | 改动 | 产物 |
|---|---|---|---|
| 2026-11-12 | 2.34.0+118 | 自定义阅读字体参与同步：新增 `data/sync/font_sync.dart`——字体文件按 sha256 上传到 `spaces/<空间>/fonts/`，清单 `fonts/manifest.json` 记录字体元数据；同步时先传本机字体、再按 sha256 去重拉取云端缺的字体，写入本机字体目录并合并进 prefs `reader.fonts`；同步面板完成后刷新 `ReaderFontsController`（免重启可用）并显示「已同步 N 个字体」（`SyncResult.fontsSynced`）；语义为并集，本机删除不影响其他设备；补 2 项回归（共 395 项） | `qyreader/QYReader-v2.34.0-20261112-font-sync.apk`、`qyreader/QYReader-v2.34.0-20261112-windows-x64.zip` |
| 2026-11-12 | 2.34.1+119 | 修「书架顶部最近在读不显示刚打开的书」：根因是 `ReaderPage.dispose` 里用 `ref.read` 调 `flushOpened`，widget 卸载后 Riverpod 抛 `Bad state: Cannot use "ref" after the widget was disposed.`，`lastOpenedAt` 从未落库；改为 `initState` 缓存 `Future<BookRepository>`，`_flushOpened()` 只用缓存，并在 paused / hidden / detached 时也落库（桌面端关窗口不漏记）；补 1 项回归（共 396 项） | `qyreader/QYReader-v2.34.1-20261112-recent-shelf-fix.apk`、`qyreader/QYReader-v2.34.1-20261112-windows-x64.zip` |
| 2026-11-12 | 2.35.0+120 | 书架右上角新增两个按钮：①「同步」点一下直接同步（不打开面板），同步中显示小菊花并禁用，结束用 `syncResultSummary` 报上传/合并/文件/字体数量，并刷新字体列表；②「亮暗切换」按当前亮度在亮/暗之间切换，新增 `AppThemeModeController`（prefs `app.themeMode`，默认跟随系统）让 `MaterialApp.themeMode` 真正可调；同步结果文案抽成共用函数；补 4 项回归（共 400 项） | `qyreader/QYReader-v2.35.0-20261112-shelf-quick-sync-theme-toggle.apk`、`qyreader/QYReader-v2.35.0-20261112-windows-x64.zip` |
| 2026-11-12 | 2.36.0+121 | 设置页重排为五组：外观（亮暗模式分段选择 + 主题色）/ 资源（阅读主题 / 字体 / 背景）/ 管理（标签 / 分类 / 书架设置 / 每日目标）/ 数据（同步 / 缓存 / 临时文件）/ 关于（关于 QYReader / 开源协议 / 数据存储）；新增分类管理页（改名 / 删除分类，逐本写 `category`）、阅读背景管理页；缓存改成三页签（书籍 / 字体 / 背景），都支持逐项与一键清除，只删本地、云端原数据保留可再下载；`BookCacheView` 从原缓存页抽出共用，设置页先渲染再异步量临时目录；补 4 项回归（共 404 项） | `qyreader/QYReader-v2.36.0-20261112-settings-sections-cache-tabs.apk`、`qyreader/QYReader-v2.36.0-20261112-windows-x64.zip` |
| 2026-11-12 | 2.36.1+122 | 精简设置页：删除「临时文件与图片」「阅读主题」「每日阅读目标」「书架设置」「数据存储」五个入口，保留外观（显示模式/主题色）、资源（字体/背景）、管理（标签/分类）、数据（同步/缓存）、关于（关于/开源协议）；设置页由 StatefulWidget 改 ConsumerWidget，去掉临时目录统计与每日目标读取逻辑；补 1 项「已移除入口不存在」回归（共 405 项） | `qyreader/QYReader-v2.36.1-20261112-settings-trim.apk`、`qyreader/QYReader-v2.36.1-20261112-windows-x64.zip` |
| 2026-11-12 | 2.36.2+123 | 外观显示模式改成单个开关（按当前实际亮度在亮 / 暗间切换，不再三段选择）；背景管理新增「上传背景」：选图后复制进 `QYReader/backgrounds/`，以当前阅读主题为底新建自定义主题并立即应用；背景说明更新为「上传 / 查看 / 清理」；补 1 项上传按钮回归（共 406 项） | `qyreader/QYReader-v2.36.2-20261112-theme-switch-background-upload.apk`、`qyreader/QYReader-v2.36.2-20261112-windows-x64.zip` |
| 2026-11-12 | 2.37.0+124 | 新增书籍阅读状态（未读 / 在读 / 已读 / 弃读）：`BookReadStatus` + `books.read_status`（schema v5 迁移只 addColumn）；书籍详情「标签分类」顶部四选一，走 `setPersonalization(readStatus:)` 并参与同步；书架筛选新增「阅读状态（任一）」多选，与星级 / 标签叠加；`bookToJson` 非 unread 才写 `readStatus`；补 2 项回归（共 407 项） | `qyreader/QYReader-v2.37.0-20261112-read-status.apk`、`qyreader/QYReader-v2.37.0-20261112-windows-x64.zip` |
| 2026-11-12 | 2.38.0+125 | ① 排版面板「主题」改成 `Wrap` 网格（多行、每块 100×64），长按自定义主题可「更换背景图 / 从背景库选择 / 清除背景」（新增 `showBackgroundLibrarySheet`）；② 背景图升级为云端资源：新增 `data/sync/background_sync.dart`，背景按 sha256 传 `spaces/<空间>/backgrounds/` + manifest，`syncNow` 在字体之后同步，拉取侧把云端缺的图片下载回背景目录（并集语义），`SyncResult.backgroundsSynced` 在同步面板显示「同步 N 张背景」；③ 背景管理改为列出背景目录里的全部图片（未被主题引用也显示），上传/清理逻辑不变；补 2 项背景同步回归（共 409 项） | `qyreader/QYReader-v2.38.0-20261112-theme-grid-background-sync.apk`、`qyreader/QYReader-v2.38.0-20261112-windows-x64.zip` |
| 2026-11-12 | 2.38.1+126 | 按用户要求把「主题」和「背景」彻底分开：上传背景只把图片放进背景库，**不再自动新建/修改主题**；主题在排版面板长按「更换背景图 / 从背景库选择 / 清除背景」来切换，一个背景可被多个主题共用（背景页显示「N 个主题使用 / 未使用」）；背景管理标题改为「背景库」，说明与设置页副标题同步更新 | `qyreader/QYReader-v2.38.1-20261112-background-library.apk`、`qyreader/QYReader-v2.38.1-20261112-windows-x64.zip` |
| 2026-11-12 | 2.38.2+127 | ① 主题长按菜单新增「修改名称」（复用 `showThemeRenameDialog`）；② 修「换了背景但阅读页不显示」：带快照的自定义主题 `apply()` 先整份还原快照、再用主题当前的 `backgroundImage` 覆盖（快照里存的是旧图路径）；换背景 / 从背景库选择后主题立即应用，阅读页背景同步更新；补 1 项回归（共 410 项） | `qyreader/QYReader-v2.38.2-20261112-theme-background-apply.apk`、`qyreader/QYReader-v2.38.2-20261112-windows-x64.zip` |
| 2026-11-12 | 2.38.3+128 | 页眉/页脚边距改为**绝对边距**、不再叠加系统安全区：`_runningHeight` 与 `_pageContent` 只用 `headerMarginTop` / `footerMarginBottom`；`ReaderPage._pagePadding` 不再加 `insets.top/bottom`；`MarginEditorOverlay` 去掉 `safeTop/safeBottom`，几何从 0 / size.height 起算；边距直调页与阅读页保持同一套坐标 | `qyreader/QYReader-v2.38.3-20261112-absolute-margins.apk`、`qyreader/QYReader-v2.38.3-20261112-windows-x64.zip` |
| 2026-11-12 | 2.39.0+129 | 阅读状态自动切换：导入默认「未读」；`ReaderController.init` 打开书时按已有进度给状态（<100% → 在读，=100% → 已读），并写回书籍；`_write` 每次进度落库后按 `readStatusForProgress(percent)` 同步（100% → 已读，回翻到前面 → 在读），状态相同不重复写；新增 `readStatusForProgress` / `kReadFinishedThreshold`；补 3 项回归（共 412 项） | `qyreader/QYReader-v2.39.0-20261112-auto-read-status.apk`、`qyreader/QYReader-v2.39.0-20261112-windows-x64.zip` |
| 2026-11-12 | 2.40.0+130 | ① 多选只选当前目录：书架首屏（根目录）只铺没有分类的书，分类里只铺该分类的书（新增 `rootShelfItems`，`ShelfPage` 多选时按 filter 选作用域）；② 删除确认统一为「取消 / 删除书籍 / 删除全部」：删除书籍保留笔记划线，删除全部连笔记、划线、书签与阅读记录一起删；选「删除全部」再弹「危险操作」二次确认（红色警示 + 继续删除），取消则什么都不删；单本与批量共用 `confirmDeleteAllDanger`；③ 单本删除不再提供「保留并导出」（导出入口随菜单移除）；补 2 项回归（共 413 项） | `qyreader/QYReader-v2.40.0-20261112-multiselect-delete-confirm.apk`、`qyreader/QYReader-v2.40.0-20261112-windows-x64.zip` |
| 2026-11-12 | 2.40.0+130 | ① `README.md` 按 v2.40.0 重写：6 张真机截图（`docs/screenshots/1–6.jpg`）、版本 / 技术栈、功能总览、下载与安装、构建与签名、同步协议、数据与备份、架构、schema v5、已知限制与更新日志入口；② 修正旧 README 的过时描述（Windows 阅读器禁用 / epub.js 渲染 / schema v3 / 封面不同步）；仅文档更新，未递增版本 | `qyreader/QYReader-v2.40.0-20261112-multiselect-delete-confirm.apk`（同版本重出）、`qyreader/QYReader-v2.40.0-20261112-windows-x64.zip`（沿用） |
