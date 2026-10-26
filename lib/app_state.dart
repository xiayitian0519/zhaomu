import 'package:flutter/material.dart';

import 'models.dart';
import 'store.dart';

/// 一组待办。2026-10-16 起主列表改成「逾期 / 各个月份 / 未定日期」。
class TodoGroup {
  const TodoGroup(
    this.title,
    this.colorValue,
    this.items, {
    this.pinTitle,
    this.pinItems,
  });

  final String title;
  final int colorValue;
  final List<Todo> items;

  /// 组内单独拎出来的「今日」小卡片（用户 2026-10-16 选的方案 C），只有本月组会用到。
  ///
  /// [pinItems] 非空时，主列表在组标题下面先画这张卡片（带 [pinTitle] 小标题），
  /// 空一行，再画 [items] —— 这就是用户要的「空一行 + 突出今日待办」。
  final String? pinTitle;
  final List<Todo>? pinItems;
}

/// 全局状态。单例，改动后调用 [save] 落盘。
class AppState extends ChangeNotifier {
  AppState._();

  static final AppState I = AppState._();

  final List<Todo> todos = <Todo>[];
  final List<String> lists = <String>['工作', '生活', '学习'];
  List<int> quadrantColorValues = List<int>.from(Priority.defaultColorValues);

  /// 'time' 按时间  |  'priority' 按优先级
  String sortMode = 'time';

  /// true = 已完成只变灰、不加删除线（晚上复盘用）
  bool noStrike = false;

  /// 几点之后记的待办算明天（默认 00:00 = 不偏移）
  int dayStartHour = 0;
  int dayStartMinute = 0;

  /// 每日感想：dateKey -> 文本
  final Map<String, String> reviewNotes = <String, String>{};

  /// 历史记录页的筛选方式：'month' | 'months' | 'year'
  String historyMode = 'month';

  /// historyMode == 'months' 时用户选中的月份（dateKey 的 'YYYY-MM' 形式）
  final Set<String> historyMonths = <String>{};

  /// historyMode == 'year' 时选中的年份
  int historyYear = DateTime.now().year;

  /// TDL 时间表：dateKey -> 时间段列表
  final Map<String, List<TdlBlock>> tdlBlocks = <String, List<TdlBlock>>{};

  /// TDL 默认一天从几点开始 / 到几点结束（分钟数）
  int tdlStartMin = 7 * 60;
  int tdlEndMin = 23 * 60;

  /// TDL 刻度：任意分钟数（不再限死 15/30/60）
  int tdlStep = 60;

  /// TDL 刻度的常用预设（设置页给快捷按钮用）
  static const List<int> tdlStepPresets = <int>[5, 10, 15, 20, 30, 45, 60, 90, 120, 180];

  /// 默认提醒开关：提醒到点时响不响铃。
  ///
  /// 默认 **true**（打开）。关掉之后就只弹横幅 + 震动，不出声。
  /// 单条待办可以在详情页里单独覆盖。
  bool defaultRemindOn = true;

  /// 「默认打开铃声」的迁移标记。true 之后就不再被迁移逻辑覆盖。
  bool remindOnMigrated = false;

  /// 默认提前多少分钟提醒（0 = 到点提醒）
  /// 提醒默认提前量，单位分钟。2026-10-16 起默认 1 小时（原来是 0 = 到点提醒）。
  ///
  /// ⚠️ 只影响新装 / 从没改过这项的存档：老存档里已经存着 0，
  /// 读回来还是 0（见 [_read]）。0 是合法值，分不清"没设过"和"特意要到点"，
  /// 所以不做自动迁移 —— 要改在「设置 → 提前多久提醒」里选。
  int defaultAheadMinutes = 60;

  /// 提醒形态：RemindStyle.banner / RemindStyle.fullScreen
  String remindStyle = 'banner';

  /// 全局默认铃声（见 SoundLibrary）。
  ///
  /// 空字符串 = 系统默认通知音。没单独设过铃声的待办都响这个。
  /// 2026-10-23 加，老存档没有这个键 → 读成空 → 系统默认音，不用迁移。
  String defaultSoundId = '';

  /// 最后一次弹出「今天都做完了」的日期，避免反复打扰
  String lastReviewPrompt = '';

