/// 朝暮 · 数据模型与日期工具（纯 Dart，不依赖 Flutter）

/// 四象限优先级
class Priority {
  Priority._();

  static const int urgentImportant = 0; // 重要且紧急
  static const int importantNotUrgent = 1; // 重要不紧急
  static const int urgentNotImportant = 2; // 不重要但紧急
  static const int notUrgentNotImportant = 3; // 不重要不紧急
  static const int none = -1; // 未标

  static const List<String> names = <String>[
    '重要且紧急',
    '重要不紧急',
    '不重要但紧急',
    '不重要不紧急',
  ];

  /// 默认配色（ARGB）
  static const List<int> defaultColorValues = <int>[
    0xFFA32D2D, // 红
    0xFF854F0B, // 琥珀
    0xFF185FA5, // 蓝
    0xFF5F5E5A, // 灰
  ];

  static String nameOf(int p) {
    if (p >= 0 && p < names.length) return names[p];
    return '未标';
  }
}

/// 重复规则
class RepeatRule {
  RepeatRule._();

  /// 存储用的值 —— **别改这些字**。老存档里已经直接存着 '无' 这类字符串，
  /// 改了会让详情页的兜底逻辑把老数据悄悄改写成新值。
  static const List<String> all = <String>['无', '每天', '每周', '每月', '每年', custom];

  /// 「自定义」的存储键。规则本体在 [Todo.repeatDays]（每月几号的列表）
  static const String custom = '自定义';

  static const String none = '无';

  /// 界面上显示的文案。
  ///
  /// 「无」用户看不懂是啥意思（2026-10-16 用户原话：「用户第一时间不知道
  /// 这个是什么意思」），改成「仅今天」—— 一眼就懂这个字段管的是"要不要重复"。
  /// 选项本身（每天/每周/每月/每年）全部保留，只换「无」那一个的显示。
  static String labelOf(String r) => r == none ? '仅今天' : r;
}

/// 一条待办
class Todo {
  String id;
  String title;
  String note;
  DateTime? due; // 截止时间（可只到日）
  bool dueHasTime; // 截止时间是否精确到分
  DateTime? remind; // 提醒时间，null = 不提醒
  int priority; // Priority.*
  String listName; // 清单
  String repeat; // RepeatRule.*
  bool done;
  DateTime created;
  DateTime? doneAt;

  /// 这条待办单独提前多少分钟提醒；-1 = 跟随设置里的默认提前量
  int aheadMinutes;

  /// 「自定义」执行日期：每月哪几号（1~31，升序）。
  /// 只有 [repeat] == RepeatRule.custom 时才有意义；空列表 = 没配好。
  /// 2026-10-16 加：奇数日 / 偶数日 / 手选多个天号（用户原话）。
  List<int> repeatDays;

  /// 用户明确点了「不提醒」。
  ///
  /// 为什么非要有这个字段：光把 [remind] 置空是不够的 —— 排程里有一条兜底
  /// 「没设提醒时间、但截止带时刻 → 就用截止时刻提醒」（见 Notifier.scheduleFor），
  /// 所以在"截止带时刻"的待办上，光清空 remind 它照样会响。
  /// 这个开关的作用就是把那条兜底关掉。
  bool remindOff;

  Todo({
    required this.id,
    required this.title,
    this.note = '',
    this.due,
    this.dueHasTime = false,
    this.remind,
    this.priority = Priority.none,
    this.listName = '生活',
    this.repeat = RepeatRule.none,
    this.done = false,
    DateTime? created,
    this.doneAt,
    this.aheadMinutes = -1,
    this.remindOff = false,
    this.repeatDays = const <int>[],
  }) : created = created ?? DateTime.now();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'note': note,
        'due': due?.toIso8601String(),
        'dueHasTime': dueHasTime,
        'remind': remind?.toIso8601String(),
        'priority': priority,
        'list': listName,
        'repeat': repeat,
        'done': done,
        'created': created.toIso8601String(),
        'doneAt': doneAt?.toIso8601String(),
        'aheadMinutes': aheadMinutes,
        'remindOff': remindOff,
        'repeatDays': repeatDays,
      };

  factory Todo.fromJson(Map<String, dynamic> m) => Todo(
        id: '${m['id'] ?? ''}',
        title: '${m['title'] ?? ''}',
        note: '${m['note'] ?? ''}',
        due: _parseDt(m['due']),
        dueHasTime: m['dueHasTime'] == true,
        remind: _parseDt(m['remind']),
        priority: (m['priority'] is num) ? (m['priority'] as num).toInt() : Priority.none,
        listName: '${m['list'] ?? '生活'}',
        repeat: '${m['repeat'] ?? RepeatRule.none}',
        done: m['done'] == true,
        created: _parseDt(m['created']) ?? DateTime.now(),
        doneAt: _parseDt(m['doneAt']),
        aheadMinutes: (m['aheadMinutes'] is num) ? (m['aheadMinutes'] as num).toInt() : -1,
        remindOff: m['remindOff'] == true,
        repeatDays: _daysFromJson(m['repeatDays']),
      );

  Todo clone() => Todo.fromJson(toJson());

  /// repeatDays 兜底解析：只收 1~31 的整数，升序
  static List<int> _daysFromJson(Object? v) {
    if (v is List) {
      final List<int> r = v
          .whereType<num>()
          .map((num e) => e.toInt())
          .where((int d) => d >= 1 && d <= 31)
          .toList()
        ..sort();
      return r;
    }
    return const <int>[];
  }

  static DateTime? _parseDt(Object? v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}

