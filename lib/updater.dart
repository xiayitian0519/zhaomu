import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// 一次「检查更新」的结果。
class UpdateInfo {
  UpdateInfo({
    required this.latest,
    required this.notes,
    required this.pageUrl,
    this.apkUrl,
    this.zipUrl,
  });

  /// 远端最新版本号，如 `2.24.1`
  final String latest;

  /// 更新说明（release notes 前 300 字）
  final String notes;

  /// release 页面地址
  final String pageUrl;

  /// 安卓 arm64 安装包直链（从 release assets 里找）
  final String? apkUrl;

  /// Windows 压缩包直链
  final String? zipUrl;
}

/// 检查更新 + 下载安装。
///
/// 2026-11-04 用户要求「点检查更新就能开始下载」，所以这里从「只跳下载页」
/// 改成「真下载」：
///   安卓 —— 下 APK 到应用私有目录，再用 FileProvider 交给系统安装器
///   电脑 —— 下 zip 到下载目录，然后打开资源管理器定位到文件
class Updater {
  Updater._();

  static const String _owner = 'xiayitian0519';
  static const String _repo = 'zhaomu';

  /// FileProvider 的 authority，要和 AndroidManifest 里的 `${applicationId}.fileprovider` 对上
  static const String _authority = 'com.xiayitian.chaomu.fileprovider';

  static Future<String> currentVersion() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// 查远端最新 release。网络不通 / 没有 release 时返回 null。
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
      if (notes.length > 300) notes = '${notes.substring(0, 300)}…';

      final String pageUrl = (o['html_url'] ?? '').toString().isEmpty
          ? 'https://github.com/$_owner/$_repo/releases'
          : o['html_url'].toString();

      // 从 assets 里挑出两个包
      String? apk;
      String? zip;
      final Object? assets = o['assets'];
      if (assets is List) {
        for (final dynamic a in assets) {
          if (a is! Map<String, dynamic>) continue;
          final String nm = (a['name'] ?? '').toString();
          final String dl = (a['browser_download_url'] ?? '').toString();
          if (dl.isEmpty) continue;
          if (nm.endsWith('.apk') && nm.contains('arm64')) apk = dl;
          if (nm.endsWith('.zip')) zip = dl;
        }
      }

      return UpdateInfo(
        latest: latest,
        notes: notes,
        pageUrl: pageUrl,
        apkUrl: apk,
        zipUrl: zip,
      );
    } catch (_) {
      return null;
    }
  }

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

  /// 下载到本地。onProgress(已下载字节, 总字节)，总字节拿不到时给 0。
  static Future<File> download({
    required String url,
    required String fileName,
    void Function(int received, int total)? onProgress,
  }) async {
    final Directory dir;
    if (Platform.isAndroid) {
      dir = await getExternalStorageDirectory() ?? await getTemporaryDirectory();
    } else {
      dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
    }
    final File f = File('${dir.path}${Platform.pathSeparator}$fileName');
    if (await f.exists()) await f.delete();

    final http.Client client = http.Client();
    try {
      final http.StreamedResponse resp =
          await client.send(http.Request('GET', Uri.parse(url)));
      if (resp.statusCode != 200) {
        throw Exception('下载失败：HTTP ${resp.statusCode}');
      }
      final int total = resp.contentLength ?? 0;
      int received = 0;
      final IOSink sink = f.openWrite();
      await for (final List<int> chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }
    return f;
  }

  /// 打开安装（安卓）/ 定位文件（电脑）。
  static Future<bool> install(File f) async {
    try {
      if (Platform.isAndroid) {
        // 文件在 getExternalStorageDirectory 下的根目录，对应 file_paths 里的 downloads
        final String name = f.uri.pathSegments.last;
        final String uri =
            'content://$_authority/downloads/${Uri.encodeComponent(name)}';
        final AndroidIntent intent = AndroidIntent(
          action: 'action_view',
          data: uri,
          type: 'application/vnd.android.package-archive',
          flags: <int>[1], // FLAG_GRANT_READ_URI_PERMISSION
        );
        await intent.launch();
        return true;
      }
      if (Platform.isWindows) {
        // 打开资源管理器并选中下载好的文件
        await Process.run('explorer', <String>['/select,', f.path]);
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  /// 兜底：打不开安装器时退回到浏览器。
  static Future<bool> openPage(String url) async {
    try {
      if (Platform.isAndroid) {
        await AndroidIntent(action: 'action_view', data: url).launch();
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
