package com.xiayitian.chaomu

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context

/**
 * 朝暮桌面小组件 · 4×4 大卡（2026-11-05 新增）。
 *
 * 为什么单独做一个 Provider，而不是在 4×2 那个里按尺寸动态换布局：
 * `onAppWidgetOptionsChanged` 各家 ROM 回调时机不一样，有的干脆不回调，
 * 动态换布局很容易翻车。做成两个独立组件，系统列表里各一条，用户自己挑，
 * 行为最可预测。
 *
 * 数据逻辑完全复用 [ChaomuWidget.buildView]，这里只换 layout 资源。
 */
class ChaomuWidgetBig : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(
                id,
                ChaomuWidget.buildView(context, R.layout.widget_chaomu_big)
            )
        }
    }
}