  /// 首次权限引导走过没有。false = 启动就进引导页
  bool onboarded = false;

  /// 界面功能引导（压暗 + 高亮 + 气泡那套）看过没有。
  /// false = 进主页后自动放一次（见 lib/guide.dart）。
  bool guideDone = false;

  /// 上次见过更新弹窗的完整版本号（如 '2.13.0+15'）。
  /// 和当前版本不一致 → 首次打开弹一次更新内容（见 updates.dart）。
  String lastSeenVersion = '';

  /// 日历页：下面的「当日待办」列表有没有折叠起来。
  ///
  /// 折叠时那块区域收掉，日历格子就能撑高、每格多显示几行待办。
  /// 存在这里是为了重启后还记着用户的选择。
  bool calendarListCollapsed = false;

  /// 主页「逾期」组折叠起来没有（折叠成一行「逾期 · N 条未完成」）。
  /// 存这里是为了重启后还记着。
  bool overdueCollapsed = false;

  bool loaded = false;

  int _seq = 0;

  // ---------------- 载入 / 保存 ----------------

  Future<void> load() async {
    final Map<String, dynamic>? m = await Store.read();
    if (m != null) _consume(m);
    loaded = true;
    notifyListeners();
  }

  void _consume(Map<String, dynamic> m) {
    final List<dynamic> rawTodos =
        (m['todos'] is List) ? (m['todos'] as List<dynamic>) : <dynamic>[];
    todos
      ..clear()
      ..addAll(rawTodos.whereType<Map<String, dynamic>>().map(Todo.fromJson));

    final List<dynamic> rawLists =
        (m['lists'] is List) ? (m['lists'] as List<dynamic>) : <dynamic>[];
    if (rawLists.isNotEmpty) {
      lists
        ..clear()
        ..addAll(rawLists.map((dynamic e) => '$e'));
    }

    final List<dynamic> rawColors =
        (m['quadrantColors'] is List) ? (m['quadrantColors'] as List<dynamic>) : <dynamic>[];
    if (rawColors.length == 4) {
      quadrantColorValues = rawColors.map((dynamic e) {
        if (e is num) return e.toInt();
        return 0xFF9E9E9E;
      }).toList();
    }

    if (m['sortMode'] is String) sortMode = m['sortMode'] as String;
    if (m['noStrike'] is bool) noStrike = m['noStrike'] as bool;
    if (m['historyMode'] is String) historyMode = m['historyMode'] as String;
    if (m['historyYear'] is num) historyYear = (m['historyYear'] as num).toInt();

    final Object? rawMonths = m['historyMonths'];
    if (rawMonths is List) {
      historyMonths
        ..clear()
        ..addAll(rawMonths.map((dynamic e) => '$e'));
    }

    final Object? rawTdl = m['tdl'];
    if (rawTdl is Map) {
      tdlBlocks.clear();
      rawTdl.forEach((dynamic k, dynamic v) {
        if (v is List) {
          tdlBlocks['$k'] =
              v.whereType<Map<String, dynamic>>().map(TdlBlock.fromJson).toList();
        }
      });
    }
    if (m['tdlStartMin'] is num) tdlStartMin = (m['tdlStartMin'] as num).toInt();
    if (m['tdlEndMin'] is num) tdlEndMin = (m['tdlEndMin'] as num).toInt();
    if (m['tdlStep'] is num) {
      final int v = (m['tdlStep'] as num).toInt();
      // 老存档里可能是非法值，兜一下
      tdlStep = (v < 1 || v > 720) ? 60 : v;
    }
    // 「默认打开铃声」的开关。
    //
    // 2.7.4 起默认值改成 **打开**（以前默认关，用户反馈说装完不响很困惑）。
    // 老存档里存着那个「默认关」的值，这里做一次一次性迁移：
    // 只要存档里没有 remindOnMigrated 标记，就当成老数据，强制改成打开。
    // 之后用户自己关掉，就会带上标记存下来，不再被迁移覆盖。
    final bool migrated = m['remindOnMigrated'] is bool && (m['remindOnMigrated'] as bool);
    if (!migrated) {
      defaultRemindOn = true;
      remindOnMigrated = true;
    } else if (m['defaultRemindOn'] is bool) {
      defaultRemindOn = m['defaultRemindOn'] as bool;
    }
    if (m['defaultAheadMinutes'] is num) {
      final int v = (m['defaultAheadMinutes'] as num).toInt();
      defaultAheadMinutes = v < 0 ? 0 : (v > 1440 ? 1440 : v);
    }
    if (m['remindStyle'] is String) {
      final String v = m['remindStyle'] as String;
      remindStyle = (v == 'fullscreen') ? 'fullscreen' : 'banner';
    }
    // 字段只为存档兼容保留：2026-10-23 晚起铃声统一交给系统渠道，
    // App 内不再有铃声库，读进来原样存着不再使用。
    if (m['defaultSoundId'] is String) {
      defaultSoundId = m['defaultSoundId'] as String;
    }
    if (m['calendarListCollapsed'] is bool) {
      calendarListCollapsed = m['calendarListCollapsed'] as bool;
    }
    if (m['overdueCollapsed'] is bool) {
      overdueCollapsed = m['overdueCollapsed'] as bool;
    }
    if (m['lastSeenVersion'] is String) {
      lastSeenVersion = m['lastSeenVersion'] as String;
    }
    if (m['dayStartHour'] is num) {
      final int v = (m['dayStartHour'] as num).toInt();
      dayStartHour = v < 0 ? 0 : (v > 23 ? 23 : v);
    }
    if (m['dayStartMinute'] is num) {
      final int v = (m['dayStartMinute'] as num).toInt();
      dayStartMinute = v < 0 ? 0 : (v > 59 ? 59 : v);
    }

    final Object? rawNotes = m['reviewNotes'];
    if (rawNotes is Map) {
      reviewNotes
        ..clear()
        ..addAll(rawNotes.map((dynamic k, dynamic v) => MapEntry<String, String>('$k', '$v')));
    }

    if (m['lastReviewPrompt'] is String) {
      lastReviewPrompt = m['lastReviewPrompt'] as String;
    }
    if (m['onboarded'] is bool) onboarded = m['onboarded'] as bool;
    if (m['guideDone'] is bool) guideDone = m['guideDone'] as bool;
  }

