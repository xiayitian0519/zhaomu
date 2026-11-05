import 'dart:io';
import 'dart:typed_data';

/// 判断一个文件像不像合法的 APK / ZIP。
///
/// 只看两处：头 4 字节是不是 `PK\x03\x04`，末尾有没有 EOCD（`PK\x05\x06`）。
/// 能挡住两类最常见的问题 —— 下载被截断、下到的其实是网页或错误页。
///
/// 单独放一个文件是为了能脱离 Flutter 直接跑测试：
/// `dart tool/test_zip_check.dart`
/// 2026-11-05 建：用户在手机上装包报
/// 「解析软件包时出现问题 (33) packageInfo is null」，那就是文件坏了。
Future<bool> looksLikeZip(File f) async {
  try {
    final int len = await f.length();
    if (len < 1024) return false;
    final RandomAccessFile raf = await f.open();
    try {
      final Uint8List head = await raf.read(4);
      if (head.length < 4 ||
          head[0] != 0x50 ||
          head[1] != 0x4B ||
          head[2] != 0x03 ||
          head[3] != 0x04) {
        return false;
      }
      // EOCD 一定落在文件末尾 64KB 注释范围内
      final int tailLen = len < 66560 ? len : 66560;
      await raf.setPosition(len - tailLen);
      final Uint8List tail = await raf.read(tailLen);
      for (int i = tail.length - 22; i >= 0; i--) {
        if (tail[i] == 0x50 &&
            tail[i + 1] == 0x4B &&
            tail[i + 2] == 0x05 &&
            tail[i + 3] == 0x06) {
          return true;
        }
      }
      return false;
    } finally {
      await raf.close();
    }
  } catch (_) {
    return false;
  }
}
