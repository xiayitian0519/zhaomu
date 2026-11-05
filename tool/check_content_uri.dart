// 自检 Updater._contentUri() 的换算规则。
//
// 逻辑和 lib/updater.dart 里那份一模一样，只是把 authority 写死方便比对。
// 跑：dart tool/check_content_uri.dart
//
// 2026-11-05 建：手机上装 APK 报 open failed: ENOENT，根因就是这里少了一层目录。

const String AUTHORITY = 'com.xiayitian.chaomu.fileprovider';

String? contentUri(String absPath) {
  String p = absPath.replaceAll('\\', '/');
  final String prefix;
  final int i = p.indexOf('/files/');
  if (i >= 0) {
    prefix = 'downloads';
    p = p.substring(i + 7);
  } else {
    final int c = p.indexOf('/cache/');
    if (c < 0) return null;
    prefix = 'cache';
    p = p.substring(c + 7);
  }
  final String rel = p
      .split('/')
      .where((String s) => s.isNotEmpty)
      .map(Uri.encodeComponent)
      .join('/');
  if (rel.isEmpty) return null;
  return 'content://$AUTHORITY/$prefix/$rel';
}

void main() {
  final Map<String, String?> cases = <String, String?>{
    // 常见情况：外部私有目录下的子目录（就是线上炸掉的那条）
    '/storage/emulated/0/Android/data/com.xiayitian.chaomu/files/chaomu_updates/chaomu-2.27.3.apk':
        'content://$AUTHORITY/downloads/chaomu_updates/chaomu-2.27.3.apk',
    // 直接放在 files 根
    '/storage/emulated/0/Android/data/com.xiayitian.chaomu/files/chaomu-2.27.3.apk':
        'content://$AUTHORITY/downloads/chaomu-2.27.3.apk',
    // 兜底路径：临时目录
    '/data/user/0/com.xiayitian.chaomu/cache/chaomu_updates/chaomu-2.27.3.apk':
        'content://$AUTHORITY/cache/chaomu_updates/chaomu-2.27.3.apk',
    // 少见的双层目录
    '/storage/emulated/0/Android/data/com.xiayitian.chaomu/files/a/b/chaomu-2.27.3.apk':
        'content://$AUTHORITY/downloads/a/b/chaomu-2.27.3.apk',
    // 既不在 files 也不在 cache -> 不给地址
    '/sdcard/Download/chaomu-2.27.3.apk': null,
  };

  int bad = 0;
  cases.forEach((String path, String? want) {
    final String? got = contentUri(path);
    final bool ok = got == want;
    if (!ok) bad++;
    print('${ok ? 'PASS' : 'FAIL'}  $path');
    if (!ok) {
      print('      想要: $want');
      print('      实得: $got');
    }
  });
  print('');
  print(bad == 0 ? '全部 ${cases.length} 条通过' : '$bad 条不通过');
}
