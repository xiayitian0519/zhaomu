import 'dart:io';
import 'dart:typed_data';

import 'package:chaomu/bspatch.dart';

/// 验证 bspatch 合并结果和原文件字节一致。
///
/// 用法：dart run tool/test_bspatch.dart
void main() {
  const String dir = r'D:\workbuddy01\2026-10-20-13-10-35';
  final File oldF = File('$dir\\_t_old.apk');
  final File patchF = File('$dir\\_t_patch.bin');
  final File wantF = File('$dir\\_t_new.apk');

  if (!oldF.existsSync() || !patchF.existsSync() || !wantF.existsSync()) {
    print('测试文件不齐，先跑 Python 那边生成');
    exit(1);
  }

  final List<int> oldB = oldF.readAsBytesSync();
  final List<int> patchB = patchF.readAsBytesSync();
  final List<int> wantB = wantF.readAsBytesSync();

  print('旧包 ${(oldB.length / 1048576).toStringAsFixed(1)} MB');
  print('patch ${(patchB.length / 1048576).toStringAsFixed(2)} MB');
  print('目标 ${(wantB.length / 1048576).toStringAsFixed(1)} MB');
  print('开始合并…');

  final Stopwatch sw = Stopwatch()..start();
  final List<int> got;
  try {
    got = BsPatch.apply(
      Uint8List.fromList(oldB),
      Uint8List.fromList(patchB),
    );
  } catch (e) {
    print('合并失败: $e');
    exit(1);
  }
  sw.stop();
  print('合并完成，耗时 ${sw.elapsedMilliseconds} ms，输出 ${got.length} 字节');

  if (got.length != wantB.length) {
    print('❌ 长度不一致：得到 ${got.length}，应为 ${wantB.length}');
    exit(1);
  }

  int diff = -1;
  for (int i = 0; i < got.length; i++) {
    if (got[i] != wantB[i]) {
      diff = i;
      break;
    }
  }
  if (diff >= 0) {
    print('❌ 第 $diff 字节不一致：得到 ${got[diff]}，应为 ${wantB[diff]}');
    exit(1);
  }

  print('✅ 完全一致，${got.length} 字节逐字节相同');
}
