import 'dart:io';

// 用别名导入：通知库里的 Priority / Importance 和朝暮自己的四象限
// Priority 同名，不加前缀会直接编译冲突。
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'app_state.dart';
import 'models.dart';
import 'reminder_windows.dart';

/// 提醒到点时怎么弹。存的是字符串，方便写进 json。
class RemindStyle {
  RemindStyle._();

  static const String banner = 'banner'; // 顶部横幅 + 响铃
  static const String fullScreen = 'fullscreen'; // 全屏闹钟式弹卡

  static const List<String> all = <String>[banner, fullScreen];
  static const List<String> display = <String>['顶部横幅', '全屏闹钟'];

  static String displayOf(String v) {
    if (v == fullScreen) return '全屏闹钟';
    return '顶部横幅';
  }
}

/// 本地通知：负责把待办提醒排进系统闹钟
///
/// 关键点（都是踩过的坑）：
/// 1. 必须用**精确闹钟**（exactAllowWhileIdle）。用 inexact 系统会攒着凑一批发，
///    晚几十分钟都正常，表现出来就是"根本不提醒"。
/// 2. Android 8+ 的通知渠道一旦建好，重要性/声音/震动就固定了，改代码没用。
///    所以渠道 id 带了版本号（v2），以后要改行为就升到 v3。
/// 3. 「在其他 App 前台时也能弹出来」靠的是 fullScreenIntent，不是普通通知。
///    需要 USE_FULL_SCREEN_INTENT 权限（Android 14+ 用户可关，所以要做降级）。
class Notifier {
  Notifier._();

  static final Notifier I = Notifier._();

  final fln.FlutterLocalNotificationsPlugin _plugin = fln.FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _tzReady = false;

  /// 试听用的原生通道（MainActivity 里实现，MediaPlayer 播 res/raw）。
  /// 和通知通道完全分开 —— 试听不该依赖通知渠道。
  static const MethodChannel _ringChannel =
      MethodChannel('com.xiayitian.chaomu/ringtone');

  /// 排程失败的原因，给设置页做诊断用。空字符串 = 没失败过。
  String lastScheduleError = '';

  /// 时区名，初始化后可用（诊断展示）
  String get tzName => _tzReady ? tz.local.name : '(未初始化)';

  /// 当前本地时区与 UTC 的偏移小时数（诊断展示）
  int get tzOffsetHours =>
      _tzReady ? tz.local.currentTimeZone.offset ~/ Duration.millisecondsPerHour : 0;

  /// 渠道 id 带版本：改行为时升版本，绕开系统缓存的老渠道设置
  ///
  /// 版本历史：
  /// 1. v2：声音用了 RawResourceAndroidNotificationSound，但指向不存在的 res/raw 资源 → 通知发不出去
  /// 2. v3：改用 UriAndroidNotificationSound，音频流却设成 alarm → 静默无声
  /// 3. v4：音频流改回 notification、渠道自带 sound，但声音仍是系统 URI → MIUI 上还是无铃声
  /// 4. v5：改用 app 内嵌铃声，彻底不依赖系统通知音
  /// 5. v6：内置四款铃声（风铃/木琴/钟声/古琴），渠道默认风铃，单条通知按用户选择覆盖
  /// 6. v7：v6 的 wav 是 8-bit PCM，Android MediaPlayer 加载失败 → 选内嵌铃声直接报错。
  ///        改成 16-bit PCM 后升渠道，让系统重建（老渠道里存着坏的声音引用）
  /// 7. v8：⚠️ **渠道不再自带 sound**。v7 及以前渠道把音色钉死成风铃，
  ///        而 Android 渠道声音是「一次设定永久固化」，优先级**高于**单条通知的 sound
  ///        —— 所以用户选木琴，响的永远是风铃。v8 让渠道只说「有声音」，
  ///        具体哪一款由每次 show() 时的 AndroidNotificationDetails.sound 决定。
  static const String _channelId = 'chaomu_remind_v8';
  /// 渠道名。**不带版本号** —— 用户在系统设置里看到的就是这个，
  /// 带 v7/v8 会让人困惑。内部靠 [_channelId] 区分版本即可。
  /// （同名渠道共存的老问题由「先删后建」解决，见 [_ensureChannel]）
  static const String _channelName = '待办提醒';
  static const String _channelDesc = '朝暮的待办与日程提醒（横幅 / 全屏闹钟）';