  Map<String, dynamic> toData() => <String, dynamic>{
        'app': '朝暮',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'todos': todos.map((Todo e) => e.toJson()).toList(),
        'lists': lists,
        'quadrantColors': quadrantColorValues,
        'sortMode': sortMode,
        'noStrike': noStrike,
        'dayStartHour': dayStartHour,
        'dayStartMinute': dayStartMinute,
        'reviewNotes': reviewNotes,
        'lastReviewPrompt': lastReviewPrompt,
        'onboarded': onboarded,
        'guideDone': guideDone,
        'calendarListCollapsed': calendarListCollapsed,
        'overdueCollapsed': overdueCollapsed,
        'lastSeenVersion': lastSeenVersion,
        'remindOnMigrated': remindOnMigrated,
        'historyMode': historyMode,
        'historyMonths': historyMonths.toList(),
        'historyYear': historyYear,
        'tdl': tdlBlocks.map(
          (String k, List<TdlBlock> v) =>
              MapEntry<String, List<Map<String, dynamic>>>(k, v.map((TdlBlock e) => e.toJson()).toList()),
        ),
        'tdlStartMin': tdlStartMin,
        'tdlEndMin': tdlEndMin,
        'tdlStep': tdlStep,
        'defaultRemindOn': defaultRemindOn,
        'defaultAheadMinutes': defaultAheadMinutes,
        'remindStyle': remindStyle,
        'defaultSoundId': defaultSoundId,
      };

  Future<void> save() async {
    await Store.write(toData());
  }

  /// 导入：整体替换
  Future<bool> applyData(Map<String, dynamic> m) async {
    if (!m.containsKey('todos')) return false;
    _consume(m);
    notifyListeners();
    await save();
    return true;
  }

  // ---------------- 基础操作 ----------------

  String newId() {
    _seq++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_seq';
  }

  Color colorOf(int p) {
    if (p < 0 || p >= quadrantColorValues.length) return const Color(0xFFBDBDBD);
    return Color(quadrantColorValues[p]);
  }

  String get defaultListName => lists.isNotEmpty ? lists.first : '生活';

