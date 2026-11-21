# AGENTS.md · QYReader

> 给 AI 编码代理（以及人类协作者）的项目作业说明书。
> **每轮对话结束前必须更新本文件**：刷新 §2「当前状态」，并在 §8「对话变更记录」追加一行。

最后更新：2026-11-20

## 1. 项目速览

| 项 | 值 |
|---|---|
| 应用 | QYReader —— 本地优先的跨平台阅读器，Android 为验收平台 |
| 技术栈 | Flutter / Dart 3.8+、Riverpod 2、drift(SQLite)、go_router、freezed |
| 包名 / 显示名 | `com.qyreader.qy_reader` / `QYReader` |
| 当前版本 | `2.78.0+224`（versionName 2.78.0 / versionCode 224），定义在 `pubspec.yaml` |
| 数据库 | SQLite（drift），schema **v6**，唯一真相源，离线可用 |
| 工作区 | `D:\Github\QYReader` |
| 仓库 | 未初始化 git；`qyreader/`、`tools/`、`.zcode/` 已被 `.gitignore` 排除 |

功能面：书架（导入 / 分类 / 标签 / 最近在读）、EPUB 阅读器（Flutter 原生排版）、
4 色划线笔记、全书检索（FTS5 trigram）、TTS 朗读、S3/本地桶同步、阅读统计。
详细能力清单与真机截图见 `README.md`。

## 2. 当前状态

- 2026-11-21：已编译并打包 v2.78.0 Windows x64 发布版，压缩包包含可执行文件、Flutter DLL 和资源；仅文档更新，未递增版本。

- 2026-11-20：整理近期版本更新说明，覆盖更新检查、选区翻页、首页推荐与无动画翻页；仅文档更新，版本不变。

- 2026-11-20（v2.78.0+224）：设置页新增 Android OSS 检查更新，读取 mtl-updates 桶 qyreader_latest.json；支持版本比较、直链下载及系统安装、网盘提取码复制与失败备用入口。真实清单目前 versionCode 23，低于本版，真机下载与安装待验收；analyze 通过、749 项测试通过、APK 已构建。

- 2026-11-20：用户要求接入阿里 OSS 更新检查及下载；桶根路径 latest.json 实测返回 404，更新功能尚未实现，清单实际路径待确认。

- 2026-11-20（v2.77.3+223）：切回首页时保留上次书籍推荐，手动刷新仍重新获取；analyze 通过、746 项测试通过，发布 APK 已构建。

- 2026-11-20（v2.77.2+222）：原生正文选区由阅读视口管理，手柄拖到页边停留约 0.4 秒会自动换页，仍可继续拖动。支持双页回翻和跨章选字，同章划线保留一条，跨章按章落库。独立「跨页」面板已移除。静态检查通过，745 项测试通过，发布 APK 签名与上一版一致，Android 真机待验收。

- 2026-11-20：用户要求重新设计分页，实现拖动选区到末尾自动翻页；已检查偏移、命中及标注接口，功能尚未实现。

- 2026-11-20：继续检查拖动选区手柄自动翻页；现有手柄绑定单页控件，标注范围按单章保存，尚无可靠实现，代码未修改。

- 2026-11-20：用户确认需要正文拖动选区手柄时自动翻页，不使用独立跨页选择面板；单页 SelectableText 的手柄在页面更换时无法延续，本轮尚未实现。

- 2026-11-20：用户明确不要独立的跨页选择；正在确认是划线后翻页还是拖动手柄时翻页，尚未修改代码。

- 2026-11-20：排查正文选区跨页拖动；正文按页分离选区且选中时禁用滚动，现有跨页选择使用独立整章面板，直接拖动跨页尚未修复。

- 2026-11-20（v2.77.1+221）：修复翻页效果「无」时横滑仍有滑动动画；松手后立即切页，analyze 通过、745 项测试通过，发布 APK 已构建，真机待验收。

- 2026-11-20：已检查阅读器翻页相关实现和测试；具体故障及复现步骤待用户提供，尚未修改代码。

- 2026-11-20（v2.77.0+220）：书架顶部支持按分类、标签、评分或阅读状态自动生成页签；书架固定左侧，右侧展开切换页签和分组，保留自定义视图；analyze 通过、745 项测试通过，发布包已构建，真机待验收。

- 2026-11-20（v2.76.1+219）：推荐详情简介并入基本信息，阅读按钮优先尝试打开微信读书应用，失败时使用阅读网页；analyze 通过、744 项测试通过，发布包已构建；真机唤起及网页回退待验收。

- 2026-11-20（v2.76.0+218）：推荐详情新增目录及微信读书阅读入口；目录与阅读链接取自官方接口，真机跳转待验收。flutter analyze 通过、744 项测试通过，发布 APK 已构建。

- 2026-11-20（v2.75.1+217）：修复 EPUB 多目录章节共用同一 HTML 路径时，续读只按 href 命中第一章；现在优先核对已存章索引与 href。已用下载目录《老实人启蒙.epub》实际解析验证重复路径章节定位，analyze 通过、744 项测试通过，真机复开流程待验收。

- 2026-11-20（v2.75.0+216）：书籍长按及书架多选新增「分享书籍」；可保存单本源文件或将多本打包 ZIP 保存，也可通过系统分享多个书源。缺失的本地文件尝试从同步库下载；Kindle 导入时转换后的 EPUB 是实际导出文件。`flutter analyze` 通过，743 项测试通过；Android 系统保存及分享流程待真机验收。

- 2026-11-20（v2.74.0+215）：书架新增「自定义」视图，保存分类、标签、最低评分与阅读状态筛选；长按书籍可添加/取消收藏，收藏卡位于首屏分类最前且保留原分类。收藏写数据库并参与同步，旧设备未带字段时保留本地收藏；schema v7 增量迁移。`flutter analyze` 通过、741 项测试通过，真机待验收。

- 2026-11-20：用户再次要求书架自定义筛选视图与收藏；收藏作为最前方独立分类卡、保留原分类。已核对 v6 数据库与书籍 LWW 同步路径，功能尚未实现。MOBI 导入失败仍需具体错误与文件。

- 2026-11-20：用户反馈 MOBI 显示导入失败；现有公版 MOBI 回归通过，具体错误需从书架「更多 → 导入记录」或失败文件定位。此前收藏分类卡与自定义视图需求仍待实现。

- 2026-11-20（v2.73.4+214）：修复原生阅读器首次分页未应用已保存的章内偏移，增加恢复偏移的组件回归；analyze 通过、734 项测试通过，真机待验收。MOBI 失败/解析错误仍需问题文件或错误信息，收藏和自定义书架视图尚未实现。

- 2026-11-20：新增自定义筛选视图及收藏需求待实现；用户确认收藏应作为书架最前方的独立分类卡，书籍保留原分类。收藏需独立于置顶并纳入数据库迁移及同步。

- 2026-11-20（v2.73.3+213）：主框架仅在页面返回时刷新，关闭推荐详情等普通弹窗不再重建首页，保持滚动位置；阅读页仍独立观察弹窗以暂停计时。analyze 通过、733 项测试通过。

- 2026-11-20（v2.73.2+212）：推荐详情的热门划线与热门书评按条展示并用分隔线区分；flutter analyze 通过，732 项测试通过。

- 2026-11-20（v2.73.1+211）：重新设计推荐书籍详情弹窗，封面、书籍概览及四页签；展示微信实际返回的在读/读完人数、字数、分类标签和评分标签，缺失字段不臆造；刷新时显示 loading。`flutter analyze` 通过、732 项测试通过；真机及微信接口字段需实测。

- 2026-11-20（v2.73.0+210）：四个底栏页面增加各自滚动位置存储；首页右上角「管理首页卡片」支持显隐及拖动排序，默认推荐在今日目标之前。推荐详情包含基本信息、简介、热门划线及热门书评页签；基于微信读书接口，真机与账号网络响应待验收。`flutter analyze` 通过、730 项测试通过。

- 2026-11-20（v2.72.1+209）：微信读书接口版本更新至 1.0.6；`upgrade_info` 不再阻断成功数据，真实错误仍提示，客户端可选回调接收升级通知。`flutter analyze` 通过，`flutter test` 729 项通过；真实微信账号需实测。

- 2026-11-20（v2.72.0+208）：首页新增微信读书「书籍推荐」卡片，已登录时请求个性化推荐，可刷新并查看作者、推荐理由与简介；未登录可进入微信读书页。`flutter analyze` 无问题，`flutter test` 728 项通过；真实账号及真机仍需验收。

- 2026-11-19（v2.71.4+207）：点击书架搜索框外部时解除焦点，同时保留原有点击操作；`flutter analyze` 0 issues，`flutter test` 726 项通过，发布版 APK 已构建。

- 2026-11-19：用户提供 Reeden 导入界面截图，确认其扫码后支持逐书逐日时长；尚未查明对应接口，本机未发现 Reeden 安装目录，功能未实现。

- 2026-11-19：核实 Reeden 文档称额外扫码登录后可获取逐书逐日时长；其具体接口未公开，QYReader 当前只保存官方 API Key，扫码会话未持久化。

- 2026-11-19：微信读书逐书逐日阅读时长尚未实现。官方 Agent API 文档仅明确单书累计时长和全账户按日汇总，当前同步把累计差额记在最后阅读日，不能视作真实逐日明细；Reeden JSON 导入可导入其逐日记录。需核实可用的逐书逐日接口与扫码会话后才能实现。

- 2026-11-19（v2.71.3+206）：设置页列表项及书籍长按操作菜单去掉说明副标题，保留操作入口；flutter analyze 无问题、725 项测试通过，APK 已构建。

- 2026-11-19（v2.71.2+205）：分类卡书位与边框留出 6dp 间距，空白书占位符左侧竖条使用明确高度；卡片外部尺寸不变。flutter analyze 通过、flutter test 725 项通过，APK 已构建。

- 2026-11-19（v2.71.1+204）：书架按分类路径逐级显示分类和书籍，包含空分类，支持返回上一级、分类长按或菜单管理及新建子分类；分类卡显示后代书数，默认网格显示名称且不画架板。阅读器「更多 → 键盘与鼠标翻页」可自定义上一页/下一页按键并启用或关闭鼠标滚轮翻页；滚动阅读模式保留滚轮滚动。真机及桌面交互仍需验收。
- 门禁：flutter analyze 0 issues，flutter test 725 项通过；APK：`qyreader/QYReader-v2.71.1-20261119-nested-shelf-input.apk`。

- 2026-11-19：书架已初步按已有书籍分类路径逐级展示，返回上一级；空分类、参考图布局、可自定义键盘快捷键与鼠标翻页尚未完成。版本 2.71.0+203，analyze 通过，723 项测试通过，APK 已构建（未完成版）。

- 2026-11-19 已检查书架参考图与嵌套分类需求：分类管理已有路径树，但书架仍按完整路径平铺；布局和逐级导航尚未实现。

- 书架滚动优化（v2.70.2）：移除书格重复入场动画，减少滚动时透明度合成和重绘；真机帧率待验收。

- 覆盖导入书源同步修复：更新书源哈希、大小、格式和目录，首次同步扫描分片修复已合并但仍保留旧书源的记录；按需下载仍需云端书源存在。

- 应用版本：2.78.0+224 
- Windows 桌面版：`qyreader/QYReader-v2.78.0-20261121-windows-x64.zip`（解压后运行 `qy_reader.exe`）
- 数据库 schema：v7（books 增加 is_favorite）
- 门禁：`flutter analyze` 0 issues、`flutter test` 749 项全绿（2026-11-20 验证）
- 最近一次构建：`qyreader/QYReader-v2.78.0-20261120-oss-update.apk`
- **作者管理（v2.70.0）**：设置 → 管理 →「作者管理」；书架的书按作者归组——未知作者组排最前（带「点击查看并补全」提示，点开书籍详情可补作者），其余按书数降序；卡片左侧 2×2 封面预览 + 本数，支持按作者名 / 书名搜索；点作者卡看名下全部书籍（显示阅读状态与进度，点书进书籍详情），菜单「重命名作者」可批量改组内全部书籍的作者名（清空 = 未知作者），详见 §7
- **分类卡与书卡同尺寸（v2.69.2）**：`CategoryCard` 去掉 Card 默认 margin 与 8px 内边距，2×2 书位铺满整个格子——网格里分类卡与书封面视觉尺寸完全一致（分类名 / 书名行高不变）
- **网格显示名称：分类也显示（v2.69.1）**：网格「显示名称」打开时分类格与书格一样显示分类名（单行居中，与书名同一字号），不再只是预留空白
- **阅读数据按书导出 / 导入（v2.69.0）**：设置 → 数据「导出阅读数据」先弹书籍选择（默认全选，可全不选）；书籍长按新增「导出阅读数据」（只导这本）与「导入阅读数据」（选 JSON，按书名找到这本书合并），详见 §7
- **网格显示书名（v2.68.0）**：书架设置 → 网格页新增「显示名称」开关（`ShelfPrefs.showGridTitle`，prefs `shelf.grid.showTitle`，默认关）；打开后网格封面下方显示单行书名，行高 +28px，分类格同步预留高度；纯封面模式不受影响
- **重复书籍整理（v2.67.0）**：设置 → 管理 →「重复书籍整理」；按书名强匹配 / 疑似匹配或文件 SHA-256 检测；匹配范围全部 / 强 / 疑似，可只匹配同作者；按阅读状态 / 分类筛选；分组显示封面、大小、字数、加入时间、分类与来源文件，支持忽略、勾选批量删除（每组至少保留一本）和逐本删除
- **AZW3 / MOBI 导入（v2.66.0）**：书架导入与「覆盖导入」都支持 `.azw3` / `.mobi`（无 DRM）——用 `kindle_unpack` 转成 EPUB 后落盘、解析章节/封面/元数据；受 DRM 保护的文件返回 `import.kindle_drm`，不静默导入乱码。转换在 isolate 里跑，ZIP 时间戳归一化保证同一文件重复导入仍按内容去重
- **导出阅读数据 JSON（v2.64.0）**：设置 → 数据 →「导出阅读数据」生成 `qyreader-reading-data` JSON（书籍信息 / 进度 / 标注 / 书签 / 累计与每日阅读时长），写应用文档 `exports/` 并可系统分享；不含书源、封面、本机路径与设备信息
- **未定位标注 UX 调整（v2.63.1）**：标注列表不再在行尾挤第三个定位按钮——**长按未定位笔记**弹「自动查询定位 / 手动定位」；长按选中正文后选区菜单多一个「定位」，可直接把这段文字设成某条未定位笔记的位置；全书搜索结果点击后按命中章 + 章内偏移跳转（原生阅读面此前只跳章首/无反应）
- **未定位标注可手动 / 自动定位（v2.63.0）**：标注列表把对不上原文的标注归入「未定位」，行内显示「未定位」角标；可「自动查询定位」（原文搜索并跳转）或「手动定位」（翻到目标页后点「设为当前页」）。手动锚点带 `manual:true`，不再按原文校验
- **覆盖导入 + 笔记重定位（v2.62.0）**：书架长按 →「覆盖导入」用新 EPUB/TXT 替换已有书正文（保留 id / 书名 / 作者 / 封面 / 进度 / 笔记 / 统计）；导入后若有带原文的笔记，弹窗问是否匹配位置，先完整原文搜、再逐字缩短继续匹配，详见 §7
- **Reeden 数据导入 + 我的书评（v2.61.0）**：设置 → 数据 →「导入 Reeden 数据」选 JSON；映射见 §7；设置 → 管理 →「我的书评」列表页（书评 / 评分 / 日期 / 封面 / 搜索，点卡片进书籍详情）
- **今年读完修复（v2.60.3）**：① `finishedThisYear` 优先用 `finishedAt` 判断年份（微信读书导入的书 `updatedAt` 会被同步刷新到今天，2024 读完的书原来会混进「今年读完」；旧数据没有 `finishedAt` 时才退回 `updatedAt` 近似）；② 首页卡片与完整页的封面 `Wrap` 外面加 `SizedBox(width: double.infinity)` 撑满宽度——Wrap 在 Column 里会收缩到内容宽度，`WrapAlignment.center` 随之失效（整行贴左、右侧留白），撑满后各行（含不足整行的末行）才真正居中。**别删这个 SizedBox**
- **分类返回记住首屏位置（v2.60.2）**：`ShelfPage` 持有书架滚动控制器 `_shelfScroll` 并传给 `_BookShelf`，`ref.listen(shelfCategoryFilterProvider)` 监听筛选切换——进分类记住首屏 offset（分类页从顶部开始），返回首屏同帧 `jumpTo` 回进入前的位置（无闪烁）；配合 v2.60.1 的一次返回手势修复，分类进出完整流畅
- **返回手势修复（v2.60.1）**：manifest 显式 `android:enableOnBackInvokedCallback="false"` 关闭预测性返回——targetSdk 35 在 Android 15+ 默认开启预测性返回，系统在手势开始瞬间抢先播「回桌面」预览动画并吞掉事件，书架分类这类 PopScope 页内层级要按两次返回才生效；关掉后走传统按键分发（手势结束才派发），一次返回必定触发 PopScope 回调。本应用未实现任何预测性返回动画，Android 14 及以下行为不变
- **原生精排**：设置 → 排版（Aa）→ 精排开关；开启后 EPUB 解析阶段会解析书内 CSS（`<style>` + OPF 外部样式表 + 内联 style），原生排版按原书字号 / 行高 / 对齐 / 首行缩进 / 段前段后距 / 粗体 / 斜体渲染，并参与分页测量；关闭仍走统一排版
- 首页「今年读完的书」：横向封面流改成自动换行（按屏宽算列数），默认最多 3 行，**封面行与「查看更多」居中**；超出显示「查看更多」，进入 `YearFinishedPage` 完整页（封面 + 书名 + 作者，右上角显示本数，封面网格居中）
- 微信读书改为**扫码登录**：右上角头像按钮打开二维码（微信确认）→ 自动取官方 API Key 存安全存储；支持保存二维码到相册后微信「扫一扫 → 相册」识别、4 位验证码、刷新二维码、退出登录 / 重新扫码；抓取结果缓存，再次进入先展示上次结果；本机没有的书也能查看划线/想法，划线能定位就导入标注、找不到原文按章首保留；累计阅读时长按差额写入本机统计（**本机更晚也补**，不再跳过），书籍信息「阅读时间」改成竖排逐日列表；本地没有的书可导入为只含书名/作者/封面/简介的占位 EPUB；同步后的进度按新位置打开；从划线/想法跳转默认不改阅读进度，右下角可选「返回原位置 / 设为阅读进度」；扫码登录流程需真机验收
- Windows 桌面版：`qyreader/QYReader-v2.70.0-20261118-windows-x64.zip`（约 16.6 MiB，解压后运行 `qy_reader.exe`）
- 文档：`README.md` 已补桌面组件与导入记录；6 张真机截图在 `docs/screenshots/1.jpg` – `6.jpg`
- 已知待办/限制：见 §7 与 `README.md`「已知限制」；**听书页/BGM/MiMo 引擎需真机验收**（音频混音焦点行为因 ROM 而异）；**MiMo 云端合成需真机配 API Key 实测**（模型 ID 文档值 `mimo-v2.5-tts`，若小米下线需改 `kMimoTtsModel`）

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
    home/     首页概览（累计 / 继续阅读 / 今日目标 / 年度）、HomeShell 与四 Tab 底栏
    home_widgets/ 桌面组件 JSON 快照、原生通道、点击导航
    shelf/    书架、导入、分类标签、最近在读、导入记录、同步面板与存储设置
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
- **预测性返回已显式关闭（v2.60.1）**：`AndroidManifest.xml` 的 `<application>` 上有
  `android:enableOnBackInvokedCallback="false"`，**不要删**——targetSdk 35 在 Android 15+
  默认开启预测性返回，系统会在手势开始瞬间抢先播「回桌面」预览动画并吞掉事件，
  书架分类这类 PopScope 页内层级（`ShelfBody` 的 canPop 随筛选翻转）要按两次返回才生效；
  关掉后走传统按键分发，一次返回必定触发 PopScope 回调。本应用没有任何预测性返回动画，
  不需要该 flag 为 true；若将来要接系统预测动画，需同时解决 canPop 原地翻转的注册同步问题。
- **作者管理（v2.70.0）**：设置 → 管理 →「作者管理」
  （`features/settings/authors_page.dart`，路由 `/settings/authors`；
  作者书籍页 `/settings/authors/books`，extra 传作者名，空字符串 = 未知作者）。
  - 纯逻辑在 `author_groups.dart`：`groupBooksByAuthor` 按作者 trim 后精确
    分组（「（美）约翰」和「约翰」算两位，不做括号归并，靠批量重命名手动合并），
    未知作者组（author 空 / 空白）排最前，其余按书数降序、同数按名字排；
    `filterAuthorGroups` 按作者名或组内任一书名命中过滤整组。
  - 列表卡片：左侧 2×2 封面预览（`_AuthorCoverGrid`，取前 4 本，空位灰块；
    **尺寸 getter 必须算上 1px 描边**：`gap*3 + cellW*2 + border*2`，漏掉会
    Row/Column 溢出 2px，flutter test 直接报 RenderFlex overflow）；
    右侧作者名 + 「N 本」；未知作者卡片带「点击查看并补全」说明、不显示菜单。
  - 重命名：卡片「⋯」菜单 → 弹窗预填当前名 → 逐本
    `updateBookMeta(id, author: 新名)`（传空串 = 清空，全部进未知作者组；
    与书籍详情「编辑书名与作者」同一语义），完成后 SnackBar 报本数；
    `shelfItemsProvider` 流自动刷新分组。
  - 作者书籍页：AppBar 显示作者名 + 「共 N 本」；未知作者组顶部有补全提示卡
    （点书进书籍详情补作者），行显示阅读状态与已读百分比。
  - 测试 fake 仓储注意：broadcast 流不缓存无监听期间的事件，fake 要先回放
    当前列表再接后续更新（`watchShelf` 里 `yield _items; yield* _controller.stream`）。
  - 回归：`author_groups_test.dart`（分组/排序/过滤）、`authors_page_test.dart`
    （卡片与未知组、搜索、点卡进书籍页、重命名批量更新、清空）、
    `settings_page_test.dart`（入口）。
