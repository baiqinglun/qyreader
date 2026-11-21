package com.qyreader.qy_reader.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject

/** 三个组件共用的刷新骨架。 */
abstract class BaseHomeWidgetProvider : AppWidgetProvider() {
    protected abstract val layoutId: Int

    protected abstract fun bind(
        context: Context,
        views: RemoteViews,
        data: JSONObject?,
    )

    /** 由 [HomeWidgetUpdater] / 系统广播触发，刷新自身全部实例。 */
    fun updateNow(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, javaClass))
        if (ids.isNotEmpty()) onUpdate(context, manager, ids)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val data = HomeWidgetStore.read(context)
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, layoutId)
            try {
                bind(context, views, data)
                appWidgetManager.updateAppWidget(id, views)
            } catch (_: Exception) {
                // 单个组件渲染失败不能连累其它组件
            }
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        updateNow(context)
    }

    protected fun show(views: RemoteViews, id: Int, visible: Boolean) {
        views.setViewVisibility(id, if (visible) View.VISIBLE else View.GONE)
    }
}