  /// 快速添加默认落到哪一天（考虑「几点之后算明天」）
  DateTime defaultDay() {
    final DateTime n = DateTime.now();
    final int minutes = n.hour * 60 + n.minute;
    final int start = dayStartHour * 60 + dayStartMinute;
    if (start > 0 && minutes >= start) {
      return dayOf(n.add(const Duration(days: 1)));
    }
    return dayOf(n);
  }

  Todo? byId(String id) {
    for (final Todo t in todos) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<Todo> add(
    String title, {
    DateTime? due,
    int priority = Priority.none,
    String? listName,
  }) async {
    final Todo t = Todo(
      id: newId(),
      title: title.trim(),
      due: due ?? defaultDay(),
      priority: priority,
      listName: listName ?? defaultListName,
    );
    todos.insert(0, t);
    notifyListeners();
    await save();
    return t;
  }

  Future<void> update(Todo t) async {
    notifyListeners();
    await save();
  }

  Future<void> setSortMode(String mode) async {
    sortMode = mode;
    notifyListeners();
    await save();
  }

  Future<void> setNoStrike(bool value) async {
    noStrike = value;
    notifyListeners();
    await save();
  }

  Future<void> setDayStart(int hour, int minute) async {
    dayStartHour = hour < 0 ? 0 : (hour > 23 ? 23 : hour);
    dayStartMinute = minute < 0 ? 0 : (minute > 59 ? 59 : minute);
    notifyListeners();
    await save();
  }

  Future<void> setQuadrantColor(int index, int argb) async {
    if (index < 0 || index >= quadrantColorValues.length) return;
    quadrantColorValues[index] = argb;
    notifyListeners();
    await save();
  }

  // 「清单」功能已于 2026-10-16 删除（用户：「备注就能代替这个清单的功能」）。
  // 数据层的 `lists` / `Todo.listName` 保留，只为兼容老存档里的 'lists' / 'list'
  // 两个 json 字段；界面上已无任何入口，新建待办一律落在 `defaultListName`。

  Future<Todo?> toggleDone(Todo t) async {
    final bool wasDone = t.done;
    t.done = !t.done;
    t.doneAt = t.done ? DateTime.now() : null;

    // 完成一条重复待办 → 按规则生成下一条（2026-10-24 补）。
    // 之前 repeat 只是存了个字符串，代码里没有任何地方读它，
    // 所以设了「每天」第二天也不会出现 —— 用户报的就是这个。
    Todo? next;
    if (!wasDone && t.done) {
      next = _spawnRepeat(t);
    }

    notifyListeners();
    await save();

    // 新生成的那条要排提醒。AppState 不认识 Notifier（会循环依赖），
    // 所以由 main.dart 注入回调，所有入口（主页 / 日历 / 已完成页）都能覆盖到。
    if (next != null) onRepeatSpawned?.call(next);
    return next;
  }

  /// 重复待办完成后生成的下一条，交给外部排提醒
  void Function(Todo t)? onRepeatSpawned;

  /// 按重复规则生成下一条。不重复 / 没有任何时间参照时返回 null。
  ///
  /// 规则：把 `due`（没有就看 `remind`）按规则往后推一格，
  /// `remind` 跟着平移同样的时长 —— 这样「提前 10 分钟提醒」在新一条上依然成立。
  Todo? _spawnRepeat(Todo t) {
    if (t.repeat == RepeatRule.none) return null;
    final DateTime? base = t.due ?? t.remind;
    if (base == null) return null;
    final DateTime nextBase = _nextRepeatDate(base, t);
    if (!nextBase.isAfter(base)) return null;
    final Duration shift = nextBase.difference(base);

    final Todo n = t.clone();
    n.id = newId();
    n.done = false;
    n.doneAt = null;
    n.created = DateTime.now();
    n.due = t.due == null ? null : nextBase;
    n.remind = t.remind == null ? null : t.remind!.add(shift);
    todos.add(n);
    return n;
  }

  /// 算下一次的日期，时分保持不变
  static DateTime _nextRepeatDate(DateTime base, Todo t) {
    switch (t.repeat) {
      case '每天':
        return base.add(const Duration(days: 1));
      case '每周':
        return base.add(const Duration(days: 7));
      case '每月':
        return _addMonths(base, 1);
      case '每年':
        return _addMonths(base, 12);
      case RepeatRule.custom:
        // 在 repeatDays 里找下一个够得着的天号，最多往后找两个月
        for (int i = 1; i <= 62; i++) {
          final DateTime d = base.add(Duration(days: i));
          if (t.repeatDays.contains(d.day)) return d;
        }
        return base.add(const Duration(days: 1));
      default:
        return base.add(const Duration(days: 1));
    }
  }

  /// 加月份。1月31日 + 1 个月 = 2月28/29（自动落到目标月的最后一天）
  static DateTime _addMonths(DateTime d, int months) {
    final int total = d.month - 1 + months;
    final int y = d.year + total ~/ 12;
    final int m = total % 12 + 1;
    final int lastDay = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, d.day > lastDay ? lastDay : d.day, d.hour, d.minute);
  }

