import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// 内置的智谱 API Key（2026-11-04 用户提供，实测 glm-4-flash 可用）。
///
/// ⚠️ APK 能反编译，这把 key 等于公开。用户已知悉并接受。
/// 如果被人刷爆，去 bigmodel.cn 控制台删掉重建，再改这里的字符串重新打包。
const String kBuiltinKey = '7ffa4a4a18be4ae196c2f043966f5723.nAEnlVxpjKwcrTKc';

/// 每天最多用几次（防 key 泄露被刷爆）。
const int kDailyLimit = 50;

/// AI 拆出来的一条待办。
class AiTodo {
  AiTodo({
    required this.title,
    this.due,
    this.priority = 'gray',
    this.repeat = 'none',
    this.remind,
    this.note = '',
  }) : editableTitle = title;

  final String title;

  /// 预览页允许改日期，所以不是 final
  DateTime? due;

  /// 提醒时间（null = 不提醒）。预览页可改。
  DateTime? remind;

  /// 备注：原文里除动作外的补充信息（带什么、找谁、注意事项）。预览页可改。
  String note;

  /// red / yellow / blue / gray
  String priority;

  /// none / daily / weekly / monthly / yearly
  String repeat;

  /// 用户勾选状态（预览页用）
  bool picked = true;

  /// 详情里能改标题
  String editableTitle;

  bool get hasDue => due != null;
}

/// AI 拆解结果。
class AiParseResult {
  AiParseResult({required this.todos, required this.usedCount, required this.left});

  final List<AiTodo> todos;

  /// 这次之后已经用了几次
  final int usedCount;

  /// 今天还剩几次
  final int left;
}

