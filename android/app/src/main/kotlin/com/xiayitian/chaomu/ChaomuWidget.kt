package com.xiayitian.chaomu

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.widget.RemoteViews
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * 朝暮的桌面小组件（2026-11-04 建，2026-11-05 恢复可滑动列表）。
 *
 * 数据来源：Flutter 把存档写在
 * `getApplicationDocumentsDirectory()/chaomu/chaomu.json`，
 * 安卓上是 `/data/user/0/<包名>/app_flutter/chaomu/chaomu.json`。
 *
 * 列表内容由 [ChaomuWidgetService] 提供（RemoteViewsService + ListView），
 * 能上下滑动看全部今日待办。
 *
 * 2026-11-05 的关键教训：RemoteViews 只允许白名单内的控件，
 * 裸 `<View>` 会抛 `Class not allowed to be inflated`，导致整块组件加载失败。
 * 之前反复的「载入窗口小部件时出现问题」就是这个原因。布局里所有色条/分隔线
 * 都已经换成 TextView。
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

        /** 背景透明度默认值：184 = 72% 不透明 */
        private const val DEFAULT_BG_ALPHA = 184

        /** 拼好整块 RemoteViews（列表内容是 Service 填的） */
        fun buildView(context: Context): RemoteViews {
            try {
                val rv = RemoteViews(context.packageName, R.layout.widget_chaomu)

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

                val stat = readTodayStat(context)
                rv.setTextViewText(R.id.widget_count, "${stat.first}/${stat.second} 条")

                // 背景透明度（用户在设置里可调，存 chaomu.json 的 widgetBgAlpha）
                val alpha = readBgAlpha(context)
                rv.setInt(
                    R.id.widget_root, "setBackgroundColor",
                    Color.argb(alpha, 255, 255, 255)
                )

                // 「今天 / 全部」切换按钮（2026-11-05）
                val showAll = WidgetScopeReceiver.showAll(context)
                rv.setTextViewText(R.id.widget_scope, if (showAll) "全部" else "今天")
                val scopeIntent = Intent(context, WidgetScopeReceiver::class.java).apply {
                    action = WidgetScopeReceiver.ACTION_TOGGLE_SCOPE
                }
                val scopePi = PendingIntent.getBroadcast(
                    context, 999, scopeIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                rv.setOnClickPendingIntent(R.id.widget_scope, scopePi)

                // 绑列表数据源
                val svcIntent = Intent(context, ChaomuWidgetService::class.java).apply {
                    data = Uri.parse("chaomu://widget/list")
                }
                rv.setRemoteAdapter(R.id.widget_list, svcIntent)
                rv.setEmptyView(R.id.widget_list, R.id.widget_empty)

                return rv
            } catch (t: Throwable) {
                // 渲染失败时把堆栈写到私有目录，App 里的「小组件自检」能读出来
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

        /** 读背景透明度（0~255），读不到用默认 184 */
        private fun readBgAlpha(context: Context): Int {
            return try {
                val f = File(context.applicationInfo.dataDir, "app_flutter/chaomu/chaomu.json")
                if (!f.exists()) return DEFAULT_BG_ALPHA
                val root = JSONObject(f.readText(Charsets.UTF_8))
                val v = root.optInt("widgetBgAlpha", DEFAULT_BG_ALPHA)
                if (v < 0 || v > 255) DEFAULT_BG_ALPHA else v
            } catch (e: Exception) {
                DEFAULT_BG_ALPHA
            }
        }

        /** 返回 (未完成条数, 总条数) */
        private fun readTodayStat(context: Context): Pair<Int, Int> {
            val f = File(context.applicationInfo.dataDir, "app_flutter/chaomu/chaomu.json")
            if (!f.exists()) return Pair(0, 0)
            var open = 0
            var total = 0
            try {
                val root = JSONObject(f.readText(Charsets.UTF_8))
                val arr = root.optJSONArray("todos") ?: return Pair(0, 0)
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
                    val dueStr = t.optString("due", "")
                    if (dueStr.isEmpty() || dueStr == "null") continue
                    val due = try {
                        iso.parse(dueStr.substring(0, minOf(19, dueStr.length)))?.time
                    } catch (e: Exception) {
                        null
                    } ?: continue
                    if (due >= dayEnd) continue
                    total++
                    if (!t.optBoolean("done", false)) open++
                }
            } catch (e: Exception) {
                return Pair(0, 0)
            }
            return Pair(open, total)
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
                    mgr.notifyAppWidgetViewDataChanged(id, R.id.widget_list)
                    mgr.updateAppWidget(id, buildView(context))
                }
            }
        }
    }
}
