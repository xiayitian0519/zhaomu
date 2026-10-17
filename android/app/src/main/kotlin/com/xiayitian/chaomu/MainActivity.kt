package com.xiayitian.chaomu

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 跳系统设置页（通知渠道 / 应用信息 / 省电策略）+ 读权限状态。
 * 试听铃声的原生 MediaPlayer 已随内置铃声一起退役
 * （2026-10-16 方案 A：铃声改由系统通知渠道设置决定）。
 *
 * 为什么跳渠道设置页不用 android_intent_plus？
 * 因为系统设置页（Settings$AppNotificationSettingsActivity 之类）不会在
 * PackageManager 里导出可解析的 Activity，`canResolveActivity()` 会误报 false，
 * 那个库「先探再跳」的逻辑就直接放弃了。这里直接 startActivity，不带探测。
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openChannelSettings" -> {
                        val channelId = call.argument<String>("channelId") ?: ""
                        result.success(openChannelSettings(channelId))
                    }
                    // 跳朝暮自己的「应用信息」页 —— 里面有「省电策略」那一项。
                    // 比直接跳系统的电池优化列表准得多，用户少找好几层。
                    "openAppDetails" -> {
                        result.success(openAppDetails())
                    }
                    // 跳各家的「省电策略 / 电池管理」专页。跳不进去返回 false。
                    "openPowerSaving" -> {
                        result.success(openPowerSaving())
                    }
                    "isIgnoringBatteryOptimization" -> {
                        result.success(isIgnoringBatteryOptimization())
                    }
                    // 查「自启动」开没开。返回 null = 这台 ROM 查不到，
                    // 由 Dart 那边按「未知」处理，让用户自己确认。
                    "isAutoStartEnabled" -> {
                        result.success(isAutoStartEnabled())
                    }
                    // App 的版本号，形如 "2.7.4+6"。
                    // 直接从 PackageManager 读，保证和装上的 APK 完全一致
                    // （写死在 Dart 里容易忘了改，踩过这个坑）。
                    "getVersion" -> {
                        result.success(getVersion())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 电池优化关了没。true = 已关（不限制），false = 还被系统优化。
     *
     * 冷启动引导要用它判断「省电策略」这一条过没过 —— 这是系统唯一
     * 公开可查的省电相关状态。
     */
    private fun isIgnoringBatteryOptimization(): Boolean {
        return try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            pm.isIgnoringBatteryOptimizations(packageName)
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 查「自启动」开没开。返回 true / false，**查不到返回 null**。
     *
     * 自启动是厂商私有权限，Android 没有标准 API。但小米 / OPPO / vivo 这类
     * ROM 把它的开关挂进了 AppOps（op 名 `android:auto_start` /
     * `android:auto_start_up`），用 AppOpsManager 就能读到真实状态。
     *
     * 读不到的情况一律返回 null：
     * - Android 10 以下（公开 SDK 从 API 29 才有 unsafeCheckOpNoThrow）
     * - 这台 ROM 没定义这个 op（传名字过去会抛 IllegalArgumentException）
     * - 读出来是 `MODE_DEFAULT`（说不准，很多 ROM 默认值不代表实际开关）
     * 交给用户自己确认，**绝不猜成 false 把用户卡在这一步**。
     *
     * ⚠️ 不能用 `AppOpsManager.getOpByName()` / `OP_NONE` —— 这两个在 AOSP 里是
     * `@hide`，公开 SDK（android.jar）里根本没有，编译直接报 Unresolved reference。
     * 只能用**按 op 名字符串查**的公开重载：
     * `unsafeCheckOpNoThrow(String op, int uid, String packageName)`（API 29 起）。
     */
    private fun isAutoStartEnabled(): Boolean? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val aom = getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager ?: return null
        val uid = Process.myUid()
        for (name in listOf("android:auto_start", "android:auto_start_up")) {
            try {
                when (aom.unsafeCheckOpNoThrow(name, uid, packageName)) {
                    AppOpsManager.MODE_ALLOWED -> return true
                    AppOpsManager.MODE_IGNORED, AppOpsManager.MODE_ERRORED -> return false
                    else -> {} // MODE_DEFAULT：说不准，试下一个 op 名
                }
            } catch (_: Exception) {
                // 这个 op 名在这台 ROM 上不认，试下一个
            }
        }
        return null
    }

    /**
     * 跳到「朝暮 → 通知 → 待办提醒 vN」这个渠道的设置页。
     *
     * 三级兜底，哪一级成功就返回：
     * 1. Android 8+ 的 `ACTION_CHANNEL_NOTIFICATION_SETTINGS` —— 精确落到某个渠道
     *    注意：这个 action 在部分 ROM 上会报 ActivityNotFound，所以必须 try 住
     * 2. `ACTION_APP_NOTIFICATION_SETTINGS` —— 落到朝暮的通知总页（渠道设置在里面一层）
     * 3. `ACTION_APPLICATION_DETAILS_SETTINGS` —— 落到应用详情页（最保底）
     *
     * 返回 true = 跳成功了（不代表用户改了什么）。
     */
    private fun openChannelSettings(channelId: String): Boolean {
        // 1. 精确跳到渠道
        if (channelId.isNotEmpty() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val i = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(i)
                return true
            } catch (_: Exception) {
                // 落到下一级
            }
        }

        // 2. 落到通知总页
        try {
            val i = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(i)
            return true
        } catch (_: Exception) {
            // 落到下一级
        }

        // 3. 最保底：应用详情页
        return try {
            val i = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(i)
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 跳到朝暮自己的「应用信息」页。
     *
     * 这一页里就有「省电策略」/「电池」那一项 —— 用户从这儿点进去，
     * 比先跳系统电池优化总列表再找应用省事得多。
     *
     * 用户原话：「提醒跳转到的切换省电策略的界面不对，要切换到应用设置里
     * 朝暮应用信息含省电策略的界面才对」。
     */
    private fun openAppDetails(): Boolean {
        return try {
            val i = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(i)
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 跳各家的「省电策略 / 电池管理」专页。逐个组件名试，跳通就返回 true。
     *
     * 这些都是厂商私有 Activity，不在标准 API 里，只能拼名字硬跳，
     * 每台机型能跳到的可能不一样，跳不到就 false，由 Dart 那边降级。
     */
    private fun openPowerSaving(): Boolean {
        val candidates = listOf(
            // 小米 / 红米：省电策略
            "com.miui.powerkeeper/.ui.HiddenAppsConfigActivity",
            "com.miui.securitycenter/com.miui.powercenter.PowerSettings",
            // 华为 / 荣耀：电池管理
            "com.huawei.systemmanager/.power.ui.HwPowerManagerActivity",
            // OPPO / 一加 / realme：耗电管理
            "com.coloros.oppoguardelf/com.coloros.powermanager.fuelgaue.PowerUsageModelActivity",
            // vivo / iQOO：后台高耗电
            "com.vivo.abe/.ui.BackgroundManagerActivity",
            // 三星
            "com.samsung.android.lool/com.samsung.android.sm.battery.ui.BatteryActivity",
        )
        for (comp in candidates) {
            try {
                val parts = comp.split("/")
                if (parts.size != 2) continue
                val cls = if (parts[1].startsWith(".")) parts[0] + parts[1] else parts[1]
                val i = Intent().apply {
                    setClassName(parts[0], cls)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(i)
                return true
            } catch (_: Exception) {
                // 试下一个
            }
        }
        return false
    }

    /**
     * 读 App 版本号，返回 "2.7.4+6" 这种形式。
     *
     * versionCode 在 Android 9+ 要用 longVersionCode 才拿得全。
     */
    private fun getVersion(): String {
        return try {
            val info = packageManager.getPackageInfo(packageName, 0)
            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            "${info.versionName}+$code"
        } catch (_: Exception) {
            ""
        }
    }

    companion object {
        private const val CHANNEL = "com.xiayitian.chaomu/ringtone"
    }
}
