package com.qyreader.qy_reader.widgets

import android.content.Context
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 桌面组件的数据仓：Flutter 每次数据变化把一份 JSON 快照写进这里，
 * 组件只在 launcher 进程里读 SharedPreferences，不启动 Flutter 引擎。
 */
object HomeWidgetStore {
    private const val PREFS = "qyreader_home_widgets"
    private const val KEY_DATA = "data"

    fun save(context: Context, json: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_DATA, json)
            .apply()
    }

    fun read(context: Context): JSONObject? {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_DATA, null) ?: return null
        return try {
            JSONObject(raw)
        } catch (_: Exception) {
            null
        }
    }

    /** 本地日期 `yyyy-MM-dd`。 */
    fun todayKey(): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    /** 快照是不是今天生成的；跨零点后今日组件归零。 */
    fun isToday(data: JSONObject?): Boolean =
        data != null && data.optString("date") == todayKey()
}
