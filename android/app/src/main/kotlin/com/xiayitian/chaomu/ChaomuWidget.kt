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

                // 背景透明度：读小组件自己的设置（SharedPreferences），
                // App / 组件 / 设置页共用一份，不再依赖 Flutter 写 chaomu.json
                val alpha = WidgetPrefs.bgAlpha(context)
                rv.setInt(
                    R.id.widget_root, "setBackgroundColor",
                    Color.argb(alpha, 255, 255, 255)
                )

                // 「今天 / 全部」当前状态
                val showAll = WidgetPrefs.showAll(context)
                rv.setTextViewText(R.id.widget_scope, if (showAll) "全部" else "今天")

                // 计数跟着当前范围走：切到「全部」时把将来的也数进去，
                // 数字会变，用户点一下就能看出真的切了（不然列表前面几行一样，
                // 会误以为按钮没生效 —— 2026-11-05 用户反馈）。
                val stat = readStat(context, showAll)
                // 把模式写进计数里：数据里没有将来待办时，两种范围列表本来就该一样，
                // 不写这几个字用户会以为按钮坏了（2026-11-05 用户反馈）。
                rv.setTextViewText(
                    R.id.widget_count,
                    "${if (showAll) "全部" else "今天"} ${stat.first}/${stat.second}"
                )
                android.util.Log.d(
                    "CMWidget",
                    "buildView alpha=$alpha showAll=$showAll stat=${stat.first}/${stat.second}"
                )

                val scopeIntent = Intent(context, WidgetScopeReceiver::class.java).apply {
                    action = WidgetScopeReceiver.ACTION_TOGGLE_SCOPE
                }
                val scopePi = PendingIntent.getBroadcast(
                    context, 999, scopeIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                rv.setOnClickPendingIntent(R.id.widget_scope, scopePi)

                // 「设置」按钮：打开小组件自己的设置页（透明度 / 显示范围）
                val settingsIntent = Intent(context, WidgetSettingsActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val settingsPi = PendingIntent.getActivity(
                    context, 998, settingsIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                rv.setOnClickPendingIntent(R.id.widget_settings, settingsPi)

                // 列表项点击必须用 template + fillIn，不能给每一行直接挂
                // setOnClickPendingIntent。真机 logcat 抓到 MIUI 的原话：
                //   W RemoteViews: Cannot SetOnClickResponse for collection item
                // 集合里的 item 直接挂 PendingIntent 会被 launcher 丢掉，
                // 表现就是「点待办没反应」。template 必须 MUTABLE，fillIn 才补得进 extras。
                val toggleTemplate = Intent(context, ToggleReceiver::class.java).apply {
                    action = ToggleReceiver.ACTION_TOGGLE
                }
                val togglePi = PendingIntent.getBroadcast(
                    context, 1000, toggleTemplate,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                )
                rv.setPendingIntentTemplate(R.id.widget_list, togglePi)

                // 绑列表数据源。data 里同时带 scope 和时间戳：
                // 换范围时 adapter 标识一定变，逼系统重新绑定 Service、重建 Factory；
                // 时间戳保证同一范围里手动刷新也能重建。
                // MIUI 会吞 notifyAppWidgetViewDataChanged（真机日志
                // "Trying to notify widget update deferred"），光靠那个通知不够。
                val scopeKey = if (showAll) "all" else "today"
                val svcIntent = Intent(context, ChaomuWidgetService::class.java).apply {
                    data = Uri.parse("chaomu://widget/list/$scopeKey/${System.currentTimeMillis()}")
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

        /** 返回 (未完成条数, 总条数)；showAll=false 只数今天+逾期 */
        private fun readStat(context: Context, showAll: Boolean): Pair<Int, Int> {
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
                    val done = t.optBoolean("done", false)
                    // 和 ChaomuWidgetService.load() 用同一套口径，
                    // 不然标题上的数字和列表里实际条数对不上
                    if (!showAll && (due >= dayEnd || (due < dayStart && done))) continue
                    total++
                    if (!done) open++
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
                    // 顺序有讲究：先换整块 RemoteViews（里面 setRemoteAdapter 的 data
                    // 已经变了，系统会重新绑定 Service），再补一次 dataChanged 通知。
                    // 反过来先通知再换，MIUI 会把那次通知标记成 deferred 然后丢掉，
                    // 真机表现就是「按钮文字变了、列表纹丝不动」。
                    mgr.updateAppWidget(id, buildView(context))
                    mgr.notifyAppWidgetViewDataChanged(id, R.id.widget_list)
                }
            }
        }
    }
}
