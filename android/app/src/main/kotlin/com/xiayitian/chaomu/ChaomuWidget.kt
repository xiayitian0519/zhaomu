package com.xiayitian.chaomu

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * 朝暮的桌面小组件（2026-11-04 新增，同日改成可滑动 + 可点完成）。
 *
 * 数据来源：Flutter 用 dart:io 把存档写在
 * `getApplicationDocumentsDirectory()/chaomu/chaomu.json`，
 * 安卓上路径是 `/data/user/0/<包名>/app_flutter/chaomu/chaomu.json`。
 * 小组件是另一个进程，读不到 Flutter 内存，但能直接读这个文件。
 *
 * 列表本身由 ChaomuWidgetService 提供（RemoteViewsService + ListView），
 * 所以能上下滑动看全部今日待办，不再限制 5 条。
 * 点一条 = 切换完成（再点撤回），走 ToggleReceiver。
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

        /** 拼好一个 RemoteViews 外壳（列表内容是 Service 填的） */
        fun buildView(
            context: Context,
            layoutId: Int = R.layout.widget_chaomu
        ): RemoteViews {
            val rv = RemoteViews(context.packageName, layoutId)

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

            // 绑列表数据源
            val svcIntent = Intent(context, ChaomuWidgetService::class.java).apply {
                data = Uri.parse("chaomu://widget/list")
            }
            rv.setRemoteAdapter(R.id.widget_list, svcIntent)

            // 列表空时显示这句话
            rv.setEmptyView(R.id.widget_list, R.id.widget_empty)

            return rv
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

        /**
         * 让所有小组件立刻刷一次。
         *
         * 2026-11-05：现在有两个组件（4×2 和 4×4 大卡），两个都要刷，
         * 否则只加了大的那个的用户会看到数据不动。
         */
        fun refresh(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            refreshOne(mgr, context, ChaomuWidget::class.java, R.layout.widget_chaomu)
            refreshOne(
                mgr, context, ChaomuWidgetBig::class.java, R.layout.widget_chaomu_big
            )
        }

        private fun refreshOne(
            mgr: AppWidgetManager,
            context: Context,
            cls: Class<*>,
            layoutId: Int
        ) {
            val ids = mgr.getAppWidgetIds(ComponentName(context, cls))
            for (id in ids) {
                mgr.notifyAppWidgetViewDataChanged(id, R.id.widget_list)
                mgr.updateAppWidget(id, buildView(context, layoutId))
            }
        }
    }
}