- **Reeden 数据导入（v2.61.0）**：`features/settings/reeden_import.dart`（纯解析）+
  `reeden_import_service.dart`（落库）。映射规矩：
  - 新书走 `buildWeReadEpub` 占位 EPUB → `importFromFile`（与微信读书导入同链路）；
    已有书按「书名去书名号/空白 + 作者（双方非空才比）」匹配合并；
  - 个人化字段（评分 / 书评 / 标签 / 分类）只在**本地为空时补**，不覆盖用户自己写的；
    多条书评用空行连接进 `books.review`；4.5 分取整进 `books.rating`；
  - 阅读状态按 `lastReadTime` LWW（本地更晚保留本地），读完时间只前进；
    进度只在本地更低时写 `saveExternalProgress`；
  - 划线按**原文收敛空白**去重（同原文不重复导入）；red→rose、blue/green/yellow 原样，
    `comment` 进想法（setNote 会把类型改成 note，这是仓储语义）；
  - 每日时长走 `recordSession`（会话 + daily_stats 同事务，参与同步）；
    当天已有累计 ≥ 导入值就跳过，**低于 10 秒的天直接算跳过**（会话门槛）；
  - 重复导入整体幂等：书合并不新建、笔记按时长/原文去重、时长按天比较。
  回归：`test/features/settings/reeden_import_test.dart`（解析 + 落库 + 幂等 + 同名合并）。
- **书架覆盖导入 + 笔记重定位（v2.62.0）**：书架长按 →「覆盖导入」用新的
  EPUB/TXT/MD 替换已有书的正文，保留书籍 id、书名/作者/封面、阅读进度、笔记与统计。
  - 仓储：`BookRepository.replaceBookContent(bookId, path)`（实现在
    `book_repository_impl.dart`）。新文件按 `<id>_<sha 前 12 位>.<ext>` 落盘，
    事务提交成功后才删旧文件（失败不会半覆盖）；同一内容直接返回、不重写章节；
    内容已在书架另一本书上仍按 `import.duplicate` 拒绝。只补空的作者/简介/语言，
    不冲掉用户改过的书名。
  - UI：`features/shelf/widgets/overwrite_import_dialog.dart` 的
    `startOverwriteImport`：选文件 → 确认 → 转圈对话框 → 导入 → 按旧百分比
    `saveExternalProgress` 重落进度 → 若书里有带原文的笔记，再弹
    「匹配笔记位置 / 暂不匹配」。长按菜单动作是 `BookShelfAction.overwriteImport`，
    菜单动作区改成 `Flexible + ListView`（矮屏可滚，别改回裸 Column）。
  - 匹配：`features/reader/note_rematch.dart` 的 `NoteLocator` —— 先完整原文
    精确搜索，再忽略空白/标点；找不到就一点点减少两端的字（每次少 1 字、
    最多 24 次，再按 75/50/35/25% 与 16/12/8/6/4 字兜底），每步取中间窗口；
    优先旧 locator 的章（索引越界也继续全书搜）。`planNoteRematch` 只产出
    锚点有变化的更新，`rematchBookNotes` 用
    `AnnotationRepository.setAnchor(..., locatorEnd:)` 同时写起点/终点。
  - 阅读器兜底：`reader_page._nativeMarks` 对没有有效 offset 的旧标注也走
    同一个 `NoteLocator`，打开书就会自动回写（每个标注只写一次）；旧章索引
    失效不再直接跳过。
  - 回归：`test/features/reader/note_rematch_test.dart`（完整/忽略标点/逐字
    缩短/同章优先/越界兜底）、`book_repository_impl_test.dart` 的
    `replaceBookContent` 组（保留个人化、替换章节、重复拒绝、同内容 no-op）、
    `annotation_repository_impl_test.dart` 的 setAnchor 起止点、
    `book_actions_sheet_test.dart`（长按菜单入口）。
- **未定位标注手动 / 自动定位（v2.63.0）**：标注列表（`annotation_tab.dart`）
  新增「未定位」分组与行内角标；`reader_page._unlocatedAnnotationIds()` 用
  `note_rematch.dart:annotationAnchorLocated` 逐条对照锚点处正文与 `quotedText`
  （手动锚点带 `manual:true` 直接视为已定位；自动匹配只对上一段也算已定位）。
  - **长按**未定位笔记（行尾不再放第三个定位按钮）弹底部面板：
    「自动查询定位」用 `NoteLocator` 搜原文，写回 `setAnchor` 后跳过去（沿用
    标注跳转的进度挂起）；「手动定位」收起抽屉，正文继续翻页，底部
    `manual_locate_bar.dart` 的「设为当前页」把当前页首 + 原文长度写成
    `{..., manual:true}` 锚点（`reader_page._confirmManualLocate`）。
  - **长按选中正文 → 选区菜单「定位」**（`SelectionMenu.onLocateNote`，有
    未定位笔记时才出现）：弹出未定位笔记列表，点一条即把当前选区设成它的
    锚点（`reader_page._pickUnlocatedForSelection`），比翻页更精确。
  - **全书搜索结果点击跳转**：`BookSearchHit` 增加 `offset`，FTS 用
    `instr(lower(body), lower(?))`、LIKE 降级用 `indexOf` 算出章内偏移；
    阅读页 `_openSearch` 改为 `_jumpToLocator`（原生面此前 bridge 为 null，
    点搜索结果只跳章首/无反应）。
  - 手动锚点会画在用户选的那一页；因为 `manual:true` 不再做原文校验，列表
    不会又变回「未定位」。回归：`annotation_tab_test.dart`（长按入口 /
    自动 / 手动回调）、`manual_locate_bar_test.dart`、`selection_menu_test.dart`
    （有未定位笔记时的「定位」入口）、`search_repository_impl_test.dart`
    （FTS / LIKE 偏移）、`note_rematch_test.dart` 的 `annotationAnchorLocated` 用例。
- **重复书籍整理（v2.67.0）**：设置 → 管理 →「重复书籍整理」
  （`features/settings/duplicate_books_page.dart`，路由 `/settings/duplicates`）。
  - 纯逻辑在 `duplicate_books.dart`：`normalizeDuplicateTitleStrong` 只去大小写、
    空白和文件扩展名；`normalizeDuplicateTitleLoose` 再去括号内容、卷/册/部/集/版、
    `全N册`、上中下册、版本词和标点。按 **loose key** 聚类：整簇 strong key 相同
    →「强匹配」，否则「疑似匹配」；这样「同名 + 同名（全7册）」只出现一组，不会
    同时出现在两个分组里。
  - 检测类型支持「书名重复」/「文件重复」（同 `fileSha256`）；匹配范围
    全部 / 强 / 疑似；`matchAuthor=true` 时作者归一化（去空白、标点、著/编/译）
    且双方都必须非空。书籍筛选支持阅读状态多选 + 分类单选。
  - 页面：分组卡显示最短书名、忽略按钮、封面、大小（`· 最大`）、字数（`· 最多`）、
    阅读状态、加入时间、分类、来源文件名和简介；`keepCandidate` 按字数 → 文件大小
    → 加入时间选建议保留项。勾选后顶部删除；**批量删除每组至少保留一本**，单本删除
    会二次确认，删除走 `BookRepository.deleteBook(deleteAnnotations: true)`（笔记 /
    书签一起清理）。「忽略」只在页面会话内生效，更多菜单可恢复。
  - 回归：`duplicate_books_test.dart`（强/疑似归一化、作者开关、范围过滤、文件哈希、
    保留建议）、`duplicate_books_page_test.dart`（390px 宽分组渲染、忽略、批量删除
    保护、范围切换）、`settings_page_test.dart`（入口）。
- **AZW3 / MOBI 导入（v2.66.0）**：`BookRepository._parseSourceBytes` 识别
  `.azw3` / `.mobi`，`_convertKindleToEpub` 调 `kindle_unpack` 的
  `KindleBook.fromBytes(bytes).toEpub()` 转成 EPUB，再走现有 EPUB 解析链；
  导入与「覆盖导入」共用。
  - **DRM 检查**：先用 `PdbFile.parse` + `PalmDocHeader.parse(records[0])` 查
    `isEncrypted`，加密文件直接抛 `ImportException('import.kindle_drm',
    'MOBI / AZW3 受 DRM 保护，暂不支持导入')`，不要交给转换器产出乱码。
  - **转换放 isolate**（`Isolate.run`），避免大文件卡 UI；失败统一成
    `import.kindle` 带原因。
  - **ZIP 时间戳归一化**：`KindleBook.toEpub()` 生成的 ZIP 每个条目时间戳是
    「现在」，同一文件隔秒转换会得到不同字节，导致重复导入检测失效。转换后
    走 `_normalizeZipTimestamps`：本地头/中央目录的 DOS 时间固定 1980-01-01，
    并把 0x5455 扩展时间戳清零。**别删这一步**。
  - **落盘**：`_ParsedSource` 带 `storedBytes` / `storedExt`，Kindle 文件落的是
    转换后的 `.epub`（不是原文件）；书籍的 `fileSha256` / `fileSize` 跟
    实际落盘内容一致，同步与章节缓存继续用 fileSha。导入先用原文件哈希查重，
    转换后再按 EPUB 哈希查一次（同一文件重复导入幂等）。
  - 回归：`book_repository_impl_test.dart` 的「MOBI 先转 EPUB 落盘…」
    （真实公版书 fixture `test/fixtures/pg1342.mobi`）、「AZW3 扩展名走同一条
    转换链」与「DRM 加密的 MOBI/AZW3 拒绝导入」（合成最小 PDB 头）。
  - 依赖：`kindle_unpack 0.2.0`（GPL-3.0，仅依赖 archive）。它同时支持
    Mobi-7 与 KF8，但不处理 DRM；若将来要分发闭源安装包，需先评估该许可证。
- **导出阅读数据 JSON（v2.64.0）**：设置 → 数据 →「导出阅读数据」
  （`features/settings/reading_data_export.dart`）。
  - JSON 顶层：`format: qyreader-reading-data` / `version: 1` /
    `exportedAt` + `exportedAtIso` / `dailyGoalMinutes` / `summary` / `books`。
  - 每本书：元数据（书名/作者/系列/简介/格式/章数字数/状态/评分/书评/标签/分类/
    时间戳）、`progress`（当前 + 最远 locator 解析成对象）、`reading`
    （累计 durationMs/charsRead + 按天升序的 `dailyDurations`）、`annotations`
    （type/color/quote/note/locator 对象/时间）、`bookmarks`（label/locator/时间）。
  - **不导出**书源文件、封面文件、`filePath` / `coverPath` / `fileSha256` /
    `deviceId` / HLC（测试里断言了这些 key 不存在）。
  - 写文件：应用文档目录 `exports/QYReader-reading-data-<yyyyMMdd-HHmmss>.json`，
    缩进 JSON；结果对话框显示书/标注/书签/时长统计与路径，可「分享文件」
    （share_plus，MIME application/json）或完成。
  - 纯函数 `buildReadingDataJson` 可单测；回归：
    `test/features/settings/reading_data_export_test.dart`（结构 / 隐私字段 /
    空书架）、`settings_page_test.dart`（入口）。
- **阅读数据按书导出 / 导入（v2.69.0）**：
  - 导出选择范围：`reading_data_export.dart` 的 `showReadingDataBookPicker`
    —— 底部弹层复选框列表（默认全选、可全不选、按钮显示已选 N/M 本），
    `exportReadingDataJson` 先弹选择再导出；`exportBookReadingData(context,
    ref, book)` 只导一本书（长按菜单入口）。
  - 单本导入：`reading_data_import.dart`。`parseReadingDataJson` 校验
    `format: qyreader-reading-data`；`matchReadingDataEntry` 按书名（去书名号/
    空白）+ 作者（双方非空才比）找目标条目。落库规则：
    - 进度只在本地更低时写 `saveProgress`（locator 从 JSON 原样还原，
      重新打开能回到原位置）；
    - 划线按原文收敛空白去重，`addHighlight` 重建 `@ci:start:end` cfiRange
      + 章索引/偏移（缺 chapterIndex/offset 的损坏锚点跳过），note 走
      `setNote`；
    - 书签按 locator JSON 原文去重后 `addBookmark`；
    - 每日时长当天已有累计 ≥ 导入值（**毫秒对毫秒**，`bookDailyDurations`
      返回 ms）或低于 10 秒就跳过；整体幂等。
  - UI 入口：长按菜单 `BookShelfAction.exportData / importData`
    （`book_actions_sheet.dart`），shelf_page 分发到
    `exportBookReadingData` / `importBookReadingData`（选 JSON → 解析 →
    找条目 → 合并 → SnackBar 摘要）。
  - 回归：`reading_data_import_test.dart`（解析 / 匹配 / 落库 / 幂等 /
    本地进度更高不回退）、`reading_data_export_test.dart` 的书籍选择、
    `book_actions_sheet_test.dart`（导出/导入菜单项）。
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
- **同步不再「看起来把所有书都同步一遍」（v2.41.6）**：① `_pull` 已知 op
  直接按对象 key（`ops/<opId>.json`）跳过，不再下载；进度只为真正要应用的
  op 报书名（原来先报后判，已应用的书也逐条刷一遍）。② 拉回来的远端 op
  以 `uploaded_at = 0` 标记，不再被当成「本机刚上传」；`_uploadShards` 只
  接收本次 `_push` 实际推出去的书（`push.books`），**拉取不会反过来重传
  分片**（原来按 uploaded_at 时间窗会把这些书重新导出上传，越同步越慢）。
  回归：`sync_repository_impl_test.dart` 的「已知 op 不再重复下载」「只拉
  远端改动时，不重新上传对应分片」。
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
- **原生精排（v2.60.0）**：`ReadingSettings.preciseTypesetting` 原来只对已旁路的
  WebView 链生效，原生阅读面完全忽略它——v2.60.0 把开关接到原生排版：
  - 解析：`epub_parser.dart` 读 `<style>`、OPF 清单里的外部 CSS（`epub_parser.dart`
    的 `externalCss`）和块内联 `style`，`epub_css.dart` 做简单选择器（tag /
    `.class` / `#id` / 组合）、祖先继承与按 specificity 排序的 cascade；
    `epub_block_style.dart` 存字号 / 行高 / 对齐 / 首行缩进 / 段上下距 / 粗体 / 斜体。
  - 存储：`ParsedChapter.paragraphStyles/paragraphStyleIds` 紧凑表 → `NativeChapter`
    同名字段 → `NativeParagraph.style`；没有样式时 style 为 null，不占额外对象。
  - 排版：`ReaderTypeSpec.preciseTypesetting` 打开后，`ChapterLayout.build` 逐段用
    `paragraphStyle/paragraphAlign/paragraphIndentChars` 取原书值；缩进补宽用
    本段字号（`LayoutParagraph.indentStyleFor`），段距用原书 `margin-top/bottom`
    （`_gapBetween` 与 `native_reader_view._gapBetween` 两处必须同步）；`signature/
    metricsSignature/textMetricsSignature` 都包含 precise 开关，切换即失效缓存。
  - 限制：不还原内嵌字体（未导入 Flutter）与文字颜色（夜间模式可读性），段内
    局部粗体/斜体不拆 run；复杂选择器、伪类、`@media` 保守跳过。回归：
    `epub_css_test.dart`（字号/行高/缩进/margin/class/外部 CSS）、
    `native_precise_typesetting_test.dart`（开关对比 / 原书字号粗体对齐缩进段距 /
    渲染片段 / 签名）。
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
- **网格显示书名（v2.68.0）**：`ShelfPrefs.showGridTitle`（prefs
  `shelf.grid.showTitle`，默认 `false`），书架设置 → 网格页的「显示名称」开关；
  `ShelfFlow.showTitle` 透传，网格行高改为 `cellWidth / 0.72 + 28`，书格用
  `Expanded(BookCard)` + 单行居中书名（key `book-title-<id>`）。**v2.69.1 起
  分类格同样显示分类名**（key `category-title-<名称>`，样式共用
  `_gridTitleStyle`），不再只预留空白；同一行书格与分类格封面比例保持一致。
  纯封面模式（`coverOnly`）永远不显示任何名称。
  回归：`shelf_settings_test.dart` 的开关落盘、「显示名称：打开后封面下方出现
  书名，关闭后消失」与「显示名称：分类格也显示分类名，与书名同一行高」。
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
  **进分类记住首屏滚动位置（v2.60.2）**：`ShelfPage._onCategoryFilterChanged` +
  `_shelfScroll`（控制器由 ShelfPage 持有传给 `_BookShelf`）在筛选切换时记忆 / 恢复
  首屏 offset（分类页从顶部开始、返回同帧跳回原位置），别改回「筛选切换丢位置」。
  分类卡：2×2 书位摆前 4 本封面，空位摆「空白书」（书脊剪影）；**卡面不写分类名和本数**
  （用户要求，v2.12.2 去掉），名称只作读屏标签，点进分类后由 AppBar 标题交代。
  **v2.69.2 起分类卡铺满整个格子**（`Card(margin: EdgeInsets.zero)` + 去掉内层
  8px Padding），网格里与书封面同尺寸；回归：
  `category_card_test.dart` 的「铺满整个格子：与书卡同尺寸」。
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
  ④ 最近在读按屏宽排版（v2.41.4）：`recentlyReadItems` 不再按固定本数截断，
  由 `ShelfPage` 用 `recentShelfVisibleItems(items, 屏宽)` 按书脊实际宽度裁到
  屏幕能放下的数量（左右各 20、书间 3）；`RecentShelf` 改成居中的 `Row`（不横滑），
  书少时整排居中、书多时填满架板。最近在读外层仍套 `RepaintBoundary`；
  `ShelfFlow` 的冷启动入场动画只作用于前 `kShelfEntranceCells = 9` 格（v2.41.1）。
  回归：`recently_read_test.dart` 的「宽屏比窄屏多摆…」「书少时全部展示」、
  `recent_shelf_test.dart` 的「书少时整排居中…」。
- **选区菜单与标注编辑（v2.44.0）**：长按选字后的 `SelectionMenu`
  （`widgets/selection_menu.dart`）改成悬浮五宫格：**复制 / 划线 / 高亮 / 笔记 / 从此听**，
  跟随阅读主题的 `chromeSurface`，在选区上方（放不下放下方）并钳制在屏内。
  - 划线：`AnnotationType.underline`（`AnnotationRepository.addHighlight(type:)`），
    正文用 `TextDecoration.underline` 画线、不铺底色；高亮仍走 `AnnotationType.highlight`。
    `NativeMark` 增加 `underline` 字段，`_runSpans` 把高亮和 underline 两套区间
    切成互不重叠的 span（`_spansWithJustify` 同时处理 backgroundColor / decoration）。
  - 笔记：先建默认黄色高亮，再打开编辑弹窗并聚焦输入框。
  - 从此听：收起菜单后从当前页调用 `TtsPlaybackController.start`。
  - 点击已有划线或刚创建的标注 → `AnnotationEditDialog`（仍用 `showDialog`，
    但内容按参考稿重排）：颜色圆点、**复制 / 擦除 / 添加笔记**、`写点笔记吧~`
    多行输入；保存返回 `AnnotationEditResult`（颜色 / 想法），复制返回 `copy`，
    擦除返回 `delete`。`_showAnnotationDialog` 只负责落库 / 移除绘制。
  - 回归：`selection_menu_test.dart`（五个动作）、`annotation_dialog_test.dart`
    （颜色 / 复制 / 擦除 / 笔记）、`native_reader_view_test.dart` 的「下划线标注…」、
    `annotation_repository_impl_test.dart` 的「addHighlight 可创建下划线类型」。
  - **键盘尺寸（v2.44.1）**：`showAnnotationEditDialog` 不能在外层再包
    `AnimatedPadding(viewInsets)`——Flutter 的 `Dialog` 自己会把 viewInsets 加进
    `insetPadding`，再叠一次会把键盘高度扣两遍，弹窗只剩标题 + 原文一条缝。
    让 Dialog 自己处理键盘，内部 `SingleChildScrollView` 在剩余高度内滚动；
    回归：`annotation_dialog_test.dart` 的「键盘升起时弹窗占满可用高度…」。
  - **标注列表按类型筛选（v2.44.1）**：`annotation_tab.dart` 头部在「按章节 /
    按颜色」后新增「全部类型 / 高亮 / 划线」下拉胶囊，`_typeFilter` 只过滤不改变
    分组方式；高亮包含旧的 `AnnotationType.note`（依附划线的笔记），划线只认
    `AnnotationType.underline`。头部计数在筛选时显示「共 X/Y 条」；回归：
    `annotation_tab_test.dart`。
  - **拖手柄调范围（v2.44.2）**：`_onRunSelection` 在
    `SelectionChangedCause.drag` 时**不要**回调 `onSelectionClear`——外层
    `setState` 会重建 `NativeReaderView`，正在拖动的选区手柄被重挂/移除，
    表现为「选中后范围拖不动」。用 `selectionChangeClosesMenu(cause)` 统一判断；
    回归：`native_reader_view_test.dart` 的「拖手柄调整选区时不收起菜单…」。
  - 视觉自检：`flutter test .zcode/selection_menu_preview_test.dart`
    → `.zcode/selection-preview/{menu,dialog}.png`。
