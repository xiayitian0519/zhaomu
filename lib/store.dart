import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 朝暮 · 本地存储（JSON 单文件）
///
/// 只依赖 dart:io + path_provider，安卓 / Windows 行为一致。
/// 将来若要换成 SQLite，只需要把这里的读写替换掉，上层不用动。
class Store {
  Store._();

  static const String _fileName = 'chaomu.json';

  static String _sep() => Platform.pathSeparator;

  /// 数据目录（应用私有目录下的 chaomu/）
  static Future<Directory> dataDir() async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory d = Directory('${base.path}${_sep()}chaomu');
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return d;
  }

  static Future<File> _dataFile() async {
    final Directory d = await dataDir();
    return File('${d.path}${_sep()}$_fileName');
  }

  /// 数据文件的完整路径（给设置页显示用）
  static Future<String> dataFilePath() async => (await _dataFile()).path;

  /// 读取；文件不存在或解析失败都返回 null
  static Future<Map<String, dynamic>?> read() async {
    try {
      final File f = await _dataFile();
      if (!await f.exists()) return null;
      final String s = await f.readAsString();
      if (s.trim().isEmpty) return null;
      final Object? o = jsonDecode(s);
      if (o is Map<String, dynamic>) return o;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 写入
  static Future<void> write(Map<String, dynamic> data) async {
    final File f = await _dataFile();
    await f.writeAsString(jsonEncode(data), flush: true);
  }

  /// 导出目录（外部可访问的 chaomu_export/），返回目录路径
  static Future<String> exportDir() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();

    final Directory out = Directory('${base.path}${_sep()}chaomu_export');
    if (!await out.exists()) {
      await out.create(recursive: true);
    }
    return out.path;
  }

  /// 把一段文本写进导出目录，返回文件完整路径。
  /// withStamp = true 时文件名带时间戳，避免覆盖上一次导出的内容。
  static Future<String> writeExport(
    String name,
    String content, {
    bool withStamp = false,
  }) async {
    final String dir = await exportDir();
    final String file = withStamp ? '${_stamp()}_$name' : name;
    final File f = File('$dir${_sep()}$file');
    await f.writeAsString(content, flush: true);
    return f.path;
  }

  /// 下载目录（部分机型可用），拿不到就回落到导出目录
  static Future<String> downloadDir() async {
    try {
      final Directory? d = await getDownloadsDirectory();
      if (d != null) {
        final Directory out = Directory('${d.path}${_sep()}chaomu');
        if (!await out.exists()) await out.create(recursive: true);
        return out.path;
      }
    } catch (_) {}
    return exportDir();
  }

  static String _stamp() {
    final DateTime n = DateTime.now();
    return '${n.year}${_two(n.month)}${_two(n.day)}_${_two(n.hour)}${_two(n.minute)}${_two(n.second)}';
  }

  /// 导出：把数据另存一份到「外部可访问目录」，返回文件路径
  static Future<String> export(Map<String, dynamic> data) async {
    final String dir = await exportDir();
    final File f = File('$dir${_sep()}chaomu_${_stamp()}.json');
    await f.writeAsString(jsonEncode(data), flush: true);
    return f.path;
  }

  static String _two(int v) => v < 10 ? '0$v' : '$v';

  /// 解析用户粘贴/选择的 json 文本
  static Map<String, dynamic>? parse(String text) {
    try {
      final Object? o = jsonDecode(text);
      if (o is Map<String, dynamic>) return o;
      return null;
    } catch (_) {
      return null;
    }
  }
}