/// AI 相关异常，带一句能直接显示给用户的话。
class AiException implements Exception {
  AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiTdl {
  AiTdl._();

  static const String _endpoint =
      'https://open.bigmodel.cn/api/paas/v4/chat/completions';

  /// 每次调用现拼 prompt。
  ///
  /// **必须带上「今天几号 + 本周每天是几号」**，否则模型不知道今天，
  /// 会把「明天」算成训练数据里的日期（2026-11-04 实测：不注入今天时
  /// glm-4-flash 把「明天下午三点」算成了 2023-04-14T15:00:00）。
  /// 注入周表之后「明天下午三点」能正确算成次日 15:00。
  static String _systemPrompt() {
    final DateTime now = DateTime.now();
    const List<String> week = <String>[
      '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日',
    ];
    String two(int v) => v.toString().padLeft(2, '0');
    final String today =
        '${now.year}-${two(now.month)}-${two(now.day)} ${week[now.weekday - 1]}';

    final DateTime monday = now.subtract(Duration(days: now.weekday - 1));
    final List<String> lines = <String>[];
    for (int i = 0; i < 7; i++) {
      final DateTime d = monday.add(Duration(days: i));
      final bool isToday =
          d.year == now.year && d.month == now.month && d.day == now.day;
      lines.add('  ${week[i]} ${two(d.month)}-${two(d.day)}'
          '${isToday ? '（今天）' : ''}');
    }

    return '今天是 $today。\n'
        '本周的日期对照（算「周五」「下周一」这种就照这几行，别自己推）：\n'
        '${lines.join('\n')}\n'
        '\n'
        '你是一个待办拆解助手。用户会给你一段文字（TDL 清单、会议记录、聊天记录、备忘录都可能），\n'
        '请把它拆成一条条独立的待办事项。\n'
        '\n'
        '规则：\n'
        '1. 每条只做一件事，不要把两件事合成一条\n'
        '2. 标题精简到 20 字以内，去掉「记得」「要」「帮我」「一下」「还有」这类废话，'
        '也去掉时间前缀和「提醒我」「叫我」这类词，只留动作和对象\n'
        '3. 只有原文明确说了日期或时间的才填 due，否则一律写 null，绝对不许猜：\n'
        '   - 说了几点就带几点（「明天下午三点」→ 明天那天的 T15:00:00）\n'
        '   - 只说了哪天就写那天的 T00:00:00\n'
        '   - 「周五前」「月底前」这种最后期限，写那天的 T23:59:59\n'
        '   - 只有重复规律（每天/每周）没具体日期的，due 写 null\n'
        '   - **原文没提时间的，due 写今天的 T23:59:59（当今日待办收尾），'
        '绝不许拿别的条目的时间凑**\n'
        '4. 优先级按四象限判断：red=重要且紧急，yellow=重要不紧急，'
        'blue=不重要但紧急，gray=都不算或判断不出\n'
        '5. 能看出重复规律的：daily / weekly / monthly / yearly，看不出写 none\n'
        '6. 原文里的编号、符号、空行都忽略，只提取真正要做的事\n'
        '7. 【重要】原文常常不标序号、不换行，几件事全挤在一句话或一段话里，'
        '例如「今晚九点开会明早交报告后天体检」这种。你必须按语义把它拆成独立条目，'
        '不要因为原文没有 1. 2. 3. 就返回一条\n'
        '8. 提醒时间 remind 的填法（**注意：提前多少分钟只影响 remind，绝不影响 due**）：\n'
        '   - 原文写了「提前十分钟提醒」→ **due 还是原来那个时间**，remind = due 往前推十分钟。'
        '例如「今晚九点提前五分钟提醒」→ due 是当天 T21:00:00，remind 是当天 T20:55:00\n'
        '   - 原文写了「八点叫我」「提醒我一下」→ 按原意算\n'
        '   - **原文没提提醒，但待办有具体时刻（due 带时分，比如「今晚九点开会」）'
        '→ remind 填成和 due 一样（准时提醒）**\n'
        '   - due 只有日期没有时刻（比如「周五前交报告」）→ remind 写 null\n'
        '   - 完全没有时间 → remind 写 null\n'
        '9. 原文里除了动作之外的补充信息（带什么东西、找谁、金额、地址、注意事项），'
        '整理成一句话放 note；没有就写空字符串\n'
        '10. 【最容易错的一条，务必看】时间只属于它所在的那一行。'
        '如果原文是「7:30起床洗漱」下面再跟着好几行没有时间的（去校区、拍视频、做项目…），'
        '那个 7:30 只属于「起床洗漱」这一条，后面每一行都**不许继承、不许补成同一个时间**。'
        '只有当某一行自己写了时间，那一行才带时间\n'
        '11. 最多返回 100 条\n'
        '\n'
        '示例（假设今天 2026-11-04 星期三）：\n'
        '- 「今晚九点提前五分钟提醒我参加仓库管理系统项目会议」→ {"title":"参加仓库管理系统项目会议",'
        '"due":"2026-11-04T21:00:00","priority":"yellow","repeat":"none",'
        '"remind":"2026-11-04T20:55:00","note":""}\n'
        '- 「每天早上背单词」→ {"title":"背单词","due":null,"priority":"blue",'
        '"repeat":"daily","remind":null,"note":""}\n'
        '- 「周五前交报告，带上上季度数据」→ {"title":"交报告",'
        '"due":"2026-11-06T23:59:59","priority":"red","repeat":"none",'
        '"remind":null,"note":"带上上季度数据"}\n'
        '- 「把房租交了，3200」→ {"title":"交房租","due":null,"priority":"gray",'
        '"repeat":"none","remind":null,"note":"3200"}\n'
        '- 「明天下午三点开会，提前十分钟提醒我」→ {"title":"开会",'
        '"due":"2026-11-05T15:00:00","priority":"gray","repeat":"none",'
        '"remind":"2026-11-05T14:50:00","note":""}\n'
        '- 「7:30起床整理内务洗漱（换行）去校区（换行）拍消防员视频」→ 三条：'
        '{"title":"起床整理内务洗漱","due":"2026-11-04T07:30:00","priority":"gray",'
        '"repeat":"none","remind":"2026-11-04T07:30:00","note":""}、'
        '{"title":"去校区","due":"2026-11-04T23:59:59","priority":"gray",'
        '"repeat":"none","remind":null,"note":""}、'
        '{"title":"拍消防员视频","due":"2026-11-04T23:59:59","priority":"gray",'
        '"repeat":"none","remind":null,"note":""}\n'
        '\n'
        '只输出 JSON 数组，不要任何解释文字、不要 markdown 代码块标记。\n'
        '格式：[{"title":"...","due":"2026-11-05T15:00:00","priority":"gray",'
        '"repeat":"none","remind":null,"note":""}]';
  }

  /// 拆解一段文字。调用方要先把 key 和剩余次数准备好。
  static Future<AiParseResult> parse({
    required String text,
    required String apiKey,
    required int usedToday,
  }) async {
    final String key = apiKey.trim();
    if (key.isEmpty) {
      throw AiException('AI 还没配好：代码里的内置 Key 是空的。需要把智谱的 key 写进 lib/ai_tdl.dart 的 kBuiltinKey 再重新打包。');
    }
    if (usedToday >= kDailyLimit) {
      throw AiException('今天的 $kDailyLimit 次已经用完了，明天再来。');
    }
    final String body = text.trim();
    if (body.isEmpty) {
      throw AiException('先粘一段文字进来。');
    }
    if (body.length > 8000) {
      throw AiException('太长了（${body.length} 字），一次最多 8000 字。分批粘吧。');
    }

    final http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: <String, String>{
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'model': 'glm-4-flash',
              'temperature': 0.2,
              'max_tokens': 2000,
              'messages': <Map<String, String>>[
                <String, String>{'role': 'system', 'content': _systemPrompt()},
                <String, String>{'role': 'user', 'content': body},
              ],
            }),
          )
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      throw AiException('网络不通，检查一下是不是断网了。（$e）');
    }

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw AiException('内置 Key 不对或者过期了，要重新换一把。');
    }
    if (resp.statusCode == 429) {
      throw AiException('调太快了（模型限流），等一分钟再试。');
    }
    if (resp.statusCode != 200) {
      throw AiException('接口返回 ${resp.statusCode}，稍后再试。');
    }

    String content;
    try {
      final Map<String, dynamic> o =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final List<dynamic> choices = o['choices'] as List<dynamic>;
      content = (choices.first as Map<String, dynamic>)['message']['content']
          as String;
    } catch (e) {
      throw AiException('接口返回的东西看不懂，稍后再试。');
    }

    final List<AiTodo> list = _parseContent(content, body);
    if (list.isEmpty) {
      throw AiException('这段文字里没找出能当待办的东西，再多写点？');
    }
    return AiParseResult(
      todos: list,
      usedCount: usedToday + 1,
      left: kDailyLimit - usedToday - 1,
    );
  }

  /// 模型有时候会包 ```json 或者加前言，这里都兜住。
  ///
  /// [input] 是用户原文，用来查「某个时刻在原文里到底出现了几次」——
  /// 模型的经典毛病是把开头的「7:30」广播给后面所有没有时间的条目。
  static List<AiTodo> _parseContent(String raw, String input) {
    String s = raw.trim();
    if (s.startsWith('```')) {
      final int firstNl = s.indexOf('\n');
      if (firstNl > 0) s = s.substring(firstNl + 1);
      if (s.endsWith('```')) s = s.substring(0, s.length - 3);
      s = s.trim();
    }
    final int lb = s.indexOf('[');
    final int rb = s.lastIndexOf(']');
    if (lb >= 0 && rb > lb) s = s.substring(lb, rb + 1);

    List<dynamic> arr;
    try {
      arr = jsonDecode(s) as List<dynamic>;
    } catch (_) {
      return <AiTodo>[];
    }

    final List<AiTodo> out = <AiTodo>[];
    for (final dynamic e in arr) {
      if (e is! Map<String, dynamic>) continue;
      final String title = (e['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      final String p = (e['priority'] ?? 'gray').toString();
      final String r = (e['repeat'] ?? 'none').toString();
      final String nt = (e['note'] ?? '').toString().trim();
      final DateTime? dueAt = _parseIso((e['due'] ?? '').toString());
      DateTime? remindAt = _parseIso((e['remind'] ?? '').toString());
      // 2026-11-04：只有日期（00:00）的截止时间不该有提醒。
      // AI 在多条连在一起时会把上一条的「提前五分钟」串到这一条，给个 00:00 的提醒，
      // 实际就是凌晨响，纯噪音。这里强制清掉。
      if (dueAt != null && dueAt.hour == 0 && dueAt.minute == 0) {
        remindAt = null;
      }

      // 兜底：用户 2026-11-04 要求「没写什么时候提醒就准时提醒」。
      // AI 偶尔会漏填，这里补上：有精确时刻的截止时间、又没提醒 -> 就在截止那一刻提醒。
      // 2026-11-05 补一条：23:59:59 表示「当日截止」，不是真的时刻，
      // 给它补提醒等于半夜叫醒人，必须排除。
      if (remindAt == null &&
          dueAt != null &&
          (dueAt.hour != 0 || dueAt.minute != 0) &&
          !(dueAt.hour == 23 && dueAt.minute >= 59)) {
        remindAt = dueAt;
      }
      out.add(AiTodo(
        title: title.length > 60 ? title.substring(0, 60) : title,
        due: dueAt,
        priority: const <String>['red', 'yellow', 'blue', 'gray'].contains(p)
            ? p
            : 'gray',
        repeat:
            const <String>['none', 'daily', 'weekly', 'monthly', 'yearly']
                    .contains(r)
                ? r
                : 'none',
        remind: remindAt,
        note: nt.length > 200 ? nt.substring(0, 200) : nt,
      ));
    }

    _fixBroadcast(out, input);

    // 用户 2026-11-05 定的规矩：没写时间的，一律当「今日待办」，截止 23:59，不设提醒。
    for (final AiTodo t in out) {
      if (t.due == null) {
        t.due = _todayEnd();
        t.remind = null;
      }
    }
    return out;
  }

  /// 今天 23:59:59
  static DateTime _todayEnd() {
    final DateTime n = DateTime.now();
    return DateTime(n.year, n.month, n.day, 23, 59, 59);
  }

  /// 把「一处时间被复制到所有条目」这种错改回来。
  ///
  /// 判据：原文里某个 HH:MM 只出现了一次，但结果里有多条用了同一个时刻
  /// -> 说明是串味了，第一条留着，其余退回当日截止 + 不提醒。
  /// 只认这一种情况，别的时间一律不动，避免误伤「真的有好几条同一时间」。
  static void _fixBroadcast(List<AiTodo> todos, String input) {
    if (todos.length < 2) return;

    final Map<String, int> inText = <String, int>{};
    final RegExp re = RegExp(r'(\d{1,2})\s*[:：]\s*(\d{2})');
    for (final RegExpMatch m in re.allMatches(input)) {
      final int h = int.tryParse(m.group(1) ?? '') ?? -1;
      final int mi = int.tryParse(m.group(2) ?? '') ?? -1;
      if (h < 0 || h > 23 || mi < 0 || mi > 59) continue;
      final String k = '$h:${mi.toString().padLeft(2, '0')}';
      inText[k] = (inText[k] ?? 0) + 1;
    }
    if (inText.isEmpty) return;

    final Map<String, int> used = <String, int>{};
    for (final AiTodo t in todos) {
      final DateTime? d = t.due;
      if (d == null) continue;
      if (d.hour == 0 && d.minute == 0) continue;
      final String k = '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
      final int seen = (used[k] ?? 0) + 1;
      used[k] = seen;
      if ((inText[k] ?? 0) <= 1 && seen > 1) {
        t.due = _todayEnd();
        t.remind = null;
      }
    }
  }

  static DateTime? _parseIso(String s) {
    if (s.isEmpty || s == 'null') return null;
    final DateTime? d = DateTime.tryParse(s);
    if (d == null) return null;
    if (d.year < 2000 || d.year > 2100) return null;
    return d;
  }

  /// 把 AI 的 priority 字面值转成 Priority 常量。
  static int priorityOf(String p) => const <String, int>{
        'red': Priority.urgentImportant,
        'yellow': Priority.importantNotUrgent,
        'blue': Priority.urgentNotImportant,
        'gray': Priority.notUrgentNotImportant,
      }[p] ??
      Priority.none;

  /// 转成 RepeatRule 的存储值（中文字面量，见 models.dart 的说明）。
  static String repeatOf(String r) => const <String, String>{
        'daily': '每天',
        'weekly': '每周',
        'monthly': '每月',
        'yearly': '每年',
      }[r] ??
      RepeatRule.none;

  /// 给预览页显示优先级的中文名。
  static String priorityLabel(String p) => const <String, String>{
        'red': '重要且紧急',
        'yellow': '重要不紧急',
        'blue': '不重要但紧急',
        'gray': '都不算',
      }[p] ??
      '都不算';
}
