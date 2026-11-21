package com.qyreader.qy_reader.widgets

import java.util.Locale
import kotlin.math.roundToInt

/** 组件里的数字文案（与 App 内格式保持一致）。 */
object WidgetText {
    /** `42.5%` / `100%`。 */
    fun percent(value: Double): String {
        val p = value.coerceIn(0.0, 1.0) * 100
        if (p >= 99.995) return "100%"
        var text = String.format(Locale.US, "%.2f", p)
        text = text.trimEnd('0').trimEnd('.')
        return "$text%"
    }

    /** 不到 1 小时 `2:13`，超过 `1:23:45`。 */
    fun clock(durationMs: Long): String {
        val total = (if (durationMs < 0) 0L else durationMs) / 1000
        val hours = total / 3600
        val minutes = (total % 3600) / 60
        val seconds = total % 60
        return if (hours > 0) {
            String.format(Locale.US, "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format(Locale.US, "%d:%02d", minutes, seconds)
        }
    }

    /** 0..1 → ProgressBar 的 0..1000。 */
    fun progress(value: Double): Int = (value.coerceIn(0.0, 1.0) * 1000).roundToInt()
}
