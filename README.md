<div align="center">

# QYReader

**本地优先的跨平台阅读器 · Flutter**

书架 · 首页概览 · 我的阅读 · 笔记回顾 · 原生排版阅读 · 四色划线 · 全书检索 · TTS 朗读 · 多设备同步 · 阅读统计

<sub>数据以 SQLite 为唯一真相源，离线可用；Android 为验收平台，同时提供 Windows 桌面版。</sub>

</div>

| 版本 | 技术栈 | 数据 | 平台 |
|---|---|---|---|
| `2.69.2+199` | Flutter 3.32 · Dart 3.8 · Riverpod 2 · drift(SQLite) · go_router · freezed | SQLite schema **v6**，离线优先 | Android（minSdk 24）· Windows x64 |

---

## 截图

<table>
  <tr>
    <td align="center">
      <img src="docs/screenshots/1.jpg" width="250" alt="书架"><br>
      <sub><b>书架</b> · 分类卡、最近在读、封面网格</sub>
    </td>
    <td align="center">
      <img src="docs/screenshots/2.jpg" width="250" alt="阅读页"><br>
      <sub><b>阅读</b> · 原生排版、页眉页脚、自定义背景</sub>
    </td>
    <td align="center">
      <img src="docs/screenshots/3.jpg" width="250" alt="排版面板"><br>
      <sub><b>排版</b> · 主题库、字号行距、页眉页脚</sub>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="docs/screenshots/4.jpg" width="250" alt="阅读统计"><br>
      <sub><b>统计</b> · 日 / 周 / 月 / 年与时长分布</sub>
    </td>
    <td align="center">
      <img src="docs/screenshots/5.jpg" width="250" alt="书籍信息"><br>
      <sub><b>书籍信息</b> · 进度、标签分类、继续阅读</sub>
    </td>
    <td align="center">
      <img src="docs/screenshots/6.jpg" width="250" alt="标签管理"><br>
      <sub><b>标签</b> · 彩色胶囊、重命名与删除</sub>
    </td>
  </tr>
</table>

## 功能

