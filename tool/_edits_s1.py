# -*- coding: utf-8 -*-
"""朝暮 2.7.13：models.dart / app_state.dart 的精确替换。
每处替换都断言「原文命中恰好 N 次」，命中数不符立刻中止，绝不半改。
"""
import io, sys, pathlib

EDITS = []


def add(path, old, new, count=1):
    EDITS.append((path, old, new, count))


M = r'D:\chaomu\lib\models.dart'
A = r'D:\chaomu\lib\app_state.dart'

# ---------- models.dart ----------

add(M, """class RepeatRule {
  RepeatRule._();
  static const List<String> all = <String>['无', '每天', '每周', '每月', '每年'];
  static const String none = '无';
}""", """class RepeatRule {
  RepeatRule._();

  /// 存储用的值 —— **别改这些字**。老存档里已经直接存着 '无' 这类字符串，
  /// 改了会让详情页的兜底逻辑把老数据悄悄改写成新值。
  static const List<String> all = <String>['无', '每天', '每周', '每月', '每年'];

  static const String none = '无';

  /// 界面上显示的文案。
  ///
  /// 「无」用户看不懂是啥意思（2026-10-16 用户原话：「用户第一时间不知道
  /// 这个是什么意思」），改成「仅今天」—— 一眼就懂这个字段管的是"要不要重复"。
  /// 选项本身（每天/每周/每月/每年）全部保留，只换「无」那一个的显示。
  static String labelOf(String r) => r == none ? '仅今天' : r;
}""")

add(M, """/// 相对今天的说法
String relativeDayLabel(DateTime d) {
  final DateTime today = dayOf(DateTime.now());
  final int diff = dayOf(d).difference(today).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '明天';
  if (diff == 2) return '后天';
  if (diff == -1) return '昨天';
  if (diff < 0) return '逾期 ${-diff} 天';
  return shortDayLabel(d);
}""", """/// 相对今天的说法
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
}""")

# ---------- app_state.dart ----------

add(A, "  int defaultAheadMinutes = 0;",
    """  /// 提醒默认提前量，单位分钟。2026-10-16 起默认 1 小时（原来是 0 = 到点提醒）。
  ///
  /// ⚠️ 只影响新装 / 从没改过这项的存档：老存档里已经存着 0，
  /// 读回来还是 0（见 [_read]）。0 是合法值，分不清"没设过"和"特意要到点"，
  /// 所以不做自动迁移 —— 要改在「设置 → 提前多久提醒」里选。
  int defaultAheadMinutes = 60;""")

add(A, """/// 一组待办（主列表里的「逾期 / 今天 / 明天 / 以后」）
class TodoGroup {
  const TodoGroup(this.title, this.colorValue, this.items);
  final String title;
  final int colorValue;
  final List<Todo> items;
}""", """/// 一组待办。2026-10-16 起主列表改成「逾期 / 各个月份 / 未定日期」。
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
}""")

add(A, """  /// 主列表分组。已完成的留在原分组，不移走。
  List<TodoGroup> groups() {
    final DateTime today = dayOf(DateTime.now());
    final List<Todo> overdue = <Todo>[];
    final List<Todo> day0 = <Todo>[];
    final List<Todo> day1 = <Todo>[];
    final List<Todo> later = <Todo>[];
    final List<Todo> undated = <Todo>[];

    for (final Todo t in todos) {
      if (t.due == null) {
        undated.add(t);
        continue;
      }
      final int d = dayOf(t.due!).difference(today).inDays;
      if (d < 0) {
        overdue.add(t);
      } else if (d == 0) {
        day0.add(t);
      } else if (d == 1) {
        day1.add(t);
      } else {
        later.add(t);
      }
    }

    sortGroup(overdue);
    sortGroup(day0);
    sortGroup(day1);
    sortGroup(later);
    sortGroup(undated);

    final List<TodoGroup> g = <TodoGroup>[];
    if (overdue.isNotEmpty) g.add(TodoGroup('逾期', 0xFFA32D2D, overdue));
    if (day0.isNotEmpty) g.add(TodoGroup('今天', 0xFF185FA5, day0));
    if (day1.isNotEmpty) g.add(TodoGroup('明天', 0xFF6E6E6E, day1));
    if (later.isNotEmpty) g.add(TodoGroup('以后', 0xFF6E6E6E, later));
    if (undated.isNotEmpty) g.add(TodoGroup('未定日期', 0xFF6E6E6E, undated));
    return g;
  }""", """  /// 主列表分组（2026-10-16 改版：按月份，不再按「今天/明天/以后」）。
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
  }""")

add(A, """  Future<void> addList(String name) async {
    final String n = name.trim();
    if (n.isEmpty || lists.contains(n)) return;
    lists.add(n);
    notifyListeners();
    await save();
  }

  Future<void> removeList(String name) async {
    if (lists.length <= 1) return;
    lists.remove(name);
    for (final Todo t in todos) {
      if (t.listName == name) t.listName = defaultListName;
    }
    notifyListeners();
    await save();
  }

""", """  // 「清单」功能已于 2026-10-16 删除（用户：「备注就能代替这个清单的功能」）。
  // 数据层的 `lists` / `Todo.listName` 保留，只为兼容老存档里的 'lists' / 'list'
  // 两个 json 字段；界面上已无任何入口，新建待办一律落在 `defaultListName`。

""")


def main():
    bad = 0
    for path, old, new, count in EDITS:
        p = pathlib.Path(path)
        src = p.read_text(encoding='utf-8')
        n = src.count(old)
        if n != count:
            print(f'[FAIL] {p.name}: 期望命中 {count} 次，实际 {n} 次')
            print(f'       原文前 60 字：{old[:60]!r}')
            bad += 1
            continue
        src = src.replace(old, new, count)
        p.write_text(src, encoding='utf-8')
        print(f'[OK]   {p.name}: 替换 {n} 处 <- {old.strip().splitlines()[0][:46]!r}')
    if bad:
        print(f'\n共 {bad} 处未通过，已中止后续检查。')
        sys.exit(1)
    print(f'\n全部 {len(EDITS)} 处替换完成。')


main()
