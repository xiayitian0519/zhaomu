import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// 内置的智谱 API Key。
///
/// **留空的话「导入 TDL」会提示用户去设置里填自己的 Key。**
/// 要内置就把 key 字符串粘到这里（形如 `xxxxx.yyyyy`），
/// 然后在设置页把「用内置额度」开关打开。
///
/// ⚠️ 提醒：APK 能反编译，写在这里的 key 等于公开。
/// 所以内置 key 请去智谱后台设一个**每日额度上限**，别用主账号的无限额度 key。
const String kBuiltinKey = '';

/// 每天最多用几次（防 key 泄露被刷爆）。
const int kDailyLimit = 50;

/// AI 拆出来的一条待办。
class AiTodo {
  AiTodo({
    required this.title,
    this.due,
    this.priority = 'gray',
    this.repeat = 'none',
  }) : editableTitle = title;

  final String title;

  /// 预览页允许改日期，所以不是 final
  DateTime? due;

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

  static const String _systemPrompt = '''
你是一个待办拆解助手。用户会给你一段文字（TDL 清单、会议记录、聊天记录、备忘录都可能），
请把它拆成一条条独立的待办事项。

规则：
1. 每条只做一件事，不要把两件事合成一条
2. 标题精简到 20 字以内，去掉"记得""要""帮我""一下"这类废话，保留关键动作和对象
3. 能看出日期时间的，转成 ISO 8601（例：2026-11-05T15:00:00）；只看得出哪天就写 2026-11-05T00:00:00；看不出来写 null
4. 优先级按四象限判断：red=重要且紧急，yellow=重要不紧急，blue=不重要但紧急，gray=都不算或判断不出
5. 能看出重复规律的：daily / weekly / monthly / yearly，看不出写 none
6. 原文里的编号、符号、空行都忽略，只提取真正要做的事
7. 如果原文是一整段没有条理的文字，也要尽量拆出可执行的条目
8. 最多返回 100 条

只输出 JSON 数组，不要任何解释文字、不要 markdown 代码块标记。
格式：[{"title":"...","due":"2026-11-05T15:00:00","priority":"gray","repeat":"none"}]
''';

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
      throw AiException('今天的 $kDailyLimit 次已经用完了，明天再来。想接着用就在设置里填自己的 Key。');
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
              'messages': <Map<String, String>>[
                <String, String>{'role': 'system', 'content': _systemPrompt},
                <String, String>{'role': 'user', 'content': body},
              ],
            }),
          )
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw AiException('网络不通，检查一下是不是断网了。（$e）');
    }

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw AiException('这个 Key 不对或者过期了，去设置里换一个。');
    }
    if (resp.statusCode == 429) {
      throw AiException('调太快了，等一分钟再试。');
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

    final List<AiTodo> list = _parseContent(content);
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
  static List<AiTodo> _parseContent(String raw) {
    String s = raw.trim();
    // 去掉 markdown 代码块
    if (s.startsWith('```')) {
      final int firstNl = s.indexOf('\n');
      if (firstNl > 0) s = s.substring(firstNl + 1);
      if (s.endsWith('```')) s = s.substring(0, s.length - 3);
      s = s.trim();
    }
    // 只截第一个 [ 到最后一个 ]
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
      out.add(AiTodo(
        title: title.length > 60 ? title.substring(0, 60) : title,
        due: _parseIso((e['due'] ?? '').toString()),
        priority: const <String>['red', 'yellow', 'blue', 'gray'].contains(p)
            ? p
            : 'gray',
        repeat:
            const <String>['none', 'daily', 'weekly', 'monthly', 'yearly']
                    .contains(r)
                ? r
                : 'none',
      ));
    }
    return out;
  }

  static DateTime? _parseIso(String s) {
    if (s.isEmpty || s == 'null') return null;
    final DateTime? d = DateTime.tryParse(s);
    if (d == null) return null;
    // 模型偶尔会给 1970 这种明显错的
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