| 模块 | 能力 |
|---|---|
| **首页** | 底栏第一个 Tab：累计阅读（时长 + 已读完本数）；继续阅读横向卡片流；今日目标圆弧计时、每日目标编辑与「开始阅读」；今年读完的书 / 年度目标；右上角刷新与目标菜单 |
| **书架** | EPUB / AZW3 / MOBI / TXT / Markdown 导入（内容寻址去重、封面压缩入库）；AZW3 / MOBI（无 DRM）导入时自动转成 EPUB 保存，DRM 文件明确提示不支持；导入完成弹窗汇总成功 / 重复 / 失败并可回看导入记录（清空前一直保留）；长按「覆盖导入」用新书源替换已有书正文，保留书名 / 封面 / 进度 / 笔记，导入后可自动匹配笔记位置（先完整原文搜，搜不到再逐字缩短继续匹配）；平铺 / 列表 / 纯封面三种展示（网格可在书架设置里开关封面进度与书名）；分类卡与未分类书同屏混排；书名搜索 + 星级 / 标签 / 阅读状态筛选；彩色胶囊标签；「最近在读」竖排架（按屏宽铺满、书少时居中）；置顶、评分、书评；多选批量删除 / 加标签 / 分组；点击右上角一键同步 |
| **重复书籍整理** | 设置 → 管理进入；按书名强匹配 / 疑似匹配或文件 SHA-256 查找重复书籍；匹配范围可选全部 / 强 / 疑似，可只匹配同作者；按阅读状态 / 分类筛选；分组显示封面、文件大小、字数、加入时间、分类与来源文件；支持忽略分组、勾选后批量删除（每组至少保留一本）或逐本删除，删除会一并清理笔记与书签 |
| **桌面组件** | Android 桌面 2×2「最近阅读」（封面 + 阅读进度条）、2×2「今日阅读」（时长 + 每日目标进度）、4×2「最近读的书」（最近三本书）；点亮组件直达阅读页 / 统计 / 书架，数据由 App 推送、离线可用 |
| **我的阅读** | 设置 → 管理进入；全部 / 在读 / 搁置 / 读完筛选；书名 / 作者搜索；按年 > 月时间线回顾（可折叠），显示读到百分比或累计时长、开始阅读 / 读完时间、字数与时长、封面；深 / 浅两套 9:16 分享海报，可保存到相册或系统分享 |
| **笔记回顾** | 设置 → 管理进入；按书汇总笔记条数、已读时长 / 字数与封面，支持书名 / 作者 / 原文 / 想法搜索与按最近 / 条数 / 书名排序；「笔记漫游」用左右滑动的卡片逐条回顾划线 / 书签，可按类型和书籍筛选 |
| **阅读器** | 原生排版（不依赖 WebView），六种翻页效果：滑动 / 覆盖 / 淡入 / 仿真 / 随手仿真 / 无；翻页音效；四向边距在页面上拖动直调；单双页；页眉页脚（章节名 / 时间 / 进度 / 电量）与九宫格点击区域；章节末「下一章 / 读完」卡片；长按选字可划线 / 高亮 / 笔记，拖动选区手柄到页边停留可自动翻页并继续选字；书籍信息显示最近阅读与读完时间（微信读书同步会写入这两个时间点） |
| **排版** | 纸 / 纯白 / 羊皮 / 夜间 / 纯黑 5 套内置主题，自定义主题保存整份排版快照；正文字号、行距、段距、字距、字重、对齐、首行缩进；标题级别样式；精排开关（切换后按书内 CSS 使用原本的字号 / 行高 / 对齐 / 缩进 / 段距 / 粗斜体；不还原内嵌字体与文字颜色）；自定义字体（TTF / OTF / TTC）；自定义背景图 |
| **标注** | 长按选字弹出「复制 / 划线 / 高亮 / 笔记 / 从此听」；划线为下划线、高亮为底色；点已有标注可改色、复制、擦除、添加笔记；添加书签时可写备注；标注抽屉支持按章节 / 颜色分组并按高亮 / 划线筛选；对不上原文的标注归入「未定位」，**长按**可自动查询定位或手动定位；选中正文后菜单可多出「定位」，直接把这段文字设成某条未定位笔记的位置；四色划线、书签；标注导出 Markdown |
| **检索** | 全书 FTS5 trigram（中文可用），不足 3 字自动降级 LIKE，命中片段高亮并跳回正文命中位置 |
| **朗读** | 系统 TTS（离线）、句级跟读高亮、自动翻页与续章、0.5–2.0 倍速、可选择系统朗读引擎（小米设备可切「小米 MiMo」）与对应中文音色、5 / 15 / 30 / 60 分钟定时停止 |
| **同步** | 本地桶或阿里云 OSS（S3 兼容）；操作日志 + 书籍分片 + 封面 + 字体 + 背景图；HLC LWW + 最远进度合并；拉取走修改时间水位线，只下变化的对象；新设备按需下载书源 |
| **微信读书（实验性）** | 设置 → 实验性功能进入；右上角头像按钮**扫码登录**（微信确认，可保存二维码到相册后用微信「扫一扫 → 相册」识别；需要 4 位验证码时在弹窗里输入），登录后自动配置官方 API Key，不再手填 Key；可退出登录 / 重新扫码。登录后拉取微信读书书架、阅读进度 / 时长与划线想法，逐本与本机书籍对比「新增 / 更新 / 一致 / 删除」，可单本或全部同步进度、阅读状态与能定位到原文的划线；本地没有正文的书可「导入」：自动生成一本只含书名、作者、封面与简介的占位 EPUB（正文为书名页），不下载微信读书正文；抓取结果会缓存，再次进入先展示上次结果，点刷新才联网；每本书可单独查看划线 / 想法（本机没有这本书也能看）；能定位到原文的划线会导入本机标注，找不到原文的按章首保留；累计阅读时长会写入本机统计（只补差额，重复同步不累加；本机更晚也补），书籍信息里的「阅读时间」竖排逐日列表能看到；进度 / 划线想法 / 书评按各自编辑时间取最新，本机更新时不会被微信读书旧数据覆盖；同步是单向导入，微信读书没有的本机数据会保留；从划线/想法跳转默认不改阅读进度，右下角可选「返回原位置」或「设为阅读进度」 |
| **数据与书评** | 设置 → 数据 →「导出阅读数据」：先勾选要导出的书籍（默认全选），把书架书籍信息 / 进度 / 划线笔记 / 书签 / 累计与每日阅读时长导出为 JSON 文件，可保存或系统分享；书籍长按「导出阅读数据」只导出这一本，长按「导入阅读数据」从导出的 JSON 里按书名找到这本书合并进度 / 笔记 / 书签 / 阅读时长（本地进度更高不回退、重复导入幂等）；「导入 Reeden 数据」：新书生成占位 EPUB，已有书按书名 + 作者合并，补阅读状态 / 进度 / 划线笔记 / 书评 / 每日时长，重复导入幂等；设置 → 管理 →「我的书评」按书评 / 星级 / 日期 / 封面查看与搜索，点卡片进书籍详情 |
| **统计** | 日 / 周 / 月 / 年周期切换与前后翻期、点日期跳转；时长、字数、会话、书籍数；24 小时 / 7 天 / 当月 / 12 月分布；按书阅读明细；每日目标、累计与连续天数 |
| **外观与数据** | 亮 / 暗 / 跟随系统；6 种主题色；标签库、分类管理；缓存中心（书籍 / 字体 / 背景，只清本地，云端可再拉回） |