- **书签可带备注（v2.45.0）**：点顶栏书签图标添加前弹
  `widgets/bookmark_note_dialog.dart`（`bookmark-note-field` / `bookmark-add` /
  `bookmark-cancel`），返回 `null`=取消、`''`=不加备注、文本=trim 后的备注。
  `_toggleBookmark` 把备注写进 `addBookmark(label:)`；`Bookmark.label` 早已存在，
  数据库与同步 payload 都按 `label` 走，不需要迁移。目录 →「书签」页签直接用
  `bm.label` 作标题（无备注回退「书签 N」），「笔记回顾」漫游也会显示书签备注。
  已有书签再次点图标仍是移除（暂不支持改备注）。
  回归：`bookmark_note_dialog_test.dart`、`annotation_repository_impl_test.dart`
  的「书签：新增/删除/列表，备注随 sync_ops 落库」。
- **朗读引擎可选小米 MiMo（v2.45.0）**：`TtsSettings` 新增 `engine`（Android TTS
  包名，null=系统默认），`TtsPlaybackController` 用 `getEngines` 枚举已安装引擎、
  `setEngine` 切换，并在切换后**重新 setLanguage('zh-CN')**（`setEngine` 会重建
  TextToSpeech），默认引擎也显式设一次，切回「系统默认」才真的切回去。
  朗读面板新增「引擎」下拉（系统默认 + 已装引擎），切换引擎会清空旧音色并按新引擎
  `getVoices` 重载；`ttsEngineLabel` 把包名映射成「小米 MiMo / 小米语音引擎 /
  Google 语音服务…」。Android manifest 已有 `TTS_SERVICE` 的 `<queries>`，不要删。
  回归：`tts_engine_test.dart`（包名映射、选 MiMo 后按引擎重载音色）、
  `tts_settings_test.dart`（engine 往返）。
  **设置恢复屏障（v2.52.2，修「弹窗每次显示系统默认」）**：`TtsSettings` 是
  异步从 prefs 恢复的，冷启动后第一次访问拿到的是默认值——弹窗会先显示
  「系统默认」，期间读取/写入都会用错值（start 用错引擎、写入把用户上次
  的选择覆盖掉）。现在：`TtsSettingsController` 有 `waitRestored()`/
  `restored`（Completer 屏障），`update()` 先等恢复再写；`_startListening`
  读取设置前先 `waitRestored()`；听书弹窗/听书页的引擎行在恢复完成前显示
  「读取中…」。回归：`tts_sheet_restore_test.dart`（种入 prefs → 弹窗显示
  MiMo / 弹窗选择 → 重开仍显示 / 恢复前写入不被覆盖）。
  视觉自检：`flutter test .zcode/selection_menu_preview_test.dart` 同目录可加面板预览。
- **听书大改版（v2.50.0，v2.52.0 控制器全局化）**：①「从此听」真正从选中的那句读起——`TtsSurface.ttsSegments`
  加 `startOffset`（章内字符偏移），`NativeTtsSurface` 按「包含该偏移的句子」过滤
  （`s.end > from`），`TtsPlaybackController.start(settings, {startOffset})` 透传；
  reader_page `_listenFromSelection` 传 `_nativeSelection!.start`（WebView 链路收下参数
  但忽略，已旁路）。② 全屏听书页 `tts/tts_page.dart`（路由 `/reader/:bookId/tts`，
  **extra 传 `TtsPageLaunch(controller, bookTitle)`**，控制器由阅读页持有不进
  provider）：当前句大字 + `i/N 句` 进度、上一句/播放暂停/下一句/停止、倍速/引擎
  /音色/定时（含 90 分）/背景音乐 + 音量；`goToSentence` 实现 = epoch++ → stop →
  置 index → 重入 `_runLoop`，暂停态调用等同从该句继续。入口：TtsBar 信息区可点
  （`onOpen`），底栏「朗读」在 `tts.active` 时直接进听书页（否则弹设置面板）。
  ③ 背景音乐：`tts/bgm_player.dart` 的 `BgmPlayer`（audioplayers，
  `PlayerMode.mediaPlayer` + `ReleaseMode.loop`，**mixWithOthers 不抢 TTS 焦点**，
  全局 keepAlive `bgmPlayerProvider` 单例），`reader_page._onTtsBgmChanged` 按
  TTS 状态起停（playing→播、paused→暂停、idle→停，**换曲只在曲目 id 变化时
  setSource**）；内置 3 条曲目在 `assets/music/`（`.zcode/gen_bgm.py` 合成：
  雨声/白噪/轻音乐，mp3 各约 230KB），导入音频由 `tts/audio_library.dart` 的
  `AudioLibraryController` 管理（目录 `<support>/music`、prefs `reader.audio`
  清单 `{id,name,file}`，扩展名 mp3/m4a/aac/wav/ogg/flac/opus，100MB 上限）；
  `TtsSettings` 加 `bgmId`（null=关）/`bgmVolume`（默认 0.3）。管理页在
  设置 → 资源 →「听书音频」（`/settings/audio`），试听走同一个 BgmPlayer
  （离页只停本页试听起的那条，不碰朗读中的 BGM）。④ 音频同步
  `data/sync/audio_sync.dart`：完全照 FontSync 模式（`spaces/<空间>/music/
  track-<sha256>.<ext>` + manifest，并集语义删除不传播），`_syncNowInner` 在
  字体/背景之后、主题之前跑，`SyncResult.audiosSynced` 摘要「同步 N 个音频」，
  同步完成后 reload `audioLibraryControllerProvider`。⑤ 缓存中心 4 页签
  （书籍/字体/背景/音频），音频清除 = 删本地文件 + 清 manifest，云端保留。
  **BGM 曲目查找必须用 `allAudioTracks(...)`（内置 + 导入）**——v2.51.3 前
  `_syncBgm`/听书页换曲只查了导入列表，选内置曲目时 `findAudioTrack` 返回
  null 直接 stop，表现为「背景音乐没有声音」。
  回归：`tts_playback_test.dart`（选区起点/句级跳转，mock flutter_tts 通道
  `speak.onComplete`）、`tts_bar_test.dart`、`tts_page_test.dart`、
  `audio_library_test.dart`（PathProviderPlatform 假实现，已加 dev 依赖）、
  `audio_sync_test.dart`、`tts_settings_test.dart`（bgm 字段）、
  `cache_center_page_test.dart`（4 页签）、`sync_result_summary_test.dart`（音频）。
  **真机验收点**：BGM 与 TTS 混音在 MIUI 上的焦点行为、MiMo 引擎在听书页
  的切换。
- **MiMo 云端大模型语音（v2.51.0）**：`TtsSettings.engine` 用保留值
  `kMimoTtsEngine = 'cloud.xiaomi.mimo'`（tts_playback.dart 顶层）表示
  「小米 MiMo · 云端」，与系统 TTS 引擎（Android 包名）并存于同一个引擎
  下拉（`availableEngines()` 把 MiMo 入口排在最前）。协议：OpenAI 兼容
  `POST {kMimoTtsBaseUrl}/chat/completions`（`data/sync` 之外，实现在
  `tts/mimo_tts_client.dart`），**待合成文本放 `role:'assistant'` 的
  content**（MiMo 约定，不是 user），`audio:{format:'wav', voice:<音色>}`
  返回 `choices[0].message.audio.data` 的 base64 WAV（24kHz）；非默认语速
  时加一条 `role:'user'` 的语速指令（MiMo 无数值语速参数）。要点：
  ① API Key 存 flutter_secure_storage `tts.mimo.apiKey`
  （`MimoTtsCredentials`，照 SyncBackendStore 规矩）；**听书弹窗与听书页
  选中云端引擎时都显示 API Key 配置卡**（v2.51.1：抽成共用组件
  `tts/mimo_key_card.dart` 的 `MimoKeyCard`：粘贴/保存/清除，secure storage
  通道可在测试里 mock），未配 Key 时
  start 报「小米 MiMo：请先在听书页配置 API Key」——`start()` 的通用
  「未找到中文系统语音」兜底改成只在 `value.error == null` 时才覆盖。
  ② 播放走 `MimoVoicePlayer`（audioplayers `BytesSource`，mixWithOthers
  不抢焦点，`onPlayerComplete` = 自然播完；stop → completer false），
  `_speak`/`_stopSpeech` 按引擎分流；控制器有 32 条 FIFO 的句子合成缓存
  （暂停续播/回听不重复请求）。**预取（v2.51.2，修句间卡顿）**：起播当前句
  的同时 `_prefetchAhead` 预取后面两句（`_mimoPrefetching` 记录在途请求，
  同句去重；读到该句时若预取仍在途就 `await` 它而不是重复请求；预取失败
  静默，真正读到时按需重试并正常报错）。**倍速（v2.51.3 重做）**：不要用
  user 指令让模型变速（实测无效）——合成结果与倍速无关（缓存 key 只含
  音色+文本），`MimoVoicePlayer.play(wav, rate:)` 用 `setPlaybackRate`
  变速播放、`updateRate` 走 `_mimoPlayer.setRate` 当前句立即生效；注意
  MediaPlayer 变速 >1x 音调会升高（audioplayers 内核限制，流式/ExoPlayer
  是后续改进项）。听书页倍速滑杆必须调 `_tts.updateRate`（v2.51.3 前只落
  设置，播放中拖动毫无反应）。③ 音色表 `kMimoVoices` 预置 9 个
  （mimo_default/冰糖/茉莉/苏打/白桦 + 4 个英文），`availableVoices` 对
  云端引擎直接返回预置表（不碰系统 TTS 的 setEngine）。④ 模型 ID 常量
  `kMimoTtsModel = 'mimo-v2.5-tts'`（官方文档示例值；小米公告 V2.5 系列
  2026.10.21 下线、建议核对 V2.6——若接口报模型不存在，改这一个常量）。
  ⑤ 合成错误（HTTP/网络/超时/解包）统一 `MimoTtsException`，经 `_fail`
  带出接口原文。测试注入缝：控制器构造参数 `mimoClient` /
  `mimoApiKeyLoader` + `MimoVoicePlayer.debugPlayOverride`。
  回归：`mimo_tts_client_test.dart`（请求体结构/语速指令/错误透出/解包）、
  `tts_playback_test.dart` 的云端用例（逐句合成推进/未配 Key 报错/引擎与
  音色表）。**真机验收**：配真实 API Key 听合成效果与逐句延迟。
- **听书控制器全局化（v2.52.0）**：`TtsPlayback` 是 Riverpod keepAlive 单例
  （`ttsPlaybackProvider`），**退出阅读页后继续朗读**。要点：
  ① 控制器自持章节表——`start(settings:, bookId:, bookTitle:, chapters:,
  chapterIdx:, startOffset:)` 由阅读页传入 `nativeChaptersProvider` 解析好的
  `NativeChapter` 列表，之后切句（`splitSentences`）、切章、高亮全在控制器内
  完成，**不再依赖阅读页桥**（旧 `NativeTtsSurface` 已删，`splitSentences`/
  `TtsHighlight` 保留在 `native_tts_surface.dart`）；章末 `_advanceChapter`
  直接从章节表取下一章（阅读页不在场也续章）。
  ② 阅读页通过 `bindReader(onJump:, onFinishedAll:)` / `unbindReader()`
  绑定/解绑「跳转执行器」（高亮句不在当前页时翻页 + 全书读完提示），退出后
  解绑、回书重新绑定；高亮经 `TtsPlaybackState.highlight` 随状态走，阅读页
  `ref.listen` 拷进 `_nativeTtsHighlight`（bookId 不匹配则清空防串染）。
  ③ **背景音乐协调搬进控制器**（`_syncBgm`，status 跳变时驱动），阅读页不再
  管 BGM——退出书后音乐跟着朗读走。
  ④ 全局控制条 `home/widgets/global_tts_bar.dart` **两个挂载点**
  （v2.52.1，v2.52.0 只挂 HomeShell——从书籍详情等二级页退出后看不到）：
  `GlobalTtsBar` 挂 HomeShell 底栏上方（条在导航栏上不遮导航）；`TtsBarOverlay`
  挂 `MaterialApp.builder` 覆盖层，只对**非主框架路由**显示（按
  `router.routerDelegate.currentConfiguration.last.matchedLocation` 判定，
  主框架 = `/` `/shelf` `/stats` 时让位）。阅读页/听书页在 initState/dispose
  调 `TtsBarOverlay.suppress()/unsuppress()`（可重入计数）声明盖住。覆盖层
  在 Navigator 的 Overlay 之外，`TtsBar` 要传 `tooltips: false`（IconButton
  的 Tooltip 需要 Overlay 祖先）；跳转用 `ref.read(routerProvider).push`
  （builder 的 context 在 Router 之上，`context.push` 拿不到 GoRouter）。
  ⑤ 听书页 `TtsPage(bookId)` 不再走 extra（控制器从 provider 取）；页头新增
  **「回到书籍」按钮**——`activeReaderBookSync() == bookId` 时 pop 回阅读页，
  否则 `push(readerPath(bookId))` 直接打开；idle 时点播放 = `restart()`（控制器
  记住上次会话的章节/停句，`canRestart`/`lastBookId` 判断能否接上）。
  ⑥ 已知限制：退出阅读页后会话已 flush，**书架/首页上的听书时长不计入统计**
  （会话跟阅读页走）；`_ttsState`（provider.read）取状态，Notifier.state 是
  protected 别在外部用。
  ⑦ **「选择声音」面板 + 切换即从当前句重读（v2.53.0）**：
  `tts/voice_picker_sheet.dart`（参照主流听书 App）：顶部「朗读引擎」卡片行
  （点进面板内引擎视图切换）→ 音色按语言分组列表（`中文 · 5` / `英文 · 4`
  分组头，行 = 名称 + 标签胶囊 + 试听 + 当前选中勾与 accent 描边）。MiMo 云端
  音色可**试听**（合成「你好，这是一段试听。」用独立 preview AudioPlayer 播，
  朗读中先暂停避免叠音；系统引擎音色无试听）。入口：听书页/弹窗的「音色」行
  （原 dropdown 已删）。**切换即重读**：`TtsPlayback.changeVoice/changeEngine`
  ——写设置后 `state.active` 时 `goToSentence(state.index)` 从当前句用新音色/
  引擎重来（MiMo 缓存 key 含音色，新音色自然重合成；切引擎走 `_ensureEngine`
  应用新引擎）。倍速滑杆 0.5–2.0 改 **0.1 步进**（divisions 15）。
  **注意（v2.53.0 大坑）**：控制器里的 `_settings` **必须是 provider 的实时
  getter**（`ref.read(ttsSettingsControllerProvider)`），不能是字段式缓存——
  字段只在 start() 同步一次，设置异步恢复完成后就陈旧（picker/听书页在未
  start 时全读到默认值）。`TtsVoice` 加 `tags`（选声音界面的胶囊标签），
  系统音色 tags=[locale]。
  回归：`voice_picker_test.dart`（分组/选中写设置/面板内切引擎；测试要 mock
  flutter_tts 通道——FakeAsync 下未 mock 的平台调用会挂起；英文组在
  ListView 视口外要 scrollUntilVisible）、`tts_playback_test.dart` 的切音色
  从当前句重读用例、`tts_engine_test.dart` 重写（音色行走选择声音面板）。
  ⑧ **听书页「文稿」式改版（v2.54.0，参照主流听书 App）**：
  `TtsPlaybackState` 加 `sentences`（当前章全部句子文本，start/续章时写入）；
  听书页中部从「当前句卡片」改为**整章文稿视图**——`ListView.builder` 逐句
  渲染（已读=alpha 0.32 / 当前句=加粗+accent 下划线 / 未读=alpha 0.78），
  点句跳转（goToSentence），当前句变化自动 `Scrollable.ensureVisible` 滚动
  到可见（GlobalKey 按需生长；只对已构建句生效，滑杆远跳可能不滚）。
  底部改为三层：**功能行**（原文=回到书籍 / 语速（显示当前倍速，点开 0.1
  步进滑杆面板）/ 音色（当前音色名，点开选择声音面板）/ 音乐（当前曲目，
  点开设置）/ 设置）→ **进度滑杆**（当前句/本章句数，两侧 上一句/下一句）→
  **运输排**（停止 / 大播放暂停 / ⏰ 定时=设置面板）。引擎/定时/背景音乐
  三组控件抽到 `tts/tts_settings_sheet.dart`（`TtsSettingsSheet`，听书页
  「设置」与 ⏰ 入口；引擎切换走 `changeEngine`（朗读中从当前句重读），
  BGM 换曲/调音量的「正在播」逻辑同旧 _patch）。控制卡 `_ControlsCard` 删除。
  测试要 mock flutter_tts 通道（同 ⑦）。回归：`tts_page_test.dart` 重写
  （空文稿提示/文稿渲染与当前句/功能行/设置面板选 BGM）。
  ⑨ **「定位朗读句」浮动按钮（v2.54.1）**：阅读页在听书会话激活
  （playing/paused）且当前句**不在可见页**时，右上角浮出
  「⌖ 定位朗读句」胶囊（chromeSurface 底 + accent 图标；章节不同先跳章）。
  可见性判断 = `NativeReaderViewState.isOffsetVisible(chapterIdx, offset)`
  （章匹配 + 偏移落在当前 spread 的任一页 range 内；双页取两页）。自动跟读
  正常时播放中基本隐藏；暂停后翻走 / 重开书位置错位 / 跳章间隙时出现。
  reader_page 每次构建时用 `_nativeKey.currentState?.isOffsetVisible(...)`
  计算（tts 状态逐句通知 + 页面落定都会触发重建，按钮及时出现/消失）。
  回归：`native_reader_view_test.dart` 的 isOffsetVisible 用例（页内 true /
  他页 false / 他章 false / 跳页后翻转）。
  ⑩ **笔记/划线/高亮卡片式分享（v2.55.0）**：`notes/annotation_share_sheet.dart`
  （`showAnnotationShareSheet(context, AnnotationCardData)`）——**三种卡片模板**
  胶囊切换：「墨句」（深色渐变 + 大字引文 + 暖金装饰）、「便签」（纸面底 +
  标注色侧条/想法色块，引文想法并重）、「简约」（白底居中排版）；卡片内容 =
  原文 + 想法（有则显示）+《书名》作者 + 日期 + QYReader 角标，比例 4:5，
  模板切换 ChoiceChip。捕获/保存/分享沿用 `reading_share_sheet` 模式
  （RepaintBoundary→PNG→gal 存相册 QYReader 相册、失败退应用目录；share_plus）。
  标注色 → 卡片强调色映射 `_accentOf`（yellow 暖金/green/blue/rose）。
  **入口**：① 笔记漫游页每张卡右上角分享按钮（`NoteEntry` 加 `colorToken`
  字段，`noteEntries` 从 `a.color.token` 填充；漫游卡片头部行紧凑 InkResponse
  防溢出）；② 阅读页标注列表每行 trailing 加「分享卡片」按钮
  （`AnnotationTab`/`TocDrawer`/`_Panel` 加 `bookTitle/author` 参数链，
  reader_page 从 `state.book` 传入；kindLabel 按类型 = 划线/笔记/高亮）。
  回归：`annotation_share_sheet_test.dart`（三模板渲染与切换/无想法不渲染
  想法区）、`annotation_tab_test.dart` 分享用例（分享按钮打开面板）、
  `notes_page_test.dart` 漫游卡头部加按钮后不再溢出。
  ⑪ **TTS 高亮不含段首缩进（v2.55.1）**：`_runSpans` 的 `addRange` 加
  `skipLeadingIndent`（TTS 高亮专用）：高亮起点钳到该段正文首字
  （`layout.paragraphs` 的 `displayStart - run.start`），再跳过残留缩进字符
  （`_isIndentChar`：FEFF 零宽锚 / NBSP / 全角空格 / 半角空格 / 制表）。
  用户反馈段首句的朗读高亮盖住缩进——测试字体下无法复现（Ahem 里缩进
  区不可见），但按设备描述钳制是构造正确的做法；视觉自检工具：
  `.zcode/tts_indent_preview_test.dart`（渲染带高亮的真机尺寸 PNG 到
  `.zcode/tts-indent-preview/`）。回归：`native_reader_view_test.dart` 的
  「TTS 朗读高亮：段首句不含缩进字符」（walk 高亮 span 断言无缩进码点）。
  ⑫ **启动窗口期可暂停（v2.55.2，修「暂停不了」）**：`pause()` 在
  `preparing` 状态（取句/合成首句的启动窗口，MiMo 首句要几秒）原来直接
  return——用户的暂停点击被丢弃。现在 preparing 时挂起 `_pauseRequested`
  标志，`start()` 在 `_updateState(playing)` 前检查：有请求就 `stop()` 直接回
  空闲（不合成不发声）；stop/fail/resume 清标志。听书页大播放键与 TtsBar
  暂停键全程可点（preparing 也能按）。逐句诊断 `tts-diag: speak i=.. ch=..`
  方便定位「开始位置」类反馈。回归：`tts_playback_test.dart` 的「启动窗口期
  暂停：开读即停」（delayed apiKeyLoader 制造 preparing 窗口）与「暂停后
  恢复：从暂停时的句子继续」。**「开始的位置不是选中的位置」**：从此听/文稿
  点句的代码路径有测试覆盖（选区起点/暂停恢复/点句跳转均正确），若真机仍
  复现，抓 `adb logcat | grep tts-diag`（speak 日志带章/序/文本）。
  回归：`tts_playback_test.dart`（ProviderContainer + debugInjectMimo：选区
  起点/续章回调/goToSentence/越界夹紧/stop 后 restart/云端与预取）、
  `tts_page_test.dart`（idle/朗读中 override/回到书籍按钮存在性/BGM 选择）、
  `global_tts_bar_test.dart`（朗读中显示+点击进听书页/空闲收缩）。
