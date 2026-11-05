package com.xiayitian.chaomu

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 小组件里点一条待办 -> 切换完成状态（2026-11-04 新增）。
 *
 * 撤回就是再点一次。改完直接写回 chaomu.json，然后让小组件自己刷。
 *
 * ⚠️ 一个已知边界：如果朝暮 App 正开着，它内存里有一份旧数据，
 * 下次保存会把这里改的覆盖掉。小组件的改动只在 App 没运行时可靠。
 * 想彻底解决要加文件锁或让 Flutter 侧监听变化，这次先按简单做。
 */
class ToggleReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_TOGGLE) return
        val id = intent.getStringExtra("todoId") ?: return
        if (id.isEmpty()) return
        android.util.Log.d("CMWidget", "toggle id=$id")

        val f = File(context.applicationInfo.dataDir, "app_flutter/chaomu/chaomu.json")
        if (!f.exists()) return

        try {
            synchronized(LOCK) {
                val root = JSONObject(f.readText(Charsets.UTF_8))
                val arr = root.optJSONArray("todos") ?: return
                var hit: JSONObject? = null
                for (i in 0 until arr.length()) {
                    val t = arr.optJSONObject(i) ?: continue
                    if (t.optString("id", "") == id) {
                        hit = t
                        break
                    }
                }
                val t = hit ?: return

                val nowDone = !t.optBoolean("done", false)
                t.put("done", nowDone)
                if (nowDone) {
                    val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
                    t.put("doneAt", fmt.format(Date()))
                } else {
                    t.put("doneAt", JSONObject.NULL)
                }

                // 先写临时文件再改名，避免 App 那边读到半截 JSON
                val tmp = File(f.parentFile, "chaomu.json.tmp")
                tmp.writeText(root.toString(), Charsets.UTF_8)
                if (!tmp.renameTo(f)) {
                    f.writeText(root.toString(), Charsets.UTF_8)
                    tmp.delete()
                }
            }
        } catch (e: Exception) {
            return
        }

        // 立刻刷小组件（4×2 和 4×4 大卡都要刷）
        ChaomuWidget.refresh(context)
    }

    companion object {
        const val ACTION_TOGGLE = "com.xiayitian.chaomu.WIDGET_TOGGLE"
        private val LOCK = Any()
    }
}
