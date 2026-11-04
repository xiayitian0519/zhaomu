import 'dart:typed_data';

import 'package:archive/archive.dart';

/// BSDFF 补丁合并（2026-11-04 新增）。
///
/// 为什么自己写：Dart 生态没有成熟的 bsdiff 库，而增量更新必须能在手机上
/// 把「旧 APK + patch」合成新 APK。bspatch 这个解包算法本身不复杂，
/// 自己实现比引一个没人维护的包靠谱。
///
/// **重要：bsdiff4 生成的三段（ctrl / diff / extra）都是 bz2 压缩的。**
/// 头部三个长度是**压缩后**的长度，要先按长度切出来再 bz2 解压，
/// 才能拿到真正的 ctrl/diff/extra 数据。这是踩过坑的地方。
///
/// patch 文件格式：
/// ```
/// 0..7      "BSDIFF40" 魔数
/// 8..15     ctrl 段长度（压缩后，offtin）
/// 16..23    diff 段长度（压缩后，offtin）
/// 24..31    新文件总长度（offtin）
/// 32...     bz2(ctrl) + bz2(diff) + bz2(extra)
/// ```
class BsPatch {
  BsPatch._();

  static const List<int> _magic = <int>[0x42, 0x53, 0x44, 0x49, 0x46, 0x46, 0x34, 0x30];

  /// 把 [oldData] 和 [patchData] 合成新文件。失败抛 [BsPatchException]。
  static Uint8List apply(Uint8List oldData, Uint8List patchData) {
    if (patchData.length < 32) {
      throw BsPatchException('patch 文件太短（${patchData.length} 字节）');
    }
    for (int i = 0; i < 8; i++) {
      if (patchData[i] != _magic[i]) {
        throw BsPatchException('patch 魔数不对，不是 BSDIFF40 格式');
      }
    }

    final int ctrlPackedLen = _offtin(patchData, 8);
    final int diffPackedLen = _offtin(patchData, 16);
    final int newSize = _offtin(patchData, 24);

    if (ctrlPackedLen <= 0 || diffPackedLen < 0 || newSize <= 0) {
      throw BsPatchException(
          'patch 头部数值异常（ctrl=$ctrlPackedLen diff=$diffPackedLen new=$newSize）');
    }
    if (newSize > 200 * 1024 * 1024) {
      throw BsPatchException('目标文件过大（$newSize 字节），拒绝处理');
    }

    final int ctrlStart = 32;
    final int diffStart = ctrlStart + ctrlPackedLen;
    final int extraStart = diffStart + diffPackedLen;
    if (extraStart > patchData.length) {
      throw BsPatchException('patch 结构越界，文件可能损坏');
    }

    // ---- 三段各自 bz2 解压 ----
    final Uint8List ctrl = _unbz2(
      Uint8List.sublistView(patchData, ctrlStart, diffStart),
      'ctrl',
    );
    final Uint8List diff = _unbz2(
      Uint8List.sublistView(patchData, diffStart, extraStart),
      'diff',
    );
    final Uint8List extra = _unbz2(
      Uint8List.sublistView(patchData, extraStart, patchData.length),
      'extra',
    );

    if (ctrl.length % 24 != 0) {
      throw BsPatchException('ctrl 段长度 ${ctrl.length} 不是 24 的整数倍');
    }

    // ---- 按 ctrl 指令逐段拼出新文件 ----
    final Uint8List out = Uint8List(newSize);
    final int oldSize = oldData.length;

    int ctrlPos = 0;
    int diffPos = 0;
    int extraPos = 0;
    int oldPos = 0;
    int newPos = 0;

    while (newPos < newSize) {
      if (ctrlPos + 24 > ctrl.length) {
        throw BsPatchException('ctrl 段读超了，patch 损坏');
      }
      final int dLen = _offtin(ctrl, ctrlPos);
      final int eLen = _offtin(ctrl, ctrlPos + 8);
      final int seek = _offtin(ctrl, ctrlPos + 16);
      ctrlPos += 24;

      if (dLen < 0 || eLen < 0) {
        throw BsPatchException('ctrl 段长度是负数，patch 损坏');
      }
      if (diffPos + dLen > diff.length) {
        throw BsPatchException('diff 段不够（需要 ${diffPos + dLen}，只有 ${diff.length}）');
      }
      if (extraPos + eLen > extra.length) {
        throw BsPatchException('extra 段不够（需要 ${extraPos + eLen}，只有 ${extra.length}）');
      }

      // 1) diff 段：old 对应位置加到 out（模 256）
      for (int i = 0; i < dLen; i++) {
        final int np = newPos + i;
        if (np >= newSize) break;
        final int op = oldPos + i;
        final int base = (op >= 0 && op < oldSize) ? oldData[op] : 0;
        out[np] = (base + diff[diffPos + i]) & 0xFF;
      }
      newPos += dLen;
      oldPos += dLen;
      diffPos += dLen;

      // 2) extra 段：直接拷贝
      for (int i = 0; i < eLen; i++) {
        final int np = newPos + i;
        if (np >= newSize) break;
        out[np] = extra[extraPos + i];
      }
      newPos += eLen;
      extraPos += eLen;

      // 3) 旧文件游标跳转
      oldPos += seek;
    }

    return out;
  }

  /// bz2 解压一段。
  static Uint8List _unbz2(Uint8List packed, String what) {
    if (packed.isEmpty) return Uint8List(0);
    try {
      final List<int>? out = BZip2Decoder().decodeBytes(packed);
      if (out == null) throw BsPatchException('$what 段 bz2 解压返回空');
      return Uint8List.fromList(out);
    } catch (e) {
      throw BsPatchException('$what 段 bz2 解压失败：$e');
    }
  }

  /// 读 8 字节小端有符号整数（bsdiff 的 offtin）。
  ///
  /// 最高字节的第 7 位是符号位，负数时要做补码还原。
  static int _offtin(Uint8List buf, int offset) {
    if (offset + 8 > buf.length) {
      throw BsPatchException('读 offtin 越界（offset=$offset, len=${buf.length}）');
    }
    int y = buf[offset + 7] & 0x7F;
    for (int i = 6; i >= 0; i--) {
      y = y * 256 + buf[offset + i];
    }
    if ((buf[offset + 7] & 0x80) != 0) {
      y = -y;
    }
    return y;
  }
}

class BsPatchException implements Exception {
  BsPatchException(this.message);

  final String message;

  @override
  String toString() => message;
}