- **TTS 切句要吞掉句末标点后的闭合引号（v2.51.4）**：`native_tts_surface.dart`
  的 `splitSentences` 原来只并连续句末标点（？！…），`你说："很好吃。"` 的
  闭合引号会被剩成下一"句"（半截引号单独占一次合成+高亮）。现在标点 run
  之后循环吞 `_sentenceClosers`（' " ’ ” 」 』 〉 》 】 〗 〕 〛 ） ］ ｝
  > ) \ ] }）与再出现的句末标点（`。"…` 交错也能吞）；**引语与叙述仍自然
  分两句**（`“很好吃。”他点点头。` = 两句，高亮更准，这是既有行为别改回）。
  回归：`split_sentences_test.dart`。
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
  v2.13.0）。Tab 定义在 `features/home/home_tabs.dart`（`HomeTab` / `kHomeTabs`：
  首页 / 书架 / 统计 / 设置），枚举顺序必须与 `kHomeTabs` 一一对应，`HomeTab.index`
  直接当 `IndexedStack` 下标；v2.41.0 起默认启动 Tab 是首页。**选中胶囊是滑动的**（v2.14.2）：`LayoutBuilder` 算出每格宽度，
  `AnimatedPositioned` 用 `kSmoothCurve` 在格与格之间滑动，别改回「每项各自
  AnimatedContainer 原地淡入」。主题 seed 换成参考稿亮蓝 `#1E7BFF`，亮色页面底色
  `#F3F4F9`，卡片白底 20 圆角无描边、AppBar 透明无阴影。别再改回 `NavigationBar`。
  回归用例：`test/features/home/floating_nav_bar_test.dart`（胶囊中途位置 + 落点）。
- **宽屏布局（v2.41.3）**：单列内容页（首页 / 统计）在宽屏上内容限宽
  `kContentMaxWidth = 900`（`app/theme/layout.dart`），外面套 `Center` +
  `ConstrainedBox`；统计汇总卡 `_PeriodSummary` 按「宽 / 210」自动分 2~4 列
  （宽屏 4 列，不再出现两张 700dp 的大空卡）；首页「开始阅读」按钮最宽 420；
  `FloatingNavBar` 居中限宽 640（手机宽度不够时不变）。**作为
  `bottomNavigationBar` 时外层 `Center` 必须传 `heightFactor: 1`**（v2.41.5）：
  不传的话 Center 会被撑满整屏，把 body 高度挤成 0、底栏浮到屏幕中间（表现为整页空白）。回归：
  `stats_page_layout_test.dart`（1400 宽：内容 900 + 4 列；390 宽：满宽 + 2 列）、
  `home_page_test.dart` 的「宽屏：内容限宽 900…」、`floating_nav_bar_test.dart` 的
  「宽屏底栏居中且限宽」「作为 bottomNavigationBar 时只占自身高度」。
- **首页（v2.41.0）**：`HomePage`（`features/home/home_page.dart`）是底栏第一个 Tab，
  由 `HomeShell` 用 `IndexedStack` 常驻；传入 `active` / `onSelectTab`，从别的 Tab
  切回来时重新拉一次统计。四张白底 20 圆角卡片：
  ① 累计阅读——`StatsRepository.overview()` 的累计时长 + 已读完本数，点卡片切到统计；
  ② 继续阅读——`continueReadingItems()`：打开过、非已读 / 弃读、进度 <100%，
     按 `lastOpenedAt` 倒序，横向卡片流；
  ③ 今日目标——`_GoalArcPainter` 画 240° 圆弧（从左下经顶到右下），中间是今日
     `分:秒` 计时与每日目标（点文字或铅笔改目标），黑底「开始阅读」优先续最近在读。
     **圆弧画布必须是 `AspectRatio(1)` 的正方形**（`ConstrainedBox(maxWidth: 300)`，
     v2.41.2）：不要用 `Positioned.fill` 铺满卡片宽度，宽高不等会把圆弧拉成扁椭圆；
  ④ 今年读完的书——`finishedThisYear()`：阅读状态已读且 `updatedAt` 落在今年
     （没有单独的读完时间戳，用状态更新时间近似），展示 `本数 / 年度目标`，
     年度目标存 prefs `home.yearlyGoalBooks`（默认 24，点数字可改）。
  数据整理全在 `home_stats.dart`（纯函数，不建表）；年度目标读写走 `home_prefs.dart`。
  视觉自检：`flutter test .zcode/home_page_preview_test.dart`
  → `.zcode/home-preview/home-page.png`（测试字体无中文，只看版式）。
  回归：`test/features/home/home_page_test.dart`、`home_stats_test.dart`、
  `home_prefs_test.dart`。
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
- **我的阅读（v2.42.0）**：设置 → 管理 →「我的阅读」，路由
  `/settings/my-reading`。页面 `features/my_reading/my_reading_page.dart`：
  顶部「全部 / 在读 / 搁置 / 读完」四个状态页签（带本数）+ 搜索框（书名 / 作者），
  下面按 **年 > 月** 时间线分组（年 / 月标题带折叠箭头、本数和分享按钮）；
  卡片大标题：在读 / 未开始显示「读到 X%」，读完 / 搁置显示累计阅读时长，
  副标题是「X月开始阅读 · N 字 · N 分钟」或「YYYY年M月读完」。
  时间取 `book.lastOpenedAt ?? book.updatedAt`；分组 / 文案是纯函数
  `features/my_reading/my_reading_data.dart`（`myReadingBooks` / `groupMyReading` /
  `myReadingMeta`），单位格式化统一走 `formatReadingDuration` / `formatReadingChars`。
  每本书累计时长与字数来自 `StatsRepository.bookTotals()`（一次查完 `daily_stats`
  的单书行、排除 `bookId=''` 的全书合计，按总时长倒序）。
  点卡片会 `touchOpened` 并进入阅读器；顶部筛选图标是阅读状态弹层，⋯ 里可
  「分享当前列表 / 刷新阅读数据」。
  分享面板 `reading_share_sheet.dart`：9:16 海报（深色 / 浅色两套模板，大号本数 +
  头像 + 书名/作者/时长/字数 + 封面），模板按钮切换；保存优先用 `gal` 存相册
  （Android / iOS，失败退回 `QYReader/shares/`），分享用 `share_plus` 走系统分享。
  **回归**：`my_reading_data_test.dart`（筛选 / 搜索 / 分组 / 文案）、
  `my_reading_page_test.dart`（时间线 / 筛选 / 搜索 / 分享面板四个动作）、
  `stats_repository_impl_test.dart` 的「bookTotals 汇总所有书…」。
  视觉自检：`flutter test .zcode/my_reading_preview_test.dart`
  → `.zcode/my-reading-preview/{page,share}.png`。
- **笔记回顾（v2.43.0）**：设置 → 管理 →「笔记回顾」，路由
  `/settings/notes`（概览）与 `/settings/notes/wander`（漫游）。
  概览页 `notes_overview_page.dart`：顶部搜索（提示「搜索 N 条笔记」）、
  卡片流按书汇总「N 条笔记 / 书名 / 已读时长 · 字数 / 封面」，
  右上角可排序（最近笔记 / 笔记数量 / 书名）和进入全部漫游。
  漫游页 `notes_wander_page.dart`：顶部「全部 / 划线 / 书签」胶囊筛选，
  `PageView` 卡片堆叠（左右可滑，卡片显示类型、`yy/MM/dd HH:mm` 时间、
  划线原文 / 书签标签、想法、底部书名作者封面），页码 `1 / N`；
  右上角可「按书籍筛选」或返回列表。
  全库数据来自 `AnnotationRepository.watchAll()` / `watchAllBookmarks()`
  （DAO 只取 `deleted_at IS NULL`，新在前），数据整理在
  `features/notes/notes_data.dart`；阅读时长 / 字数复用
  `myReadingTotalsProvider`。`notes_providers.dart` 的
  `allAnnotationsProvider` / `allBookmarksProvider` 是流，增删标注会实时刷新。
  回归：`notes_data_test.dart`（汇总 / 排序 / 搜索 / 类型 / 时间）、
  `notes_page_test.dart`（概览搜索 / 漫游筛选与翻页）、
  `annotation_repository_impl_test.dart` 的「watchAll…」。
  视觉自检：`flutter test .zcode/notes_preview_test.dart`
  → `.zcode/notes-preview/{overview,wander}.png`。
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
  - 管理 → 分类：`CategoryManagerPage`（`/settings/categories`）——**层级
    分类管理（v2.56.0，参照主流阅读 App）**：分类支持「/」路径层级
    （`小说/科幻`——`科幻` 是 `小说` 的子分类），纯函数建树在
    `settings/category_tree.dart`（`buildCategoryTree` / `flattenCategoryTree` /
    `categoryUnderPath` / `renameCategoryPath`）；页面 = AppBar（🔍 搜索 +
    ＋ 新建）+ 「N 个分类 / 收起全部·展开全部」头 + 树形列表（行 = 缩进 +
    折叠箭头 + 文件夹图标 + 名称 + 计数（含后代）+ ⋯ 菜单：重命名 / 添加
    子分类 / 删除，删除=清空子树内所有书的分类，书籍不动）；搜索时全部
    展开只留匹配节点。**空分类**（0 本书）持久化在 prefs `categories.extra`
    （StringList 路径），与书的分类合并建树。重命名=子树整体改前缀
    （逐本 setPersonalization，同步日志）。书架/批量分组沿用完整路径字符串
    （书架分组名显示全路径）。长按多选与拖拽排序暂未做。回归：
    `category_tree_test.dart`（建树/计数/折叠展平/子树改名）+
    `category_manager_page_test.dart`（层级渲染折叠/搜索/新建含路径的空分类）。
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
- **阅读主题也参与同步（v2.41.7）**：`data/sync/theme_sync.dart` 把自定义主题
  清单整体同步到 `spaces/<空间>/themes.json`（`{updatedAt, themes}`，按
  `updatedAt` LWW）。`ReaderThemesController._writeCustom` 每次保存 / 改名 /
  删除都写 `reader.themesSyncAt`；旧版本没有时间戳时与云端按 id 并集后上传，
  不丢本机主题。主题里的背景图只存**文件名**，下载时还原到本机
  `QYReader/backgrounds/`，所以主题同步排在 `BackgroundSync` 之后。删除主题
  会随清单一起传播；同步完成后书架快捷同步与同步面板都调
  `ReaderThemesController.reload()`，列表立即更新；当前主题 id 不存在时回退
  「纸」。`SyncResult.themesSynced` 给面板显示「同步 N 个主题」。回归：
  `theme_sync_test.dart`（背景路径可移植 / 删除传播 / 首次并集）、
  `reader_themes_test.dart` 的「reload…」。
- **阅读时长（会话）参与同步（v2.46.0）**：`reading_sessions` 明细走 op 日志。
  `StatsRepositoryImpl.recordSession` 在与会话**同一个事务**里写一条
  `entity='session'` 的 sync_op，**opId 固定为 `ses-<会话id>`**（补传与
  recordSession 同一规则，天然去重），payload = `{id, bookId, startedAt,
  endedAt, durationMs, charsRead, deviceId, hlc}`，entityId=bookId；`_push`
  对它没有特殊处理（不是 book 实体、不传书源），`_bookIdOfOp` 对 session
  **返回 null**——会话不属于分片数据，别让它触发分片重传。拉取侧
  `_applyRemoteOp` 新增 `case 'session'` → `_mergeSession`：会话只增不改，
  **按 id 幂等**（已存在直接跳过，不用 LWW），插入后按 `startedAt` 的本地日
  `_recomputeDailyStats(day)` 重算 daily_stats——**重算而不是增量累加**，
  即使 op 幂等记录丢了也不会重复计数；当天会话已消失的书（删书墓碑清了
  sessions）对应聚合行归零。天的口径与 `stats_repository_impl._dayOf` 一致
  （本地时区、按 startedAt 落日，跨午夜的会话整段算起始日）。同步进度里
  session 显示为「阅读时长」（`_entityLabel`）。多设备同一天各读一段时，
  合并后当日合计是两段之和。
  **历史会话补传**：升级前的会话没有 op，`syncNow` 开头跑
  `_backfillSessionOps`——状态表 `sync.sessionsBackfilled` 未置位时，把
  **deviceId 是本机**的会话逐条补写 op（只认本机会话：远端合并来的会话由
  对方设备补传，否则回声），置位后不再跑；补传中断对端也幂等。**别改成
  「补传所有会话」或把 session 加进 `_bookIdOfOp`**。
  回归：`sync_repository_impl_test.dart` 的「阅读时长（会话）同步到另一台
  设备…」「两台设备各读一段…」「升级补传：旧版本记录的历史会话…」、
  `stats_repository_impl_test.dart` 的「记录会话同时写 session 同步 op…」。
- **同步报错要带出真实 S3 错误码（v2.45.1）**：minio SDK 的 `MinioS3Error`
  toString 只有 message——请求没有响应体时（HEAD 桶存在性检查）SDK 退化成
  HTTP reason phrase，用户只能看到「MinioError: Forbidden」，看不出真实原因
  （实测阿里云账号停机时真码是 `UserDisable`）。新增
  `s3_object_store.dart` 顶层函数 `describeStoreError(e)`：从
  `MinioS3Error.error/.response` 提取 HTTP 状态码、S3 Code/Message、
  `x-oss-request-id` / `x-amz-request-id`，非 S3 异常原样透传（所有 catch
  处可放心调用）。`testConnection` 改成 **GET 列举探测**（不再用
  `bucketExists` 的 HEAD）：GET 的错误响应带 XML，能拿到真码；桶不存在按
  404/NoSuchBucket 识别。`syncNow` 总 catch、`_backupLocalBlobs`、字体/
  背景/主题阶段都改用 `describeStoreError`。排查 403 类问题时优先拿
  RequestId 去阿里云后台查，或匿名 curl 桶端点看 `<Code>`/`<EC>`
  （`UserDisable`/EC 0003-00000801 = OSS 服务被停止，先查欠费）。
  回归：`s3_error_describe_test.dart`（UserDisable 带请求 ID / HEAD 空体
  兜底 / NoSuchBucket 双字段 / 非 S3 透传）。
- **双页的页眉/页脚整屏只有一份（v2.46.1）**：双页（`doublePage`）下页眉/页脚
  由 `_spreadFrame` 画在**整屏宽度**上（`_dualSpread`：Column[带, Row[左栏, gutter,
  右栏], 带]），两栏正文用 `_pageBodyFor`（正文-only，不带各自的带）；带的内容按
  本屏第一张可见内容页解析（普通屏 = 左页，与翻页锚点 `_report(spread * pagesPerView)`
  同口径；跨章哨兵屏 = 右栏那页）。页内正文区抽成了 `_pageBody`（不带 Expanded，
  调用方包进 Flex）、带抽成了 `_runningBand`（几何与 `_runningHeight` 一致，槽位
  全关时透明占位）。**分页几何没变**（带高不变、正文区高度不变），改这里别动
  `_runningHeight` / textAreaH 的口径。排版面板/边距直调的预览页在双页下也走
  整屏单份带（build 里的 previewPage 分支）。单页模式仍是每页自带页眉页脚。
  回归：`native_reader_view_test.dart` 的「双页 + 页眉页脚：两栏各自排版，
  页眉页脚整屏一份，不溢出」（章页码与全书进度都只出现一次）。
- **自动同步：按间隔定时跑 syncNow（v2.47.0）**：间隔存 prefs
  `sync.autoMinutes`（0 = 关闭），入口在「同步设置」页顶部的「自动同步」下拉
  （关闭 / 5 / 10 / 15 / 30 / 60 分钟；该页原「同步存储」已改名「同步设置」，
  同步面板 ⚙ 的 tooltip 同步改成「同步设置」）。实现是
  `features/shelf/auto_sync.dart` 的 `AutoSyncController`（持有
  `Timer.periodic`，`setMinutes` 落盘并重排；`runSync` 闭包由 keepAlive 的
  `autoSyncProvider` 注入 = 读 syncRepositoryProvider + syncNow），
  **HomeShell initState 里 `ref.read(autoSyncProvider)` 启动**（别改成别处，
  HomeShell 常驻才保活）。守卫：非 resumed 生命周期不跑（回前台后下一跳
  补上）；控制器与 `SyncRepositoryImpl.syncNow` 各有一道防重入（撞车时
  后到的 `syncNow` 返回空 `SyncResult`）；后端没配好时
  syncRepositoryProvider 抛错被静默吞掉。自动同步**不弹提示**：结果记状态表
  （面板可见上次时间/错误），`syncNow` 里别加 SnackBar。回归：
  `auto_sync_test.dart`（restore 默认关 / 落盘重排 / 防重入 / 后台不跑）。
- **首页 / 统计页每次显示就刷新（v2.48.1）**：`StatsPage` 加 `active` 参数
  （镜像 HomePage 的机制：`didUpdateWidget` 里 active false→true 重拉 `_load`）；
  HomeShell 混入 `RouteAware`，`didPopNext`（从阅读器 / 详情等盖住主框架的
  路由回来）→ `_shownTick++`，给 `HomePage` / `StatsPage` 传
  `ValueKey('home-<tick>')`——key 变化重建页面状态并重拉数据。Tab 内切换走
  active，从阅读器回来走 tick。别去掉这两条（否则刚读完书数字不更新）。
  回归：`stats_page_layout_test.dart` 的「切回统计 Tab（active false→true）
  重新拉一次统计」。
- **单页最长计时（v2.48.0）**：一页停留超过上限的部分不计入统计（开着书
  离开/睡着不灌爆时长）。设置在统计页 AppBar 的 ⏱（`_editPageCap`，选项
  不限制 / 1 / 2 / 3 / 5 / 10 / 15 / 20 / 30 分钟，默认 10，prefs
  `stats.pageCapMinutes`，存取在 `features/stats/stats_prefs.dart`）。
  `ReadingSessionTracker` 按页分段计时：两次 relocated 之间算「在一页上」，
  `flush` 时每段 min(实际, 上限) 求和成 `countedDurationMs` 传给
  `recordSession`——**startedAt/endedAt 保持真实墙钟，计入时长单独承载**
  （不传 = 全额，老调用/测试不受影响）；会话 op 的 `durationMs` 也是计入值，
  多设备同步口径一致。时钟可注入（`now:` 参数）供测试。**别改回全额计时**。
  回归：`reading_session_tracker_test.dart`（封顶/回翻/同页回报/字数不受影响）、
  `stats_repository_impl_test.dart` 的「recordSession 传 countedDurationMs…」、
  `stats_prefs_test.dart`。
- **全书进度按内容字符量算（v2.48.0）**：旧口径 = 「(章序号 + 页内比例) /
  章数」均摊，长短章一视同仁，进度与实际读到的内容对不上（一章顶半本书时
  读完整章才走 10%）。现在统一走 `native_reader_view.dart` 顶层的
  `bookContentPercent(chapters, chapterIdx, 章内字符偏移)` /
  `chapterForContentPercent(chapters, v)`（拖动反解，与上报互逆）：`_report`
  上报、`_onSeek` 全书拖动、页眉页脚「全文进度」、书架角标 / 续读 percent
  全部同口径。**别改回章数均摊**。阅读界面底栏进度条的「全书 / 本章」切换
  本来就有（排版面板 → 页面 → 进度条，默认全书），本轮只修全书口径。
  回归：`native_reader_view_test.dart` 的「全书进度按内容字符量算…」
  「上报的全书进度按内容字符量算…」。
