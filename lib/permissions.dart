/// 朝暮 · 权限与系统设置跳转
///
/// 设计原则：
/// 1. **只做能确认的事**。安卓标准的入口（通知 / 电池优化 / 精确闹钟 /
///    全屏弹出）用官方 API；国产厂商私有的（自启动 / 后台弹出 / 省电策略）
///    没有标准入口，只能拼 Activity 名硬跳。
/// 2. **跳之前先探**。用 `AndroidIntent.canResolveActivity` 确认目标 Activity
///    真实存在，探不到就不跳，避免抛 ActivityNotFoundException 把 App 搞崩。
/// 3. **探不到就退化成文字指引**，让用户照着系统设置里的路径自己点。
library;

import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';

/// 一条待检查的权限
class PermItem {
  const PermItem({
    required this.id,
    required this.title,
    required this.why,
    required this.manualPath,
    this.canJump = false,
    this.jumpNote,
  });

  final String id;
  final String title;

  /// 为什么需要它 —— 不批会怎样
  final String why;

  /// 跳不进去时，让用户照着点的路径
  final String manualPath;

  /// 能不能一键跳系统页
  final bool canJump;

  /// 跳转后要看到什么
  final String? jumpNote;
}

/// 权限工具箱
class Permissions {
  Permissions._();

  static bool get isAndroid => Platform.isAndroid;