/// TDL 时间表里的一段时间条（如 07:00-07:40 起床整理内务）
class TdlBlock {
  String id;
  int startMin; // 从 00:00 起的分钟数
  int endMin;
  String text;
  bool done;

  TdlBlock({
    required this.id,
    required this.startMin,
    required this.endMin,
    this.text = '',
    this.done = false,
  });

  int get minutes {
    final int m = endMin - startMin;
    return m > 0 ? m : 0;
  }

  String get rangeLabel => '${tdlLabel(startMin)}-${tdlLabel(endMin)}';

  /// 时长的中文说法：2h / 1h30m / 40m
  String get durationLabel {
    final int m = minutes;
    if (m <= 0) return '';
    final int h = m ~/ 60;
    final int mm = m % 60;
    if (h == 0) return '${mm}m';
    if (mm == 0) return '${h}h';
    return '${h}h${mm}m';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'start': startMin,
        'end': endMin,
        'text': text,
        'done': done,
      };

  factory TdlBlock.fromJson(Map<String, dynamic> m) => TdlBlock(
        id: '${m['id'] ?? ''}',
        startMin: (m['start'] is num) ? (m['start'] as num).toInt() : 0,
        endMin: (m['end'] is num) ? (m['end'] as num).toInt() : 0,
        text: '${m['text'] ?? ''}',
        done: m['done'] == true,
      );

  TdlBlock clone() => TdlBlock.fromJson(toJson());
}

/// 分钟数 -> HH:mm
String tdlLabel(int minutes) {
  int m = minutes % (24 * 60);
  if (m < 0) m += 24 * 60;
  final int h = m ~/ 60;
  final int mi = m % 60;
  return '${h < 10 ? '0$h' : '$h'}:${mi < 10 ? '0$mi' : '$mi'}';
}

// ---------------- 日期工具 ----------------
/// 取「日」——把时分秒抹掉
DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _two(int v) => v < 10 ? '0$v' : '$v';

/// 2026-10-12
String dateKey(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// 09:05
String timeLabel(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// 2026-10-12 09:05
String dateTimeLabel(DateTime d) => '${dateKey(d)} ${timeLabel(d)}';

/// 2026年10月12日
String dayLabel(DateTime d) => '${d.year}年${d.month}月${d.day}日';

/// 10月12日
String shortDayLabel(DateTime d) => '${d.month}月${d.day}日';

/// 10月12日 星期一
String headerDate(DateTime d) {
  const List<String> w = <String>['一', '二', '三', '四', '五', '六', '日'];
  return '${d.month}月${d.day}日 星期${w[d.weekday - 1]}';
}

/// 相对今天的说法
String relativeDayLabel(DateTime d) {
  final DateTime today = dayOf(DateTime.now());
  final int diff = dayOf(d).difference(today).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '明天';
  if (diff == 2) return '后天';
  if (diff == -1) return '昨天';
  if (diff < 0) return '逾期 ${-diff} 天';
  return shortDayLabel(d);
}

/// 「自定义」重复的显示文案：自定义 · 奇数日 / 偶数日 / 顿号天号列表。
String customRepeatLabel(List<int> days) {
  final List<int> d = days.toList()..sort();
  const List<int> odd = <int>[1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31];
  const List<int> even = <int>[2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30];
  bool same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  if (same(d, odd)) return '自定义 · 奇数日';
  if (same(d, even)) return '自定义 · 偶数日';
  if (d.isEmpty) return '自定义';
  return '自定义 · ${d.join('、')} 号';
}

/// 提前量的说法。整小时的说「1 小时」比「60 分钟」顺口；0 单独说成「到点提醒」。
String aheadLabel(int m) {
  if (m <= 0) return '到点提醒';
  if (m % 60 == 0) return '提前 ${m ~/ 60} 小时';
  return '提前 $m 分钟';
}

/// 主列表每条待办下面那行日期。
///
/// 1. 逾期 → `10月12日 · 逾期 4 天`（外面配红字）
/// 2. 其余 → `今天` / `明天` / `后天` / `10月20日`
/// 3. [hasTime] 为真时末尾接上 `18:00`
///
/// 用户 2026-10-16：「待办事项下方添加截止日期，不带具体时刻也要显示日期」——
/// 所以只要 due 不为空就一定出这行，有没有时刻只是多不多一段而已。
String listDueLabel(DateTime due, bool hasTime) {
  final DateTime d = dayOf(due);
  final int diff = d.difference(dayOf(DateTime.now())).inDays;
  final String when =
      diff < 0 ? '${shortDayLabel(d)} · 逾期 ${-diff} 天' : relativeDayLabel(d);
  return hasTime ? '$when ${timeLabel(due)}' : when;
}
