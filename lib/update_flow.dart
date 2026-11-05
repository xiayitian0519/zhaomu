import 'dart:io';

import 'package:flutter/material.dart';

import 'updater.dart';

/// App 内下载并安装更新。
///
/// 2026-11-05 从 settings_page 抽出来。原因：「发现新版本」弹窗里的
/// 「去更新」原本直接跳浏览器，用户从网页下到的是完整包，
/// 把增量更新（只下几百 KB 的补丁）整个绕过去了。
/// 现在设置里的「检查更新」和首页那个弹窗共用这一段，都走 App 内下载。
Future<void> runUpdateFlow(
  BuildContext ctx,
  UpdateInfo info,
  String current,
) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(ctx);
  final ValueNotifier<double> prog = ValueNotifier<double>(0);
  final String fileName = Platform.isAndroid
      ? 'chaomu-${info.latest}.apk'
      : 'chaomu-${info.latest}-windows.zip';

  showDialog<void>(
    context: ctx,
    barrierDismissible: false,
    builder: (BuildContext c) => AlertDialog(
      title: const Text('正在下载'),
      content: ValueListenableBuilder<double>(
        valueListenable: prog,
        builder: (BuildContext c, double v, _) {
          final int pct = (v * 100).clamp(0, 100).round();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LinearProgressIndicator(
                value: v <= 0 ? null : v,
                minHeight: 6,
                backgroundColor: const Color(0xFFE6E9EF),
              ),
              const SizedBox(height: 10),
              Text(
                v <= 0 ? '正在连接…' : '$pct%',
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A91A0)),
              ),
              const SizedBox(height: 4),
              Text(
                fileName,
                style: const TextStyle(fontSize: 11, color: Color(0xFFB4BAC6)),
              ),
            ],
          );
        },
      ),
    ),
  );

  UpdateFile? got;
  String? err;
  try {
    got = await Updater.fetch(
      info: info,
      currentVersion: current,
      onProgress: (int r, int t) {
        if (t > 0) prog.value = r / t;
      },
    );
  } catch (e) {
    err = e.toString();
  }

  if (!ctx.mounted) {
    prog.dispose();
    return;
  }
  Navigator.of(ctx).pop(); // 关进度框
  prog.dispose();

  final File? file = got?.file;
  final bool byPatch = got?.wasPatch ?? false;

  if (file == null) {
    final bool ok = await Updater.openPage(info.pageUrl);
    if (ctx.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(ok
              ? '下载失败（${err ?? '未知原因'}），已帮你打开下载页'
              : '下载失败，手动访问：${info.pageUrl}'),
        ),
      );
    }
    return;
  }

  final bool ok = await Updater.install(file);
  if (!ctx.mounted) return;
  final String how = byPatch
      ? '增量包 ${formatMb(got!.bytes)}（省了大部分流量）'
      : '完整包 ${formatMb(got?.bytes ?? 0)}';
  messenger.showSnackBar(
    SnackBar(
      content: Text(ok
          ? (Platform.isAndroid
              ? '已下好，$how。按系统提示安装'
              : '已下好，$how。在打开的文件夹里')
          : '已下到：${file.path}'),
      duration: const Duration(seconds: 6),
    ),
  );
}

/// 字节数转成好读的「x.x MB」
String formatMb(int bytes) {
  if (bytes <= 0) return '未知大小';
  if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}