- **阅读时长计时规则（v2.48.1）**：只有两种情况计时——① 阅读页在最上层
  （前台可见）；② **听书播放中 = 在读**（`TtsPlaybackStatus.playing`）。
  其余（被盖住且没在听书、切后台且没在听书）一律不计时。实现：
  `app/router.dart` 的 `routeObserver`（挂进 GoRouter `observers`）+
  ReaderPage `RouteAware`：`didPushNext` → 置 `_readerCovered`，**没在听书才
  `flush()`**；`didPopNext` → `start()`；tracker 构造传 `isListening:
  _isTtsPlaying` / `isCovered: () => _readerCovered`，lifecycle 回前台时
  「盖住且没在听书」才不恢复。ReaderPage 还监听 `_tts`（ValueNotifier）状态
  跳变（`_onTtsStateChanged`，只在 playing↔非 playing 才动作）：盖住期间
  开始播放 → `start()`，停了 → `flush()`——开着朗读面板听书照样计时，
  面板里暂停就走表。听书中切后台也不结算（后台收听计入，回来接着算）。
  页内抽屉（目录）不算覆盖，仍计时。**别去掉 routeObserver / isListening
  / isCovered**——那是「挂个页面时长也涨」或「听书不计」的根因。
  回归：`reading_session_tracker_test.dart` 的「听书播放中：切后台不结算…」
  「被盖住且没在听书…」「被盖住但在听书…」「阅读页最上层…」。
- **点桌面图标：阅读中保持阅读页，其它页回首页**（v2.22.1 调整，v2.41.0 起 `/` 的默认
  Tab 是首页）：`launchMode=singleTop`，进程还活着时点图标 Android 走 `onNewIntent`；
  `MainActivity` 发 `qyreader/launch`，`app/launch_reset.dart` 先查
  `activeReaderBookSync()/activeReaderBook()`：**正在阅读就忽略归位**（切后台再回来
  不合书），不在阅读页才 `router.go('/')`。
  阅读标记在 `ReaderPage.initState` 同步写内存 + prefs，`dispose` 清掉。
  冷启动本来就从 `/` 起；深链 / 文件「打开方式」（VIEW/SEND）不触发归位。
  回归用例：`test/app/launch_reset_test.dart`（阅读中不掉书 / 退出后才归位）。
- 阅读器诊断：顶栏 🐛 打开诊断面板；debug 构建可用
  `adb forward tcp:9222 localabstract:webview_devtools_remote_<pid>` 配合 `tools/devtools_eval.dart`。
- **Android 桌面组件（v2.49.0）**：三个 AppWidget——2×2「最近阅读」（封面 + 书名 +
  进度条）、2×2「今日阅读」（时长 + 每日目标进度）、4×2「最近读的书」（最近三本）。
  Flutter 侧 `features/home_widgets/` 把书架 + 统计整理成 JSON 快照，经
  `qyreader/home_widgets` 通道推给原生；Kotlin 存在 prefs `qyreader_home_widgets`
  并用 RemoteViews 渲染（不启动 Flutter 引擎）。封面在 `WidgetBitmap` 里按中心裁切
  成圆角 Bitmap（避免 Binder 超限），没有封面画书形占位图；配色走
  `values/values-night` 的 `widget_*` 颜色。点击组件经
  `HomeWidgetUpdater.openApp` 显式启动 MainActivity 并带 `EXTRA_WIDGET_ACTION`
  （`book:<id>` / `stats` / `shelf`），MainActivity 再通过
  `qyreader/widget_action` 交给 `app/widget_action.dart` 转 go_router；**不要用
  MAIN/LAUNCHER 启动**，否则会触发「点图标回首页」的 LaunchReset。同步触发点是
  `HomeWidgetSync`（书架流 / `statsRevision` / 回前台 / 每 5 分钟，600ms 防抖），
  在 `QyReaderApp.build` 里 watch 一次。`updatePeriodMillis` 30 分钟只用于跨零点
  归零与换主题，数据仍以最近一次 App 推送为准。
- **导入结果弹窗 / 导入记录（v2.49.0）**：选择器导入完成后弹 `ImportResultDialog`
  （成功 / 重复 / 失败计数 + 逐文件结果），关掉后可从书架「⋯ → 导入记录」再打开；
  记录存 prefs `import.history`（`ImportHistoryController`，keepAlive，最多 200 条），
  只有「清空记录」会删，清空不影响已导入的书。重复判定用 `import.duplicate` 错误码，
  `ImportController.importPaths` 把每个文件都写成 `ImportRecord` 再写历史；
  `importFromPath`（打开方式）也写历史但 `ImportDone.records` 留空，避免结果弹窗
  挡住自动进阅读器。`ImportDone` / `ImportError` 因此增加了 `records` 字段
  （freezed 已重新生成）。
- **自建 `Viewport` 必须显式传 `axisDirection`**：它默认是 `AxisDirection.down`，与
  `Scrollable(axisDirection: right)` 不一致时页面会竖排——手指左右滑、内容上下翻
  （v2.10.3 修的正是这个）。回归用例在 `test/features/reader/native_reader_view_test.dart`
  的「翻页沿横轴：视口主轴右向，横滑前进、竖滑不换页」。

- **微信读书同步（v2.56.0，实验性）**：设置 →「实验性功能」→「微信读书」
  （`features/settings/weread/`，路由 `/settings/weread`）。走官方 Agent API
  Gateway `POST https://i.weread.qq.com/api/agent/gateway`，Header
  `Authorization: Bearer wrk-…`，body 平铺 `api_name` + 业务参数 +
  `skill_version`（当前常量 `kWeReadSkillVersion='1.0.5'`，服务端回
  `upgrade_info` 时抛可读异常）。API Key 存 flutter_secure_storage
  `weread.apiKey`（`WeReadCredentials`）。**v2.59.0 起页面不再让用户手填 Key，
  改成扫码登录**：右上角头像按钮 → `weread_login.dart` 的 `WeReadQrLoginService`
  走网页登录接口拿 `uid`，把 `https://weread.qq.com/web/confirm?uid=…` 用
  `QrPainter`（`qr_flutter: 4.1.0`）画成二维码；用户用微信扫码确认后，
  `GET /api/auth/getLoginInfo?uid=&otp=` 返回 `succeed/webLoginVid/accessToken/
  refreshToken`，写 `wr_vid` / `wr_skey` / `wr_ql` / `wr_rt` Cookie，再
  `GET /api/userInfo?userVid=` 取昵称、`GET /api/skills/apikeyGet?only_show=1`
  （带 `X-Vid` / `X-Skey`）取官方 `wrk-` Key 存安全存储。后续同步仍走官方
  Agent API，不把 Cookie 暴露给业务层。二维码弹窗支持「保存二维码到相册」
  （微信「扫一扫 → 相册」，同一台手机也能登录）、4 位验证码（`NEED_OTP`）、
  刷新、5 分钟过期；`getLoginInfo` 是长轮询，单次 8s 超时后继续轮询。
  `wr_fp` 设备指纹存 prefs `weread.deviceFingerprint`（每台设备一份，避免扫码
  顶掉另一台的会话）。换账号时清 `weread.syncState` / `weread.lastSnapshot`；
  退出登录清 Key、账号昵称/vid 与同步状态。昵称/vid 存 prefs
  `weread.accountName` / `weread.accountVid`。页面右上角头像按钮已登录时打开
  账号弹窗（退出登录 / 重新扫码）。
  接口：`/shelf/sync` 书架、`/user/notebooks` 笔记概览（`count` + `lastSort`
  游标分页）、`/book/getprogress` 逐本进度（4 并发，单本失败不拖垮整次拉取）、
  `/book/bookmarklist` + `/review/list/mine` 划线/想法（同 range 合并）。
  对比在 `weread_compare.dart`（纯函数）：先按上次 link，再规范化书名+作者，
  再唯一书名 / 去括注书名；结论 added/updated/synced/deleted，updated 只包含
  「微信读书更新」的方向（本机进度更靠后不产生更新，绝不下调本地进度）。
  「删除」= 上次 `seen` 有、这次书架没有（首次同步不会凭空产生），本机书不删，
  只可「忽略」解除关联。同步写回：进度优先用刚解析出的 `NativeChapter.text.length`
  换算章索引+偏移（`locatePercentInChapters`），不依赖 DB `chapters.char_count`
  ——旧书/同步书的 char_count 可能是 0，会让同步后仍从第一章打开；解析失败才退回
  `saveExternalProgress`，而它现在在 char_count 全 0 时也会按章节数落到大致章节。
  EPUB 解析器同时把 `charCount` 回填为章正文长度。`applyReadingState` 写阅读状态 +
  `lastOpenedAt`；微信读书 `recordReadingTime` 与本机已导入的差额通过
  `StatsRepository.recordSession` 写成本机会话（`importedReadingSeconds` 防重复，
  会话锚在最后阅读日、最多往前 1 小时），所以书籍信息「累计时长」和统计页能看到；
  划线/想法跳转走 `_gotoAnnotationLocator`：跳转前 `holdProgress()` 挂起进度并记下
  原 locator，右下角浮出 `ReaderJumpActions`「返回原位置 / 设为阅读进度」；返回时
  `cancelProgressHold()` 回跳，设为进度时 `releaseProgress(saveCurrent:true)` 才落库。
  标注浏览中退出阅读器也保留原进度（dispose 只 cancel 不 flush）。
  **注意：微信官方 Agent API 只提供单本书累计 `recordReadingTime`，没有每日明细**，
  所以只能把累计时长按差额写成一个本机会话（锚最后阅读日），不能还原微信 App 里
  “哪些天读了多少”的逐日记录；`/readdata/detail` 的 `dailyReadTimes` 是用户级
  总时长，不能拆到单本书。
  划线用原文在本机 `NativeChapter.text` 里定位（先精确、再忽略
  空白与常见标点），找不到原文时兜底到对齐章节开头（`locateWeReadNoteFallback`），
  不再直接丢掉；只有无章节/无原文才 skipped，`importedMarks` / `importedCounts`
  防重复；整本书评按编辑时间取最新写 `Book.review`。**本机没有这本书也能看划线**：
  每张书卡都有「划线/想法」按钮，`notesFor(bookId)` 按需拉 `/book/bookmarklist` +
  `/review/list/mine` 并在面板里展示原文/想法（服务内按书缓存；两个接口各自容错，
  一个失败仍显示另一个）。状态存 prefs `weread.syncState`
  （links/seen/known/importedMarks/importedCounts/skippedCounts），上次抓取快照存
  prefs `weread.lastSnapshot`：再次进入页面先 `loadCached()` 展示（并与当前本机
  书架重新对比），**不自动联网**，点右上角刷新才重新拉取。微信读书有、
  本机没有的书可点「导入」：`/book/info` 补简介/分类/出版社，下载封面，
  用 `weread_epub.dart` 的 `buildWeReadEpub` 生成合法 EPUB 3（mimetype 首项不压缩，
  元数据含书名/作者/简介/分类/出版社/封面，**正文只有书名页**），写临时文件后走
  `BookRepository.importFromFile` 入库，再继续同步进度/状态/划线；不下载微信读书
  正文。**按编辑时间 LWW（v2.58.4）**：进度用 `currentProgress.updatedAt` 对比
  微信读书 `readUpdateTime`，远端更晚才覆盖（连回退也跟），本机更晚则保留；阅读状态
  同样只在远端更晚时改；阅读时长**只补未导入的差额，不受本机时间戳影响**（v2.59.0：
  本机更晚也补，否则微信读书那部分时长永远进不了书籍信息；`importedReadingSeconds`
  单调前进防重复）；划线/想法按 `WeReadNote.editedAt`（review 的
  `updateTime` 优先）对比本机 `Annotation.updatedAt`，只更新更晚的想法/颜色；整本
  书评按编辑时间对比 `Book.updatedAt` 取最新。
  **「同步完再进又提示新增划线」修复（v2.59.3）**：`newNoteCount` 原来用
  `totalNotes - importedCounts - skippedCounts` 反推，但 `totalNotes` 含整本书评
  （不导入标注）、同一 `range` 的多条想法又会被 `fetchNotes` 合并成一条，差值
  永远抹不平，返回页面就反复提示「新增 N 条」。现在 `WeReadSyncState` 增加
  `syncedNoteTotals`（每本上次成功处理时的远端笔记总数）：`apply` 在「笔记拉取
  完成 + 章节可用 + 远端有笔记时确实拉到了笔记」后写入 `remote.totalNotes`，
  `compare` 用它判断新增（没有基线时仍按 imported + skipped 兜底）；`fetch()`
  重建 state 时必须继续带上这个字段。回归：`weread_compare_test.dart` 的两条
  基线用例、`weread_sync_state_test.dart` 的往返断言。
  **阅读时间点 / 读完时间（v2.59.4）**：`Book` 新增 `finishedAt`（schema v6，
  `books.finished_at`），同步 payload 也带；微信读书 `apply` 取
  `/book/getprogress` 的 `book.finishTime`（只在 progress=100 时返回）写入，
  没有 `finishTime` 时退回 `readUpdateTime`。`lastOpenedAt` 继续存最后阅读时间。
  书籍信息「基础信息」新增「阅读记录」两行：最近阅读 / 读完时间（精确到分钟）。
  微信读书对比页在远端读完时间比本机新时提示「读完时间 YYYY-MM-DD」，保证
  已读完但本机还没记时间的书也会被抓取一次。注意官方接口只给最后阅读时间 +
  读完时间，**没有单本书逐日阅读明细**。回归：`weread_compare_test.dart` 的
  读完时间用例、`book_repository_impl_test.dart`（applyReadingState / 手动已读）、
  `book_test.dart` 的 `finishedAt` 往返。回归：`weread_client_test.dart`、
  `weread_compare_test.dart`、
  `weread_anchor_test.dart`、`weread_sync_state_test.dart`（状态 + 快照往返）、
  `weread_epub_test.dart`（mimetype/元数据/正文只有书名）、`weread_page_test.dart`
  （含缓存优先、360 窄屏、可重试失败、新增书导入、无本机书查看划线）、
  `reader_jump_actions_test.dart`（跳转后两个进度选择）、
  `progress_repository_impl_test.dart` 的百分比落点、
  `book_repository_impl_test.dart` 的 `applyReadingState`。**真实 API Key / 封面
  下载 / 划线定位需真机验收**。
- **书籍信息页阅读时间（v2.58.0，v2.59.0 改竖排列表）**：`BookDetailPage` 拉全量
  `daily_stats`（`bookDailyDurations(days: 36500)`）。`BookDailyBars` 不再画横向
  柱状图，改成**竖排逐日列表**（v2.59.0）：每行 = 日期 + 星期 / 横向时长条 / 时长，
  只列有记录的前 14 天；记录超过 14 天时显示 `book-daily-show-more`「显示更多（还有
  N 天）」，展开列出更早记录（`book-daily-more-<date>`，整行日期），可「收起」。
  头部是「阅读时间 + 共 N 天 · 总时长」；行 key `book-daily-row-<yyyy-MM-dd>`。
  微信读书导入的累计时长（v2.59.0 起不再因本机更新而跳过）也写进 `daily_stats`，
  所以会出现在这个列表里；受官方 API 限制只有累计值，整段锚在最后阅读日。
  回归：`test/features/book_detail/book_daily_bars_test.dart`。
  视觉自检：`flutter test .zcode/book_daily_preview_test.dart`
  → `.zcode/book-daily-preview/list.png`。
- **书籍信息笔记可跳转 / 分享（v2.58.5）**：`BookNoteCard`（`book_detail/widgets/`）
  整卡 `InkWell` 跳到阅读器里的标注位置；右上角 `book-note-share-<id>` 单独打开
  `AnnotationShareSheet`（点分享不会触发跳转）。跳转通过
  `BookLaunch.initialLocatorJson` + `holdProgress: true` 传给 `ReaderPage`：
  打开后直接落在笔记位置，但进度先挂起，右下角仍是「返回原位置 / 设为阅读进度」，
  不会因为看一条笔记改掉阅读进度。原生阅读面的起始位置由 `_nativeTargetLocator()`
  统一取「路由目标 locator → 控制器恢复进度」，`_nativeChapterFor` /
  `_nativeOffsetFor` 都走它（v2.58.6 修「只打开书、没跳到笔记位置」）。
  回归：`book_note_card_test.dart`。
- **跨页选字（v2.58.6）**：原生排版每页一个 `SelectableText`，系统选区手柄无法跨页。
  选区菜单新增「跨页」（`onCrossPage`）：打开 `cross_page_selection_sheet.dart`，
  把整章文本放进一个可滚动 `TextField(readOnly)`，在其中长按/拖手柄选任意区间，
  再点复制 / 划线 / 高亮 / 笔记；结果按章内字符区间交给阅读页直接
  `addHighlight`（`AnnotationType.underline` 或 `highlight`），笔记动作随后打开
  笔记编辑。回归：`selection_menu_test.dart`（六个动作）、
  `cross_page_selection_sheet_test.dart`（选中区间返回）。

## 8. 对话变更记录

| 2026-11-18 | 2.70.2+202 | 书架移除重复入场动画，优化滚动 | QYReader-v2.70.2-20261118-shelf-scroll.apk |

| 2026-11-18 | 2.70.1+201 | 修复覆盖导入正文后跨设备书源不同步，并恢复旧记录；分析及 723 项测试通过 | QYReader-v2.70.1-20261118-content-sync.apk；QYReader-v2.70.1-20261118-windows-x64.zip |

