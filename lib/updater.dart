import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// 一次「检查更新」的结果。
class UpdateInfo {
  UpdateInfo({
    required this.latest,
    required this.notes,
    required this.pageUrl,
  });

  /// 远端最新版本号，如 `2.23.1`
  final String latest;

  /// 更新说明（release notes 的前几行）
  final String notes;

  /// release 页面地址，点「去下载」就开这个
  final String pageUrl;
}

/// 检查更新。查 GitHub Release，不走任何中间服务。
///
/// 只负责「告诉用户有新版本 + 把他送到下载页」，不在 App 内下 APK 装 ——
/// 安卓那边要配 FileProvider、申请安装未知应用权限，没真机反复试会翻车，
/// 先按稳的做（用户 2026-11-04 拍板「先做 App 内检查更新」）。
class Updater {
  Updater._();

  static const String _owner = 'xiayitian0519';
  static const String _repo = 'zhaomu';

  /// 当前版本（从 package_info 读，形如 2.23.0）
  static Future<String> currentVersion() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// 查远端最新 release。网络不通 / 没有 release 时返回 null（不报错，静默）。
  static Future<UpdateInfo?> check() async {
    final Uri api = Uri.parse(
      'https://api.github.com/repos/$_owner/$_repo/releases/latest',
    );
    final http.Response resp;
    try {
      resp = await http.get(
        api,
        headers: <String, String>{'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 20));
    } catch (_) {
      return null;
    }
    if (resp.statusCode != 200) return null;

    try {
      final Map<String, dynamic> o =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final String tag = (o['tag_name'] ?? '').toString();
      final String latest = tag.startsWith('v') ? tag.substring(1) : tag;
      if (latest.isEmpty) return null;

      String notes = (o['body'] ?? '').toString();
      // 只取前 300 字，弹窗放不下那么多
      if (notes.length > 300) notes = '${notes.substring(0, 300)}…';

      final String pageUrl = (o['html_url'] ?? '').toString().isEmpty
          ? 'https://github.com/$_owner/$_repo/releases'
          : o['html_url'].toString();

      return UpdateInfo(latest: latest, notes: notes, pageUrl: pageUrl);
    } catch (_) {
      return null;
    }
  }

  /// latest 比 current 新吗（只比 主.次.补丁，不管构建号）。
  static bool isNewer(String current, String latest) {
    final List<int> a = _parts(current);
    final List<int> b = _parts(latest);
    for (int i = 0; i < 3; i++) {
      if (b[i] > a[i]) return true;
      if (b[i] < a[i]) return false;
    }
    return false;
  }

  static List<int> _parts(String v) {
    final String core = v.split('+').first;
    final List<String> seg = core.split('.');
    return <int>[
      int.tryParse(seg.isNotEmpty ? seg[0] : '0') ?? 0,
      int.tryParse(seg.length > 1 ? seg[1] : '0') ?? 0,
      int.tryParse(seg.length > 2 ? seg[2] : '0') ?? 0,
    ];
  }

  /// 打开下载页。安卓走 intent，Windows 走系统默认浏览器。
  static Future<bool> openDownloadPage(String url) async {
    try {
      if (Platform.isAndroid) {
        final AndroidIntent intent = AndroidIntent(
          action: 'action_view',
          data: url,
        );
        await intent.launch();
        return true;
      }
      if (Platform.isWindows) {
        await Process.run(
          'rundll32',
          <String>['url.dll,FileProtocolHandler', url],
        );
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }
}