  Future<void> remove(Todo t) async {
    todos.removeWhere((Todo e) => e.id == t.id);
    notifyListeners();
    await save();
  }

  Future<void> insertAt(int index, Todo t) async {
    final int i = index < 0 ? 0 : (index > todos.length ? todos.length : index);
    todos.insert(i, t);
    notifyListeners();
    await save();
  }

  // ---------------- 分组与排序 ----------------

  static int _cmpTime(Todo a, Todo b) {
    final DateTime da = a.due ?? a.created;
    final DateTime db = b.due ?? b.created;
    final int c = da.compareTo(db);
    if (c != 0) return c;
    return a.created.compareTo(b.created);
  }

  static int _cmpPriority(Todo a, Todo b) {
    final int pa = a.priority < 0 ? 99 : a.priority;
    final int pb = b.priority < 0 ? 99 : b.priority;
    final int c = pa.compareTo(pb);
    if (c != 0) return c;
    return _cmpTime(a, b);
  }

  void sortGroup(List<Todo> l) {
    l.sort(sortMode == 'priority' ? _cmpPriority : _cmpTime);
  }

  /// 主列表分组（2026-10-16 改版：按月份，不再按「今天/明天/以后」）。
  ///
  /// 结构：
  ///   逾期（红字，日期行里带逾期天数）
  ///   → 各个月份（`2026年10月` / `2026年11月` …，本月用蓝字）
  ///   → 未定日期
  ///
  /// **本月组**里额外挂一张「今日」小卡片（[TodoGroup.pinTitle] / [pinItems]）：
  /// 今天那几条先从月份列表里摘出去单独成卡，卡片后面由界面补一个空行再接本月其余。
  /// 用户原话：「可以空一行并且突出一下今日代办」。
  ///
  /// 已完成的留在原分组，不移走。
  List<TodoGroup> groups() {
    final DateTime today = dayOf(DateTime.now());
    final List<Todo> overdue = <Todo>[];
    final List<Todo> undated = <Todo>[];
    final Map<String, List<Todo>> byMonth = <String, List<Todo>>{};
    final Map<String, DateTime> firstOfMonth = <String, DateTime>{};

    for (final Todo t in todos) {
      if (t.due == null) {
        undated.add(t);
        continue;
      }
      final DateTime d = dayOf(t.due!);
      if (d.isBefore(today)) {
        // 逾期组同时收「已完成」和「未完成」（2026-10-21 用户要求）。
        // 做完的那条不消失、位置不动，由列表画成灰字 + 删除线；
        // 标题上的「N 条未完成」只数没做完的。
        // 这条推翻了 2026-10-18 的「完成即移出逾期组」。
        overdue.add(t);
        continue;
      }
      final DateTime m = DateTime(d.year, d.month, 1);
      final String key = dateKey(m);
      (byMonth[key] ??= <Todo>[]).add(t);
      firstOfMonth[key] = m;
    }

    sortGroup(overdue);
    sortGroup(undated);

    final List<String> keys = byMonth.keys.toList()
      ..sort((String a, String b) => firstOfMonth[a]!.compareTo(firstOfMonth[b]!));

    final String thisMonth = dateKey(DateTime(today.year, today.month, 1));

    final List<TodoGroup> g = <TodoGroup>[];
    if (overdue.isNotEmpty) g.add(TodoGroup('逾期', 0xFFA32D2D, overdue));

    for (final String k in keys) {
      final List<Todo> list = byMonth[k]!;
      final bool isThisMonth = k == thisMonth;
      String? pinTitle;
      List<Todo>? pinItems;

      if (isThisMonth) {
        // 今天的摘出来单独成卡，摘完月份组里只剩「本月其余」
        final List<Todo> todayItems =
            list.where((Todo t) => sameDay(t.due!, today)).toList();
        if (todayItems.isNotEmpty) {
          list.removeWhere((Todo t) => sameDay(t.due!, today));
          sortGroup(todayItems);
          pinTitle = '今天 · ${shortDayLabel(today)}';
          pinItems = todayItems;
        }
      }

      sortGroup(list);
      final DateTime m = firstOfMonth[k]!;
      g.add(TodoGroup(
        '${m.year}年${m.month}月',
        isThisMonth ? 0xFF185FA5 : 0xFF6E6E6E,
        list,
        pinTitle: pinTitle,
        pinItems: pinItems,
      ));
    }

    if (undated.isNotEmpty) g.add(TodoGroup('未定日期', 0xFF6E6E6E, undated));
    return g;
  }

