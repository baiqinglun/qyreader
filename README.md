# QYReader

本地优先的跨平台阅读器（v1，Android 验收）。书架 / EPUB 阅读 / 4 色标注 / 全书检索 /
TTS 朗读 / 多设备同步 / 阅读统计，数据以 SQLite 为唯一真相源，离线可用。

## 功能（v1）

| 模块 | 能力 |
|---|---|
| 书架 | EPUB 导入（内容寻址去重）、封面、进度条、空态；**三种展示形式**（平铺网格 / 列表一行一本 / 纯封面，右上角菜单切换并记住）、**书籍分类**（信息面板设置；分类卡与未分类的书排在同一套网格里，分类在前、手机一行 3 个，点分类卡进去看该分类的书）、**书名搜索**（标题栏下方常驻搜索框，命中就压平只摆书）、**彩色胶囊标签**（同名标签全 App 同色，明暗主题自适应）；**最近在读竖排书架**（按最近打开排序，可收起/展开，默认显示）；打开/退出书籍有封面展开与收回动画；个人评分 / 书评 / 标签、书架置顶（长按或卡片右上角编辑） |
| 阅读器 | 原生排版、5 种翻页方式（滑动 / 覆盖 / 淡入 / 仿真 / 无）+ **翻页音效**（书页 / 薄书 / 厚书 / 无）、4 色划线、正文 HUD（目录/进度/排版/朗读，主题在排版面板首个页签）、四向独立边距（拖动实时预览，松手重排回原句）、**精排开关**（关＝统一字号行距；开＝保留书籍原样式）、**自定义字体**（导入 TTF/OTF/TTC，排版面板与设置页均可管理）、**标题识别**（h1–h6/标题类段落单独排版）、正文/标题分组排版（行距/段距/字距/字重/对齐/缩进）、页眉页脚（时间/章节名/进度/电量）、单双页、章内页码 + 全书估算页（标「约」）、章节末下一章卡片 / 读完卡片、沉浸式 + 常亮、首次操作引导 |
| 标注 | 长按选字 → 4 色划线、笔记、复制；点划线改色/编辑/删除；书签；抽屉「目录/书签/标注」三页；标注导出 Markdown |
| 检索 | 全书 FTS5 trigram（中文），<3 字自动降级 LIKE，命中片段高亮并跳转 |
| 朗读 | 系统 TTS（离线）、句级跟读高亮、自动翻页与续章、0.5–2.0 倍速、中文音色选择、5/15/30/60 分钟定时停止 |
| 同步 | 操作日志复制（书籍文件 + 进度 + 标注 + 书签），LWW + 最远进度 max；后端可选本地桶或 S3 兼容存储（AWS/R2/B2/MinIO）；幂等重放 |
| 统计 | 日/周/月/年周期切换与前后翻期；周期时长 / 字数 / 会话 / 书籍数、24 小时 / 7 天 / 当月 / 12 月分布、按书阅读内容明细；今日目标、累计与连续天数 |

## 构建

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze          # 要求 0 issues
flutter test             # 全绿
flutter build apk --release
```

产物：`build/app/outputs/flutter-apk/app-release.apk`。

### 正式签名

- 密钥：`android/qyreader-release.jks`（alias `qyreader`），密码在
  `android/key.properties`；两者都已被 `.gitignore` 排除，**请自行备份**，丢失后
  无法覆盖升级安装。
- 缺少 `key.properties` 时自动退回 debug 签名（仍可侧载调试）。
- 查看当前 APK 签名：
  `apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk`

### 依赖版本注意

- `fl_chart` 锁 **0.69.2**：1.x 需要 vector_math 2.2，Flutter 3.32 锁 2.1.4。
- `flutter_tts` 要求 `minSdk >= 24`（已配置）；minSdk≥23 时 AGP 默认不压缩 .so，
  本项目用 `packaging { jniLibs { useLegacyPackaging = true } }` 维持 ~27MB。

## 同步配置

1. 书架 → 云图标 → 齿轮「存储设置」。
2. 选「本地桶」（默认，离线可用）或「S3」：
   - 端点（域名/IP，不含协议）、桶名、对象前缀（建议 `qyreader/`，用于限定授权）、
     区域（AWS 必填）、端口、HTTPS 开关、AccessKey/SecretKey。
   - 密钥存 `flutter_secure_storage`（系统安全存储），不入库、不写偏好文件。
   - 「测试连接」校验桶存在与读权限。
3. 多台设备配置**相同的桶 + 前缀**即共享同一同步空间。

同步协议：本地每次写同事务追加 `sync_ops`；推送未上传操作到
`<prefix>/spaces/<空间>/ops/<opId>.json`，书籍文件按 sha256 存
`<prefix>/spaces/<空间>/books/<sha>.epub`；拉取按 `opId` 幂等去重，实体按
HLC LWW 合并（进度最远百分比取 max）。

## 已知限制

- **Windows 桌面阅读器禁用**：`flutter_inappwebview_windows` 0.6.0 beta 有合成
  缺陷；待插件稳定后再评估（记入后续版本）。
- **iOS 后台朗读**不支持；`Info.plist` 已配显示名，但本机无 macOS 未验证构建。
- **仿真翻页**是透视折叠近似（WebView 无截图能力，非真纸张卷曲像素）。翻页手势
  在 reader.html 内逐帧上报（HC 模式下 Flutter 收不到触摸），已实现跟手拖拽与
  连续翻页；目标页未就绪时用同尺寸骨架占位，动画不等待异步同步。
- 同步：无端到端加密（设计预留 AES-GCM + Argon2id，未实现）；封面不同步；
  同实体并发按 HLC 整行 LWW，无字段级合并（旧版本客户端回写书籍时可能覆盖
  新版的评分/书评/标签/置顶字段）。
- 阅读字数按页级位置增量 × 全书字数估算，非精确逐字统计。
- 统计：会话 = 前台连续时间，<10s 丢弃；切后台即结算。统计只统计本机
  阅读会话（会话明细不参与同步，多设备总量不合并）。
- 阅读器 `chapterIndex+offset` 字符偏移兜底未实现（降级链为 CFI → pos → 章起始）。

## 诊断

- 阅读器顶栏 🐛 打开诊断面板；`adb logcat | grep reader-diag` 查看全链路打点。
- 看门狗：桥 8s / 书籍渲染 45s 未就绪时自动展示诊断。
- debug 构建启用 WebView 远程调试：
  `adb forward tcp:9222 localabstract:webview_devtools_remote_<pid>`，配合
  `tools/devtools_eval.dart` 可在页面内求值（含 iframe 穿透）。

## 目录

```
lib/
  app/            主题、路由、providers
  core/           HLC、Locator、drift 数据库与 DAO
  data/           仓储实现、EPUB 解析、对象存储（local/S3）
  domain/         实体与仓储接口（页面层不依赖 data/core-db）
  features/
    shelf/        书架、导入、同步面板与存储设置
    reader/       阅读器（池化 WebView、桥、标注、TTS）、检索页
    stats/        阅读统计
assets/reader/    reader.html + epub.js/jszip（内联注入）
tools/            诊断脚本（vm_dump / devtools_eval）
```

## 数据库

schema v3：books（含 rating / review / tags / pinned_at 个人化字段）/
chapters / reading_progress / annotations / bookmarks / reading_sessions /
daily_stats / sync_ops / sync_state + `book_fts`（FTS5 trigram 虚拟表，
派生数据可重建）。迁移纪律：按版本增量迁移，不删表重建。
