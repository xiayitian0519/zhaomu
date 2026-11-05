// 实测 AI 导入的时间分配：一条写了 7:30，后面的条目绝不能跟着变 7:30。
//
// 跑：dart tool/test_ai_import.dart
// 2026-11-05 建。用户在手机上报了这个 bug：8 条全变成「今天 07:30 + 提醒 07:30」。
import '../lib/ai_tdl.dart';

String fmt(DateTime? d) {
  if (d == null) return 'null';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.month}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

Future<void> main() async {
  const String input = '7:30起床整理内务洗漱\n'
      '去校区\n'
      '拍消防员视频\n'
      '练习上周的秀\n'
      '做项目：\n'
      '学员档案UI布局优化和学员信息导入\n'
      '练习音标20min\n'
      '练习文章30遍';

  final AiParseResult r =
      await AiTdl.parse(text: input, apiKey: kBuiltinKey, usedToday: 0);

  print('拆出 ${r.todos.length} 条：');
  int bad = 0;
  for (final AiTodo t in r.todos) {
    print('  ${t.title}');
    print('      截止 ${fmt(t.due)}   提醒 ${fmt(t.remind)}');
    // 除第一条外，任何 07:30 都算串味
    final bool isFirstLine = t.title.contains('洗漱');
    if (!isFirstLine && t.due != null && t.due!.hour == 7) bad++;
  }
  print('');
  print(bad == 0 ? '通过：只有第一行带 7:30' : '不通过：$bad 条被串成了 7:30');
}
