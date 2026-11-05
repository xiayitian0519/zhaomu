// 自检「安装包完整性判断」。
// 跑：dart tool/test_zip_check.dart
//
// 三个样本：
//   1. 桌面上的真 APK —— 必须判成合法
//   2. 截断到一半的 APK —— 必须判成坏包（模拟下载中断）
//   3. 一段 HTML —— 必须判成坏包（模拟下到错误页）
import 'dart:io';

import '../lib/zip_check.dart';

void main() async {
  int bad = 0;

  Future<void> check(String name, File f, bool want) async {
    final bool got = await looksLikeZip(f);
    final bool ok = got == want;
    if (!ok) bad++;
    print('${ok ? 'PASS' : 'FAIL'}  $name → ${got ? '合法' : '坏包'}'
        '（期望 ${want ? '合法' : '坏包'}）');
  }

  final String apkPath = r'C:\Users\18814\Desktop\朝暮\手机安装包\朝暮-2.27.11.apk';
  final File apk = File(apkPath);
  if (await apk.exists()) {
    await check('真 APK ${await apk.length()} 字节', apk, true);

    // 截断一半
    final File half = File('${Directory.systemTemp.path}/half_apk.bin');
    final RandomAccessFile src = await apk.open();
    final int keep = (await apk.length()) ~/ 2;
    final List<int> bytes = await src.read(keep);
    await src.close();
    await half.writeAsBytes(bytes, flush: true);
    await check('截断一半的 APK', half, false);
    await half.delete();
  } else {
    print('跳过 APK 样本：$apkPath 不存在');
  }

  final File html = File('${Directory.systemTemp.path}/fake.apk');
  await html.writeAsString(
    '<!DOCTYPE html><html><body>404 not found</body></html>',
    flush: true,
  );
  await check('HTML 冒充的 apk', html, false);
  await html.delete();

  print('');
  print(bad == 0 ? '全部通过' : '$bad 条不通过');
}
