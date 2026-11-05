package com.xiayitian.chaomu

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 小组件上「今天 / 全部」切换按钮的接收器（2026-11-05 加）。
 *
 * 点一下切换「只显示今天+逾期」和「显示全部（含将来）」两种范围，
 * 状态存在 SharedPreferences（widget 进程和 App 进程同包名，都能读写），
 * 不动 chaomu.json，避免和 Flutter 主进程并发写坏存档。
 */
class WidgetScopeReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_TOGGLE_SCOPE) return
        val next = !WidgetPrefs.showAll(context)
        WidgetPrefs.setShowAll(context, next)
        android.util.Log.d("CMWidget", "scope toggle -> showAll=$next")
        // 刷新所有小组件（refresh 里会重建 adapter，见 ChaomuWidget 的注释）
        ChaomuWidget.refresh(context)
    }

    companion object {
        const val ACTION_TOGGLE_SCOPE = "com.xiayitian.chaomu.WIDGET_TOGGLE_SCOPE"

        // 下面几个保留是为了兼容老调用，统一委托给 WidgetPrefs
        const val PREFS = WidgetPrefs.PREFS
        const val KEY_SHOW_ALL = WidgetPrefs.KEY_SHOW_ALL
        fun showAll(context: Context): Boolean = WidgetPrefs.showAll(context)
    }
}
