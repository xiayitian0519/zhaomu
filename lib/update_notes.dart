import 'update_model.dart';
import 'updates_gen.dart';

/// 版本号比较（只比 主.次.补丁，构建号不参与）。
/// 返回 <0 表示 a 比 b 旧，>0 表示新，0 表示一样。
int compareVersion(String a, String b) {
  final List<int> x = a.split('.').map((String e) => int.tryParse(e) ?? 0).toList();
  final List<int> y = b.split('.').map((String e) => int.tryParse(e) ?? 0).toList();
  for (int i = 0; i < 3; i++) {
    final int xi = i < x.length ? x[i] : 0;
    final int yi = i < y.length ? y[i] : 0;
    if (xi != yi) return xi.compareTo(yi);
  }
  return 0;
}

/// 这些词说明那条更新写的是「怎么改的」，不是「用户能感觉到什么」。
/// 命中就滤掉，避免弹窗里出现 `lib/updater.dart` 这种用户看不懂的东西。
const List<String> _techWords = <String>[
  'lib/',
  '.dart',
  '.kt',
  'Manifest',
  'receiver',
  'provider',
  'exported',
  'previewLayout',
  'APPWIDGET',
  'JSON',
  'MethodChannel',
  'build.gradle',
  'pubspec',
];

/// 把一条更新翻译成用户视角的短句。
///
/// 规则很简单：命中技术词的条目直接丢掉；全丢光了就退回原文第一条，
/// 免得某一版弹出来是空的。
List<String> userFacing(List<String> items) {
  final List<String> kept = items
      .where((String e) => !_techWords.any((String w) => e.contains(w)))
      .toList();
  if (kept.isNotEmpty) return kept;
  return items.isEmpty ? <String>[] : <String>[items.first];
}

/// 取「从旧到新这一段」之间的所有版本，新的在前。
///
/// [from] 是用户当前版本，[to] 是远端最新版本，两端都按「大于旧、小于等于新」取。
List<AppUpdate> updatesBetween(String from, String to) {
  final List<AppUpdate> out = kUpdatesGenerated
      .where((AppUpdate u) =>
          compareVersion(u.version, from) > 0 &&
          compareVersion(u.version, to) <= 0)
      .toList();
  out.sort((AppUpdate a, AppUpdate b) => compareVersion(b.version, a.version));
  return out;
}

/// 把 '2026-11-05' 写成 '11月5日'，给弹窗当小标题用。
String shortDate(String iso) {
  final List<String> p = iso.split('-');
  if (p.length != 3) return iso;
  final int? m = int.tryParse(p[1]);
  final int? d = int.tryParse(p[2]);
  if (m == null || d == null) return iso;
  return '$m月$d日';
}
