package com.qyreader.qy_reader.widgets

import android.content.Context
import android.widget.RemoteViews
import com.qyreader.qy_reader.R
import org.json.JSONObject

/** 2×2：今日阅读时长 + 每日目标进度。 */
class TodayReadingWidgetProvider : BaseHomeWidgetProvider() {
    override val layoutId: Int = R.layout.widget_today_reading

    override fun bind(context: Context, views: RemoteViews, data: JSONObject?) {
        val today = data?.optJSONObject("today")
        val isToday = HomeWidgetStore.isToday(data)
        val duration = if (isToday) today?.optLong("durationMs", 0L) ?: 0L else 0L
        val goal = today?.optInt("goalMinutes", 0) ?: 0
        val progress = if (isToday) {
            today?.optDouble("progress", 0.0) ?: 0.0
        } else {
            0.0
        }

        val clock = WidgetText.clock(duration)
        val goalText = if (goal > 0) "目标 $goal 分钟" else "未设目标"
        views.setTextViewText(R.id.widget_today_time, clock)
        views.setTextViewText(R.id.widget_today_goal, goalText)
        views.setTextViewText(
            R.id.widget_today_percent,
            if (goal > 0) "完成 ${WidgetText.percent(progress)}" else "翻开一本书吧",
        )
        views.setProgressBar(
            R.id.widget_today_progress,
            1000,
            WidgetText.progress(progress),
            false,
        )
        views.setOnClickPendingIntent(
            R.id.widget_today_root,
            HomeWidgetUpdater.openApp(context, "stats", REQUEST_TODAY),
        )
        views.setContentDescription(
            R.id.widget_today_root,
            "今日阅读 $clock，$goalText",
        )
    }

    private companion object {
        const val REQUEST_TODAY = 102
    }
}
