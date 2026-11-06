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
  static String _systemPrompt(DateTime? listDay) {
    final DateTime now = DateTime.now();
    const List<String> week = <String>[
      '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日',
    ];
    String two(int v) => v.toString().padLeft(2, '0');
    final String today =
        '${now.year}-${two(now.month)}-${two(now.day)} ${week[now.weekday - 1]}';
    final String listIso = listDay == null
        ? ''
        : '${listDay.year}-${two(listDay.month)}-${two(listDay.day)}';

    final DateTime monday = now.subtract(Duration(days: now.weekday - 1));
    final List<String> lines = <String>[];
    for (int i = 0; i < 7; i++) {
      final DateTime d = monday.add(Duration(days: i));
      final bool isToday =
          d.year == now.year && d.month == now.month && d.day == now.day;
      lines.add('  ${week[i]} ${two(d.month)}-${two(d.day)}'
          '${isToday ? '（今天）' : ''}');
    }

    // 2026-11-06：TDL 开头常写「11.5TDL」「明天的TDL」「周五TDL」，
    // 那是整张单子的归属日，不是某一行的时间。先前 prompt 没这个概念，
    // 模型只把带时刻的第一行归到那天，其余全按「今天」兜底。
    final String dayNote = listDay == null
        ? ''
        : '\n【这一段清单的归属日是 $listIso】\n'
            '用户在开头写了日期标题，意思是**下面整张单子都是这一天的事**。\n'
            '- 没写具体时刻的条目，due 一律写 $listIso'
            'T23:59:59，remind 写 null；不许写成今天，也不许写别的日期\n'
            '- 写了具体时刻的条目（如「7:00 起床」），也归 $listIso 这一天，时刻照写\n'
            '- 只有某一行自己明确写了另一个日期，那一行才用那个日期\n'
            '- 这一条优先级高于下面规则 3 里「没提时间就写今天」的默认说法\n';

    return '今天是 $today。\n'
        '本周的日期对照（算「周五」「下周一」这种就照这几行，别自己推）：\n'
        '${lines.join('\n')}\n'
        '$dayNote'
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
        '   - **原文没提时间的，due 写「清单归属日」的 T23:59:59（当日待办收尾）；'
        '上面没给归属日时才写今天的 T23:59:59。绝不许拿别的条目的时间凑**\n'
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
        '11. 【日期和时刻要分开看】开头那种「11.5TDL」「明天的TDL」「周五TDL」'
        '是整张单子的日期，所有条目都归这一天，不算把时间串味；'
        '而「7:00」这种时刻只属于它所在的那一行，绝对不许广播给别的条目\n'
        '12. 最多返回 100 条\n'
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

    // 2026-11-06：先看开头有没有「整张单子的日期标题」。
    // 有就把它同时塞进 prompt（让模型自己算对）和后面的兜底校正（双保险）。
    final DateTime? listDay = listDayOf(body);

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
                <String, String>{
                  'role': 'system',
                  'content': _systemPrompt(listDay),
                },
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

    final List<AiTodo> list = _parseContent(content, body, listDay);
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
  static List<AiTodo> _parseContent(
      String raw, String input, DateTime? listDay) {
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

    _fixBroadcast(out, input, listDay);

    // 用户 2026-11-05 定的规矩：没写时间的，一律当日截止 23:59、不提醒。
    // 2026-11-06 补：这里的「当日」是整张单子的归属日（标题写了 11.5 就是 11.5），
    // 不是「今天」。没标题时才退回今天。
    final DateTime end = _dayEnd(listDay ?? DateTime.now());
    for (final AiTodo t in out) {
      if (t.due == null) {
        t.due = end;
        t.remind = null;
      }
    }

    // 双保险：模型可能把没写时间的条目自己填成「今天 23:59:59」（旧 prompt 的习惯），
    // 而不是留 null。这种也要搬到归属日。
    _applyListDay(out, input, listDay);
    return out;
  }

  /// 某一天的 23:59:59
  static DateTime _dayEnd(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 整张单子的归属日一致性校正。
  ///
  /// 只搬「被算成今天、且没有具体时刻」的条目：
  /// 1. 带时刻的（7:00）可能是模型按某行真实时间算的，不动，避免误伤
  /// 2. 模型已经填成归属日的，不动
  /// 3. 明确写了别的日期（如「周五前」），不动
  /// 4. 原文里出现「今天/今日/本日」→ 整批不校正，保留模型判断
  static void _applyListDay(
      List<AiTodo> todos, String input, DateTime? listDay) {
    if (listDay == null) return;
    final DateTime today = DateTime.now();
    if (_sameDay(listDay, today)) return; // 归属日就是今天，无需动
    if (RegExp(r'今天|今日|本日|当天').hasMatch(input)) return;

    final DateTime target = _dayEnd(listDay);
    for (final AiTodo t in todos) {
      final DateTime? d = t.due;
      if (d == null) continue;
      if (_sameDay(d, listDay)) continue;
      final bool isToday = _sameDay(d, today);
      final bool noClock = d.hour == 23 && d.minute == 59 && d.second == 59;
      if (isToday && noClock) {
        t.due = target;
        t.remind = null;
      }
    }
  }

  /// 认 TDL 开头的日期标题，返回整张单子的归属日；没写返回 null。
  ///
  /// 只认**开头 24 个字符内**且紧跟 TDL / 清单 / 待办等词的写法，
  /// 避免把正文里的「明天下午三点开会」误当成整张单子的日期。
  /// 支持：11.5TDL / 11月5日 TDL / 2026-11-05 TDL / 明天的TDL /
  /// 后天TDL / 周五TDL / 下周一TDL / 今天TDL。
  static DateTime? listDayOf(String input) {
    final DateTime now = DateTime.now();
    final String head = input.trim().substring(
        0, input.trim().length > 28 ? 28 : input.trim().length);
    final String h = head.replaceAll(RegExp(r'\s+'), '');

    // 相对说法：明天 / 后天 / 大后天 / 今天 / 今日
    final RegExp rel = RegExp(
        r'^(明天|明日|后天|大后天|今天|今日|今日份|明儿)(?:的)?'
        r'(?=TDL|tdl|Tdl|清单|待办|计划|TO|to|[:：,，、.。]|$)');
    final RegExpMatch? rm = rel.firstMatch(h);
    if (rm != null) {
      final String w = rm.group(1) ?? '';
      final int delta = w == '后天'
          ? 2
          : w == '大后天'
              ? 3
              : (w == '今天' || w == '今日' || w == '今日份')
                  ? 0
                  : 1;
      return DateTime(now.year, now.month, now.day + delta);
    }

    // 周几 / 下周几
    final RegExp wk = RegExp(
        r'^(下|本|这)?(?:周|星期|礼拜)([一二三四五六日天])'
        r'(?:的)?(?=TDL|tdl|清单|待办|计划|TO|to|[:：,，、.。]|$)');
    final RegExpMatch? wm = wk.firstMatch(h);
    if (wm != null) {
      const Map<String, int> cn = <String, int>{
        '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6,
        '日': 7, '天': 7,
      };
      final int target = cn[wm.group(2)] ?? 0;
      if (target == 0) return null;
      int delta = target - now.weekday;
      if (wm.group(1) == '下') delta += 7;
      // 「周五」若已过去，通常指下周五
      if (delta < 0) delta += 7;
      return DateTime(now.year, now.month, now.day + delta);
    }

    // 具体日期：2026-11-05 / 11.5 / 11月5日 / 11/5
    final RegExp dm = RegExp(
        r'^(?:(\d{4})[-/.年])?(\d{1,2})[-/.月](\d{1,2})(?:日|号)?'
        r'(?=TDL|tdl|Tdl|清单|待办|计划|TO|to|[:：,，、.。]|$)');
    final RegExpMatch? mm = dm.firstMatch(h);
    if (mm != null) {
      final int? y = mm.group(1) == null ? null : int.tryParse(mm.group(1)!);
      final int? mo = int.tryParse(mm.group(2) ?? '');
      final int? da = int.tryParse(mm.group(3) ?? '');
      if (mo == null || da == null || mo < 1 || mo > 12 || da < 1 || da > 31) {
        return null;
      }
      // 没写年份：取最近的那个。今年已经过去很久（>30 天）才顺延到明年，
      // 避免把「昨天/上周」的单子推到明年去。
      int year = y ?? now.year;
      if (y == null) {
        final DateTime d = DateTime(year, mo, da);
        if (now.difference(d).inDays > 30) year += 1;
      }
      return DateTime(year, mo, da);
    }
    return null;
  }

  /// 把「一处时间被复制到所有条目」这种错改回来。
  ///
  /// 判据：原文里某个 HH:MM 只出现了一次，但结果里有多条用了同一个时刻
  /// -> 说明是串味了，第一条留着，其余退回当日截止 + 不提醒。
  /// 只认这一种情况，别的时间一律不动，避免误伤「真的有好几条同一时间」。
  static void _fixBroadcast(
      List<AiTodo> todos, String input, DateTime? listDay) {
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
        // 串味退回「当日截止」，这个当日同样跟随整张单子的归属日
        t.due = _dayEnd(listDay ?? DateTime.now());
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