## 下载

| 平台 | 产物 | 说明 |
|---|---|---|
| Android | `qyreader/QYReader-v2.60.0-20261117-native-refined-typesetting.apk` | 33.9 MB，已用 `qyreader-release.jks` 正式签名，可直接侧载 |
| Windows x64 | `qyreader/QYReader-v2.45.0-20261113-windows-x64.zip` | 15.2 MB，解压后运行 `qy_reader.exe`，`data/` 目录必须一起保留 |

> `qyreader/` 是本地产物归档（已被 `.gitignore` 排除），只增不改；更早的版本也放在这里。

- Android：允许「安装未知来源应用」后安装；覆盖升级需使用同一签名。
- Windows：书库位于 `我的文档\QYReader`（`books/`、`covers/`、`backgrounds/`、`fonts/`），
  数据库与偏好位于 `%APPDATA%\com.qyreader\qy_reader`。

## 构建

环境：Flutter **3.32.0** / Dart **3.8.0**，Android SDK 36+，Windows 桌面版还需要 `nuget.exe` 在 `PATH` 中。

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # 改了 drift / freezed 注解后必跑
flutter analyze                                            # 要求 0 issues
flutter test                                               # 全绿（当前 519 项）
flutter build apk --release                                # build/app/outputs/flutter-apk/app-release.apk
```

```powershell
# Windows 桌面版（flutter_tts 的 Windows 插件需要 nuget.exe）
$env:PATH = "$PWD\tools\nuget;" + $env:PATH
flutter build windows --release
# 整个 Release 目录一起打包，缺 data/ 会白屏
Compress-Archive -Path "build\windows\x64\runner\Release\*" `
  -DestinationPath "qyreader\QYReader-v<版本>-<yyyyMMdd>-windows-x64.zip"
```

### 签名

- 密钥：`android/qyreader-release.jks`（alias `qyreader`），密码在 `android/key.properties`；
  两者都已被 `.gitignore` 排除，**请自行备份**，丢失后无法覆盖升级。
- 缺少 `key.properties` 时自动回退 debug 签名，仍可侧载调试。
- 校验签名：`apksigner verify --print-certs build\app\outputs\flutter-apk\app-release.apk`。

## 同步

入口：**设置 → 数据 → 同步设置 → 存储**。

1. 选「本地桶」或「阿里云 OSS」。
2. OSS 填端点、桶名、对象前缀（建议 `qyreader/`）、AccessKey / SecretKey；
   区域形如 `oss-cn-hangzhou`。**OSS / R2 必须关闭路径风格**（走 `桶名.端点`），
   本项目在 OSS 配置下自动使用虚拟主机风格。
3. 密钥只存 `flutter_secure_storage`，不写库、不落偏好文件。
4. 多台设备配置**相同的桶 + 前缀 + 空间**即共享同一同步空间。

同步协议：

- 本地每次写入在同事务追加 `sync_ops`；推送未上传操作到
  `spaces/<空间>/ops/<opId>.json`。
- 书源按 SHA-256 内容寻址：`spaces/<空间>/books/<sha>.epub`；封面按书 id：
  `spaces/<空间>/covers/<bookId>.jpg`；阅读数据按书分片；字体与背景图各带 `manifest.json`。
- 拉取按 `opId` 幂等去重，对象按服务端修改时间水位线增量下载；实体按 HLC LWW 合并，
  阅读进度取最远百分比。
- 删除书籍时上传墓碑并清理云端书源 / 封面 / 分片；只清本地缓存则保留云端备份。

> 同步没有端到端加密（设计预留 AES-GCM + Argon2id，尚未实现）；凭据只保护在系统安全存储里。

## 数据与备份

