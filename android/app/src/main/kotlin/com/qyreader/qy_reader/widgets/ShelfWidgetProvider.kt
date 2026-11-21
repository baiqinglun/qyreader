package com.qyreader.qy_reader.widgets

import android.content.Context
import android.widget.RemoteViews
import com.qyreader.qy_reader.R
import org.json.JSONObject
import kotlin.math.min

/** 4×2：最近阅读的三本书（封面 + 书名 + 进度）。 */
class ShelfWidgetProvider : BaseHomeWidgetProvider() {
    override val layoutId: Int = R.layout.widget_shelf

    override fun bind(context: Context, views: RemoteViews, data: JSONObject?) {
        val books = data?.optJSONArray("shelf")
        val count = min(3, books?.length() ?: 0)
        show(views, R.id.widget_shelf_content, count > 0)
        show(views, R.id.widget_shelf_empty, count == 0)

        for (index in 0 until 3) {
            val slot = SLOT_IDS[index]
            if (index >= count) {
                show(views, slot, false)
                continue
            }
            val book = books?.optJSONObject(index)
            if (book == null) {
                show(views, slot, false)
                continue
            }
            show(views, slot, true)
            val title = book.optString("title").ifBlank { "未命名" }
            val percent = book.optDouble("percent", 0.0).coerceIn(0.0, 1.0)
            views.setTextViewText(TITLE_IDS[index], title)
            views.setTextViewText(PERCENT_IDS[index], WidgetText.percent(percent))
            views.setImageViewBitmap(
                COVER_IDS[index],
                WidgetBitmap.cover(
                    context,
                    book.optString("coverPath", ""),
                    widthDp = 54,
                    heightDp = 72,
                    radiusDp = 8f,
                ),
            )
            val bookId = book.optString("id")
            val action = if (bookId.isNotBlank()) "book:$bookId" else "shelf"
            views.setOnClickPendingIntent(
                slot,
                HomeWidgetUpdater.openApp(context, action, REQUEST_SLOT_BASE + index),
            )
            views.setContentDescription(
                slot,
                "《$title》，${WidgetText.percent(percent)}",
            )
        }

        views.setOnClickPendingIntent(
            R.id.widget_shelf_root,
            HomeWidgetUpdater.openApp(context, "shelf", REQUEST_SHELF),
        )
        views.setContentDescription(
            R.id.widget_shelf_root,
            when (count) {
                0 -> "最近阅读：书架还是空的"
                1 -> "最近阅读《${books?.optJSONObject(0)?.optString("title")}》"
                else -> "最近阅读：共 $count 本书"
            },
        )
    }

    private companion object {
        const val REQUEST_SHELF = 103
        const val REQUEST_SLOT_BASE = 110

        val SLOT_IDS = intArrayOf(
            R.id.widget_shelf_slot_0,
            R.id.widget_shelf_slot_1,
            R.id.widget_shelf_slot_2,
        )
        val COVER_IDS = intArrayOf(
            R.id.widget_shelf_cover_0,
            R.id.widget_shelf_cover_1,
            R.id.widget_shelf_cover_2,
        )
        val TITLE_IDS = intArrayOf(
            R.id.widget_shelf_title_0,
            R.id.widget_shelf_title_1,
            R.id.widget_shelf_title_2,
        )
        val PERCENT_IDS = intArrayOf(
            R.id.widget_shelf_percent_0,
            R.id.widget_shelf_percent_1,
            R.id.widget_shelf_percent_2,
        )
    }
}