| 2026-11-18 | 2.70.0+200 | 排查覆盖导入后跨设备书源不同步，发现合并遗漏书源字段，尚未修复；仅文档更新，未递增版本 | QYReader-v2.70.0-20261118-author-manager.apk |

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
| 2026-11-12 | 2.41.0+131 | 新增「首页」底部 Tab（四个 Tab：首页 / 书架 / 统计 / 设置，默认启动首页）：`home_tabs.dart` 统一定义 `HomeTab` / `kHomeTabs`，`HomeShell` 用 `IndexedStack` 承载 `HomePage`；首页四张白卡片——累计阅读（累计时长 + 已读完本数，点卡片进统计）、继续阅读（`continueReadingItems`，最近打开倒序）、今日目标（240° 圆弧 + 今日分:秒 + 每日目标编辑 +「开始阅读」优先续最近在读）、今年读完的书（`finishedThisYear` + 年度目标 prefs `home.yearlyGoalBooks` 默认 24）；数据整理在 `home_stats.dart`（纯函数）、年度目标在 `home_prefs.dart`；补 14 项回归（共 427 项） | `qyreader/QYReader-v2.41.0-20261112-home-dashboard.apk`、`qyreader/QYReader-v2.41.0-20261112-windows-x64.zip` |
| 2026-11-12 | 2.41.1+132 | ① 最近在读上限：`recentlyReadItems` 默认最多 `kRecentShelfMax = 8` 本（原先 20 本会横向滑出架板、书脊被切在屏幕外），超出的书仍留在下面的网格里；② 书架滑动优化：`ShelfPage` 给最近在读外层套 `RepaintBoundary`，竖向滚动只平移不重画书脊渐变；`ShelfFlow` 的冷启动 stagger 入场动画只作用于前 `kShelfEntranceCells = 9` 格，滚动懒加载的新行不再重放 0.5s 淡入（滑动掉帧的主因）；补 1 项回归（共 428 项） | `qyreader/QYReader-v2.41.1-20261112-home-dashboard-shelf-scroll.apk`、`qyreader/QYReader-v2.41.1-20261112-windows-x64.zip` |
| 2026-11-12 | 2.41.2+133 | 修首页「今日目标」圆弧被拉扁：原来 `CustomPaint` 用 `Positioned.fill` 铺满卡片宽度、高度只有 224，宽高不等把圆弧画成扁椭圆；改为 `Center` + `ConstrainedBox(maxWidth/maxHeight: 300)` + `AspectRatio(1)` 的正方形画布，圆弧恢复正圆比例（小屏自适应缩写）；离屏预览确认 300dp 圆弧与卡片宽度协调 | `qyreader/QYReader-v2.41.2-20261112-home-arc-round.apk`、`qyreader/QYReader-v2.41.2-20261112-windows-x64.zip` |
| 2026-11-12 | 2.41.3+134 | 宽屏布局适配：新增 `app/theme/layout.dart` 的 `kContentMaxWidth = 900`，首页 / 统计页的 ListView 外套 `Center` + `ConstrainedBox`，统计汇总卡 `_PeriodSummary` 按宽度自动 2~4 列（1512 宽从两张巨卡变为四张正常卡片）；首页「开始阅读」按钮最宽 420；`FloatingNavBar` 居中限宽 640，不再横跨整屏；补 4 项回归（`stats_page_layout_test.dart`、首页宽屏、底栏宽屏，共 432 项） | `qyreader/QYReader-v2.41.3-20261112-wide-layout.apk`、`qyreader/QYReader-v2.41.3-20261112-windows-x64.zip` |
| 2026-11-12 | 2.41.4+135 | 书架「最近在读」不再固定 8 本：新增 `recentShelfVisibleItems(items, 屏宽)`，按书脊实际宽度（30/34/38 + 书间 3、左右各 20）从最近打开往前取到放不下为止；`ShelfPage` 传入屏宽裁切，`RecentShelf` 由横向 ListView 改为居中的 `Row`（书少居中、书多填满架板，不横滑、不裁半本）；`recentlyReadItems` 取消默认上限（`limit` 只留给单测）；补 4 项回归（宽窄屏取数、居中、无截断，共 436 项） | `qyreader/QYReader-v2.41.4-20261112-recent-shelf-fit.apk`、`qyreader/QYReader-v2.41.4-20261112-windows-x64.zip` |
| 2026-11-13 | 2.41.5+136 | 修 2.41.3 引入的底栏布局 bug：`FloatingNavBar` 限宽用的 `Center` 在 `bottomNavigationBar` 插槽里被撑满整屏，body 高度变 0、底栏浮到屏幕中间（用户截图整页空白）。给 `Center` 加 `heightFactor: 1`，底栏只占自身 76dp；补「作为 bottomNavigationBar 时只占自身高度」回归（共 437 项） | `qyreader/QYReader-v2.41.5-20261113-nav-height-fix.apk`、`qyreader/QYReader-v2.41.5-20261113-windows-x64.zip` |
| 2026-11-13 | 2.41.6+137 | 修同步「只读一本书却像把所有书都同步一遍」：① `_pull` 已知 op 直接按对象 key（`ops/<opId>.json`）跳过，不再下载，进度只为真正应用的 op 报书名；② 拉回来的远端 op 以 `uploaded_at = 0` 标记，`_uploadShards` 只接收本次 `_push` 实际推出去的书（`push.books`），拉取不再反过来重传分片（旧逻辑按 `uploaded_at` 时间窗会把远端改动过的书全部重新导出上传，越同步越慢）；`LocalObjectStore` 加 `putKeys` 供测试断言；补 2 项回归（共 439 项） | `qyreader/QYReader-v2.41.6-20261113-sync-incremental.apk`、`qyreader/QYReader-v2.41.6-20261113-windows-x64.zip` |
| 2026-11-13 | 2.41.7+138 | 阅读主题参与同步：新增 `data/sync/theme_sync.dart`，自定义主题清单整体上传到 `spaces/<空间>/themes.json`（`{updatedAt, themes}`，LWW）；`ReaderThemesController` 每次保存 / 改名 / 删除写 `reader.themesSyncAt`，旧版本无时间戳时与云端按 id 并集；主题背景图只存文件名，下载后还原到本机 `QYReader/backgrounds/`（排在背景同步之后），删除主题随清单传播；同步完成后面板 / 书架快捷同步调 `ReaderThemesController.reload()`，当前主题不存在时回退「纸」；`SyncResult.themesSynced` + 摘要「同步 N 个主题」；补 4 项回归（共 443 项） | `qyreader/QYReader-v2.41.7-20261113-theme-sync.apk`、`qyreader/QYReader-v2.41.7-20261113-windows-x64.zip` |
| 2026-11-13 | 2.41.8+139 | 阅读背景图不再只能裁切：`ReadingSettings` 新增 `backgroundFit`（填充裁切 / 完整显示 / 拉伸铺满 / 适应宽度 / 适应高度），`_PageBackground` 按该值映射 `BoxFit`；排版面板「页面」页签在设置了背景图时显示「背景图显示」下拉框，选中即写入设置并随主题快照 / 主题同步走；补 3 项回归（设置往返、五种 BoxFit 映射、面板切换，共 446 项） | `qyreader/QYReader-v2.41.8-20261113-background-fit.apk`、`qyreader/QYReader-v2.41.8-20261113-windows-x64.zip` |
| 2026-11-13 | 2.42.0+140 | 新增「我的阅读」：设置 → 管理进入，按「全部 / 在读 / 搁置 / 读完」筛选、书名/作者搜索，按年 > 月时间线展示（可折叠、带本数），卡片显示读到百分比或累计时长 + 开始阅读/读完时间 + 字数/时长 + 封面；数据汇总新增 `StatsRepository.bookTotals()`（一次读 `daily_stats` 单书行，排除全书合计）；分享面板提供深/浅两套 9:16 海报模板，`保存` 走 `gal` 存相册（失败退应用目录）、`分享` 走 `share_plus` 系统分享；新增 `share_plus` / `gal` 依赖；补 8 项回归（数据/页面/分享面板/bookTotals，共 454 项） | `qyreader/QYReader-v2.42.0-20261113-my-reading.apk`、`qyreader/QYReader-v2.42.0-20261113-windows-x64.zip` |
| 2026-11-13 | 2.43.0+141 | 新增「笔记回顾」：设置 → 管理进入，概览页按书汇总笔记数 + 已读时长/字数 + 封面，支持书名/作者/原文/想法搜索和按最近 / 条数 / 书名排序；笔记漫游页按「全部 / 划线 / 书签」筛选，`PageView` 卡片式左右滑动（类型、`yy/MM/dd HH:mm`、原文/标签、想法、书名作者封面、`1 / N` 页码），可按书籍筛选；`AnnotationRepository` 新增 `watchAll()` / `watchAllBookmarks()` 全库流，增删实时刷新；补 8 项回归（笔记数据 / 两页交互 / 全库流，共 462 项） | `qyreader/QYReader-v2.43.0-20261113-notes-review.apk`、`qyreader/QYReader-v2.43.0-20261113-windows-x64.zip` |
| 2026-11-13 | 2.44.0+142 | 重做阅读页选中弹窗：长按选字后为「复制 / 划线 / 高亮 / 笔记 / 从此听」五项悬浮菜单；划线使用新增的 `AnnotationType.underline`（正文 `TextDecoration.underline`、不铺底色），高亮仍铺底色；笔记先建默认高亮再聚焦输入；从此听从当前页启动 TTS；标注编辑弹窗改为颜色圆点 + 复制 / 擦除 / 添加笔记 + 「写点笔记吧~」输入；`addHighlight` 支持 `type`，`NativeMark` 支持 underline 并参与 span 拆分；补 4 项回归（菜单五项 / 编辑弹窗 / 下划线渲染 / 下划线类型落库，共 466 项） | `qyreader/QYReader-v2.44.0-20261113-selection-menu.apk`、`qyreader/QYReader-v2.44.0-20261113-windows-x64.zip` |
| 2026-11-13 | 2.44.1+143 | ① 修键盘升起时标注编辑弹窗被压成一条缝：去掉外层重复的 `AnimatedPadding(viewInsets)`，让 Dialog 自己处理键盘 inset，内容在可用高度内滚动；② 标注列表新增「全部类型 / 高亮 / 划线」筛选胶囊，与按章节 / 按颜色分组可叠加，筛选后计数显示「共 X/Y 条」，空结果有提示；补 2 项回归（键盘高度 / 类型筛选，共 468 项） | `qyreader/QYReader-v2.44.1-20261113-annotation-fix.apk`、`qyreader/QYReader-v2.44.1-20261113-windows-x64.zip` |
| 2026-11-13 | 2.44.2+144 | 修「已选中文字后拖手柄无法扩展选区」：`_onRunSelection` 在 `SelectionChangedCause.drag` 时不再回调 `onSelectionClear`，避免外层 setState 重建 `NativeReaderView`、把正在拖动的选区手柄重挂/移除；新增 `selectionChangeClosesMenu` 纯函数回归（共 469 项） | `qyreader/QYReader-v2.44.2-20261113-selection-drag-fix.apk`、`qyreader/QYReader-v2.44.2-20261113-windows-x64.zip` |
| 2026-11-13 | 2.45.0+145 | ① 添加书签前弹备注输入（可留空/取消），备注写入 `Bookmark.label` 并随 sync_ops 同步，目录书签与笔记漫游直接展示；② 朗读面板新增 Android 引擎选择：`TtsSettings.engine` + `getEngines`/`setEngine`，切换引擎后重设中文并按新引擎重载音色，`ttsEngineLabel` 识别「小米 MiMo」；补 5 项回归（书签备注弹窗 / 仓储 label / 引擎映射 / 面板切引擎，共 474 项） | `qyreader/QYReader-v2.45.0-20261113-mimo-tts.apk`、`qyreader/QYReader-v2.45.0-20261113-windows-x64.zip` |
| 2026-11-13 | 2.45.1+146 | 修同步报错只有「MinioError: Forbidden」看不出真实原因：排查确认是阿里云 OSS 账号停机（匿名探桶返回 `UserDisable` / EC 0003-00000801，欠费结清后恢复）；App 侧新增 `describeStoreError`（带 HTTP 状态 / S3 Code / 请求 ID，非 S3 异常透传），「测试连接」改为 GET 列举探测拿真码（HEAD 无响应体拿不到），syncNow 总 catch 与备份阶段都改用它；补 6 项回归（共 480 项） | `qyreader/QYReader-v2.45.1-20261113-sync-error-detail.apk` |
| 2026-11-13 | 2.46.0+147 | 阅读时长参与同步（此前 daily_stats / reading_sessions 完全不在同步协议里，换设备看不到当日时长）：`recordSession` 与会话同事务写 `entity='session'` op（opId=`ses-<会话id>`），`_mergeSession` 按会话 id 幂等合并（只增不改、不用 LWW），合并后按 `startedAt` 本地日**重算** daily_stats（单书 + 全书合计，会话消失的书归零），会话不触发分片重传（`_bookIdOfOp` 排除 session）；**历史会话补传**：`syncNow` 首次跑 `_backfillSessionOps` 把升级前 deviceId 为本机的会话补写 op（状态表 `sync.sessionsBackfilled` 置位、只认本机会话防回声），同步进度显示「正在同步《书》的阅读时长」；补 4 项回归（会话 op 落库 / 两设备合并重算 / 各读一段求和 / 历史补传，共 484 项） | `qyreader/QYReader-v2.46.0-20261113-reading-time-sync.apk`（含补传重出） |
| 2026-11-14 | 2.46.1+148 | 双页模式下页眉/页脚改为整屏一份（原来每页各画一份，两份章名/时间/电量并排）：正文区抽成 `_pageBody`、带抽成 `_runningBand`，`_spreadFrame` 双页走 Column[带, Row[左右两栏正文], 带]，带的内容按本屏第一张可见内容页解析（普通屏 = 左页，与翻页锚点同口径）；分页几何与正文区高度不变；排版/边距预览页在双页下同样整屏单份；原双页回归加强为断言章页码与全书进度各只出现一次（共 484 项） | `qyreader/QYReader-v2.46.1-20261114-dual-page-single-chrome.apk` |
| 2026-11-14 | 2.47.0+149 | 新增自动同步：「同步存储」页改名「同步设置」，顶部加「自动同步」间隔下拉（关闭 / 5 / 10 / 15 / 30 / 60 分钟，prefs `sync.autoMinutes`）；`AutoSyncController` 持 Timer.periodic 按间隔静默跑 syncNow（前台才执行、进行中/未配置跳过、不弹提示），HomeShell initState 启动 keepAlive 控制器；`syncNow` 加防重入守卫（撞车返回空结果）；补 5 项回归（共 489 项） | `qyreader/QYReader-v2.47.0-20261114-auto-sync.apk` |
| 2026-11-14 | 2.48.0+150 | ① 单页最长计时：统计页 ⏱ 设置上限（默认 10 分钟），会话按页分段计时、每段封顶后求和（`countedDurationMs`，startedAt/endedAt 保持真实墙钟），会话 op 同口径；② 全书进度改按内容字符量（原按章数均摊失真）：上报 / 书架角标 / 全书拖动跳转 / 页眉页脚全文进度同口径（底栏进度条「全书/本章」切换原本就有，默认全书）；③ 阅读时长只在阅读页最上层计时：RouteAware 盖住（搜索/弹窗/面板）即结算暂停、回来恢复，回前台仍被盖住不恢复；补 14 项回归（封顶分段/回翻/同页/内容口径往返/上报口径/mayResume 守卫/prefs，共 503 项） | `qyreader/QYReader-v2.48.0-20261114-pagecap-progress.apk` |
| 2026-11-14 | 2.48.1+151 | 阅读时长计时规则收紧：只有「阅读页最上层（前台）」或「听书播放中」才计时，其余（被搜索/面板/弹窗盖住且没在听书、切后台没在听书）不计时；tracker 改 isListening/isCovered 双门，ReaderPage 监听 TTS 播放状态跳变（盖住期间开播恢复计时、暂停结算），听书中切后台也不结算（后台收听计入）；首页/统计页每次显示就刷新（StatsPage 加 active 切 Tab 重拉，HomeShell RouteAware 回到主框架时重建首页/统计页）；补 4 项计时规则回归 + 1 项统计页刷新回归（共 506 项） | `qyreader/QYReader-v2.48.1-20261114-time-rules-refresh.apk` |
| 2026-11-14 | 2.49.0+152 | 新增 Android 桌面组件：2×2 最近阅读（封面 + 进度条）、2×2 今日阅读（时长 + 目标）、4×2 最近三本书；Flutter 推 JSON 快照（`qyreader/home_widgets`），Kotlin RemoteViews 渲染并做圆角封面，点击经 `qyreader/widget_action` 直达书籍 / 统计 / 书架；新增导入结果弹窗（成功 / 重复 / 失败计数 + 逐文件记录），记录持久化在 prefs `import.history`，可从书架「⋯ → 导入记录」回看、清空前一直保留；顺手修 `route_aware_shell_test` 里 `await router.push` 导致的 10 分钟超时；补 11 项回归（桌面组件数据 4 / 导入记录 4 / 弹窗 3），另修 `route_aware_shell_test` 的 `await router.push` 超时；共 519 项） | `qyreader/QYReader-v2.49.0-20261114-home-widgets.apk` |
| 2026-11-15 | 2.50.0+153 | 听书大改版：①「从此听」真正从选中的那句读起（`TtsSurface.ttsSegments` 加 `startOffset`，原生桥按「包含该偏移的句子」过滤，WebView 链路收下忽略）；② 新增全屏听书页 `/reader/:bookId/tts`（extra 传 `TtsPageLaunch(controller, bookTitle)`）：当前句大字 + i/N 进度、上一句/下一句/播放暂停/停止（`goToSentence` = epoch++ → stop → 置 index → 重入 runLoop）、倍速/引擎/音色/定时（含 90 分）/背景音乐+音量；朗读控制条信息区可点进听书页，听书中点底栏「朗读」也直达；③ 背景音乐：`BgmPlayer`（audioplayers 循环播放、mixWithOthers 不抢 TTS 焦点、全局单例），跟随朗读起停；内置 3 条曲目（`.zcode/gen_bgm.py` 合成雨声/白噪/轻音乐，`assets/music/` 各约 230KB）；导入音频由 `AudioLibraryController` 管理（`<support>/music` + prefs `reader.audio`，7 种扩展名、100MB 上限），`TtsSettings` 加 `bgmId`/`bgmVolume`；设置 → 资源新增「听书音频」管理页（试听/导入/删除，删除引用中的曲目同时清设置）；④ 音频参与同步：`AudioSync` 照 FontSync 模式（`spaces/<空间>/music/track-<sha256>.<ext>` + manifest、并集语义），`SyncResult.audiosSynced` 摘要「同步 N 个音频」，同步完成自动刷新音频库；⑤ 缓存中心 3→4 页签（新增「音频」，只清本地、云端保留）；补 14 项回归（选区起点/句级跳转/控制条/听书页/音频库/音频同步/bgm 字段/4 页签/摘要，共 533 项）；BGM 混音焦点与 MiMo 引擎待真机验收 | `qyreader/QYReader-v2.50.0-20261115-tts-listen-page-bgm.apk` |
| 2026-11-15 | 2.51.0+154 | 接入小米 MiMo 云端大模型语音合成（mimo.mi.com 开放平台，OpenAI 兼容 chat/completions）：引擎下拉新增「小米 MiMo · 云端」（`kMimoTtsEngine='cloud.xiaomi.mimo'`），选中后逐句经云端合成（文本放 assistant 消息、`audio.format=wav`、base64 解码后 BytesSource 播放），非默认语速加 user 语速指令；预置 9 个音色（冰糖/茉莉/苏打/白桦 + 英文 4 个 + 默认）；API Key 存 flutter_secure_storage（听书页选中云端引擎时出配置卡，未配 Key 报具体提示）；32 条句子合成缓存（暂停续播/回听不重复请求）；合成错误带出接口原文（HTTP 状态 + error.message）；模型 ID 常量 `kMimoTtsModel='mimo-v2.5-tts'`（小米若下线 V2.5 改一个常量即可）；补 9 项回归（客户端请求/响应/错误 + 控制器云端路径/未配 Key/音色表，共 542 项）；需真机配 API Key 验收合成效果与延迟 | `qyreader/QYReader-v2.51.0-20261115-mimo-cloud-tts.apk` |
| 2026-11-15 | 2.51.1+155 | 听书弹窗直接配置 MiMo API Key：`_MimoKeyCard` 从听书页抽成共用组件 `tts/mimo_key_card.dart`（`MimoKeyCard`），朗读面板选中「小米 MiMo · 云端」时内嵌 Key 输入卡（粘贴/保存/清除，secure storage 即时读写，保存后下次开始朗读生效），不用再跳听书页；说明文案同步更新；补 1 项回归（弹窗选云端引擎 → 出现 Key 卡 → 保存落 secure storage → 清除，共 543 项） | `qyreader/QYReader-v2.51.1-20261115-mimo-key-in-sheet.apk` |
| 2026-11-15 | 2.51.2+156 | 修 MiMo 云端朗读句间明显卡顿（每句都要现场等一次 HTTP 合成）：起播当前句的同时**预取后面两句**（`_prefetchAhead`/`_prefetchOne`，`_mimoPrefetching` 记在途请求防重复，读到时仍在途就等它），把合成延迟藏进上一句的播放时间里；预取失败静默、读到时按需重试并正常报错；合成缓存沿用 32 条 FIFO；补 1 项回归（播第一句时第二句已在请求、全章各合成一次无重复，共 544 项） | `qyreader/QYReader-v2.51.2-20261115-mimo-tts-prefetch.apk` |
| 2026-11-15 | 2.51.3+157 | 修两个真机问题：① 听书不能倍速——听书页倍速滑杆只落设置从未调 `updateRate`（播放中拖动无反应），且 MiMo 的 user 语速指令实测无效；重做为播放器即时变速（`setPlaybackRate`，当前句生效、合成缓存不再按倍速分开、删掉指令），滑杆拖动实时调 `_tts.updateRate`；② 背景音乐没有声音——`_syncBgm`/听书页换曲的曲目查找只查了导入音频列表，选内置曲目（雨声等）时返回 null 直接 stop；改回 `allAudioTracks(...)`（内置 + 导入）；补 1 项倍速路径回归、删 1 项指令用例（共 543 项）；>1x 音调升高为 MediaPlayer 内核限制，后续可上流式/ExoPlayer | `qyreader/QYReader-v2.51.3-20261115-mimo-rate-bgm-fix.apk` |
| 2026-11-15 | 2.51.4+159 | 修 TTS 切句：`splitSentences` 只并连续句末标点，`你说："很好吃。"` 的闭合引号被剩成下一句（半截引号单独合成+高亮错位）；句末标点 run 后现在会吞闭合引号/括号/书名号（含 `。"…` 交错），引语与叙述仍自然分句；补 6 项切句回归（共 549 项） | `qyreader/QYReader-v2.51.4-20261115-tts-quote-split.apk` |
| 2026-11-15 | 2.52.0+160 | 听书控制器全局化：`TtsPlayback` 改 Riverpod keepAlive 单例（退出阅读页继续朗读，切句/切章/高亮不依赖阅读页，旧 NativeTtsSurface 删除）；阅读页 bindReader/unbindReader 绑定跳转执行器与全书读完提示，高亮走状态 + ref.listen；背景音乐协调搬进控制器；HomeShell 底栏上方常驻全局听书控制条（GlobalTtsBar，点信息区进听书页）；听书页去 extra 改按 bookId 从 provider 取状态，页头新增「回到书籍」（栈里有阅读页就 pop，否则直接打开该书的阅读页），idle 点播放从上次停下的句子 restart；已知限制：退出书后听书时长不计入统计（会话跟阅读页走）；重写 tts_playback/tts_page 测试 + 新增全局条测试（共 554 项） | `qyreader/QYReader-v2.52.0-20261115-global-tts-bar.apk` |
| 2026-11-15 | 2.52.1+161 | 修「退出书籍后主页看不到听书控制条」：v2.52.0 只把条挂在 HomeShell 上，从书籍详情/我的阅读等二级页进出书籍、或路由栈变化时看不到；改为双挂载点——HomeShell 底栏上方（导航栏不遮）+ MaterialApp.builder 覆盖层（只对非主框架路由显示，按栈顶 matchedLocation 判定；阅读页/听书页用可重入 suppress 计数声明盖住）；TtsBar 加 tooltips 开关（覆盖层在 Navigator Overlay 之外，Tooltip 需要 Overlay 祖先）；覆盖层跳转改走 routerProvider.push（builder context 拿不到 GoRouter）；补 4 项覆盖层回归（主框架让位/非主框架显示+点击进听书页/suppress 隐藏/空闲收缩，共 556 项）；同版本重出追加 tts-diag 日志（start/stop/fail/pause） | `qyreader/QYReader-v2.52.1-20261115-tts-bar-everywhere.apk` |
| 2026-11-15 | 2.52.2+162 | 修「每次点开听书弹窗引擎都显示系统默认」：`TtsSettings` 是异步从 prefs 恢复的，冷启动后第一次访问拿到默认值（引擎=null → 显示系统默认；期间的读取/写入会用错值，开始朗读用错引擎、写入抹掉上次选择）；`TtsSettingsController` 加 `waitRestored()/restored` 屏障——`update()` 先等恢复再写、`_startListening` 读取设置前先等恢复、弹窗与听书页的引擎行恢复完成前显示「读取中…」；补 3 项回归（种入 prefs 弹窗显示 MiMo / 弹窗选择后重开仍显示 / 恢复前写入不被覆盖，共 559 项） | `qyreader/QYReader-v2.52.2-20261115-tts-engine-restore.apk` |
| 2026-11-15 | 2.53.0+163 | ① 新增「选择声音」音色面板（照主流听书 App）：顶部朗读引擎卡片行（面板内切引擎）+ 音色按语言分组（中文·5 / 英文·4，行 = 名称+标签胶囊+试听+当前选中勾与描边）；MiMo 云端音色可试听（独立播放器合成一小段示例，朗读中自动暂停避免叠音）；听书页/弹窗的音色 dropdown 换成该面板入口；② 听书中切音色/引擎**从当前句重新读**（`changeVoice`/`changeEngine`：写设置 → active 时 goToSentence 当前句，MiMo 按音色重新合成、切引擎走 _ensureEngine）；③ 倍速滑杆改 0.1 步进（divisions 15）；④ 大修：控制器 `_settings` 从字段缓存改为 provider 实时读取（字段式缓存在设置异步恢复完成后陈旧，picker/听书页读全是默认值），`start()` 收编传入设置；补 6 项回归（picker 分组/选中/面板内切引擎 + 切音色重读等，共 563 项） | `qyreader/QYReader-v2.53.0-20261115-voice-picker-rate010.apk` |
| 2026-11-15 | 2.54.0+164 | 听书页改版为「文稿」式（参照主流听书 App，不必全同）：中部整章句子随朗读滚动（已读变淡/当前句加粗+accent 下划线/未读正常，点句跳转，自动滚到当前句）；底部三层——功能行（原文=回到书籍 / 语速（显示倍速，点开 0.1 步进面板）/ 音色（选择声音面板）/ 音乐 / 设置）、进度滑杆（当前句/本章句数 + 两侧上一句/下一句）、运输排（停止 / 大播放键 / ⏰）；引擎/定时/背景音乐抽到独立「朗读设置」面板；状态加 sentences（start/续章写入）；旧控制卡删除；测试重写（共 563 项） | `qyreader/QYReader-v2.54.0-20261115-tts-manuscript-ui.apk` |
| 2026-11-15 | 2.54.1+165 | 听书中「定位朗读句」按钮：阅读页在听书激活且当前句不在可见页时，右上角浮出定位胶囊，点按跳到正在读的句（章节不同先跳章）；`NativeReaderViewState` 新增 `isOffsetVisible(chapterIdx, offset)`（章匹配 + 偏移落在当前 spread 任一页 range 内，双页取两页）；补 1 项回归（页内可见/他页/他章不可见/跳页翻转，共 564 项） | `qyreader/QYReader-v2.54.1-20261115-tts-locate-button.apk` |
| 2026-11-15 | 2.55.0+166 | 笔记/划线/高亮卡片式分享：新增「卡片分享」面板（三模板胶囊切换——墨句深色渐变/便签纸面+标注色侧条/简约白底居中；内容 = 原文+想法+书名作者+日期+角标，4:5 比例；RepaintBoundary→PNG→gal 存相册/share_plus 分享）；入口 = 笔记漫游页卡片分享按钮（NoteEntry 加 colorToken）+ 阅读页标注列表行分享按钮（AnnotationTab/TocDrawer/_Panel 传书名作者链，kindLabel 按类型）；补 4 项回归（三模板渲染切换/无想法划线/列表分享入口/漫游头部不溢出，共 567 项） | `qyreader/QYReader-v2.55.0-20261115-annotation-card-share.apk` |
| 2026-11-15 | 2.55.1+167 | 修听书高亮盖住段首缩进：`_runSpans` 的 TTS 高亮加 `skipLeadingIndent`——起点钳到段正文首字（layout.paragraphs 的 displayStart）并跳过缩进字符（零宽锚/NBSP/全角半角空格），无论缩进来自哪条路径都不参与高亮；用户标注（划线/高亮）不受影响（仍按原区间）；补 1 项 span 级回归（高亮 span 无缩进码点，共 568 项）；视觉自检 `.zcode/tts_indent_preview_test.dart` | `qyreader/QYReader-v2.55.1-20261115-tts-indent-fix.apk` |
| 2026-11-15 | 2.56.0+168 | 分类管理页改版为层级分类（参照主流阅读 App）：分类支持「/」路径（小说/科幻），管理页建树展示（缩进+折叠箭头+文件夹图标+计数含后代+⋯菜单：重命名/添加子分类/删除=清空子树）；AppBar 加搜索（过滤分类）与新建；头部「N 个分类 + 收起全部/展开全部」；空分类持久化 prefs categories.extra 与书分类合并建树；重命名=子树整体改前缀（逐本同步日志）；纯函数层 category_tree.dart 可单测；长按多选/拖拽排序未做；补 8 项回归（建树/计数/折叠/搜索/改名/页面渲染/新建路径/空分类，共 575 项） | `qyreader/QYReader-v2.56.0-20261115-category-tree-manager.apk` |
| 2026-11-15 | 2.55.2+169 | 修「听书暂停不了」：启动窗口期（preparing，MiMo 首句合成要几秒）pause 原来直接 return，用户点击被丢弃——现在挂起 `_pauseRequested` 标志、开读即停；听书页大播放键与 TtsBar 暂停键全程可点；逐句 tts-diag: speak 日志（章/序/文本）便于定位开始位置类反馈；补 2 项回归（preparing 窗口暂停开读即停 / 暂停后恢复从原句继续，共 577 项） | `qyreader/QYReader-v2.55.2-20261115-tts-pause-window-fix.apk` |
| 2026-11-17 | 2.56.0+170 | 新增实验性功能「微信读书」：设置 → 实验性功能 → 微信读书（`/settings/weread`），右上角钥匙按钮填 API Key（flutter_secure_storage `weread.apiKey`），走官方 Agent API Gateway（`/shelf/sync`、`/user/notebooks` 分页、`/book/getprogress` 4 并发、`/book/bookmarklist`+`/review/list/mine`）；拉取后逐本与本机书架对比：新增（微信读书有、本机无，不自动下载正文）/ 更新（进度、已读完、划线想法、最近阅读更晚）/ 一致 / 删除（上次 seen 有、这次移除，本机书保留可忽略）；支持单本 / 全部同步——百分比按章节字数换算 locator 落点、写 readStatus + lastOpenedAt、划线按原文定位导入（精确 + 忽略空白，找不到跳过并计数）、整本书评补到 Book.review；`importedMarks`/`importedCounts`/`skippedCounts` 防重复，状态存 prefs `weread.syncState`；同步只前进不后退，划线接口/章节解析失败时可重试（不标「已一致」）；补 30 项回归（客户端/对比/定位/状态/页面含 360 窄屏与可重试失败/百分比进度/applyReadingState，共 607 项）；真实 API Key 与划线定位需真机验收 | `qyreader/QYReader-v2.56.0-20261117-weread-sync.apk` |
| 2026-11-17 | 2.57.0+171 | 微信读书「新增」书可导入：本机没有的书点「导入/全部导入」→ `/book/info` 补简介/分类/出版社，下载封面（协议相对 URL 补 https，8MB 上限），`weread_epub.dart:buildWeReadEpub` 生成合法 EPUB 3（mimetype 首项 store、书名/作者/简介/分类/出版社/封面元数据、正文只有书名页），写临时文件后走 `BookRepository.importFromFile` 入库（重复则复用），再继续同步进度/状态/划线；导入后差异行用 `localOverride` 变成本机已一致；新增 5 项回归（EPUB mimetype/元数据/正文、`/book/info` 解析、页面导入，共 612 项）；真机验收封面下载与生成书阅读 | `qyreader/QYReader-v2.57.0-20261117-weread-import-epub.apk` |
| 2026-11-17 | 2.58.0+172 | ① 微信读书抓取结果缓存（prefs `weread.lastSnapshot`）：再次进入先 `loadCached()` 展示上次快照并与当前本机书架重新对比，不自动联网，点刷新才重新拉取；② 修「同步后仍从第一章打开」：进度优先用解析出的 `NativeChapter.text.length` 换算章索引/偏移（`locatePercentInChapters`），不依赖可能为 0 的 `chapters.char_count`；EPUB 解析器回填 `charCount`，`saveExternalProgress` 在 char_count 全 0 时按章节数兜底；③ 书籍信息页阅读时间只显示有记录的前 14 天（不再补 0 值空柱），超过 14 天显示「显示更多（还有 N 天）」并可展开/收起更早记录；补 7 项回归（快照往返、缓存优先、进度落点、日柱展开等，共 619 项） | `qyreader/QYReader-v2.58.0-20261117-weread-cache-progress-daily.apk` |
| 2026-11-17 | 2.58.1+173 | 修「微信读书划线没同步、没书也看不到」：① 每张微信读书书卡新增「划线/想法」按钮（`weread-notes-sheet.dart`），`notesFor(bookId)` 按需拉 `/book/bookmarklist` + `/review/list/mine`，**本机没有这本书也能查看原文与想法**；② 两个笔记接口各自容错，一个失败仍显示另一个，并兼容 `updated`/`bookmarks` 两种回包；③ 原文定位忽略空白与常见标点，仍找不到时兜底到对齐章节开头（`locateWeReadNoteFallback`）而不是丢弃；④ 导入同步时共用按书缓存的笔记，避免查看后再次请求；补 4 项回归（无本机书查看划线、划线接口失败仍有想法、标点差异定位、章首兜底，共 623 项） | `qyreader/QYReader-v2.58.1-20261117-weread-notes-view.apk` |
| 2026-11-17 | 2.58.2+174 | 修「阅读时间没有同步过来」：微信读书 `/book/getprogress` 的 `recordReadingTime` 之前只用于页面展示，没有写进本机统计。现在同步时按 `importedReadingSeconds` 只补差额，通过 `StatsRepository.recordSession` 写成本机会话（会话锚最后阅读日、最多回看 1 小时，`durationMs` 为完整差额），书籍信息「累计时长」与统计页可见；差异对比增加「阅读时长 +X」并标更新；补 3 项回归（时长差额导入标记、状态往返、对比提示，共 624 项） | `qyreader/QYReader-v2.58.2-20261117-weread-reading-time.apk` |
| 2026-11-17 | 2.58.3+175 | 修「从划线定位跳转后默认改了阅读进度」：标注跳转改为 `_gotoAnnotationLocator`，跳转前 `holdProgress()` 挂起进度并记下原 locator，`onRelocated` / `flushProgress` / `saveLocator` / `_write` 全部在挂起时跳过；右下角浮出 `ReaderJumpActions`「返回原位置 / 设为阅读进度」，返回走 `cancelProgressHold()` 回跳，设为进度才 `releaseProgress(saveCurrent:true)`；标注浏览中退出阅读器保留原进度。`AnnotationTab` / `TocDrawer` 区分 `onGotoAnnotation` 与书签的 `onGotoLocator`。补 1 项回归（两个按钮回调，共 625 项）。同日确认微信官方 Agent API 只有单本累计时长、无逐日明细 | `qyreader/QYReader-v2.58.3-20261117-weread-jump-progress.apk` |
| 2026-11-17 | 2.58.4+176 | 微信读书同步改为按编辑时间 LWW：① 进度用本机 `ReadingProgress.updatedAt` 对比远端 `readUpdateTime`，远端更晚才覆盖（含回退），本机更晚保留本机；② 阅读状态只在远端更晚时改；③ 阅读时长远端更晚才补差额，本机更晚则把当前总量记为已处理并提示；④ 划线/想法按 `WeReadNote.editedAt`（review `updateTime` 优先）对比 `Annotation.updatedAt`，只更新更晚的想法/颜色；⑤ 整本书评取最新一条并对比 `Book.updatedAt`；对比页增加「微信读书更晚但进度回退」提示；补 2 项回归（想法编辑时间、回退进度），共 626 项 | `qyreader/QYReader-v2.58.4-20261117-weread-lww-sync.apk` |
| 2026-11-17 | 2.58.5+177 | 书籍信息「笔记」页签每条划线/高亮/笔记整卡可点，跳阅读器并定位到标注位置；右上角新增独立分享按钮（不触发跳转），复用 `AnnotationShareSheet` 三模板卡片。跳转通过 `BookLaunch.initialLocatorJson` + `holdProgress` 传入 `ReaderPage`：直接落在笔记处但挂起进度，右下角仍可选「返回原位置 / 设为阅读进度」。抽出 `BookNoteCard` 便于测试；补 1 项回归（点卡片/点分享互不干扰，共 627 项） | `qyreader/QYReader-v2.58.5-20261117-book-note-jump-share.apk` |
| 2026-11-17 | 2.58.6+178 | ① 修笔记跳转只打开书不定位：原生阅读面起点原来只读 `_controllerState.initialLocator`，新增 `_nativeTargetLocator()` 优先读 `_initialLocatorJson`（路由目标），`_nativeChapterFor` / `_nativeOffsetFor` 都改走它；② 原生排版跨页选字：每页一个 `SelectableText`，系统手柄不能跨页，选区菜单新增「跨页」（第六个动作），打开 `cross_page_selection_sheet.dart`（整章 `TextField(readOnly)` 可滚动选任意区间），选完支持复制 / 划线 / 高亮 / 笔记，按章内字符区间直接落标注；补 1 项回归（区间返回，共 628 项） | `qyreader/QYReader-v2.58.6-20261117-book-note-jump-crosspage.apk` |
| 2026-11-17 | 2.59.0+179 | 微信读书改为**扫码登录**，不再手填 API Key：新增 `weread_login.dart`（网页登录协议：`/r/weread-skills` 取 `wr_fp` → `/api/auth/getLoginUid` → 二维码 `https://weread.qq.com/web/confirm?uid=…` → `/api/auth/getLoginInfo` 轮询 → `/api/userInfo` + `/api/skills/apikeyGet?only_show=1` 自动取官方 `wrk-` Key 存 secure storage；长轮询 8s 超时、5 分钟过期、`NEED_OTP` 4 位验证码；`wr_fp` 设备指纹防顶号；换账号清同步状态/快照）；新增 `weread_login_dialog.dart`（`qr_flutter 4.1.0` 的 `QrPainter` 渲染二维码、保存到相册、刷新、验证码；同机可微信「扫一扫 → 相册」）；页面右上角改成头像按钮（已登录显示账号弹窗：退出登录 / 重新扫码），引导文案与说明卡同步更新；`getLoginInfo` 长轮询超时改为继续等待（`WeReadLoginException.retryable`），不会 8 秒就报登录失败；书籍信息「阅读时间」由横向柱状图改成**竖排逐日列表**（日期 + 星期 / 时长条 / 时长，前 14 天可展开），行 key `book-daily-row-<yyyy-MM-dd>`；微信读书累计时长不再因「本机更晚」跳过，始终补未导入差额；**修「导入的书没有阅读时间」**：书架快照的进度是 4 并发 + 45 秒预算批量拉的，书多时很多书没有 `recordReadingTime`——单本同步/导入时再用 `/book/getprogress` 拉一次（`mergeWeReadProgress` 合并，进度为 0 不冲掉快照），并且 `fetch` 不再把 `importedReadingSeconds` 重置为空（原来每次刷新后重同步都会重复导入）；旧版「跳过但记为已导入」的状态用「本机累计时长 < 已导入值」判定后清零重补；补 5 项登录单测（含长轮询超时）+ 3 项书籍阅读时间用例 + 4 项进度合并用例（共 638 项）。扫码真机流程需验收 | `qyreader/QYReader-v2.59.0-20261117-weread-qr-login.apk` |
| 2026-11-17 | 2.59.1+180 | 首页「今年读完的书」由横向滑动封面流改成**自动换行**：按卡片可用宽度算列数（82dp 封面 + 10dp 间距），默认最多 **3 行**，超出显示 `home-year-more`「查看更多」；新增 `year_finished_page.dart` 完整页（标题「今年读完的书」+ 右上角 N 本，`Wrap` 封面 + 书名 + 作者，点击进阅读器，key `year-finished-book-<id>`）；封面缩略图抽到 `features/home/widgets/cover_thumb.dart` 的 `CoverThumb` 供首页与完整页共用；补 1 项首页回归（400 宽下 3 行 9 本 + 查看更多进页，共 639 项）。视觉自检：`.zcode/year_finished_preview_test.dart` | `qyreader/QYReader-v2.59.1-20261117-year-finished-wrap.apk` |
| 2026-11-17 | 2.59.2+181 | 首页「今年读完的书」封面行改为**居中**（`WrapAlignment.center`），最后一行不足整行时也居中，不再贴左；「查看更多」按钮同步从右下角改为居中；完整页 `YearFinishedPage` 的封面网格也居中。390/400 宽下仍是一行 3 本、默认 3 行，交互不变 | `qyreader/QYReader-v2.59.2-20261117-year-finished-center.apk` |
| 2026-11-17 | 2.60.0+184 | 原生阅读面接入**精排**（此前开关只对已旁路的 WebView 链有效）：新增 `epub_block_style.dart`（字号/行高/对齐/首行缩进/段上下距/粗斜体）、`epub_css.dart`（`<style>` + OPF 外部 CSS + 内联 style，tag/.class/#id 选择器、祖先继承、specificity 排序、px/em/rem/%/pt 单位）；`ParsedChapter` 增加 `paragraphStyles/paragraphStyleIds` 紧凑表 → `NativeChapter` → `NativeParagraph.style`；`ReaderTypeSpec.preciseTypesetting` 打开后 `ChapterLayout.build` 逐段取原书字体/对齐/缩进，缩进补宽按本段字号，段距用原书 margin，分页与测量签名包含开关；面板 hint 与 README 同步说明限制（不还原内嵌字体/颜色、段内局部粗斜体不拆 run）；补 3 项 CSS 解析 + 4 项原生精排回归（共 649 项） | `qyreader/QYReader-v2.60.0-20261117-native-refined-typesetting.apk` |
| 2026-11-17 | 2.59.3+182 | 修微信读书「同步后显示一致、退出再进又提示新增划线」：① `WeReadSyncState` 新增 `syncedNoteTotals`，记录每本上次成功处理时的远端笔记总数；`compare` 的 `newNoteCount` 改为 `totalNotes - syncedNoteTotals`（无基线时才回退 imported + skipped），不再用会被整本书评 / 同 range 合并想法永久拉大的差值；② `apply` 仅在「笔记拉取完成 + 章节可用 + 远端有笔记时确实拉到」后推进基线，接口失败/章节未解析/空数组不推进，下次重试；③ `fetch()` 重建 state 时保留该字段，prefs 往返带 `syncedNoteTotals`；补 3 项回归（状态往返、基线不再误报、超过基线才算新增，共 641 项） | `qyreader/QYReader-v2.59.3-20261117-weread-note-baseline.apk` |
| 2026-11-17 | 2.59.4+183 | 微信读书补「最近阅读时间 / 读完时间」：① `Book` 新增 `finishedAt`，drift schema v6 加 `books.finished_at`，同步 payload 往返；② `/book/getprogress` 的 `finishTime`（progress=100 才有）写入 `finishedAt`，缺失时退回 `readUpdateTime`；`lastOpenedAt` 继续存最后阅读时间；③ 对比页在远端读完时间更新时提示「读完时间 YYYY-MM-DD」，已读完但本机没时间的书也会被抓一次；④ 书籍信息基础页新增「阅读记录」两行（最近阅读 / 读完时间，精确到分钟）；手动切到已读也记完成时间，取消已读保留历史；⑤ `_mergeBook` 补写 `finishedAt` / `readStatus`；补 3 项回归（读完时间对比、applyReadingState finishedAt、JSON 往返，共 642 项） | `qyreader/QYReader-v2.59.4-20261117-weread-finish-time.apk` |
| 2026-11-17 | 2.60.1+185 | 修「从分类返回要两次返回手势」：manifest `<application>` 显式 `android:enableOnBackInvokedCallback="false"` 关闭预测性返回——targetSdk 35（Flutter 3.32 默认）在 Android 15+ 设备上默认开启预测性返回，系统在**手势开始瞬间**就决定播「回桌面」预览动画并吞掉事件，而书架分类是页内状态（`ShelfBody` PopScope 的 canPop 随筛选原地翻转），引擎向系统的注册状态更新不同步，第一次手势动画结束不生效、第二次才派发给 PopScope 回调；关掉后走传统按键分发（手势结束才派发），一次返回必定触发回调。书架分类页本身逻辑未改；本应用未实现任何预测性返回动画，Android 14 及以下行为不变。纯 manifest 改动，无新增回归（共 649 项） | `qyreader/QYReader-v2.60.1-20261117-back-gesture-fix.apk` |
| 2026-11-17 | 2.60.2+186 | 书架进分类记住首屏位置：`ShelfPage` 新增 `_shelfScroll`（滚动控制器，传给 `_BookShelf` 挂 CustomScrollView）+ `_onCategoryFilterChanged`（`ref.listen(shelfCategoryFilterProvider)`）——'' → 分类：记住首屏 offset、分类页从顶部开始；分类 → ''：同帧 `jumpTo` 回进入前的位置（jumpTo 在内容重排同帧生效，不闪一帧旧位置；书架子树无滚动通知监听，build 外跳转安全）。补 1 项回归（滚下去 → 进分类回到顶部 → 返回首屏偏移与进入前一致，共 650 项） | `qyreader/QYReader-v2.60.2-20261117-category-back-restore.apk` |
| 2026-11-18 | 2.60.3+187 | 修「今年读完的书」两个问题：① 2024 年读完的微信读书导入书混进今年列表——`finishedThisYear` 原来用 `updatedAt` 近似读完时间，微信读书同步会把 `updatedAt` 刷新到今天；改为优先 `finishedAt`（v2.59.4 起微信读书导入书写入真实读完时间），没有的旧本机数据才退回 `updatedAt`，排序同口径；② 首页卡片与完整页封面行未居中——`Wrap` 在 Column / SingleChildScrollView 里收缩到内容宽度，`WrapAlignment.center` 等于没生效（整行贴左、右侧留白），两处都加 `SizedBox(width: double.infinity)` 撑满再居中；补 2 项回归（往年 finishedAt 不算今年读完 / 首行与末行居中偏移，共 652 项） | `qyreader/QYReader-v2.60.3-20261118-year-finished-fix.apk` |
| 2026-11-18 | 2.61.0+188 | 支持导入 Reeden 导出数据 + 新增「我的书评」页面：① 设置 → 数据 →「导入 Reeden 数据」选 JSON——解析（`reeden_import.dart`）出书籍 / 阅读状态 / 划线笔记 / 书评 / 每日时长，落库（`reeden_import_service.dart`）：新书走 `buildWeReadEpub` 占位 EPUB 入库，已有书按书名+作者合并；个人化字段本地为空才补；阅读状态按 lastReadTime LWW、进度只前进；划线按原文去重（comment 进想法、red→rose）；每日时长走 recordSession 进 daily_stats 并参与同步（同天已有时长≥导入值跳过、<10 秒跳过），重复导入整体幂等；② 设置 → 管理 →「我的书评」（`/settings/book-reviews`）：书评列表页（标题 / 作者 / 星级评分 / 日期 / 封面 / 全文可展开 / 搜索，点卡片进书籍详情）；补 5 项回归（解析兜底 / 落库 / 重复导入幂等 / 同名合并 / 设置页，共 657 项） | `qyreader/QYReader-v2.61.0-20261118-reeden-import-reviews.apk` |
| 2026-11-18 | 2.62.0+189 | 书架长按新增「覆盖导入」+ 笔记位置重定位：① `BookRepository.replaceBookContent` 用新 EPUB/TXT/MD 替换已有书正文，保留 id / 书名 / 作者 / 封面 / 进度 / 笔记 / 统计；新文件按 `<id>_<sha12>.<ext>` 落盘、事务成功后才删旧文件，同一内容 no-op、重复内容拒绝；② `overwrite_import_dialog.dart` 选文件 → 确认 → 转圈导入 → 按旧百分比重落进度 → 有笔记时弹「匹配笔记位置 / 暂不匹配」；③ `note_rematch.dart` 的 `NoteLocator` 先完整原文（精确 → 忽略空白/标点），找不到再逐字缩短（1..24 字 + 75/50/35/25% + 16/12/8/6/4 字，取中间窗口，优先旧章），`setAnchor(..., locatorEnd:)` 同时写起止点；阅读器 `_nativeMarks` 的旧标注兜底也走同一匹配器，打开书即自动回写；④ 长按菜单动作区改 `Flexible + ListView` 防矮屏溢出；补 15 项回归（匹配 8 / 仓储 4 / 锚点 1 / 菜单 1 / 既有测试适配，共 672 项） | `qyreader/QYReader-v2.62.0-20261118-book-overwrite-import.apk` |
| 2026-11-18 | 2.63.0+190 | 标注「未定位」可手动 / 自动定位：① `note_rematch.dart` 新增 `annotationAnchorLocated`——锚点处正文与 `quotedText` 对照（占位章首 0..0、旧章号越界、原文对不上都算未定位；手动锚点带 `manual:true` 直接算已定位；自动匹配只对上一段也算已定位）；② 标注列表把未定位标注归入「未定位」分组 + 行内角标，定位按钮（`annotation-locate-<id>`）弹「自动查询定位 / 手动定位」；自动定位用 `NoteLocator` 搜原文、`setAnchor` 后跳过去，手动定位收起抽屉并浮出 `ManualLocateBar`，翻到目标页点「设为当前页」写成 `{..., manual:true}` 锚点；③ 新增 `manual_locate_bar.dart` 与 `annotation_tab_test` / `manual_locate_bar_test` / `annotationAnchorLocated` 回归（共 679 项） | `qyreader/QYReader-v2.63.0-20261118-note-locate.apk` |
| 2026-11-18 | 2.63.1+191 | 未定位标注 UX 调整 + 搜索结果跳转修复：① 标注列表行尾不再挤第三个定位按钮，改为**长按未定位笔记**弹「自动查询定位 / 手动定位」；② 选区菜单新增「定位」（`SelectionMenu.onLocateNote`，有未定位笔记时才出现）——长按选中正文后可从列表挑一条未定位笔记，直接把当前选区写成它的锚点（`_pickUnlocatedForSelection`），比翻页定位更精确；③ `BookSearchHit` 增加 `offset`（FTS 用 `instr(lower(body), lower(?))`、LIKE 用 `indexOf`），`_openSearch` 改走 `_jumpToLocator`，修原生阅读面点搜索结果只跳章首/无反应；补 3 项回归（长按入口 / 选区「定位」/ 搜索偏移，共 680 项） | `qyreader/QYReader-v2.63.1-20261118-note-locate-ux.apk` |
| 2026-11-18 | 2.64.0+192 | 支持导出阅读数据 JSON：设置 → 数据 →「导出阅读数据」→ `reading_data_export.dart` 汇总书架书籍元数据 / 当前与最远进度 / 划线高亮笔记 / 书签 / 累计与每日阅读时长，写成 `exports/QYReader-reading-data-<时间>.json`（缩进 JSON，可系统分享）；顶层 `format=qyreader-reading-data` / `version=1` / `summary` / `books`，locator 解析成对象；不导出书源、封面、本机路径、哈希与设备 id；结果对话框显示统计与路径；补 3 项回归（JSON 结构 / 隐私字段 / 空书架 + 设置入口，共 682 项） | `qyreader/QYReader-v2.64.0-20261118-export-json.apk` |
| 2026-11-18 | 2.65.0+193 | 支持导入 AZW3：`book_repository_impl._parseSourceBytes` 识别 `.azw3`，`_convertKindleToEpub` 用 `kindle_unpack` 转 EPUB（isolate 内跑）、DRM 文件用 PDB/PalmDOC 头提前拒绝（`import.azw3_drm`）；`_ParsedSource` 增加 `storedBytes/storedExt`，落盘转换后的 EPUB，哈希/大小按实际文件；ZIP 时间戳归一化（DOS 时间 + 0x5455 扩展时间）保证重复导入仍按内容去重；书架导入与覆盖导入的扩展名/文案同步支持 AZW3；补 2 项回归（真实公版书转 EPUB + DRM 拒绝，共 684 项）；依赖 `kindle_unpack 0.2.0`（GPL-3.0） | `qyreader/QYReader-v2.65.0-20261118-azw3-import.apk` |
| 2026-11-18 | 2.66.0+194 | 支持导入 MOBI：把 Kindle 转换入口从 `.azw3` 扩展为 `.azw3` / `.mobi`（`isKindle`），书架导入、覆盖导入、空书架提示与不支持格式文案都加入 MOBI；DRM 错误码统一为 `import.kindle_drm`、解析错误为 `import.kindle`；fixture 更正为 `test/fixtures/pg1342.mobi`，新增「MOBI 转 EPUB」「AZW3 扩展名同链路」「DRM 拒绝」3 项回归（共 685 项）；`kindle_unpack` 同时支持 Mobi-7 与 KF8 | `qyreader/QYReader-v2.66.0-20261118-mobi-import.apk` |
| 2026-11-18 | 2.67.0+195 | 设置新增「重复书籍整理」：`duplicate_books.dart` 做书名强/疑似归一化（大小写/空白/扩展名；括号/卷册/版本词/标点）、按 loose key 聚类且整簇同名才判强匹配、作者开关、文件 SHA-256 重复；`duplicate_books_page.dart` 提供检测类型 / 匹配范围 / 匹配作者 / 阅读状态+分类筛选，分组卡显示封面 / 最大 / 最多 / 状态 / 时间 / 分类 / 来源，支持忽略、逐本删除、勾选批量删除（每组至少保留一本，删除连带笔记书签）；设置页加入口与路由 `/settings/duplicates`；补 14 项回归（逻辑 11 + 页面 3，共 699 项） | `qyreader/QYReader-v2.67.0-20261118-duplicate-books.apk` |
| 2026-11-18 | 2.68.0+196 | 书架网格新增「显示名称」开关：`ShelfPrefs.showGridTitle`（prefs `shelf.grid.showTitle`，默认关），书架设置网格页加 `_ToggleRow`；`ShelfFlow` 行高改为 `cellWidth/0.72 + 28`，书格用 `Expanded(BookCard)` + 单行居中书名，分类格预留同高度；纯封面模式不受影响；补 2 项回归（开关落盘 + 书名显示/隐藏，共 701 项） | `qyreader/QYReader-v2.68.0-20261118-grid-title-option.apk` |
| 2026-11-18 | 2.69.0+197 | 阅读数据按书导出/导入：设置→数据「导出阅读数据」先弹书籍选择（`showReadingDataBookPicker`，默认全选）；长按菜单新增「导出阅读数据」（`exportBookReadingData` 只导这本）与「导入阅读数据」（`reading_data_import.dart`：选 JSON → 校验 format → 按书名/作者匹配条目 → 合并进度（本地更低才写，locator 原样还原）/划线笔记（原文去重）/书签（locator 去重）/每日时长（毫秒比较，≥10s，幂等））；补 8 项回归（导入 6 + 导出选择 + 菜单项，共 709 项） | `qyreader/QYReader-v2.69.0-20261118-reading-data-transfer.apk` |
| 2026-11-18 | 2.69.1+198 | 网格「显示名称」打开时分类格也显示分类名：`_gridCategoryCell` 从只预留 28px 改为显示单行居中分类名（key `category-title-<名称>`，样式与书名共用 `_gridTitleStyle`），同一行书格 / 分类格封面比例保持一致；补 1 项回归（分类名显示与字号一致，共 710 项） | `qyreader/QYReader-v2.69.1-20261118-grid-category-title.apk` |
| 2026-11-18 | 2.69.2+199 | 分类卡与书卡同尺寸：`CategoryCard` 的 Card 改 `margin: EdgeInsets.zero` 并去掉内层 8px Padding，2×2 书位铺满整个格子，网格里与书封面视觉尺寸一致（分类名/书名行高不变）；补 1 项回归（分类卡铺满格子，共 711 项） | `qyreader/QYReader-v2.69.2-20261118-category-full-bleed.apk` |
| 2026-11-18 | 2.70.0+200 | 新增「作者管理」页面：设置 → 管理 →「作者管理」（路由 `/settings/authors`，`authors_page.dart` + 纯逻辑 `author_groups.dart`）——书架的书按作者 trim 分组，未知作者组排最前（带「点击查看并补全」说明），其余按书数降序；卡片左侧 2×2 封面预览 + 「N 本」，支持按作者名 / 书名搜索；点作者卡进作者书籍页（`/settings/authors/books`，extra 传作者名）看名下全部书籍（阅读状态 + 已读百分比，点书进书籍详情），未知作者组顶部有补全提示卡；「⋯」菜单「重命名作者」弹窗批量改组内全部书籍（`updateBookMeta` 逐本，清空 = 未知作者）；设置页副标题显示作者数；补 11 项回归（分组逻辑 6 + 页面 5，共 722 项） | `qyreader/QYReader-v2.70.0-20261118-author-manager.apk` |