  /// 点通知时想跳到哪条待办。UI 那边设置这个回调。
  void Function(String todoId)? onOpenTodo;

  /// 冷启动时点开的待办 id（App 还没起来就点了通知）
  String? pendingTodoId;

  bool get available => Platform.isAndroid || Platform.isIOS || Platform.isWindows;

  /// Windows 专属调度器。Android / iOS 上是 null，相关分支不会进。
  ///
  /// 为什么不和 Android 共用 zonedSchedule：见 reminder_windows.dart 顶部注释。
  WindowsReminder? _win;

  /// 设置页要显示「Windows 调度器排了几条 / 是不是活着」
  WindowsReminder? get windowsReminder => _win;

  Future<void> init() async {
    if (_ready || !available) return;
    try {
      tzdata.initializeTimeZones();
      // 关键：只 initializeTimeZones() 不会设置本地时区！
      // tz.local 默认是 UTC，排 15:00 的提醒会按 UTC 15:00 触发，
      // 北京时间就是 23:00 —— 表现就是「到点完全没动静」。
      _setLocalZone();
      _tzReady = true;

      const fln.AndroidInitializationSettings android =
          fln.AndroidInitializationSettings('@mipmap/ic_launcher');
      const fln.DarwinInitializationSettings darwin = fln.DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      // Windows：appUserModelId 会写进
      // HKCU\Software\Classes\AppUserModelId\<aumid>，
      // 未打包成 MSIX 的 exe 靠这条注册表才能弹 Toast。
      // guid 是点通知回传回调用的标识，只要求全局唯一、不要随便改。
      const fln.WindowsInitializationSettings windows =
          fln.WindowsInitializationSettings(
        appName: '朝暮',
        appUserModelId: 'com.xiayitian.chaomu',
        guid: '3f2504e0-4f89-41d3-9a0c-0305e82c3301',
      );
      await _plugin.initialize(
        const fln.InitializationSettings(
          android: android,
          iOS: darwin,
          windows: windows,
        ),
        onDidReceiveNotificationResponse: (fln.NotificationResponse r) {
          _handleTap(r.payload);
        },
      );
      _ready = true;

      // Windows：插件的排程不可靠，改用它自己的定时比对（15 秒一拍）。
      // 注意别写成 `_win ??= X()..start()` —— cascade 和 ??= 的组合在
      // Dart 里解析结果不是"在新建对象上调用 start"，实测定时器根本没起来。
      if (Platform.isWindows) {
        _win ??= WindowsReminder(_showWinToast);
        _win!.start();
      }

      // 冷启动：App 是被通知点开的
      try {
        final fln.NotificationAppLaunchDetails? d =
            await _plugin.getNotificationAppLaunchDetails();
        if (d != null && d.didNotificationLaunchApp) {
          _handleTap(d.notificationResponse?.payload);
        }
      } catch (_) {}

      // 提前把渠道建出来，保证重要性/声音/震动是我们要的那套
      await _ensureChannel();
    } catch (_) {
      _ready = false;
    }
  }

