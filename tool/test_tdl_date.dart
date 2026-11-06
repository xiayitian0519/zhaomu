// TDL 标题日期回归测试：真调智谱，验证「开头写了日期标题 → 整张单子归那天」。
// 跑：dart tool/test_tdl_date.dart
// 2026-11-06 建。用户报：「说了是明天的 TDL，结果除了带 7:00 的都是今天的」。
import '../lib/ai_tdl.dart';

String fmt(DateTime? d) {
  if (d == null) return 'null';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

int failed = 0;
int passed = 0;

void check(bool ok, String what) {
  if (ok) {
    passed++;
  } else {
    failed++;
    print('  ✗ $what');
  }
}

Future<AiParseResult?> run(String label, String input) async {
  print('===== $label =====');
  try {
    final AiParseResult r =
        await AiTdl.parse(text: input, apiKey: kBuiltinKey, usedToday: 0);
    for (final AiTodo t in r.todos) {
      print('  ${t.title} → ${fmt(t.due)} / 提醒 ${fmt(t.remind)}');
    }
    return r;
  } catch (e) {
    print('  调用失败：$e');
    return null;
  }
}

/// 一整批都该落在 [day]，只有带时刻的第一条允许是 07:00。
void expectAllOn(AiParseResult? r, DateTime day, String label) {
  if (r == null) {
    check(false, '$label：接口没返回结果');
    return;
  }
  check(r.todos.length >= 7, '$label：至少拆出 7 条（实际 ${r.todos.length}）');
  for (final AiTodo t in r.todos) {
    final DateTime? d = t.due;
    check(d != null, '$label：${t.title} 没有截止日期');
    if (d == null) continue;
    check(
      d.year == day.year && d.month == day.month && d.day == day.day,
      '$label：${t.title} 落在 ${fmt(d)}，应是 ${day.month}-${day.day}',
    );
    if (d.hour == 7 && d.minute == 0) {
      check(t.remind != null, '$label：${t.title} 带 7:00 却没准时提醒');
    } else {
      check(d.hour == 23 && d.minute == 59,
          '$label：${t.title} 没写时刻却不是当日 23:59 截止');
      check(t.remind == null, '$label：${t.title} 没写时刻却设了提醒');
    }
  }
  print('  → $label 校验完毕');
}

Future<void> main() async {
  const String body = '7:00起床整理内务洗漱吃早饭 跟同学借鞋子 跟南昌赋能官沟通 '
      '练口语拍视频 复习上周的秀1.5h 练文章20遍 练自我介绍30遍 练音标20遍';
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);

  // A 用户原话：11.5TDL（今天是 11-06，所以是 11-05）
  final DateTime d1105 = AiTdl.listDayOf('11.5TDL $body')!;
  expectAllOn(await run('A 用户原话（11.5 日期标题）', '11.5TDL $body'), d1105,
      'A 整批归 11-05');

  // B 相对词标题
  final DateTime tomorrow = AiTdl.listDayOf('明天的TDL $body')!;
  check(tomorrow.difference(today).inDays == 1, 'B 明天应等于今天 +1 天');
  expectAllOn(await run('B 相对词标题（明天）', '明天的TDL $body'), tomorrow,
      'B 整批归明天');

  // C 对照组：没标题，行为必须完全不变
  check(AiTdl.listDayOf(body) == null, 'C 纯时刻开头不应识别成标题日期');
  expectAllOn(await run('C 无标题（对照组）', body), today, 'C 整批仍归今天');

  // D 识别器反例：正文里的相对词 / 小数不能被当成整张单子的标题
  for (final String s in <String>[
    '明天下午三点开会',
    '复习上周的秀1.5h',
    '7:00起床洗漱',
    '今天先把报告交了',
  ]) {
    check(AiTdl.listDayOf(s) == null, 'D 不应识别成标题日期：$s');
  }

  // E 识别器正例
  check(fmt(AiTdl.listDayOf('11.5TDL x')).startsWith('2026-11-05'),
      'E 11.5TDL 应认出 11-05');
  check(AiTdl.listDayOf('2026-11-05 TDL') != null, 'E 带年份应认出');
  check(AiTdl.listDayOf('11月5日 TDL') != null, 'E 中文月日应认出');
  check(AiTdl.listDayOf('后天TDL')!.difference(today).inDays == 2,
      'E 后天应等于 +2 天');
  check(AiTdl.listDayOf('今天TDL')!.difference(today).inDays == 0,
      'E 今天应等于 +0 天');

  print('');
  print('通过 $passed 项，失败 $failed 项');
  if (failed > 0) throw StateError('TDL 标题日期回归测试失败 $failed 项');
  print('全部通过');
}
