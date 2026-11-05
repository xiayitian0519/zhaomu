package com.xiayitian.chaomu

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Paint
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * 小组件的数据源（2026-11-04 新增）。
 *
 * 用 RemoteViewsService + RemoteViewsFactory 提供 ListView 的数据，
 * 这样小组件里能**上下滑动**看全部待办，不再被 5 行限制住。
 *
 * 数据还是读 Flutter 写的那份 chaomu.json，只读不改；
 * 改状态（点完成/撤回）走 ToggleReceiver。
 */
class ChaomuWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return Factory(applicationContext)
    }

    class Factory(private val ctx: Context) : RemoteViewsFactory {

        /** 一条待办的最小信息 */
        data class Row(
            val id: String,
            val title: String,
            val done: Boolean,
            val overdue: Boolean,
            val priority: Int,
            val timeText: String,
        )

        private var rows: List<Row> = emptyList()

        override fun onCreate() {}

        override fun onDataSetChanged() {
            rows = load()
        }

        override fun onDestroy() {
            rows = emptyList()
        }

        override fun getCount(): Int = rows.size

        override fun getViewAt(position: Int): RemoteViews {
            val rv = RemoteViews(ctx.packageName, R.layout.widget_item)
            if (position >= rows.size) return rv
            val r = rows[position]

            rv.setTextViewText(R.id.item_title, r.title)

            // 时间：逾期用红字并加「逾期」前缀
            rv.setTextViewText(
                R.id.item_time,
                if (r.timeText.isEmpty()) "" else if (r.overdue) "逾期 · ${r.timeText}" else r.timeText
            )
            rv.setTextColor(
                R.id.item_time,
                if (r.overdue) Color.parseColor("#A32D2D") else Color.parseColor("#949CAA")
            )
            rv.setViewVisibility(R.id.item_time, if (r.timeText.isEmpty()) View.GONE else View.VISIBLE)

            // 完成态：变灰 + 划线。灰色要够深，半透明白底上才看得清
            // （2026-11-05 用户反馈「跟背景一个色」，从 #B8BDC8 → #8A91A0 → #6B7280）
            val titleColor = if (r.done) Color.parseColor("#454D5C") else Color.parseColor("#1A1D26")
            rv.setTextColor(R.id.item_title, titleColor)
            rv.setInt(R.id.item_title, "setPaintFlags",
                if (r.done) Paint.ANTI_ALIAS_FLAG or Paint.STRIKE_THRU_TEXT_FLAG
                else Paint.ANTI_ALIAS_FLAG)

            // 左边的小圆点：完成 = 实心对勾，未完成 = 空心
            rv.setImageViewResource(
                R.id.item_check,
                if (r.done) android.R.drawable.checkbox_on_background
                else android.R.drawable.checkbox_off_background
            )

            // 优先级色条
            val bar = when (r.priority) {
                0 -> "#D63A3A"
                1 -> "#C8871A"
                2 -> "#2B6CD4"
                else -> "#5A6270"
            }
            rv.setInt(R.id.item_bar, "setBackgroundColor", Color.parseColor(bar))

            // 点整行 = 切换完成状态（可撤回：再点一次）。
            // 集合型组件的标准做法：外层 setPendingIntentTemplate +
            // 每一行 setOnClickFillInIntent 补 todoId。
            // 之前给每一行直接 setOnClickPendingIntent，真机日志报
            // "Cannot SetOnClickResponse for collection item"，点击全被丢掉。
            rv.setOnClickFillInIntent(
                R.id.item_root,
                Intent().putExtra("todoId", r.id)
            )

            return rv
        }

        override fun getViewTypeCount(): Int = 1

        override fun hasStableIds(): Boolean = false

        /** 加载中占位：不需要，返回 null 用系统默认 */
        override fun getLoadingView(): RemoteViews? = null

        override fun getItemId(position: Int): Long = position.toLong()

        /** 读 chaomu.json，取今天及逾期的未完成 + 今天已完成的 */
        private fun load(): List<Row> {
            val f = File(ctx.applicationInfo.dataDir, "app_flutter/chaomu/chaomu.json")
            if (!f.exists()) return emptyList()

            val all = WidgetPrefs.showAll(ctx)
            val out = ArrayList<Row>()
            // 分布统计：今天 / 逾期未完成 / 逾期已完成 / 明天及以后
            var cToday = 0
            var cOverdueOpen = 0
            var cOverdueDone = 0
            var cFuture = 0
            try {
                val root = JSONObject(f.readText(Charsets.UTF_8))
                val arr = root.optJSONArray("todos") ?: return emptyList()

                val cal = Calendar.getInstance()
                cal.set(Calendar.HOUR_OF_DAY, 0)
                cal.set(Calendar.MINUTE, 0)
                cal.set(Calendar.SECOND, 0)
                cal.set(Calendar.MILLISECOND, 0)
                val dayStart = cal.timeInMillis
                val dayEnd = dayStart + 24 * 3600 * 1000L

                val iso = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)

                for (i in 0 until arr.length()) {
                    val t = arr.optJSONObject(i) ?: continue
                    val done = t.optBoolean("done", false)
                    val dueStr = t.optString("due", "")
                    if (dueStr.isEmpty() || dueStr == "null") continue

                    val due = try {
                        iso.parse(dueStr.substring(0, minOf(19, dueStr.length)))?.time
                    } catch (e: Exception) {
                        null
                    } ?: continue

                    val isOverdue = due < dayStart
                    val isFuture = due >= dayEnd

                    when {
                        isFuture -> cFuture++
                        isOverdue && done -> cOverdueDone++
                        isOverdue -> cOverdueOpen++
                        else -> cToday++
                    }

                    // 默认视图 = 今天全部（含已完成，置底） + 逾期未完成。
                    // 逾期已完成的、将来的一律不进默认视图 —— 否则一堆历史旧待办
                    // 把今天那几条淹了，而且「今天/全部」两种模式条数一样，
                    // 用户会以为按钮坏了（2026-11-05 用户纠正：今天才 11 条，
                    // 其他很多是逾期已完成的）。点「全部」才全放出来。
                    if (!all && (isFuture || (isOverdue && done))) continue

                    val title = t.optString("title", "").trim()
                    if (title.isEmpty()) continue

                    val overdue = isOverdue && !done
                    val hasTime = t.optBoolean("dueHasTime", false)
                    val hhmm = if (hasTime) {
                        SimpleDateFormat("HH:mm", Locale.US).format(Date(due))
                    } else {
                        ""
                    }
                    // 「全部」模式下每行都带日期：即使待办全挤在今天、两种范围
                    // 条数一样，列表每行多一行日期，也能一眼看出模式切了。
                    val timeText = if (all) {
                        val md = SimpleDateFormat("M月d日", Locale.CHINA).format(Date(due))
                        if (hhmm.isEmpty()) md else "$md $hhmm"
                    } else {
                        hhmm
                    }

                    out.add(
                        Row(
                            id = t.optString("id", ""),
                            title = title,
                            done = done,
                            overdue = overdue,
                            priority = t.optInt("priority", -1),
                            timeText = timeText,
                        )
                    )
                }
            } catch (e: Exception) {
                return emptyList()
            }

            // 未完成在前（逾期优先），已完成沉底
            val rows = out.sortedWith(
                compareBy<Row> { it.done }.thenByDescending { it.overdue }
            )
            android.util.Log.d(
                "CMWidget",
                "load: showAll=$all today=$cToday overdueOpen=$cOverdueOpen " +
                    "overdueDone=$cOverdueDone future=$cFuture -> rows=${rows.size}"
            )
            return rows
        }
    }
}