| 2026-11-18 | 2.70.0+200 | 编译 Windows Release 并打包完整运行目录；仅文档更新，未递增版本 | `qyreader/QYReader-v2.70.0-20261118-windows-x64.zip` |


| 2026-11-19 | 2.70.2+202 | 检查书架布局与分类树现状；需求尚未实现，仅文档更新，未递增版本 | 未生成 |

| 2026-11-19 | 2.71.0+203 | 初步实现按书籍分类路径逐级展示和返回；参考图布局、空分类及键鼠翻页尚待完成；analyze 通过，723 项测试通过 | `qyreader/QYReader-v2.71.0-20261119-category-wip.apk` |

| 2026-11-19 | 2.71.1+204 | 书架嵌套分类、空分类与分类卡计数；默认网格显示名称；阅读器可自定义上一页/下一页按键及鼠标滚轮翻页；analyze 通过、725 项测试通过 | `qyreader/QYReader-v2.71.1-20261119-nested-shelf-input.apk` |

| 2026-11-19 | 2.71.2+205 | 修复分类卡空白书脊条不可见，封面与占位符距卡片边框 6dp；analyze 与 725 项测试通过 | `qyreader/QYReader-v2.71.2-20261119-category-spacing.apk` |

| 2026-11-19 | 2.71.3+206 | 去除设置列表与书籍长按操作菜单的说明副标题；analyze 通过，725 项测试通过 | `qyreader/QYReader-v2.71.3-20261119-compact-menus.apk` |

