/// 应用启动装配：初始化全局基础设施。
///
/// 领域依赖（数据库、仓储、HLC）由 [app/providers.dart] 的 Riverpod
/// provider 惰性创建，这里只负责进程级初始化。
library;

import 'package:flutter/widgets.dart';

import 'open_with.dart';

/// 启动前初始化：绑定、日志、崩溃钩子。
///
/// M0 仅初始化绑定；日志与崩溃收集在后续里程碑接入。
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 文件管理器「打开方式」：先挂上通道，冷启动带进来的文件会先排队
  await OpenWithService.start();
}
