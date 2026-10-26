/// 一个版本的更新内容。
///
/// 单独放一个文件是因为 [lib/updates_gen.dart] 是脚本自动生成的，它也要用这个类；
/// 如果定义在 updates.dart 里，生成文件就得反过来 import 业务代码，形成循环。
class AppUpdate {
  const AppUpdate(this.version, this.date, this.items);

  /// 不带构建号，如 '2.21.0'
  final String version;

  /// '2026-10-25'
  final String date;

  /// 更新条目，一行一条
  final List<String> items;
}