  // ---------------- 统计 ----------------

  /// 某一天的待办
  List<Todo> onDay(DateTime day) =>
      todos.where((Todo t) => t.due != null && sameDay(t.due!, day)).toList();

  /// 今天该做的
  List<Todo> todayList() => onDay(DateTime.now());

  int todayTotal() => todayList().length;

  int todayDone() => todayList().where((Todo t) => t.done).length;

  /// 今天完成的
  List<Todo> doneToday() {
    final DateTime today = DateTime.now();
    final List<Todo> r =
        todos.where((Todo t) => t.done && t.doneAt != null && sameDay(t.doneAt!, today)).toList();
    r.sort((Todo a, Todo b) => a.doneAt!.compareTo(b.doneAt!));
    return r;
  }

  /// 昨天没做完的
  List<Todo> yesterdayUndone() {
    final DateTime y = DateTime.now().subtract(const Duration(days: 1));
    final List<Todo> r = todos.where((Todo t) => !t.done && t.due != null && sameDay(t.due!, y)).toList();
    sortGroup(r);
    return r;
  }

  /// 有事的日期（给日历画小圆点）
  Set<String> daysWithTodo({bool includeDone = false}) {
    final Set<String> s = <String>{};
    for (final Todo t in todos) {
      if (t.due == null) continue;
      if (!includeDone && t.done) continue;
      s.add(dateKey(t.due!));
    }
    return s;
  }

  // ---------------- TDL 时间表 ----------------

  /// 某天的时间段，按开始时间排好序
  List<TdlBlock> tdlOf(DateTime day) {
    final List<TdlBlock> l = tdlBlocks[dateKey(day)] ?? <TdlBlock>[];
    l.sort((TdlBlock a, TdlBlock b) => a.startMin.compareTo(b.startMin));
    return l;
  }

  /// 某天有没有写过 TDL
  bool hasTdl(DateTime day) => (tdlBlocks[dateKey(day)] ?? const <TdlBlock>[]).isNotEmpty;

  Future<void> tdlAdd(DateTime day, TdlBlock b) async {
    final String k = dateKey(day);
    tdlBlocks.putIfAbsent(k, () => <TdlBlock>[]).add(b);
    notifyListeners();
    await save();
  }

  Future<void> tdlUpdate(DateTime day, TdlBlock b) async {
    final List<TdlBlock>? l = tdlBlocks[dateKey(day)];
    if (l == null) return;
    final int i = l.indexWhere((TdlBlock e) => e.id == b.id);
    if (i >= 0) l[i] = b;
    notifyListeners();
    await save();
  }

  Future<void> tdlRemove(DateTime day, TdlBlock b) async {
    final String k = dateKey(day);
    tdlBlocks[k]?.removeWhere((TdlBlock e) => e.id == b.id);
    if ((tdlBlocks[k] ?? const <TdlBlock>[]).isEmpty) tdlBlocks.remove(k);
    notifyListeners();
    await save();
  }

  /// 删除全部作息，只删这段时间条，保留作息安排本身
  Future<void> tdlClearText(DateTime day) async {
    for (final TdlBlock b in tdlOf(day)) {
      b.text = '';
      b.done = false;
    }
    notifyListeners();
    await save();
  }

