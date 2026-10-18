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
  await Notifier.I.init();

  // 引导页完成后进主页。用注入的方式避免 onboard_page <-> home_page 循环依赖。
  OnboardEntry.child = (BuildContext _) => const HomePage();

  // 点通知 -> 跳进对应待办详情
  Notifier.I.onOpenTodo = _openTodoById;
  // 冷启动就带着待办 id（App 是被通知点开的），等第一帧之后再跳
  final String? pending = Notifier.I.pendingTodoId;
  if (pending != null) {
    Notifier.I.pendingTodoId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _openTodoById(pending));
  }

  // 新手指引要切页面，但 guide.dart 不直接依赖 pages（会循环引用），
  // 所以在这里把跳转动作注入进去。
  GuideController.I.pushSettings = () {
    rootNavKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  };
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
