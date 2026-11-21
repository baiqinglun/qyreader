package com.qyreader.qy_reader.widgets

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import com.qyreader.qy_reader.R
import java.io.File
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * 组件封面：把本地封面裁成圆角方形；没有封面 / 解码失败时画一个书形占位图。
 *
 * RemoteViews 没法给 ImageView 做圆角裁剪，所以这里直接在 Bitmap 上裁好
 * 再 setImageViewBitmap（也顺便把大图缩小，避免 Binder 事务超限）。
 */
object WidgetBitmap {
    fun cover(
        context: Context,
        path: String?,
        widthDp: Int,
        heightDp: Int,
        radiusDp: Float = 8f,
    ): Bitmap {
        val density = context.resources.displayMetrics.density
        val width = max(1, (widthDp * density).roundToInt())
        val height = max(1, (heightDp * density).roundToInt())
        val radius = radiusDp * density
        val source = decodeCover(path, width, height)
            ?: return placeholder(context, width, height, radius)
        return try {
            rounded(source, width, height, radius)
        } finally {
            source.recycle()
        }
    }

    private fun decodeCover(path: String?, reqWidth: Int, reqHeight: Int): Bitmap? {
        if (path.isNullOrBlank()) return null
        val file = File(path)
        if (!file.isFile) return null
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= reqWidth &&
                bounds.outHeight / (sample * 2) >= reqHeight
            ) {
                sample *= 2
            }
            BitmapFactory.decodeFile(
                path,
                BitmapFactory.Options().apply {
                    inSampleSize = sample
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                },
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun rounded(source: Bitmap, width: Int, height: Int, radius: Float): Bitmap {
        val output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val scale = max(
            width.toFloat() / source.width,
            height.toFloat() / source.height,
        )
        val dx = (width - source.width * scale) / 2f
        val dy = (height - source.height * scale) / 2f
        val shader = BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        shader.setLocalMatrix(Matrix().apply {
            setScale(scale, scale)
            postTranslate(dx, dy)
        })
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
            this.shader = shader
        }
        canvas.drawRoundRect(
            RectF(0f, 0f, width.toFloat(), height.toFloat()),
            radius,
            radius,
            paint,
        )
        return output
    }

    private fun placeholder(
        context: Context,
        width: Int,
        height: Int,
        radius: Float,
    ): Bitmap {
        val output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val background = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = context.getColor(R.color.widget_cover_placeholder)
        }
        val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
        canvas.drawRoundRect(rect, radius, radius, background)

        val accent = context.getColor(R.color.widget_accent)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = accent
            style = Paint.Style.STROKE
            strokeWidth = max(2f, width * 0.018f)
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        val centerX = width / 2f
        val top = height * 0.30f
        val bottom = height * 0.70f
        val leftPath = Path().apply {
            moveTo(centerX, top + height * 0.035f)
            cubicTo(
                width * 0.40f, top,
                width * 0.27f, top,
                width * 0.18f, top + height * 0.03f,
            )
            lineTo(width * 0.18f, bottom - height * 0.03f)
            cubicTo(
                width * 0.28f, bottom - height * 0.02f,
                width * 0.42f, bottom,
                centerX, bottom + height * 0.035f,
            )
            close()
        }
        val rightPath = Path().apply {
            moveTo(centerX, top + height * 0.035f)
            cubicTo(
                width * 0.60f, top,
                width * 0.73f, top,
                width * 0.82f, top + height * 0.03f,
            )
            lineTo(width * 0.82f, bottom - height * 0.03f)
            cubicTo(
                width * 0.72f, bottom - height * 0.02f,
                width * 0.58f, bottom,
                centerX, bottom + height * 0.035f,
            )
            close()
        }
        canvas.drawPath(leftPath, paint)
        canvas.drawPath(rightPath, paint)
        return output
    }
}