  Future<void> setTdlRange(int startMin, int endMin) async {
    tdlStartMin = startMin;
    tdlEndMin = endMin < startMin + 15 ? startMin + 15 : endMin;
    notifyListeners();
    await save();
  }

  /// 设置 TDL 刻度。允许任意分钟数，范围 1~720，超范围兜到 60。
  Future<void> setTdlStep(int step) async {
    tdlStep = (step < 1 || step > 720) ? 60 : step;
    notifyListeners();
    await save();
  }

  /// 按当前刻度把一天切开：返回每段的起始分钟
  List<int> tdlSlots() {
    final List<int> r = <int>[];
    for (int m = tdlStartMin; m + tdlStep <= tdlEndMin; m += tdlStep) {
      r.add(m);
    }
    return r;
  }

  /// 把某一段复制成一条空的时间条
  TdlBlock tdlBlockAt(int startMin) => TdlBlock(
        id: newId(),
        startMin: startMin,
        endMin: startMin + tdlStep,
        text: '',
      );

  Future<void> setDefaultRemindOn(bool v) async {
    defaultRemindOn = v;
    // 用户手动设过之后就不再走迁移逻辑
    remindOnMigrated = true;
    notifyListeners();
    await save();
  }

  /// 默认提前多少分钟提醒（0 = 到点）
  Future<void> setDefaultAheadMinutes(int v) async {
    defaultAheadMinutes = v < 0 ? 0 : (v > 1440 ? 1440 : v);
    notifyListeners();
    await save();
  }

  /// 提醒形态：banner / fullscreen
  Future<void> setRemindStyle(String v) async {
    remindStyle = (v == 'fullscreen') ? 'fullscreen' : 'banner';
    notifyListeners();
    await save();
  }

  /// 全局默认铃声。空串 = 系统默认通知音；认不出来的 id 也回落成空串。
  ///
  /// 改完要重排全部提醒 —— 排程时就已经把声音定死在通知里了（Android 的
  /// zonedSchedule 是提前把通知交给系统），不重排老提醒还是响旧的。
  Future<void> setDefaultSoundId(String v) async {
    defaultSoundId = v;
    notifyListeners();
    await save();
  }

  /// 记下「首次权限引导已经走过」，下次启动直接进主页
  Future<void> setOnboarded(bool v) async {
    onboarded = v;
    notifyListeners();
    await save();
  }

  /// 界面功能引导看过没有。走完 / 点跳过都会置 true。
  Future<void> setGuideDone(bool v) async {
    guideDone = v;
    notifyListeners();
    await save();
  }

  /// 「设置 → 重看引导」用：清掉标记后重新放一次
  Future<void> replayGuide() async {
    guideDone = false;
    notifyListeners();
    await save();
  }

  /// 记下「这个版本的更新弹窗已经看过了」
  Future<void> setLastSeenVersion(String v) async {
    lastSeenVersion = v;
    await save();
  }

  /// 日历页「当日待办」列表折叠 / 展开
  Future<void> setCalendarListCollapsed(bool v) async {
    calendarListCollapsed = v;
    notifyListeners();
    await save();
  }

  /// 主页「逾期」组折叠 / 展开
  Future<void> setOverdueCollapsed(bool v) async {
    overdueCollapsed = v;
    notifyListeners();
    await save();
  }

  String reviewNoteOf(DateTime d) => reviewNotes[dateKey(d)] ?? '';

  Future<void> setReviewNote(DateTime d, String text) async {
    final String key = dateKey(d);
    if (text.trim().isEmpty) {
      reviewNotes.remove(key);
    } else {
      reviewNotes[key] = text;
    }
    notifyListeners();
    await save();
  }

  // ---------------- 历史记录统计 ----------------

  /// 某一天的状态：当天登记的条数、其中已完成条数、当天实际勾掉的条数
  DayStat statOnDay(DateTime day) {
    final List<Todo> items = onDay(day);
    final int total = items.length;
    final int done = items.where((Todo t) => t.done).length;
    final int finished = todos
        .where((Todo t) => t.done && t.doneAt != null && sameDay(t.doneAt!, day))
        .length;
    return DayStat(day: dayOf(day), total: total, done: done, finished: finished);
  }

