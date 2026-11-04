import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:android_intent_plus/android_intent.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'bspatch.dart';

/// 一次「检查更新」的结果。
class UpdateInfo {
  UpdateInfo({
    required this.latest,
    required this.notes,
    required this.pageUrl,
    this.apkUrl,
    this.zipUrl,
    this.patchUrl,
    this.patchFrom,
    this.patchSize,
  });

  /// 远端最新版本号，如 `2.26.2`
  final String latest;

  /// 更新说明（release notes 前 300 字）
  final String notes;

  /// release 页面地址
  final String pageUrl;

  /// 安卓 arm64 安装包直链
  final String? apkUrl;

  /// Windows 压缩包直链
  final String? zipUrl;

  /// 增量补丁直链（相对某一版）
  final String? patchUrl;

  /// 这个补丁是从哪个版本打到 [latest] 的
  final String? patchFrom;

  /// 补丁大小（字节），拿不到就是 null
  final int? patchSize;

  /// 能不能走增量（有补丁 + 本地有这个版本的完整包）
  bool get hasPatch => patchUrl != null && patchFrom != null;
}

/// 拿到的更新文件。
class UpdateFile {
  UpdateFile({required this.file, required this.bytes, required this.wasPatch});

  final File file;

  /// 实际传输了多少字节（增量时是 patch 的体积）
  final int bytes;

  /// true = 走的增量合成，false = 下的完整包
  final bool wasPatch;
}

/// 检查更新 + 下载安装。
///
/// 2026-11-04 加了**增量更新**：
///   1. 每次下完完整包都会在应用私有目录留一份 `chaomu-<版本>.apk`
///   2. 下次检查更新时，如果 Release 里有 `<旧版本>-to-<新版本>.patch`
///      且本地有旧版完整包 -> 只下 patch（实测省 96%），本地用 bspatch 合成
///   3. 任何一步不满足（没补丁 / 没缓存 / 合成失败）-> 自动退回完整包
///
/// ⚠️ 第一次从旧版升级时必然是全量（本地没有旧包缓存），
/// 从这一次之后才会走增量。
class Updater {
  Updater._();

  static const String _owner = 'xiayitian0519';
  static const String _repo = 'zhaomu';

  /// FileProvider 的 authority，要和 AndroidManifest 里对上
  static const String _authority = 'com.xiayitian.chaomu.fileprovider';

  static Future<String> currentVersion() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// 存放下载包和补丁的目录（安卓用外部私有目录，桌面用下载目录）。
  static Future<Directory> updatesDir() async {
    final Directory base;
    if (Platform.isAndroid) {
      base = await getExternalStorageDirectory() ?? await getTemporaryDirectory();
    } else {
      base = await getDownloadsDirectory() ?? await getTemporaryDirectory();
    }
    final Directory d = Directory('${base.path}${Platform.pathSeparator}chaomu_updates');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// 查远端最新 release。
  ///
  /// [current] 传当前版本号的话，会顺便找「从当前版本到最新版本」的补丁包。
  static Future<UpdateInfo?> check({String? current}) async {
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

      String? apk;
      String? zip;
      String? patch;
      String? patchFrom;
      int? patchSize;

      final Object? assets = o['assets'];
      if (assets is List) {
        for (final dynamic a in assets) {
          if (a is! Map<String, dynamic>) continue;
          final String nm = (a['name'] ?? '').toString();
          final String dl = (a['browser_download_url'] ?? '').toString();
          final int sz = (a['size'] is num) ? (a['size'] as num).toInt() : 0;
          if (dl.isEmpty) continue;

          if (nm.endsWith('.apk') && nm.contains('arm64')) apk = dl;
          if (nm.endsWith('.zip')) zip = dl;

          // 补丁命名约定：<旧版本>-to-<新版本>.patch
          // 例如 2.26.1-to-2.26.2.patch
          if (nm.endsWith('.patch') && current != null && current.isNotEmpty) {
            final String base = nm.substring(0, nm.length - 6);
            final List<String> seg = base.split('-to-');
            if (seg.length == 2 && seg[0] == current) {
              patch = dl;
              patchFrom = seg[0];
              patchSize = sz > 0 ? sz : null;
            }
          }
        }
      }

      return UpdateInfo(
        latest: latest,
        notes: notes,
        pageUrl: pageUrl,
        apkUrl: apk,
        zipUrl: zip,
        patchUrl: patch,
        patchFrom: patchFrom,
        patchSize: patchSize,
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

  /// 下载一个 URL 到指定文件。
  static Future<void> downloadTo(
    String url,
    File dest, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (await dest.exists()) await dest.delete();
    final http.Client client = http.Client();
    try {
      final http.StreamedResponse resp =
          await client.send(http.Request('GET', Uri.parse(url)));
      if (resp.statusCode != 200) {
        throw Exception('下载失败：HTTP ${resp.statusCode}');
      }
      final int total = resp.contentLength ?? 0;
      int received = 0;
      final IOSink sink = dest.openWrite();
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
  }

  /// 拿更新文件：能走增量就走增量，否则下完整包。
  ///
  /// 返回的文件一定是可以直接交给安装器的完整 APK（安卓）
  /// 或 zip（电脑）。
  static Future<UpdateFile> fetch({
    required UpdateInfo info,
    required String currentVersion,
    void Function(int received, int total)? onProgress,
  }) async {
    final Directory dir = await updatesDir();
    final String sep = Platform.pathSeparator;
    final String target = Platform.isAndroid ? info.apkUrl ?? '' : info.zipUrl ?? '';
    if (target.isEmpty) {
      throw Exception('这个版本没有可用的安装包');
    }
    final String ext = Platform.isAndroid ? 'apk' : 'zip';
    final File newFile = File('${dir.path}$sep' + 'chaomu-${info.latest}.$ext');

    // ---- 先试增量 ----
    if (info.hasPatch && Platform.isAndroid) {
      final File oldApk = File('${dir.path}${sep}chaomu-${info.patchFrom}.$ext');
      if (await oldApk.exists()) {
        try {
          final File patchFile = File('${dir.path}${sep}patch-${info.latest}.bin');
          await downloadTo(info.patchUrl!, patchFile, onProgress: onProgress);

          final Uint8List oldBytes = await oldApk.readAsBytes();
          final Uint8List patchBytes = await patchFile.readAsBytes();
          final Uint8List newBytes = BsPatch.apply(oldBytes, patchBytes);

          await newFile.writeAsBytes(newBytes, flush: true);
          try {
            await patchFile.delete();
          } catch (_) {}
          return UpdateFile(
            file: newFile,
            bytes: patchBytes.length,
            wasPatch: true,
          );
        } catch (e) {
          // 增量失败（补丁坏了 / 旧包版本对不上），静默退回全量
          try {
            if (await newFile.exists()) await newFile.delete();
          } catch (_) {}
        }
      }
    }

    // ---- 全量 ----
    await downloadTo(target, newFile, onProgress: onProgress);
    return UpdateFile(file: newFile, bytes: await newFile.length(), wasPatch: false);
  }

  /// 打开安装（安卓）/ 定位文件（电脑）。
  static Future<bool> install(File f) async {
    try {
      if (Platform.isAndroid) {
        final String name = f.uri.pathSegments.last;
        final String uri =
            'content://$_authority/downloads/${Uri.encodeComponent(name)}';
        final AndroidIntent intent = AndroidIntent(
          action: 'action_view',
          data: uri,
          type: 'application/vnd.android.package-archive',
          flags: <int>[1],
        );
        await intent.launch();
        return true;
      }
      if (Platform.isWindows) {
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