  /// 把 tz.local 设成设备当前时区。
  ///
  /// 不引新插件，直接用系统给的 UTC 偏移反查时区名。
  /// 查不到就落到 Asia/Shanghai（用户在中国，固定 +8 不会错）。
  void _setLocalZone() {
    try {
      final int offMin = DateTime.now().timeZoneOffset.inMinutes;
      // 偏移(分钟) -> 常见时区名。命中不了的按整点偏移兜底。
      const Map<int, String> byOffset = <int, String>{
        480: 'Asia/Shanghai', // +8 中国标准时间
        540: 'Asia/Tokyo', // +9
        420: 'Asia/Bangkok', // +7
        330: 'Asia/Kolkata', // +5:30
        0: 'UTC',
        -300: 'America/New_York',
        -480: 'America/Los_Angeles',
        60: 'Europe/Paris',
        -60: 'Europe/London',
        -180: 'America/Sao_Paulo',
        600: 'Australia/Brisbane',
        720: 'Pacific/Auckland',
      };
      final String? name = byOffset[offMin];
      if (name != null) {
        tz.setLocalLocation(tz.getLocation(name));
        return;
      }
      // 偏移不是常见值：用 Etc/GMT±N 兜底（注意 Etc/GMT 的符号是反的）
      final int hours = offMin ~/ 60;
      final String etc = hours >= 0 ? 'Etc/GMT-$hours' : 'Etc/GMT+${-hours}';
      tz.setLocalLocation(tz.getLocation(etc));
    } catch (_) {
      // 兜底：中国用户固定 +8
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
      } catch (_) {
        // 连这个都失败就保持 UTC，但会记在 lastScheduleError 里
      }
    }
  }

  void _handleTap(String? payload) {
    final String? id = (payload == null || payload.isEmpty) ? null : payload;
    if (id == null) return;
    final void Function(String)? cb = onOpenTodo;
    if (cb != null) {
      cb(id);
    } else {
      // UI 还没挂上，先存着
      pendingTodoId = id;
    }
  }

  /// 手动建通知渠道。不建的话插件会用默认参数建，重要性可能不是 max。
  ///
  /// 顺序很重要：**先删旧渠道，再建新渠道**。
  /// 反过来的话，MIUI 上会出现多个同名渠道，系统可能把通知路由到旧的那个
  /// （旧渠道是静音的），表现出来就是"什么都没有"。
  Future<void> _ensureChannel() async {
    if (!Platform.isAndroid) return;
    try {
      final fln.AndroidFlutterLocalNotificationsPlugin? a = _plugin
          .resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();
      if (a == null) return;

      // 1. 先清理所有历史渠道
      for (final String old in <String>[
        'chaomu_remind',
        'chaomu_remind_v2',
        'chaomu_remind_v3',
        'chaomu_remind_v4',
        'chaomu_remind_v5',
        'chaomu_remind_v6',
        'chaomu_remind_v7',
      ]) {
        try {
          await a.deleteNotificationChannel(old);
        } catch (_) {}
      }

      // 2. 再建当前渠道。渠道名不带版本号（用户看到的是「待办提醒」），
      //    版本只体现在 [_channelId] 上。
      //    ⚠️ **这里故意不给 sound**：渠道一旦带上 sound，Android 就把它固化成
      //    「这个渠道的音色」，且优先级高于单条通知的 sound —— 之后用户在 app 里
      //    换铃声（风铃→木琴）完全没用，响的永远是渠道里那个。所以渠道只声明
      //    「有声音 + 有震动」，具体哪一款由发通知时 [_details] 里的 sound 决定。
      await a.createNotificationChannel(
        fln.AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: fln.Importance.max,
          // 渠道层允许出声；真正响不响、响哪款，看每条通知自己的设置
          playSound: true,
          enableVibration: true,
          showBadge: true,
          // 穿透「免打扰」。漏了这个，开了 DND 的机型就是一声不响
          bypassDnd: true,
          // 通知音走 notification 音频流。用 alarm 流会静默无声且不报错。
          audioAttributesUsage: fln.AudioAttributesUsage.notification,
        ),
      );
    } catch (_) {}
  }

  /// 申请通知权限（Android 13+ / iOS）
  Future<bool> requestPermission() async {
    if (!available) return false;
    await init();
    if (!_ready) return false;
    try {
      if (Platform.isAndroid) {
        final fln.AndroidFlutterLocalNotificationsPlugin? a = _plugin
            .resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();
        final bool? ok = await a?.requestNotificationsPermission();
        return ok ?? false;
      }
      final fln.IOSFlutterLocalNotificationsPlugin? i =
          _plugin.resolvePlatformSpecificImplementation<fln.IOSFlutterLocalNotificationsPlugin>();
      final bool? ok = await i?.requestPermissions(alert: true, badge: true, sound: true);
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 已给的通知权限有没有批下来
  Future<bool> hasPermission() async {
    if (!available) return false;
    await init();
    if (!_ready) return false;
    // Windows 没有「运行时申请通知权限」这一说，弹不弹只受系统
    // 「通知和操作」总开关控制，代码里查不到也不该拦用户
    if (Platform.isWindows) return true;
    try {
      if (Platform.isAndroid) {
        final fln.AndroidFlutterLocalNotificationsPlugin? a = _plugin
            .resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();
        return await a?.areNotificationsEnabled() ?? false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 精确闹钟权限（Android 12+ 要单独批，不批就只能用不准的闹钟）
  /// 返回 null = 系统低于 12 或问不出来（按"可以"处理）
  Future<bool?> canScheduleExact() async {
    if (!Platform.isAndroid) return null;
    await init();
    if (!_ready) return null;
    try {
      final fln.AndroidFlutterLocalNotificationsPlugin? a = _plugin
          .resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();
      return await a?.canScheduleExactNotifications();
    } catch (_) {
      return null;
    }
  }

  /// 跳去系统页让用户批准"闹钟和提醒"（精确闹钟）权限
  Future<void> requestExactAlarm() async {
    if (!Platform.isAndroid) return;
    await init();
    if (!_ready) return;
    try {
      final fln.AndroidFlutterLocalNotificationsPlugin? a = _plugin
          .resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();
      await a?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  /// 「自启动」开没开。
  ///
  /// 返回 true / false = 查到了；**返回 null = 这台 ROM 查不到**。
  /// 自启动是厂商私有权限，没有标准 API —— 只有部分 ROM 把它挂在 AppOps 里
  /// （op 名 `android:auto_start`）才读得到。查不到时按「未知」处理，
  /// 让用户自己确认，绝不猜成 false 卡住用户。
  Future<bool?> isAutoStartEnabled() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _ringChannel.invokeMethod<bool>('isAutoStartEnabled');
    } catch (_) {
      return null;
    }
  }

  /// 电池优化有没有关掉（false = 没关，后台会被冻住）
  ///
  /// 用原生 PowerManager.isIgnoringBatteryOptimizations 查，这是系统唯一
  /// 公开可查的「省电策略」状态。查不到返回 null（按未知处理）。
  Future<bool?> isIgnoringBatteryOptimization() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _ringChannel.invokeMethod<bool>('isIgnoringBatteryOptimization');
    } catch (_) {
      return null;
    }
  }

  /// 「后台弹出界面」权限（Android 14+ 官方入口）。
  /// 没有它，其他 App 在前台时全屏闹钟弹不出来，只会静默躺在通知栏。
  ///
  /// 注意：这个库只提供了「请求」，没有提供「检测当前是否已批准」的接口，
  /// 所以这里只做跳转，状态交给用户在系统页自己看。
  Future<bool?> requestFullScreenIntent() async {
    if (!Platform.isAndroid) return null;
    await init();
    if (!_ready) return null;
    try {
      final fln.AndroidFlutterLocalNotificationsPlugin? a = _plugin
          .resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();
      return await a?.requestFullScreenIntentPermission();
    } catch (_) {
      return null;
    }
  }

  static int _idOf(String todoId) {
    // 用 id 的 hash 做通知 id，同一条待办改时间会覆盖掉旧的
    int h = 0;
    for (final int c in todoId.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  static String _2(int v) => v < 10 ? '0$v' : '$v';

  tz.TZDateTime? _at(DateTime d) {
    if (!_tzReady) return null;
    try {
      return tz.TZDateTime.from(d, tz.local);
    } catch (_) {
      return null;
    }
  }

  /// 拼一套通知参数。fullScreen = true 时到点直接全屏弹卡。
  /// title / body 只用于展开视图（bigText），不传也能跑。
  ///
  /// [soundOn] = 总的「要不要出声」开关（对应设置里的「默认打开铃声」）。
  /// 传 false 就是静默推送：横幅照弹、震动照震，但不出声。
  ///
  /// 注意：**震动和铃声是两回事**，不要绑在一起。
  /// `ring == false`（选了「不响铃」）只该关声音，震动照留 ——
  /// 之前 `enableVibration: ring` 把两个绑一起，用户选「不响铃」会连震动一起没。
  fln.NotificationDetails _details({
    required bool fullScreen,
    bool soundOn = true,
    String title = '',
    String body = '',
  }) {
    // 出声 = 设置里的「默认打开铃声」开着。响哪首歌由系统通知渠道设置决定
    // （2026-10-16 起铃声全部交给系统渠道：在渠道声音里挑本地/在线铃声），
    // 这里不再指定 sound，playSound: true 就是「用渠道里选的那首」。
    final bool ring = soundOn;
    return fln.NotificationDetails(
      android: fln.AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: fln.Importance.max,
        // 注意：fln.Priority 是通知优先级，不是朝暮自己的四象限 Priority
        priority: fln.Priority.max,
        playSound: ring,
        // 铃声不在这指定 —— 用系统渠道设置里选的那首（方案 A，2026-10-16）。
        // 渠道 v8 本来就没写死 sound，不传 sound 就是渠道配置的声音。
        // 震动独立于铃声：不出声也要震
        enableVibration: true,
        // 锁屏也显示内容（否则锁屏只显示"已隐藏内容"，等于没提醒）
        visibility: fln.NotificationVisibility.public,
        // 归类成闹钟：部分机型这个类目能穿透免打扰
        category: fln.AndroidNotificationCategory.alarm,
        // 声音走「通知」音频流。不要用 alarm ——
        // 系统会按闹钟流去解析「通知音 URI」，MIUI 上匹配失败就是静默无声。
        audioAttributesUsage: fln.AudioAttributesUsage.notification,
        // 单个通知也声明穿 DND（渠道那边也设了，双重保险）
        channelBypassDnd: true,
        // 常驻直到用户处理
        ongoing: fullScreen,
        autoCancel: !fullScreen,
        // 悬浮横幅（heads-up）。没有它就只在通知栏留一行。
        fullScreenIntent: fullScreen,
        // 展开视图多几行。bigText 是必填位置参数（19.5.0 起）
        styleInformation: fln.BigTextStyleInformation(
          body.isEmpty ? '朝暮提醒' : body,
          contentTitle: title.isEmpty ? null : title,
          summaryText: null,
        ),
        ticker: '朝暮提醒',
      ),
      iOS: fln.DarwinNotificationDetails(
        presentAlert: true,
        presentSound: ring,
        presentBanner: true,
        // iOS 锁屏也显示
        presentBadge: true,
        interruptionLevel: fln.InterruptionLevel.timeSensitive,
      ),
      windows: _winDetails(title: title, body: body),
    );
  }

  /// Windows 通知参数。
  ///
  /// 故意不设 scenario：
  /// - `alarm` 会让系统循环播放闹钟音，Windows 上很吵（用户选的是系统默认提示音）；
  /// - `reminder` 必须配合后台任务 action 才生效，单独设了是无效属性。
  ///
  /// 也**不设 subtitle**：插件渲染时 title / body / subtitle 是分开的三块，
  /// 把 body 再塞进 subtitle 会让同一句话显示两遍（2026-10-18 实测过）。
  fln.WindowsNotificationDetails _winDetails({
    required String title,
    required String body,
  }) =>
      fln.WindowsNotificationDetails(
        // 默认几秒就收进操作中心，容易错过；long 会多停一会儿
        duration: fln.WindowsNotificationDuration.long,
      );

  /// Windows 到点弹一条，由 [WindowsReminder] 的定时器回调进来。
  Future<void> _showWinToast(String todoId, String title, String body) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        // 补弹的汇总通知没有 todoId，用固定 id 避免每次叠一条
        todoId.isEmpty ? 999999 : _idOf(todoId),
        title,
        body,
        fln.NotificationDetails(windows: _winDetails(title: title, body: body)),
        payload: todoId,
      );
      // 打日志便于排查「到点没反应」：能看到调度器确实触发了，
      // 剩下的问题就只在系统通知开关上
      // ignore: avoid_print
      print('[win-toast] $title | 剩 ${_win?.count ?? 0} 条待弹');
    } catch (e) {
      lastScheduleError = 'Windows 弹窗失败：$e（多半是系统的通知权限被关了）';
    }
  }

  /// 给一条待办排提醒。remind == null 或者铃声/开关关掉则取消。
  ///
  /// [aheadMinutes] 提前多少分钟提醒（0 = 到点提醒）
  /// [style] 横幅还是全屏（RemindStyle.*）
  /// [soundOn] 设置里的「默认打开铃声」。false = 只弹横幅 + 震动，不出声
  Future<void> scheduleFor(
    Todo t, {
    bool soundOn = true,
    int aheadMinutes = 0,
    String style = RemindStyle.banner,
  }) async {
    /// 记诊断信息。info 类（正常跳过）不覆盖已有错误，错误类才覆盖。
    void note(String msg, {bool isError = false}) {
      if (msg.isEmpty) return;
      if (isError) {
        lastScheduleError = msg;
      } else if (lastScheduleError.isEmpty) {
        lastScheduleError = msg;
      }
    }

    if (!available) {
      note('当前平台不支持本地通知', isError: true);
      return;
    }
    await init();
    if (!_ready) {
      note('通知插件初始化失败（看 logcat 有没有 initialize 报错）', isError: true);
      return;
    }

    final int id = _idOf(t.id);
    await cancelFor(t);

    if (t.done) {
      note('这条已勾选完成，不排提醒');
      return;
    }

    // 没设提醒时间，但有截止时刻 -> 用截止时刻。
    // 用户明确点过「不提醒」（remindOff）就不走这条兜底，否则那条待办还是会响。
    DateTime? when = t.remind;
    if (!t.remindOff && when == null && t.due != null && t.dueHasTime) when = t.due;
    if (when == null) {
      note(t.remindOff
          ? '这条设了「不提醒」'
          : '这条没填「提醒时间」，也没填带时刻的「截止时间」');
      return;
    }

    // 提前量：把提醒时刻往前挪
    if (aheadMinutes > 0) when = when.subtract(Duration(minutes: aheadMinutes));

    final String body = t.note.trim().isEmpty ? '朝暮提醒' : t.note.trim();

    if (!when.isAfter(DateTime.now())) {
      // Windows：过去 12 小时内的算「关机 / 休眠时错过的」，先收起来，
      // 由 rescheduleAll 末尾统一汇总成一条弹；再早的不提了，弹了也没意义。
      if (Platform.isWindows &&
          DateTime.now().difference(when) <= const Duration(hours: 12)) {
        _win?.putMissed(
          todoId: t.id,
          title: t.title,
          body: body,
          when: when,
        );
      }
      note(
        '提醒时刻 ${when.year}-${_2(when.month)}-${_2(when.day)} '
        '${_2(when.hour)}:${_2(when.minute)} 已经过去了，没排',
      );
      return;
    }

    // Windows：不进系统排程，交给内部调度器（原因见 reminder_windows.dart）
    if (Platform.isWindows) {
      _win?.put(todoId: t.id, title: t.title, body: body, when: when);
      note('Windows：已排进托盘调度器（当前 ${_win?.count ?? 0} 条）');
      return;
    }

    final tz.TZDateTime? whenTz = _at(when);
    if (whenTz == null) {
      note('时区没初始化成功（tz.local 不可用），排不了', isError: true);
      return;
    }

    // 先按精确闹钟排；没权限会抛异常，降级成不精确的（晚到总比不响好）
    fln.AndroidScheduleMode mode = fln.AndroidScheduleMode.exactAllowWhileIdle;
    final bool? exactOk = await canScheduleExact();
    if (exactOk == false) {
      mode = fln.AndroidScheduleMode.inexactAllowWhileIdle;
    }

    try {
      await _plugin.zonedSchedule(
        id,
        t.title,
        body,
        whenTz,
        _details(
          fullScreen: style == RemindStyle.fullScreen,
          soundOn: soundOn,
          title: t.title,
          body: body,
        ),
        androidScheduleMode: mode,
        payload: t.id,
        matchDateTimeComponents: null,
      );
      if (exactOk == false) {
        note('排上了（不精确模式：没有「闹钟和提醒」权限，可能晚几分钟到几十分钟）');
      }
      return;
    } catch (e) {
      // 精确排不上，退一步用不精确的
      note('精确排程失败，改用不精确模式：$e', isError: true);
    }

    try {
      await _plugin.zonedSchedule(
        id,
        t.title,
        body,
        whenTz,
        _details(
          fullScreen: style == RemindStyle.fullScreen,
          soundOn: soundOn,
          title: t.title,
          body: body,
        ),
        androidScheduleMode: fln.AndroidScheduleMode.inexactAllowWhileIdle,
        payload: t.id,
      );
      note('精确排程失败，已降级成不精确模式（可能晚到）', isError: true);
    } catch (e) {
      note('排程彻底失败：$e', isError: true);
    }
  }

  /// 马上弹一条，用来验证通知到底通不通
  Future<bool> showNow({bool soundOn = true}) async {
    lastScheduleError = '';
    if (!available) {
      lastScheduleError = '当前平台不支持本地通知';
      return false;
    }
    await init();
    if (!_ready) {
      lastScheduleError = '通知插件初始化失败（_ready=false，看 logcat 的 initialize 报错）';
      return false;
    }
    try {
      await _plugin.show(
        999999,
        '朝暮 · 测试提醒',
        '看到这条并且有声音，说明通知是通的。',
        _details(
          fullScreen: false,
          soundOn: soundOn,
          title: '朝暮 · 测试提醒',
          body: '看到这条并且有声音，说明通知是通的。',
        ),
        payload: '',
      );
      return true;
    } catch (e) {
      lastScheduleError = '测试提醒发送失败：$e';
      return false;
    }
  }

  /// 马上弹一条全屏的，验证全屏闹钟权限
  Future<bool> showNowFullScreen({bool soundOn = true}) async {
    lastScheduleError = '';
    if (!available) {
      lastScheduleError = '当前平台不支持本地通知';
      return false;
    }
    await init();
    if (!_ready) {
      lastScheduleError = '通知插件初始化失败（_ready=false，看 logcat 的 initialize 报错）';
      return false;
    }
    try {
      await _plugin.show(
        999998,
        '朝暮 · 全屏测试',
        '看到这张全屏卡片，说明全屏闹钟是通的。',
        _details(
          fullScreen: true,
          soundOn: soundOn,
          title: '朝暮 · 全屏测试',
          body: '看到这张全屏卡片，说明全屏闹钟是通的。',
        ),
        payload: '',
      );
      return true;
    } catch (e) {
      lastScheduleError = '测试全屏提醒发送失败：$e';
      return false;
    }
  }

  /// 跳到系统里「朝暮 → 通知 → 待办提醒」这个渠道的设置页。
  ///
  /// 走原生 startActivity（三级兜底：渠道页 → 通知总页 → 应用详情页），
  /// **不走 android_intent_plus** —— 系统设置页不在 PackageManager 里导出，
  /// 那个库的 `canResolveActivity()` 会误报 false 然后放弃跳转。
  ///
  /// 返回 true = 跳成功了（不代表用户改了什么）。
  Future<bool> openChannelSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? ok = await _ringChannel.invokeMethod<bool>(
        'openChannelSettings',
        <String, dynamic>{'channelId': _channelId},
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳到系统的「朝暮 应用信息」页。
  ///
  /// 这一页里有「省电策略」那一项，用户从这儿进去比先跳电池优化总列表少找好几层。
  /// 返回 true = 跳成功了。
  Future<bool> openAppDetails() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? ok = await _ringChannel.invokeMethod<bool>('openAppDetails');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳各家的「省电策略 / 电池管理」专页（小米 / 华为 / OPPO / vivo / 三星）。
  /// 跳不进去返回 false，由调用方降级。
  Future<bool> openPowerSaving() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? ok = await _ringChannel.invokeMethod<bool>('openPowerSaving');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 读 App 版本号，形如 "2.7.4+6"。
  ///
  /// Android 从 PackageManager 读，Windows 从 exe 自带的版本信息读 ——
  /// 都不写死在代码里，否则每次发版都得记得改，早晚会忘。
  /// 读不到返回空串。
  Future<String> appVersion() async {
    if (Platform.isWindows) {
      try {
        final PackageInfo p = await PackageInfo.fromPlatform();
        if (p.version.isEmpty) return '';
        return p.buildNumber.isEmpty
            ? p.version
            : '${p.version}+${p.buildNumber}';
      } catch (_) {
        return '';
      }
    }
    if (!Platform.isAndroid) return '';
    try {
      return await _ringChannel.invokeMethod<String>('getVersion') ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> cancelFor(Todo t) async {
    if (!available) return;
    // Windows：只在内部调度器里删，系统的 cancel() 对非 MSIX 应用是空操作
    if (Platform.isWindows) {
      _win?.remove(t.id);
      return;
    }
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(_idOf(t.id));
    } catch (_) {}
  }
  /// 把所有未完成的待办重新排一遍（启动时调）
  Future<void> rescheduleAll() async {
    if (!available) return;
    await init();
    lastScheduleError = '';
    // Windows：先清空上次运行留下的内存表，避免新旧混在一起
    if (Platform.isWindows) _win?.clear();
    final AppState st = AppState.I;
    for (final Todo t in st.todos) {
      await scheduleFor(
        t,
        // 「默认打开铃声」关掉 → 只弹不响。不传这个的话那个开关就是个摆设
        soundOn: st.defaultRemindOn,
        // 单条自己设过就用它自己的，没设（-1）才跟随全局
        aheadMinutes: t.aheadMinutes < 0 ? st.defaultAheadMinutes : t.aheadMinutes,
        style: st.remindStyle,
      );
    }
    // Windows：把错过的汇总成一条补弹
    if (Platform.isWindows) await _win?.flushMissed();
  }
}
