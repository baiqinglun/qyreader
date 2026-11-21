package com.qyreader.qy_reader.widgets

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.qyreader.qy_reader.MainActivity

/** 组件点击 / 刷新入口。 */
object HomeWidgetUpdater {
    /** 组件点击用的自定义 action（不要用 MAIN/LAUNCHER，否则会触发启动归位）。 */
    const val ACTION_OPEN_FROM_WIDGET = "com.qyreader.qy_reader.OPEN_FROM_WIDGET"

    /** Intent extra：`book:<id>` / `stats` / `shelf`。 */
    const val EXTRA_WIDGET_ACTION = "qyreader.widgetAction"

    /** 刷新三个组件的全部实例（没有添加组件时是空操作）。 */
    fun updateAll(context: Context) {
        BookProgressWidgetProvider().updateNow(context)
        TodayReadingWidgetProvider().updateNow(context)
        ShelfWidgetProvider().updateNow(context)
    }

    /** 打开 App 并带上组件动作；同一个 requestCode 只保留最新动作。 */
    fun openApp(context: Context, action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            this.action = ACTION_OPEN_FROM_WIDGET
            putExtra(EXTRA_WIDGET_ACTION, action)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(context, requestCode, intent, flags)
    }
}