| 2026-11-19 | 2.71.3+206 | 调研微信读书逐书逐日阅读时长：官方 Agent API 未明确提供该明细；当前实现仅导入累计差额，需求未完成。仅文档更新，未递增版本 | `qyreader/QYReader-v2.71.3-20261119-compact-menus.apk` |

| 2026-11-19 | 2.71.3+206 | 核实 Reeden 扫码导入阅读时长与本项目登录流程差异；仅文档更新，未递增版本 | `qyreader/QYReader-v2.71.3-20261119-compact-menus.apk` |

| 2026-11-19 | 2.71.3+206 | 核对 Reeden 截图并继续调研逐书逐日接口，尚未确认接口；仅文档更新，未递增版本 | `qyreader/QYReader-v2.71.3-20261119-compact-menus.apk` |
| 2026-11-19 | 2.71.4+207 | 修复点击书架搜索框外部时未失焦；分析通过、726 项测试通过 | `qyreader/QYReader-v2.71.4-20261119-search-unfocus.apk` |
| 2026-11-20 | 2.72.0+208 | 首页新增微信读书个性化推荐卡片、登录入口与刷新；analyze 通过、728 项测试通过 | `qyreader/QYReader-v2.72.0-20261120-book-recommendations.apk` |
| 2026-11-20 | 2.72.1+209 | 修复微信读书升级通知误阻断接口：更新版本并保留成功响应，接口错误继续提示；analyze 通过、729 项测试通过 | `qyreader/QYReader-v2.72.1-20261120-weread-upgrade-fix.apk` |
| 2026-11-20 | 2.73.0+210 | 底部页面滚动位置存储、首页卡片显隐排序、微信读书推荐详情四页签；analyze 通过、730 项测试通过，真机待验收 | `qyreader/QYReader-v2.73.0-20261120-home-cards-detail.apk` |
| 2026-11-20 | 2.73.1+211 | 优化推荐详情弹窗及元数据展示，刷新显示加载状态；analyze 通过、732 项测试通过 | `qyreader/QYReader-v2.73.1-20261120-recommendation-ui.apk` |
| 2026-11-20 | 2.73.2+212 | 推荐详情的热门划线与热门书评逐条分隔；analyze 通过、732 项测试通过 | `qyreader/QYReader-v2.73.2-20261120-recommendation-separators.apk` |
| 2026-11-20 | 2.73.3+213 | 修复关闭推荐详情弹窗后首页位置变化，区分弹窗与页面返回；analyze 通过、733 项测试通过 | `qyreader/QYReader-v2.73.3-20261120-home-dialog-position.apk` |
| 2026-11-20 | 2.73.3+213 | 确认收藏展示方式并检查分类、标签与同步实现；自定义视图及收藏尚未实现。仅文档更新，未递增版本 | `qyreader/QYReader-v2.73.3-20261120-home-dialog-position.apk` |
| 2026-11-20 | 2.73.4+214 | 修复原生阅读器恢复章内偏移；analyze 通过、734 项测试通过；MOBI 与收藏视图仍待处理 | `qyreader/QYReader-v2.73.4-20261120-reader-resume.apk` |
| 2026-11-20 | 2.73.4+214 | 排查 MOBI 导入失败流程；等待错误详情及问题文件，尚未修复。仅文档更新，未递增版本 | `qyreader/QYReader-v2.73.4-20261120-reader-resume.apk` |
| 2026-11-20 | 2.73.4+214 | 排查书架筛选、收藏数据与同步设计；功能尚未实现，仅文档更新，未递增版本 | `qyreader/QYReader-v2.73.4-20261120-reader-resume.apk` |
| 2026-11-20 | 2.74.0+215 | 新增自定义筛选视图与收藏分类；schema v7 增量迁移、收藏同步与旧设备兼容；analyze 通过、741 项测试通过 | `qyreader/QYReader-v2.74.0-20261120-shelf-custom-favorites.apk` |
| 2026-11-20 | 2.75.0+216 | 书籍长按及多选支持本地导出和系统分享；多本本地导出为 ZIP，按需下载云端书源；analyze 通过、743 项测试通过 | `qyreader/QYReader-v2.75.0-20261120-book-file-share.apk` |
| 2026-11-20 | 2.75.1+217 | 修复 EPUB 多章共用 href 时续读跳回同文件首章；用《老实人启蒙》实际文件验证，analyze 通过、744 项测试通过 | `qyreader/QYReader-v2.75.1-20261120-epub-chapter-resume.apk` |

| 2026-11-20 | 2.76.0+218 | 推荐详情新增目录和去阅读按钮；analyze 通过、744 项测试通过，真机跳转待验收 | `qyreader/QYReader-v2.76.0-20261120-recommendation-reading.apk` |

| 2026-11-20 | 2.76.1+219 | 推荐详情简介并入基本信息；阅读按钮优先打开微信读书应用，失败回退网页；analyze 通过、744 项测试通过，真机待验收 | `qyreader/QYReader-v2.76.1-20261120-weread-app-link.apk` |

| 2026-11-20 | 2.77.0+220 | 书架分组页签、固定书架入口和展开快速切换；analyze 通过、745 项测试通过，真机待验收 | `qyreader/QYReader-v2.77.0-20261120-shelf-group-tabs.apk` |

| 2026-11-20 | 2.77.0+220 | 排查翻页功能入口，等待具体故障与复现步骤；仅文档更新，未递增版本 | `qyreader/QYReader-v2.77.0-20261120-shelf-group-tabs.apk` |

| 2026-11-20 | 2.77.1+221 | 修复无动画模式下横滑仍显示滑动效果；analyze 通过、745 项测试通过 | `qyreader/QYReader-v2.77.1-20261120-page-turn-none.apk` |

| 2026-11-20 | 2.77.1+221 | 排查拖动选区跨页，尚未修复；仅文档更新，未递增版本 | `qyreader/QYReader-v2.77.1-20261120-page-turn-none.apk` |

| 2026-11-20 | 2.77.1+221 | 用户不需要跨页选择面板，等待确认翻页交互；仅文档更新，未递增版本 | `qyreader/QYReader-v2.77.1-20261120-page-turn-none.apk` |

| 2026-11-20 | 2.77.1+221 | 确认选区手柄拖动时自动翻页需求；尚未实现，仅文档更新，未递增版本 | `qyreader/QYReader-v2.77.1-20261120-page-turn-none.apk` |

| 2026-11-20 | 2.77.1+221 | 检查选区手柄及标注范围，自动翻页尚未实现；仅文档更新，未递增版本 | `qyreader/QYReader-v2.77.1-20261120-page-turn-none.apk` |

| 2026-11-20 | 2.77.1+221 | 排查分页重设计所需的选区和坐标接口；功能尚未实现，仅文档更新，未递增版本 | `qyreader/QYReader-v2.77.1-20261120-page-turn-none.apk` |
| 2026-11-20 | 2.77.2+222 | 在正文拖动手柄到页边自动翻页并继续选字，支持跨章和双页回翻，移除独立跨页面板。analyze 通过、745 项测试通过，发布 APK 签名验证通过 | `qyreader/QYReader-v2.77.2-20261120-selection-auto-page-turn.apk` |

| 2026-11-20 | 2.77.3+223 | 返回首页保留上次推荐，手动刷新重新获取；analyze 通过、746 项测试通过 | `qyreader/QYReader-v2.77.3-20261120-home-recommendation-cache.apk` |

| 2026-11-20 | 2.77.3+223 | 排查 OSS 更新接入，根目录 latest.json 返回 404，功能尚未实现；仅文档更新，未递增版本 | `qyreader/QYReader-v2.77.3-20261120-home-recommendation-cache.apk` |

| 2026-11-20 | 2.78.0+224 | 设置页新增 OSS 更新检查、APK 下载与安装、网盘入口；analyze 通过、749 项测试通过，真机待验收 | `qyreader/QYReader-v2.78.0-20261120-oss-update.apk` |

| 2026-11-20 | 2.78.0+224 | 整理近期更新内容；仅文档更新，未递增版本 | `qyreader/QYReader-v2.78.0-20261120-oss-update.apk` |

| 2026-11-21 | 2.78.0+224 | 编译 Windows x64 发布包并核验文件；仅文档更新，未递增版本 | `qyreader/QYReader-v2.78.0-20261121-windows-x64.zip`、`qyreader/QYReader-v2.78.0-20261120-oss-update.apk` |
