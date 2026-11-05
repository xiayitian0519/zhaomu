// 自检「跨版本更新清单」和「人话过滤」。
// 跑：dart tool/test_update_notes.dart
import '../lib/update_model.dart';
import '../lib/update_notes.dart';

void main() {
  int bad = 0;
  void check(String name, bool ok, [String extra = '']) {
    print('${ok ? 'PASS' : 'FAIL'}  $name${extra.isEmpty ? '' : '  $extra'}');
    if (!ok) bad++;
  }

  check('2.27.5 < 2.27.7', compareVersion('2.27.5', '2.27.7') < 0);
  check('2.27.10 > 2.27.9', compareVersion('2.27.10', '2.27.9') > 0);
  check('同版本相等', compareVersion('2.27.7', '2.27.7') == 0);

  final List<AppUpdate> seg = updatesBetween('2.27.5', '2.27.7');
  final List<String> vs = seg.map((AppUpdate u) => u.version).toList();
  print('  从 2.27.5 到 2.27.7 之间：$vs');
  check('区间含 2.27.7 和 2.27.6', vs.contains('2.27.7') && vs.contains('2.27.6'));
  check('区间不含当前版本 2.27.5', !vs.contains('2.27.5'));
  check('新的排前面', vs.isNotEmpty && vs.first == '2.27.7');

  final List<AppUpdate> far = updatesBetween('2.20.0', '2.27.7');
  print('  从 2.20.0 到 2.27.7 之间：${far.length} 个版本');
  check('跨多个版本能全取出来', far.length >= 10);

  final List<String> raw = <String>[
    '修 AI 导入把一行的 7:30 复制给所有条目',
    '改 lib/updater.dart 里的拼路径逻辑',
    '新增 4×4 大卡',
  ];
  final List<String> nice = userFacing(raw);
  print('  过滤后：$nice');
  check('技术条目被滤掉', !nice.any((String e) => e.contains('lib/')));
  check('人话条目保留', nice.contains('新增 4×4 大卡'));

  final List<String> allTech = <String>['改 lib/a.dart', '改 MainActivity.kt'];
  check('全被滤掉时留一条兜底', userFacing(allTech).length == 1);

  print('');
  print(bad == 0 ? '全部通过' : '$bad 条不通过');
}