| 内容 | 位置 |
|---|---|
| 数据库 | `%APPDATA%\com.qyreader\qy_reader\qy_reader.sqlite3`（Windows）／应用私有目录（Android） |
| 书源、封面、背景、字体 | `我的文档\QYReader\`（Windows）／应用支持目录（Android） |
| 排版、书架、主题等偏好 | `shared_preferences` |
| 同步凭据 | 系统安全存储（Keychain / Keystore / DPAPI） |
| 构建产物归档 | `qyreader/`（本地，不入库） |

整库备份 = 复制数据库 + `QYReader` 目录；恢复时保持两者版本一致。

## 架构

```
lib/
  app/            主题、路由、Riverpod providers、启动、页面转场
  core/           HLC 时钟、Locator、drift 数据库与 DAO、通用组件
  data/           仓储实现、EPUB/AZW3/TXT 解析、封面压缩、对象存储（本地 / S3）
  domain/         实体与仓储接口（页面层不依赖 data / core-db）
  features/
    home/         首页概览、底部导航壳
    home_widgets/ 桌面组件 JSON 快照 / 原生通道 / 点击导航
    shelf/        书架、导入、搜索筛选、分类标签、同步面板、批量操作、导入记录
    reader/       原生排版阅读器、划线标注、书签、TTS、全书检索、排版面板
    stats/        阅读统计（fl_chart）
    settings/     设置、阅读主题、字体 / 背景 / 缓存 / 分类管理
    tags/         标签库、标签管理、标签选择器
assets/reader/    旧 WebView + epub.js 渲染链（当前已旁路，仅保留）
assets/sounds/    翻页音效
android/app/src/main/kotlin/com/qyreader/qy_reader/widgets/  三个桌面组件（RemoteViews）
test/             单元与组件测试（519 项）
integration_test/ 翻页 / 阅读性能测试
docs/             截图与历史变更记录
qyreader/         APK / Windows 包归档（本地）
```

分层约定：`features` 只通过 Riverpod provider 拿 `domain` 接口；实现放在 `data`；
页面层不直接访问 DAO 或数据库。

## 数据库

schema **v5**，迁移只做增量 `addColumn`，不删表重建：

`books`（含 `rating` / `review` / `tags` / `pinned_at` / `category` / `read_status`）·
`chapters` · `reading_progress` · `annotations` · `bookmarks` · `reading_sessions` ·
`daily_stats` · `sync_ops` · `sync_state`，以及可重建的派生表
`book_fts`（FTS5 trigram，全书检索用）。

## 已知限制

- **PDF 暂不支持导入**：解析链覆盖 EPUB / AZW3 / MOBI / TXT / Markdown（`BookFormat.pdf` 为预留值）。AZW3 / MOBI 只支持无 DRM 文件，导入时会转成 EPUB 存入库；DRM 文件会提示「受 DRM 保护，暂不支持导入」。
- **iOS**：未在本机验证构建；后台朗读不支持。
- **同步冲突**：同实体并发按整行 HLC LWW，没有字段级合并；无端到端加密。
- **统计口径**：字数按翻页进度增量 × 全书字数估算，全书页数按当前章速度推算，均为约数；
  阅读会话只统计前台时长。阅读时长（会话明细）已参与同步（v2.46.0）：
  多设备合并后当日 / 累计时长是各设备会话之和，跨午夜会话整段算起始日所在时区日。
- **旧 WebView 链路**：`assets/reader/` 与桥接代码仍在库里，但阅读器只走原生排版。
- **桌面组件**：仅 Android；数据来自 App 最近一次推送，进程被杀后组件仍显示上次快照
  （今日组件跨零点会归零）。导入记录只存在本机 prefs，不参与云同步。
- **依赖锁定**：`fl_chart` 锁 **0.69.2**（1.x 与 Flutter 3.32 的 `vector_math` 冲突）。

## 更新日志

- [`docs/changelog-20261111.md`](docs/changelog-20261111.md)（2.10.1 – 2.20.5）
- [`docs/changelog-20261112.md`](docs/changelog-20261112.md)（2.21.1 – 2.33.1）
- 最新版本与逐条改动见 [`AGENTS.md`](AGENTS.md) §8。

## 开发说明

面向 AI 编码代理与人类协作者的作业规范（版本递增、门禁、构建、产物命名、已知坑）
统一维护在 [`AGENTS.md`](AGENTS.md)：改代码跑 `flutter analyze` + `flutter test`，
按改动性质递增版本号，产物归档到 `qyreader/`。
