package com.qyreader.qy_reader

import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.BatteryManager
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.WindowManager
import com.qyreader.qy_reader.widgets.HomeWidgetStore
import com.qyreader.qy_reader.widgets.HomeWidgetUpdater
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var openChannel: MethodChannel? = null
    private var launchChannel: MethodChannel? = null
    private var widgetChannel: MethodChannel? = null
    private var pendingOpenPath: String? = null
    private var pendingWidgetAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // 文件「打开方式」的 data URI 不能交给 Flutter 当深链路由：
        // 先自己接走文件，再把 data 清空（reader:// 深链保持原样）。
        val path = copyIncomingFile(intent)
        if (path != null) {
            pendingOpenPath = path
            intent?.data = null
        }
        // 桌面组件冷启动：记下动作，等 Flutter 侧来取（取完即清）。
        val widgetAction = intent?.getStringExtra(HomeWidgetUpdater.EXTRA_WIDGET_ACTION)
        if (!widgetAction.isNullOrEmpty()) {
            pendingWidgetAction = widgetAction
            intent?.removeExtra(HomeWidgetUpdater.EXTRA_WIDGET_ACTION)
        }
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "qyreader/app_version")
            .setMethodCallHandler { call, result ->
                if (call.method == "versionCode") {
                    @Suppress("DEPRECATION")
                    val info = packageManager.getPackageInfo(packageName, 0)
                    val code = if (android.os.Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                    result.success(code)
                } else if (call.method == "installApk") {
                    try {
                        val args = call.arguments as Map<*, *>
                        val file = File(args["path"] as String).canonicalFile
                        val expected = (args["versionCode"] as Number).toLong()
                        require(file.parentFile == cacheDir.canonicalFile && file.name == "qyreader-update.apk")
                        @Suppress("DEPRECATION")
                        val info = packageManager.getPackageArchiveInfo(file.path, 0)
                            ?: throw IllegalArgumentException("安装包无效")
                        @Suppress("DEPRECATION")
                        val version = if (android.os.Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                        require(info.packageName == packageName && version == expected) { "安装包与更新清单不匹配" }
                        val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.updates", file)
                        startActivity(Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        })
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("install", e.message, null)
                    }
                } else result.notImplemented()
            }
        // 阅读页常亮：避免依赖额外的 wakelock 插件
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "qyreader/screen"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "keepAwake" -> {
                    val on = call.arguments as? Boolean ?: false
                    if (on) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // 页眉/页脚电量：读系统电池粘性广播（无需权限）
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "qyreader/battery"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "level" -> {
                    val intent = registerReceiver(
                        null,
                        IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                    )
                    val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                    val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                    if (level >= 0 && scale > 0) {
                        result.success(level * 100 / scale)
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        // 文件管理器「用其他应用打开」：content:// 复制到缓存再交给 Dart 导入
        openChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "qyreader/open"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialFile" -> {
                        result.success(pendingOpenPath)
                        pendingOpenPath = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
        val fromIntent = copyIncomingFile(intent)
        if (fromIntent != null) pendingOpenPath = fromIntent
        // 点桌面图标重新进入（进程还在、停在阅读页）：通知 Dart 回书架。
        // launchMode=singleTop，所以这一路走 onNewIntent，见下方。
        launchChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "qyreader/launch"
        ).also { channel ->
            channel.setMethodCallHandler { _, result -> result.notImplemented() }
        }
        // 桌面组件：Flutter 推送数据快照 → 存 prefs 并刷新三个组件；
        // 组件点击 → 送到 Dart（WidgetActionRouter 转成 go_router 导航）。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "qyreader/home_widgets"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val json = call.arguments as? String
                    if (json.isNullOrBlank()) {
                        result.error("bad_args", "缺少桌面组件数据", null)
                    } else {
                        val appContext = applicationContext
                        // 解码封面 + RemoteViews 更新放到后台线程，别卡 UI。
                        Thread {
                            try {
                                HomeWidgetStore.save(appContext, json)
                                HomeWidgetUpdater.updateAll(appContext)
                            } catch (_: Throwable) {
                                // 组件刷新失败不能拖垮 App
                            }
                        }.start()
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "qyreader/widget_action"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialAction" -> {
                        result.success(pendingWidgetAction)
                        pendingWidgetAction = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        // 同上：先接文件再清 data，避免 Flutter 把 file/content URI 当路由
        val path = copyIncomingFile(intent)
        if (path != null) intent.data = null
        val fromLauncher = isLauncherIntent(intent)
        val widgetAction = intent.getStringExtra(HomeWidgetUpdater.EXTRA_WIDGET_ACTION)
        if (!widgetAction.isNullOrEmpty()) {
            intent.removeExtra(HomeWidgetUpdater.EXTRA_WIDGET_ACTION)
        }
        super.onNewIntent(intent)
        // 从桌面图标重新进入：回书架（用户要求「下次启动在书架，不回到阅读页」）。
        if (fromLauncher) {
            launchChannel?.invokeMethod("resetToShelf", null)
        }
        // 组件点击（进程还在）：直接通知 Dart 导航。
        if (!widgetAction.isNullOrEmpty()) {
            val channel = widgetChannel
            if (channel != null) {
                channel.invokeMethod("open", widgetAction)
            } else {
                pendingWidgetAction = widgetAction
            }
        }
        if (path == null) return
        val channel = openChannel
        if (channel != null) {
            channel.invokeMethod("openFile", path)
        } else {
            pendingOpenPath = path
        }
    }

    /** 是否「点桌面图标启动」的意图（MAIN + LAUNCHER）。 */
    private fun isLauncherIntent(intent: Intent?): Boolean =
        intent?.action == Intent.ACTION_MAIN &&
            intent.categories?.contains(Intent.CATEGORY_LAUNCHER) == true

    /** 从 VIEW / SEND 意图取出文件并复制到应用缓存，返回本地路径。 */
    private fun copyIncomingFile(intent: Intent?): String? {
        if (intent == null) return null
        val uri: Uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
            }
            else -> null
        } ?: return null
        if (uri.scheme != "content" && uri.scheme != "file") return null

        val name = queryDisplayName(uri)
        val ext = name?.substringAfterLast('.', "")?.lowercase()
            ?.takeIf { it in setOf("epub", "txt", "md", "markdown") }
            ?: when (contentResolver.getType(uri)) {
                "application/epub+zip" -> "epub"
                "text/markdown", "text/x-markdown" -> "md"
                "text/plain" -> "txt"
                else -> "epub"
            }
        return try {
            val out = File(cacheDir, "open_${System.currentTimeMillis()}.$ext")
            val input = if (uri.scheme == "file") {
                File(uri.path ?: return null).inputStream()
            } else {
                contentResolver.openInputStream(uri) ?: return null
            }
            input.use { ins ->
                out.outputStream().use { outs -> ins.copyTo(outs) }
            }
            out.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    /** 文件显示名（带扩展名）。 */
    private fun queryDisplayName(uri: Uri): String? {
        if (uri.scheme == "file") return uri.lastPathSegment
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else null
            }
        } catch (_: Exception) {
            null
        }
    }
}
