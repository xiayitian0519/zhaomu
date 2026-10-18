import 'dart:async';
import 'dart:io';
import 'dart:ui' show Color, Size;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
// 0.8.0 把 API 换成了 nativeapi，旧的一套仍在 legacy 里，
// 这里用旧的：文档全、行为确定，新 API 还没稳定。
// ignore: deprecated_member_use
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/window_manager.dart';

/// Windows 桌面外壳：窗口尺寸、托盘常驻、开机自启。
///
/// 三件事都是为了同一个目标 —— **提醒不能丢**：
/// 1. 窗口按手机比例开（430×900），页面布局一行不用改；
/// 2. 点关闭不是退出，是收进托盘，进程继续跑，定时器继续走；
/// 3. 开机自启，关机重启后它自己回来。
class WindowsShell with WindowListener, TrayListener {
  WindowsShell._();
  static final WindowsShell I = WindowsShell._();

  static const Size _defaultSize = Size(430, 900);
  static const Size _minSize = Size(380, 620);

  bool _inited = false;
  bool _quitting = false;

  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    await windowManager.ensureInitialized();

    // 关窗口拦截必须**在窗口显示之前**就挂上，否则用户点关闭时还没生效，
    // 窗口直接关掉、进程退出，提醒也跟着没了。
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    const WindowOptions options = WindowOptions(
      size: _defaultSize,
      minimumSize: _minSize,
      center: true,
      title: '朝暮',
      backgroundColor: Color(0xFFFFFFFF),
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    // ⚠️ 这个 Future 要等第一帧渲染完才完成 —— **绝对不能 await**。
    // await 的话 main() 会一直卡在这里，runApp 永远不执行，窗口一片空白
    // （2026-10-18 踩过一次）。
    unawaited(windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    }));

    await _setupTray();
  }

  // ---------------- 托盘 ----------------

  Future<void> _setupTray() async {
    try {
      trayManager.addListener(this);
      final String icon = await _materializeTrayIcon();
      if (icon.isNotEmpty) {
        await trayManager.setIcon(icon);
      }
      await trayManager.setToolTip('朝暮 · 待办提醒');
      await trayManager.setContextMenu(
        Menu(
          items: <MenuItem>[
            MenuItem(key: 'show', label: '打开朝暮'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: '退出'),
          ],
        ),
      );
    } catch (_) {
      // 托盘起不来不该挡着主流程，App 仍然能在任务栏用
    }
  }

  /// 托盘只能吃文件路径，asset 里的 ico 得先落到磁盘上。
  Future<String> _materializeTrayIcon() async {
    try {
      final ByteData data = await rootBundle.load('assets/app_icon.ico');
      final Directory dir = await getTemporaryDirectory();
      final File f = File('${dir.path}${Platform.pathSeparator}chaomu_tray.ico');
      await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return f.path;
    } catch (_) {
      return '';
    }
  }

  @override
  void onTrayIconMouseDown() {
    _reveal();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _reveal();
      case 'quit':
        quit();
    }
  }

  Future<void> _reveal() async {
    await windowManager.show();
    await windowManager.focus();
  }

  // ---------------- 关窗口 = 收进托盘 ----------------

  @override
  void onWindowClose() async {
    if (_quitting) return;
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    }
  }

  /// 真的退出（托盘菜单里点「退出」才走这条）
  Future<void> quit() async {
    _quitting = true;
    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {
      exit(0);
    }
  }

  // ---------------- 开机自启 ----------------

  /// 启动目录里的那个静默启动脚本
  File get _startupFile {
    final String appData = Platform.environment['APPDATA'] ?? '';
    return File(
      '$appData\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\朝暮.vbs',
    );
  }

  bool get autoStartEnabled => _startupFile.existsSync();

  /// 开 / 关开机自启。返回操作后的真实状态（写失败就还是 false）。
  ///
  /// 用 vbs 而不是 exe 快捷方式：vbs 能带「隐藏窗口」参数启动，
  /// 开机时不会先闪一个黑框。exe 路径直接写进去，所以程序挪位置后
  /// 需要重开一次这个开关。
  Future<bool> setAutoStart(bool on) async {
    try {
      if (!on) {
        if (_startupFile.existsSync()) _startupFile.deleteSync();
        return autoStartEnabled;
      }
      final String exe = Platform.resolvedExecutable;
      final String vbs = 'exe = "$exe"\r\n'
          'CreateObject("WScript.Shell").Run """" & exe & """", 0, False\r\n';
      await _startupFile.writeAsString(vbs, flush: true);
      return autoStartEnabled;
    } catch (_) {
      return autoStartEnabled;
    }
  }
}
