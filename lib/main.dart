import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'guide.dart';
import 'models.dart';
import 'notifier.dart';
import 'pages/calendar_page.dart';
import 'pages/detail_page.dart';
import 'pages/home_page.dart';
import 'pages/onboard_page.dart';
import 'pages/settings_page.dart';
import 'pages/sound_page.dart';
import 'sound_lib.dart';
import 'sound_player.dart';
import 'windows_shell.dart';

/// 全局导航 key：点通知要能在任意页面跳去待办详情
final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Windows：先把桌面外壳起起来（窗口尺寸 430×900 + 托盘），再加载数据。
  // 放在 load 之前，用户看到的启动过程更短。
  if (Platform.isWindows) {
    await WindowsShell.I.init();
  }

  await AppState.I.load();

  // 预扫一遍导入的铃声目录。SoundLib.byId 是同步的（界面每帧都要调），
  // 不预加载的话冷启动后第一条提醒解析不出 lib:* 会回落成系统默认。
  await SoundLib.refreshImported();

  await Notifier.I.init();

  // 引导页完成后进主页。用注入的方式避免 onboard_page <-> home_page 循环依赖。
  OnboardEntry.child = (BuildContext _) => const HomePage();

  // 点通知 -> 跳进对应待办详情
  Notifier.I.onOpenTodo = _openTodoById;

  // 重复待办完成后自动生成的下一条，要排提醒。
  // AppState 不认识 Notifier（会循环依赖），所以在这里注入。
  AppState.I.onRepeatSpawned = (Todo t) {
    final AppState st = AppState.I;
    Notifier.I.scheduleFor(
      t,
      soundOn: st.defaultRemindOn,
      aheadMinutes:
          t.aheadMinutes < 0 ? st.defaultAheadMinutes : t.aheadMinutes,
      style: st.remindStyle,
    );
  };
  // 冷启动就带着待办 id（App 是被通知点开的），等第一帧之后再跳
  final String? pending = Notifier.I.pendingTodoId;
  if (pending != null) {
    Notifier.I.pendingTodoId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _openTodoById(pending));
  }

  // 新手指引要切页面，但 guide.dart 不直接依赖 pages（会循环引用），
  // 所以在这里把跳转动作注入进去。
  GuideController.I.pushCalendar = () {
    rootNavKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => const CalendarPage()),
    );
  };
  GuideController.I.goHome = () {
    rootNavKey.currentState?.popUntil((Route<dynamic> r) => r.isFirst);
  };

  // 启动时把没完成的提醒重新排一遍（换手机 / 重装后仍然有效）
  await Notifier.I.rescheduleAll();

  // 自测入口：`chaomu.exe --selftest` 立刻弹一条系统通知，并在 20 秒后
  // 再弹一条定时通知，用来验证 Windows 的 Toast 链路和调度器。
  // **必须放在 rescheduleAll 之后** —— rescheduleAll 开头会 clear() 清空调度表，
  // 放前面会被一起清掉（踩过）。不传这个参数时行为完全不变。
  if (args.contains('--selftest')) {
    final bool ok = await Notifier.I.showNow();
    debugPrint('[selftest] 立即弹窗 = $ok, err=${Notifier.I.lastScheduleError}');
    Notifier.I.windowsReminder?.put(
      todoId: 'selftest-timer',
      title: '朝暮 · 定时提醒',
      body: '这条由调度器在 20 秒后触发',
      when: DateTime.now().add(const Duration(seconds: 20)),
    );
    debugPrint('[selftest] 已排 20 秒后一条，当前排着 '
        '${Notifier.I.windowsReminder?.count} 条');
  }

  // 调试入口：`chaomu.exe --settings` 启动后直接进设置页，方便截图/排查
  if (args.contains('--settings')) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      rootNavKey.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
      );
    });
  }
  // 调试入口：`chaomu.exe --sound` 直接进铃声页（截图 / 排查用）
  if (args.contains('--sound')) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      rootNavKey.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => const SoundPage()),
      );
    });
  }

  // 自测入口：`chaomu.exe --ringtest` 依次播一遍各类铃声，打印能不能播。
  // 用来确认 audioplayers 在 Windows 上真的能加载 asset / 系统 wav。
  if (args.contains('--ringtest')) {
    Future<void>.delayed(const Duration(seconds: 3), () async {
      final List<SoundItem> all = <SoundItem>[
        ...SoundLib.builtin,
        ...SoundLib.presets,
        ...SoundLib.systemMedia().take(2),
      ];
      for (final SoundItem s in all) {
        final bool ok = await SoundPlayer.playItem(s, force: true);
        debugPrint('[ringtest] ${s.id} | ${s.name} -> ${ok ? 'OK' : 'FAIL'}');
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
      debugPrint('[ringtest] 全部播完，共 ${all.length} 款');
    });
  }

  // 调试入口：`chaomu.exe --clock` 打开第一条未完成待办的「时钟」面板，
  // 用来截图 / 验证铃声入口（正常点击要连点两下才能进详情，截图脚本容易点错）
  if (args.contains('--clock')) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Todo? target;
      for (final Todo t in AppState.I.todos) {
        if (!t.done) {
          target = t;
          break;
        }
      }
      final Todo? picked = target;
      if (picked == null) return;
      rootNavKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => DetailPage(todo: picked, autoClock: true),
        ),
      );
    });
  }

  // 调试入口：`chaomu.exe --sound-single` 单条待办的铃声页（截图 / 排查用）
  if (args.contains('--sound-single')) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      rootNavKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => const SoundPage(single: true),
        ),
      );
    });
  }

  // 调试入口：`chaomu.exe --detail` 直接进第一条未完成待办的详情页，**不弹时钟面板**。
  // 和 --clock 只差 autoClock 一个参数。加它是因为截图取证时需要一个干净的
  // 详情页（--clock 会把下半屏的面板打开，挡住时钟行），模拟点击和模拟 Esc
  // 都进不去 Flutter 窗口，只能从启动参数走。
  if (args.contains('--detail')) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Todo? target;
      for (final Todo t in AppState.I.todos) {
        if (!t.done) {
          target = t;
          break;
        }
      }
      final Todo? picked = target;
      if (picked == null) return;
      rootNavKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => DetailPage(todo: picked),
        ),
      );
    });
  }

  // 调试入口：`chaomu.exe --calendar` 启动后直接进日历页
  if (args.contains('--calendar')) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      rootNavKey.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => const CalendarPage()),
      );
    });
  }

  // 调试入口：`chaomu.exe --traymenu` 启动 3 秒后走一遍托盘右键回调，
  // 用来确认「右键是不是真能弹出菜单」（2026-10-21 排查「关不掉后台」）。
  // 走的是 onTrayIconRightMouseUp 本身，不是另开一条路，所以验的就是真实逻辑。
  if (args.contains('--traymenu')) {
    Future<void>.delayed(const Duration(seconds: 3), () {
      WindowsShell.I.onTrayIconRightMouseUp();
    });
  }

  runApp(const ChaomuApp());
}

/// 按 id 打开待办详情。找不到就什么都不做（可能已经被删了）。
void _openTodoById(String id) {
  final Todo? t = AppState.I.byId(id);
  if (t == null) return;
  final NavigatorState? nav = rootNavKey.currentState;
  if (nav == null) return;
  nav.push(
    MaterialPageRoute<void>(builder: (_) => DetailPage(todo: t)),
  );
}

class ChaomuApp extends StatelessWidget {
  const ChaomuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '朝暮',
      navigatorKey: rootNavKey,
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en', 'US')],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF185FA5)),
        scaffoldBackgroundColor: const Color(0xFFF7F7F8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFFFF),
          foregroundColor: Color(0xFF1F1F1F),
          elevation: 0,
          scrolledUnderElevation: 0.5,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Color(0xFF1F1F1F),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFEAEAEA),
          thickness: 1,
          space: 1,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: AppState.I.onboarded ? const HomePage() : const OnboardPage(),
      // 引导层包在 builder 里 —— 它在 Navigator 之上，切页面（设置 / 日历）时
      // 不会被新推入的页面盖住，跨页引导才能连起来。
      builder: (BuildContext context, Widget? child) {
        return GuideHost(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
