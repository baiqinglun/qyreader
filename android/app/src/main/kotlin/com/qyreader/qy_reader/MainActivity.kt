package com.qyreader.qy_reader

import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.BatteryManager
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var openChannel: MethodChannel? = null
    private var launchChannel: MethodChannel? = null
    private var pendingOpenPath: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // 文件「打开方式」的 data URI 不能交给 Flutter 当深链路由：
        // 先自己接走文件，再把 data 清空（reader:// 深链保持原样）。
        val path = copyIncomingFile(intent)
        if (path != null) {
            pendingOpenPath = path
            intent?.data = null
        }
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
    }

    override fun onNewIntent(intent: Intent) {
        // 同上：先接文件再清 data，避免 Flutter 把 file/content URI 当路由
        val path = copyIncomingFile(intent)
        if (path != null) intent.data = null
        val fromLauncher = isLauncherIntent(intent)
        super.onNewIntent(intent)
        // 从桌面图标重新进入：回书架（用户要求「下次启动在书架，不回到阅读页」）。
        if (fromLauncher) {
            launchChannel?.invokeMethod("resetToShelf", null)
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