  /// 探一个 Activity 在不在。探不到返回 false，绝不硬跳。
  static Future<bool> _canJump({
    String? action,
    String? componentName,
  }) async {
    if (!isAndroid) return false;
    if (action == null && componentName == null) return false;
    try {
      final AndroidIntent intent = AndroidIntent(
        action: action,
        componentName: componentName,
      );
      final bool? ok = await intent.canResolveActivity();
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳一个 Activity。跳失败返回 false（不抛异常）。
  static Future<bool> _launch({
    String? action,
    String? componentName,
    Map<String, dynamic>? arguments,
  }) async {
    if (!isAndroid) return false;
    if (action == null && componentName == null) return false;
    try {
      // 先探一下，探不到直接放弃，避免崩
      final bool ok = await _canJump(action: action, componentName: componentName);
      if (!ok) return false;

      final AndroidIntent intent = AndroidIntent(
        action: action,
        componentName: componentName,
        arguments: arguments,
      );
      await intent.launch();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 跳到「本应用详情页」（几乎所有厂商都支持，最稳的兜底）
  static Future<bool> openAppDetails() => _launch(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        arguments: <String, dynamic>{'package': _pkg},
      );

  /// 跳到「通知设置」
  static Future<bool> openNotificationSettings() => _launch(
        action: 'android.settings.APP_NOTIFICATION_SETTINGS',
        arguments: <String, dynamic>{
          'android.provider.extra.APP_PACKAGE': _pkg,
        },
      );

  /// 跳到「电池优化」列表（系统级，和你说的"省电策略"是两回事）
  static Future<bool> openBatteryOptimization() => _launch(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        arguments: <String, dynamic>{'package': _pkg},
      );

  /// 跳到「电池优化」总列表（上面那个跳不进去时的备选）
  static Future<bool> openBatteryOptimizationList() => _launch(
        action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
      );

  /// 跳到「精确闹钟」设置（Android 12+）
  static Future<bool> openExactAlarm() => _launch(
        action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
        arguments: <String, dynamic>{'package': _pkg},
      );

  /// 跳到「勿扰 / 通知策略」访问授权
  static Future<bool> openNotificationPolicy() => _launch(
        action: 'android.settings.NOTIFICATION_POLICY_ACCESS_SETTINGS',
      );

  // ---------------- 厂商私有页（可能不存在，跳前会探） ----------------

  /// 尝试跳「自启动」管理页。国产系统各家不同，逐个试。
  /// 返回 true = 跳成功了。
  static Future<String?> openAutoStart() async {
    // 品牌 -> (组件名, 页面上该看到什么)
    final List<(String, String)> candidates = <(String, String)>[
      // 小米 / 红米
      ('com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity', '自启动管理'),
      // 华为 / 荣耀
      ('com.huawei.systemmanager/com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity', '应用启动管理'),
      ('com.huawei.systemmanager/.appcontrol.activity.StartupAppControlActivity', '启动管理'),
      // OPPO / 一加 / realme
      ('com.coloros.safecenter/com.coloros.safecenter.permission.startup.StartupAppListActivity', '自启动管理'),
      ('com.coloros.safecenter/.startupapp.StartupAppListActivity', '自启动管理'),
      // vivo / iQOO
      ('com.vivo.permissionmanager/.activity.BgStartUpManagerActivity', '自启动管理'),
      ('com.iqoo.secure/.safeguard.PurviewTabActivity', '自启动管理'),
      // 三星
      ('com.samsung.android.lool/com.samsung.android.sm.ui.battery.BatteryActivity', '电池'),
      // 魅族
      ('com.meizu.safe/.permission.SmartBGActivity', '后台管理'),
      // 联想
      ('com.lenovo.security/.cleanupmanager.autorun.AutoRunActivity', '自启动'),
    ];

    for (final (String comp, String label) in candidates) {
      final bool ok = await _launch(componentName: comp);
      if (ok) return label;
    }
    return null;
  }

  /// 尝试跳「后台弹出界面 / 悬浮窗」管理页
  static Future<String?> openBackgroundPopup() async {
    final List<(String, String)> candidates = <(String, String)>[
      // 小米：权限管理
      ('com.miui.securitycenter/com.miui.permcenter.permissions.PermissionsEditorActivity', '权限管理'),
      ('com.miui.securitycenter/com.miui.permcenter.permissions.AppPermissionsEditorActivity', '权限管理'),
      // 华为：权限管理
      ('com.huawei.systemmanager/.appcontrol.activity.StartupAppControlActivity', '启动管理'),
      // OPPO：权限管理
      ('com.coloros.safecenter/com.coloros.safecenter.permission.PermissionManagerActivity', '权限管理'),
      // vivo：权限管理
      ('com.vivo.permissionmanager/.activity.PurviewTabActivity', '权限管理'),
    ];
    for (final (String comp, String label) in candidates) {
      final bool ok = await _launch(componentName: comp);
      if (ok) return label;
    }
    return null;
  }

  /// 尝试跳「省电策略 / 电池管理」页
  static Future<String?> openPowerSaving() async {
    final List<(String, String)> candidates = <(String, String)>[
      // 小米：省电策略
      ('com.miui.powerkeeper/.ui.HiddenAppsConfigActivity', '省电策略'),
      ('com.miui.securitycenter/com.miui.powercenter.PowerSettings', '电池与性能'),
      // 华为：应用启动管理 / 电池优化
      ('com.huawei.systemmanager/.power.ui.HwPowerManagerActivity', '电池管理'),
      // OPPO：应用速冻
      ('com.coloros.oppoguardelf/com.coloros.powermanager.fuelgaue.PowerUsageModelActivity', '耗电管理'),
      // vivo：后台高耗电
      ('com.vivo.abe/.ui.BackgroundManagerActivity', '后台管理'),
      // 三星
      ('com.samsung.android.lool/com.samsung.android.sm.battery.ui.BatteryActivity', '电池'),
    ];
    for (final (String comp, String label) in candidates) {
      final bool ok = await _launch(componentName: comp);
      if (ok) return label;
    }
    return null;
  }

  /// 本应用包名
  static const String _pkg = 'com.xiayitian.chaomu';

  /// 全部要引导的项。settings 页照着这个渲染。
  static List<PermItem> allItems() => const <PermItem>[
        PermItem(
          id: 'notify',
          title: '允许通知',
          why: '不批的话，提醒到点系统直接把它丢掉，什么都不显示。',
          manualPath: '设置 → 应用管理 → 朝暮 → 通知 → 允许通知（含横幅）',
          canJump: true,
          jumpNote: '跳到系统页后，把「允许通知」打开，并把「横幅」选上。',
        ),
        PermItem(
          id: 'channel',
          title: '通知权限（声音 / 震动 / 悬浮）',
          why: '开关声音、震动、悬浮通知都在这一页。选「本地铃声」也在这里挑。',
          manualPath: '设置 → 应用管理 → 朝暮 → 通知 → 待办提醒',
          canJump: true,
          jumpNote: '跳到「待办提醒」这一页，声音 / 震动 / 悬浮通知都在里面。',
        ),
        PermItem(
          id: 'exact',
          title: '闹钟和提醒（精确闹钟）',
          why: '不批只能用「大致时间」的闹钟，系统会攒着凑一批再发，晚几十分钟很正常 —— 这就是提醒像没响的原因。',
          manualPath: '设置 → 应用管理 → 朝暮 → 闹钟和提醒 → 允许',
          canJump: true,
          jumpNote: '跳到系统页后，把「闹钟和提醒」打开。',
        ),
        PermItem(
          id: 'fullscreen',
          title: '后台弹出界面',
          why: '不批的话，别的 App 在前台时全屏闹钟弹不出来，只能静默躺在通知栏。',
          manualPath: '设置 → 应用管理 → 朝暮 → 后台弹出界面 → 允许',
          canJump: true,
          jumpNote: '跳到系统页后，把「后台弹出界面」打开。',
        ),
        PermItem(
          id: 'battery',
          title: '省电策略 / 电池优化',
          why: '不设无限制的话，系统会在后台把朝暮冻住，到点也不唤醒。',
          manualPath: '设置 → 应用管理 → 朝暮 → 省电策略 → 无限制',
          canJump: true,
          jumpNote: '跳到「应用信息」页后，点「省电策略」，选「无限制」。这一页里也有「自启动」。',
        ),
        PermItem(
          id: 'autostart',
          title: '自启动',
          why: '不打开的话，手机重启后提醒不会自动重排，重装或重启后全丢。',
          manualPath: '设置 → 应用管理 → 朝暮 → 自启动 → 允许',
          canJump: true,
          jumpNote: '跳到「应用信息」页后，把「自启动」打开。有的机型会直接跳到自启动列表。',
        ),
        PermItem(
          id: 'lockscreen',
          title: '锁屏显示通知',
          why: '不设置的话，锁屏时通知只显示「已隐藏内容」，等于没提醒。',
          manualPath: '设置 → 通知 → 锁屏通知 → 显示所有通知内容',
          canJump: false,
        ),
        PermItem(
          id: 'dnd',
          title: '允许打扰（免打扰例外）',
          why: '开了免打扰时，只有允许打扰的应用才能弹出提醒。',
          manualPath: '设置 → 声音与振动 → 免打扰 → 允许打扰 → 朝暮 打开',
          canJump: true,
          jumpNote: '跳到系统页后，找到「允许打扰」里的朝暮，打开。',
        ),
        PermItem(
          id: 'locktask',
          title: '最近任务里加锁',
          why: '一键清理会把朝暮干掉，干掉之后提醒就没了。',
          manualPath: '按「最近任务」键 → 找到朝暮卡片 → 点小锁 / 下拉锁定',
          canJump: false,
        ),
      ];
}
