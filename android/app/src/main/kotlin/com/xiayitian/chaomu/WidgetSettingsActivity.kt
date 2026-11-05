package com.xiayitian.chaomu

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView

/**
 * 桌面小组件自己的设置页（2026-11-05 用户明确要求：透明度别放 App 设置里）。
 *
 * 两个入口能到这儿：
 * 1. 组件标题栏最右边的「设置」按钮（PendingIntent.getActivity）
 * 2. App 设置 → 桌面 → 小组件设置（MethodChannel openWidgetSettings）
 * 从系统「添加小部件」的配置流程进来时也认 EXTRA_APPWIDGET_ID。
 *
 * 拖一下滑块 / 拨一下开关就立刻落盘 + 刷新组件，边调边能在桌面上看到效果，
 * 不用点「完成」才生效。「完成」只是把结果码带回去并关掉这一页。
 *
 * 刻意不继承 FlutterActivity：这是个纯原生的轻量页面，起得快，
 * 也不会和 Flutter 引擎抢生命周期。
 */
class WidgetSettingsActivity : Activity() {

    private lateinit var seek: SeekBar
    private lateinit var percent: TextView
    private lateinit var preview: View
    private lateinit var swAll: Switch
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        appWidgetId = intent?.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        setContentView(R.layout.widget_settings)
        seek = findViewById(R.id.seek_alpha)
        percent = findViewById(R.id.txt_percent)
        preview = findViewById(R.id.preview_card)
        swAll = findViewById(R.id.switch_all)

        seek.max = 255
        seek.progress = WidgetPrefs.bgAlpha(this)
        updatePreview(seek.progress)
        swAll.isChecked = WidgetPrefs.showAll(this)

        // 把数据分布摊开写清楚。用户 2026-11-05 纠正过：今天才 11 条，
        // 其余很多是逾期已完成的 —— 默认视图不该把那堆旧待办也塞进来。
        val b = WidgetPrefs.todoBreakdown(this)
        findViewById<TextView>(R.id.txt_scope_hint).text =
            "现在：今天 ${b[0]} 条 · 逾期未完成 ${b[1]} 条 · " +
                "逾期已完成 ${b[2]} 条 · 明天以后 ${b[3]} 条\n" +
                "点「今天」只看前两类，点「全部」才把后两类也放出来。"

        seek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(sb: SeekBar?, v: Int, fromUser: Boolean) {
                WidgetPrefs.setBgAlpha(this@WidgetSettingsActivity, v)
                updatePreview(v)
                ChaomuWidget.refresh(this@WidgetSettingsActivity)
            }

            override fun onStartTrackingTouch(sb: SeekBar?) {}
            override fun onStopTrackingTouch(sb: SeekBar?) {}
        })

        swAll.setOnCheckedChangeListener { _, v ->
            WidgetPrefs.setShowAll(this, v)
            ChaomuWidget.refresh(this)
        }

        findViewById<Button>(R.id.btn_done).setOnClickListener {
            ChaomuWidget.refresh(this)
            val data = Intent().apply {
                if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                }
            }
            setResult(RESULT_OK, data)
            finish()
        }
    }

    private fun updatePreview(v: Int) {
        percent.text = "${(v / 255.0 * 100).toInt()}%（越往左越透）"
        preview.setBackgroundColor(Color.argb(v, 255, 255, 255))
    }
}