  /// 按天统计一段区间（含首尾）
  List<DayStat> statsByDay(DateTime from, DateTime to) {
    final List<DayStat> r = <DayStat>[];
    for (DateTime d = dayOf(from); !d.isAfter(dayOf(to)); d = d.add(const Duration(days: 1))) {
      r.add(statOnDay(d));
    }
    return r;
  }

  /// 按月统计：返回该月每一天
  List<DayStat> statsOfMonth(int year, int month) {
    final DateTime from = DateTime(year, month, 1);
    final DateTime to = DateTime(year, month + 1, 0);
    return statsByDay(from, to);
  }

  /// 汇总一批 DayStat
  static StatSum sumOf(List<DayStat> list) {
    int total = 0;
    int done = 0;
    int finished = 0;
    for (final DayStat s in list) {
      total += s.total;
      done += s.done;
      finished += s.finished;
    }
    return StatSum(total: total, done: done, finished: finished);
  }

  /// 所有写过的复盘总结，按日期倒序
  List<MapEntry<DateTime, String>> allReviewNotes() {
    final List<MapEntry<DateTime, String>> r = <MapEntry<DateTime, String>>[];
    reviewNotes.forEach((String k, String v) {
      if (v.trim().isEmpty) return;
      final DateTime? d = DateTime.tryParse(k);
      if (d != null) r.add(MapEntry<DateTime, String>(d, v));
    });
    r.sort((MapEntry<DateTime, String> a, MapEntry<DateTime, String> b) => b.key.compareTo(a.key));
    return r;
  }

  // ---------------- 导出 ----------------

  /// 只含复盘总结的导出内容
  Map<String, dynamic> reviewExportData() {
    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    for (final MapEntry<DateTime, String> e in allReviewNotes()) {
      final DayStat s = statOnDay(e.key);
      items.add(<String, dynamic>{
        'date': dateKey(e.key),
        'weekday': '星期${'一二三四五六日'[e.key.weekday - 1]}',
        'total': s.total,
        'done': s.done,
        'finished': s.finished,
        'summary': e.value,
        'doneItems': onDay(e.key)
            .where((Todo t) => t.done)
            .map((Todo t) => t.title)
            .toList(),
      });
    }
    return <String, dynamic>{
      'app': '朝暮',
      'kind': 'review',
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'count': items.length,
      'reviews': items,
    };
  }

  /// 只含待办历史的导出内容（按完成 / 未完成分开，方便喂给知识库）
  Map<String, dynamic> historyExportData() {
    final List<Todo> doneList =
        todos.where((Todo t) => t.done && t.doneAt != null).toList()
          ..sort((Todo a, Todo b) => b.doneAt!.compareTo(a.doneAt!));

    final List<Map<String, String>> done = doneList.map((Todo t) => <String, String>{
          'title': t.title,
          'list': t.listName,
          'priority': Priority.nameOf(t.priority),
          'due': t.due == null ? '' : dateKey(t.due!),
          'doneAt': dateTimeLabel(t.doneAt!),
          'note': t.note,
        }).toList();

    final List<Map<String, String>> undone = todos
        .where((Todo t) => !t.done)
        .map((Todo t) => <String, String>{
              'title': t.title,
              'list': t.listName,
              'priority': Priority.nameOf(t.priority),
              'due': t.due == null ? '' : dateKey(t.due!),
              'note': t.note,
            })
        .toList();

    return <String, dynamic>{
      'app': '朝暮',
      'kind': 'history',
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'doneCount': done.length,
      'undoneCount': undone.length,
      'done': done,
      'undone': undone,
    };
  }
}

/// 某天的统计
class DayStat {
  const DayStat({
    required this.day,
    required this.total,
    required this.done,
    required this.finished,
  });

  final DateTime day;
  final int total; // 当天登记的待办条数
  final int done; // 其中已勾掉的
  final int finished; // 当天真正勾掉的（可能来自其它日期）

  double get ratio => total == 0 ? 0 : done / total;
}

/// 一段时间的汇总
class StatSum {
  const StatSum({required this.total, required this.done, required this.finished});

  final int total;
  final int done;
  final int finished;

  double get ratio => total == 0 ? 0 : done / total;
}
