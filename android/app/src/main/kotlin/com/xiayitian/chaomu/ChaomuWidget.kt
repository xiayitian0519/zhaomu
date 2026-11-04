package com.xiayitian.chaomu

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * 朝暮的桌面小组件（2026-11-04 新增）。
 *
 * 数据从哪来：Flutter 用 dart:io 把存档写在
 * `getApplicationDocumentsDirectory()/chaomu/chaomu.json`，
 * 安卓上这个目录是 `/data/user/0/<包名>/app_flutter/chaomu/chaomu.json`。
 * 小组件是另一个进程，读不到 Flutter 的内存，但能直接读这个文件 ——
 * 所以不需要 MethodChannel、不需要 shared_preferences 桥接。
 *
 * 刷新时机：
 * 1. updatePeriodMillis（widget_info.xml 里设了 30 分钟，系统最小就是这个值）
 * 2. 用户点小组件标题行手动刷
 *
 * ⚠️ 小米/红米上「定时刷新」经常不执行（省电策略杀后台）。用户要在
 * 系统设置里把朝暮加进「自启动」白名单、省电策略选「无限制」，才会稳定。
 */
class ChaomuWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, buildView(context))
        }
    }

    companion object {
        private const val PREFS = "chaomu_widget"

        /** Flutter 存档路径 */
        private fun archiveFile(context: Context): File =
            File(context.applicationInfo.dataDir, "app_flutter/chaomu/chaomu.json")

        /** 拼好一个 RemoteViews */
        fun buildView(context: Context): RemoteViews {
            val rv = RemoteViews(context.packageName, R.layout.widget_chaomu)

            // 点标题行 → 打开 App
            val launch = android.content.Intent(context, MainActivity::class.java).apply {
                flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK or
                        android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pi = android.app.PendingIntent.getActivity(
                context, 0, launch,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                        android.app.PendingIntent.FLAG_IMMUTABLE
            )
            rv.setOnClickPendingIntent(R.id.widget_head, pi)

            val items = readToday(context)

            // 日期标题
            val df = SimpleDateFormat("M月d日 EEEE", Locale.CHINA)
            rv.setTextViewText(R.id.widget_date, df.format(Date()))

            if (items.isEmpty()) {
                rv.setTextViewText(R.id.widget_empty, "今天没有待办")
                rv.setViewVisibility(R.id.widget_empty, View.VISIBLE)
                for (i in 1..5) {
                    rv.setViewVisibility(rowId(i), View.GONE)
                }
                return rv
            }

            rv.setViewVisibility(R.id.widget_empty, View.GONE)
            rv.setTextViewText(R.id.widget_count, "${items.size} 条")

            // 最多显示 5 条，超出的显示「还有 N 条」
            for (i in 1..5) {
                val rid = rowId(i)
                if (i <= items.size) {
                    val it = items[i - 1]
                    rv.setViewVisibility(rid, View.VISIBLE)
                    rv.setTextViewText(titleId(rid), it.first)
                    // 红黄蓝灰 四象限色点
                    rv.setTextColor(titleId(rid), it.second)
                } else {
                    rv.setViewVisibility(rid, View.GONE)
                }
            }

            if (items.size > 5) {
                rv.setTextViewText(R.id.widget_more, "还有 ${items.size - 5} 条")
                rv.setViewVisibility(R.id.widget_more, View.VISIBLE)
            } else {
                rv.setViewVisibility(R.id.widget_more, View.GONE)
            }

            return rv
        }

        private fun rowId(i: Int): Int = when (i) {
            1 -> R.id.widget_row1
            2 -> R.id.widget_row2
            3 -> R.id.widget_row3
            4 -> R.id.widget_row4
            else -> R.id.widget_row5
        }

        private fun titleId(rid: Int): Int = when (rid) {
            R.id.widget_row1 -> R.id.widget_t1
            R.id.widget_row2 -> R.id.widget_t2
            R.id.widget_row3 -> R.id.widget_t3
            R.id.widget_row4 -> R.id.widget_t4
            else -> R.id.widget_t5
        }

        /** 读存档，返回今天未完成的待办：标题 + 颜色 */
        private fun readToday(context: Context): List<Pair<String, Int>> {
            val f = archiveFile(context)
            if (!f.exists()) return emptyList()

            val out = ArrayList<Pair<String, Int>>()
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
                    if (t.optBoolean("done", false)) continue

                    val dueStr = t.optString("due", "")
                    if (dueStr.isEmpty() || dueStr == "null") continue

                    val due = try {
                        iso.parse(dueStr.substring(0, minOf(19, dueStr.length)))?.time
                    } catch (e: Exception) {
                        null
                    } ?: continue

                    // 只要今天的（含更早的逾期，一起顶上来）
                    if (due >= dayEnd) continue

                    val title = t.optString("title", "").trim()
                    if (title.isEmpty()) continue

                    val color = when (t.optInt("priority", -1)) {
                        0 -> Color.parseColor("#D63A3A") // 重要且紧急
                        1 -> Color.parseColor("#C8871A") // 重要不紧急
                        2 -> Color.parseColor("#2B6CD4") // 不重要但紧急
                        else -> Color.parseColor("#5A6270") // 都不算
                    }
                    // 逾期的条目前面加个「! 」
                    val prefix = if (due < dayStart) "! " else ""
                    out.add(Pair(prefix + title, color))
                }
            } catch (e: Exception) {
                return emptyList()
            }

            // 逾期的排前面，其次按 due 升序（readToday 里没存 due，简化：保持原顺序）
            return out
        }

        /** 让所有小组件立刻刷一次 */
        fun refresh(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, ChaomuWidget::class.java))
            if (ids.isEmpty()) return
            for (id in ids) {
                mgr.updateAppWidget(id, buildView(context))
            }
        }
    }
}
