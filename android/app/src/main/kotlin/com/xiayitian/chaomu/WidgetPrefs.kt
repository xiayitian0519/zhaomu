package com.xiayitian.chaomu

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * 桌面小组件自己的设置（2026-11-05 加）。
 *
 * 为什么单独存一份：透明度以前写在 chaomu.json 里，由 Flutter 的 AppState 管。
 * 但组件是独立渲染的，App 改完存档组件不会自己知道；反过来组件设置页直接写
 * chaomu.json 又会和 Flutter 主进程并发写坏存档（ToggleReceiver 已踩过这个边界）。
 * 所以组件相关的开关统一放这份 SharedPreferences，App / 组件 / 设置页都只读写这里。
 *
 * 用 apply() 而不是 commit()：同一进程内 apply 同步更新内存缓存，
 * 紧跟着的 ChaomuWidget.refresh() 立刻就能读到新值，不用等落盘。
 */
object WidgetPrefs {
    const val PREFS = "chaomu_widget_prefs"
    const val KEY_SHOW_ALL = "widgetShowAll"
    const val KEY_BG_ALPHA = "widgetBgAlpha"

    /** 默认 160 = 63% 不透明，装完就能看出半透明，不用先去调 */
    private const val DEFAULT_BG_ALPHA = 160

    private fun sp(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** true = 显示全部（含将来的待办）；false = 只显示今天 + 逾期 */
    fun showAll(context: Context): Boolean =
        sp(context).getBoolean(KEY_SHOW_ALL, false)

    fun setShowAll(context: Context, v: Boolean) {
        sp(context).edit().putBoolean(KEY_SHOW_ALL, v).apply()
    }

    /**
     * 背景不透明度 0~255。
     * 老版本把值存在 chaomu.json 的 widgetBgAlpha 里，这里做一次兼容：
     * SharedPreferences 里没存过就回去读老存档，读到就搬过来，用户之前调过的不丢。
     */
    fun bgAlpha(context: Context): Int {
        val p = sp(context)
        if (p.contains(KEY_BG_ALPHA)) {
            return p.getInt(KEY_BG_ALPHA, DEFAULT_BG_ALPHA).coerceIn(0, 255)
        }
        val legacy = legacyAlpha(context)
        if (legacy != null) {
            p.edit().putInt(KEY_BG_ALPHA, legacy).apply()
            return legacy
        }
        return DEFAULT_BG_ALPHA
    }

    fun setBgAlpha(context: Context, v: Int) {
        sp(context).edit().putInt(KEY_BG_ALPHA, v.coerceIn(0, 255)).apply()
    }

    /**
     * 待办分布：[今天, 逾期未完成, 逾期已完成, 明天及以后]。
     * 设置页用它把数据摊开给用户看：为什么「今天」只列十几条、
     * 「全部」才把逾期已完成和将来的放出来，避免误以为按钮坏了。
     */
    fun todoBreakdown(context: Context): IntArray {
        val r = IntArray(4)
        try {
            val f = File(context.applicationInfo.dataDir, "app_flutter/chaomu/chaomu.json")
            if (!f.exists()) return r
            val root = JSONObject(f.readText(Charsets.UTF_8))
            val arr = root.optJSONArray("todos") ?: return r
            val cal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val dayStart = cal.timeInMillis
            val dayEnd = dayStart + 24 * 3600 * 1000L
            val iso = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
            for (i in 0 until arr.length()) {
                val t = arr.optJSONObject(i) ?: continue
                val s = t.optString("due", "")
                if (s.isEmpty() || s == "null") continue
                val due = try {
                    iso.parse(s.substring(0, minOf(19, s.length)))?.time
                } catch (e: Exception) {
                    null
                } ?: continue
                val done = t.optBoolean("done", false)
                when {
                    due >= dayEnd -> r[3]++
                    due < dayStart && done -> r[2]++
                    due < dayStart -> r[1]++
                    else -> r[0]++
                }
            }
        } catch (e: Exception) {
        }
        return r
    }

    private fun legacyAlpha(context: Context): Int? = try {
        val f = File(context.applicationInfo.dataDir, "app_flutter/chaomu/chaomu.json")
        if (!f.exists()) {
            null
        } else {
            val root = JSONObject(f.readText(Charsets.UTF_8))
            if (root.has("widgetBgAlpha")) {
                root.optInt("widgetBgAlpha", DEFAULT_BG_ALPHA).coerceIn(0, 255)
            } else {
                null
            }
        }
    } catch (e: Exception) {
        null
    }
}
