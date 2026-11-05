package com.xiayitian.chaomu

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * 朝暮的桌面小组件（2026-11-04 建，2026-11-05 改成静态行）。
 *
 * 数据来源：Flutter 把存档写在
 * `getApplicationDocumentsDirectory()/chaomu/chaomu.json`，
 * 安卓上是 `/data/user/0/<包名>/app_flutter/chaomu/chaomu.json`。
 * 小组件是另一个进程，读不到 Flutter 内存，但能直接读这个文件。
 *
 * **为什么不用 ListView（2026-11-05）**：
 * 原来走 RemoteViewsService + ListView 做集合型组件，小米上反复显示
 * 「载入窗口小部件时出现问题」。alpha、service exported、URI 唯一化都试过，
 * 没根治 —— 集合型组件要跨进程绑定数据源，这条路在这台机器上就是不通。
 * 现在改成静态 5 行，updateAppWidget 一次把内容填进去，不依赖任何绑定。
 * 代价：不能上下滑，只显示前 5 条。
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

        /** 静态布局里最多显示几行，要和 widget_chaomu_static.xml 对得上 */
        private const val MAX_ROWS = 4

        private val ROW_IDS = intArrayOf(
            R.id.row1, R.id.row2, R.id.row3, R.id.row4, R.id.row5
        )
        private val BAR_IDS = intArrayOf(
            R.id.row1_bar, R.id.row2_bar, R.id.row3_bar, R.id.row4_bar, R.id.row5_bar
        )
        private val CHECK_IDS = intArrayOf(
            R.id.row1_check, R.id.row2_check, R.id.row3_check, R.id.row4_check,
            R.id.row5_check
        )
        private val TITLE_IDS = intArrayOf(
            R.id.row1_title, R.id.row2_title, R.id.row3_title, R.id.row4_title,
            R.id.row5_title
        )
        private val TIME_IDS = intArrayOf(
            R.id.row1_time, R.id.row2_time, R.id.row3_time, R.id.row4_time,
            R.id.row5_time
        )

        /** 四象限色条 */
        private val PRIORITY_COLORS = intArrayOf(
            0xFFE24B4A.toInt(), // 0 重要紧急
            0xFFEF9F27.toInt(), // 1 重要不紧急
            0xFF378ADD.toInt(), // 2 不重要紧急
            0xFF8A91A0.toInt()  // 3 都不算
        )

        /** 一条待办，给静态行用 */
        private class Row(
            val id: String,
            val title: String,
            val hhmm: String,
            val done: Boolean,
            val priority: Int
        )

        /** 拼好整块 RemoteViews（内容直接填进去，没有列表控件） */
        fun buildView(context: Context): RemoteViews {
            try {
                val rv = RemoteViews(context.packageName, R.layout.widget_chaomu_static)

                // 点标题行 → 打开 App
                val launch = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val pi = PendingIntent.getActivity(
                    context, 0, launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                rv.setOnClickPendingIntent(R.id.widget_head, pi)

                val df = SimpleDateFormat("M月d日 EEEE", Locale.CHINA)
                rv.setTextViewText(R.id.widget_date, df.format(Date()))

                val rows = readTodayRows(context)
                val total = rows.size
                val done = rows.count { it.done }
                rv.setTextViewText(R.id.widget_count, "$done/$total 条")

                for (i in 0 until MAX_ROWS) {
                    if (i < rows.size) {
                        val r = rows[i]
                        rv.setViewVisibility(ROW_IDS[i], View.VISIBLE)
                        rv.setTextViewText(TITLE_IDS[i], r.title)
                        rv.setTextViewText(TIME_IDS[i], r.hhmm)
                        rv.setTextViewText(CHECK_IDS[i], if (r.done) "✓" else "○")
                        rv.setTextColor(
                            TITLE_IDS[i],
                            if (r.done) 0xFFB8BDC8.toInt() else 0xFF2C2F38.toInt()
                        )
                        rv.setInt(BAR_IDS[i], "setBackgroundColor", barColor(r.priority))

                        // 点整行 = 切换完成（再点撤回），走 ToggleReceiver
                        val toggle = Intent(context, ToggleReceiver::class.java).apply {
                            action = ToggleReceiver.ACTION_TOGGLE
                            putExtra("todoId", r.id)
                        }
                        val tpi = PendingIntent.getBroadcast(
                            context, 100 + i, toggle,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        rv.setOnClickPendingIntent(ROW_IDS[i], tpi)
                    } else {
                        rv.setViewVisibility(ROW_IDS[i], View.GONE)
                    }
                }

                if (total == 0) {
                    rv.setViewVisibility(R.id.widget_empty, View.VISIBLE)
                } else {
                    rv.setViewVisibility(R.id.widget_empty, View.GONE)
                }

                return rv
            } catch (t: Throwable) {
                // 桌面显示「载入窗口小部件时出现问题」时，把真实堆栈写到私有目录，
                // App 里的「小组件自检」能读出来（2026-11-05）
                try {
                    val f = File(context.filesDir, "widget_error.txt")
                    f.writeText(
                        SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date()) +
                            "\n" + android.util.Log.getStackTraceString(t)
                    )
                } catch (_: Throwable) {
                }
                throw t
            }
        }

        private fun barColor(priority: Int): Int {
            if (priority < 0 || priority > 3) return 0xFF8A91A0.toInt()
            return PRIORITY_COLORS[priority]
        }

        /** 读今天的待办，未完成在前、按时间排，最多 MAX_ROWS 条 */
        private fun readTodayRows(context: Context): List<Row> {
            val f = File(context.applicationInfo.dataDir, "app_flutter/chaomu/chaomu.json")
            if (!f.exists()) return emptyList()
            val out = ArrayList<Row>()
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
                val hm = SimpleDateFormat("HH:mm", Locale.CHINA)

                for (i in 0 until arr.length()) {
                    val t = arr.optJSONObject(i) ?: continue
                    val dueStr = t.optString("due", "")
                    if (dueStr.isEmpty() || dueStr == "null") continue
                    val due = try {
                        iso.parse(dueStr.substring(0, minOf(19, dueStr.length)))?.time
                    } catch (e: Exception) {
                        null
                    } ?: continue
                    if (due < dayStart || due >= dayEnd) continue
                    val title = t.optString("title", "").trim()
                    if (title.isEmpty()) continue
                    val hhmm = hm.format(Date(due))
                    // 23:59 表示「当天截止」，不显示具体时分，免得看着像半夜提醒
                    out.add(
                        Row(
                            id = t.optString("id", ""),
                            title = title,
                            hhmm = if (hhmm == "23:59") "" else hhmm,
                            done = t.optBoolean("done", false),
                            priority = t.optInt("priority", -1)
                        )
                    )
                }
            } catch (e: Exception) {
                return emptyList()
            }
            // 未完成在前；同状态按时间（同一天内 HH:mm 字典序等于时间序）
            out.sortWith(compareBy({ it.done }, { it.hhmm }))
            return if (out.size > MAX_ROWS) out.subList(0, MAX_ROWS) else out
        }

        /** 让所有小组件立刻刷一次（4×2 和 4×4 都刷） */
        fun refresh(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            for (cls in arrayOf(
                ChaomuWidget::class.java,
                ChaomuWidgetBig::class.java
            )) {
                val ids = mgr.getAppWidgetIds(ComponentName(context, cls))
                for (id in ids) {
                    mgr.updateAppWidget(id, buildView(context))
                }
            }
        }
    }
}
