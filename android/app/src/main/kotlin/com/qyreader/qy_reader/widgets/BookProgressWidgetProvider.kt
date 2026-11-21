package com.qyreader.qy_reader.widgets

import android.content.Context
import android.widget.RemoteViews
import com.qyreader.qy_reader.R
import org.json.JSONObject

/** 2×2：最近阅读的一本书（封面 + 书名 + 阅读进度条）。 */
class BookProgressWidgetProvider : BaseHomeWidgetProvider() {
    override val layoutId: Int = R.layout.widget_book_progress

    override fun bind(context: Context, views: RemoteViews, data: JSONObject?) {
        val book = data?.optJSONObject("recentBook")
        val hasBook = book != null
        show(views, R.id.widget_book_content, hasBook)
        show(views, R.id.widget_book_empty, !hasBook)
        if (book == null) {
            views.setOnClickPendingIntent(
                R.id.widget_book_root,
                HomeWidgetUpdater.openApp(context, "shelf", REQUEST_BOOK),
            )
            views.setContentDescription(
                R.id.widget_book_root,
                "最近阅读：还没有阅读记录",
            )
            return
        }

        val title = book.optString("title").ifBlank { "未命名" }
        val author = book.optString("author").trim().ifBlank { "未知作者" }
        val percent = book.optDouble("percent", 0.0).coerceIn(0.0, 1.0)
        val bookId = book.optString("id")

        views.setTextViewText(R.id.widget_book_title, title)
        views.setTextViewText(R.id.widget_book_author, author)
        views.setTextViewText(R.id.widget_book_percent, WidgetText.percent(percent))
        views.setProgressBar(
            R.id.widget_book_progress,
            1000,
            WidgetText.progress(percent),
            false,
        )
        views.setImageViewBitmap(
            R.id.widget_book_cover,
            WidgetBitmap.cover(
                context,
                book.optString("coverPath", ""),
                widthDp = 68,
                heightDp = 92,
                radiusDp = 10f,
            ),
        )
        val action = if (bookId.isNotBlank()) "book:$bookId" else "shelf"
        views.setOnClickPendingIntent(
            R.id.widget_book_root,
            HomeWidgetUpdater.openApp(context, action, REQUEST_BOOK),
        )
        views.setContentDescription(
            R.id.widget_book_root,
            "最近阅读《$title》，${WidgetText.percent(percent)}",
        )
    }

    private companion object {
        const val REQUEST_BOOK = 101
    }
}
