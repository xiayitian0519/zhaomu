# -*- coding: utf-8 -*-
"""自定义执行日期：RepeatRule 加「自定义」+ Todo.repeatDays + 详情页面板"""
import io

def load(p): return io.open(p, 'r', encoding='utf-8').read()
def save(p, s): io.open(p, 'w', encoding='utf-8', newline='').write(s)
def apply(path, pairs):
    s = load(path)
    for old, new, cnt in pairs:
        n = s.count(old)
        assert n == cnt, '%s 命中 %d(期望 %d): %s...' % (path, n, cnt, old[:60])
        s = s.replace(old, new)
    save(path, s)
    print('OK %s' % path.split('\\')[-1])

# ---------------- 1. models.dart ----------------
MOD = r'D:\chaomu\lib\models.dart'
apply(MOD, [
    (u"""  static const List<String> all = <String>['无', '每天', '每周', '每月', '每年'];""",
     u"""  static const List<String> all = <String>['无', '每天', '每周', '每月', '每年', custom];

  /// 「自定义」的存储键。规则本体在 [Todo.repeatDays]（每月几号的列表）
  static const String custom = '自定义';""", 1),
    (u"""  /// 用户明确点了「不提醒」。""",
     u"""  /// 「自定义」执行日期：每月哪几号（1~31，升序）。
  /// 只有 [repeat] == RepeatRule.custom 时才有意义；空列表 = 没配好。
  /// 2026-10-16 加：奇数日 / 偶数日 / 手选多个天号（用户原话）。
  List<int> repeatDays;

  /// 用户明确点了「不提醒」。""", 1),
    (u"""    this.aheadMinutes = -1,
    this.remindOff = false,""",
     u"""    this.aheadMinutes = -1,
    this.remindOff = false,
    this.repeatDays = const <int>[],""", 1),
    (u"""        'remindOff': remindOff,
      };""",
     u"""        'remindOff': remindOff,
        'repeatDays': repeatDays,
      };""", 1),
    (u"""        remindOff: m['remindOff'] == true,
      );""",
     u"""        remindOff: m['remindOff'] == true,
        repeatDays: _daysFromJson(m['repeatDays']),
      );""", 1),
    (u"""  static DateTime? _parseDt(Object? v) {""",
     u"""  /// repeatDays 兜底解析：只收 1~31 的整数，升序
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

  static DateTime? _parseDt(Object? v) {""", 1),
    (u"""/// 提前量的说法。""",
     u"""/// 「自定义」重复的显示文案：自定义 · 奇数日 / 偶数日 / 顿号天号列表。
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

/// 提前量的说法。""", 1),
])

# ---------------- 2. detail_page.dart ----------------
DET = r'D:\chaomu\lib\pages\detail_page.dart'
apply(DET, [
    (u"""  /// 用户明确点了「不提醒」。
  ///
  /// 光清空 [_remind] 不够 —— 排程里有兜底「截止带时刻就按截止提醒」
  /// （见 Notifier.scheduleFor），这个开关把那条兜底也关掉。
  bool _remindOff = false;""",
     u"""  /// 用户明确点了「不提醒」。
  ///
  /// 光清空 [_remind] 不够 —— 排程里有兜底「截止带时刻就按截止提醒」
  /// （见 Notifier.scheduleFor），这个开关把那条兜底也关掉。
  bool _remindOff = false;

  /// 「自定义」执行日期：每月哪几号（升序）。只有 [_repeat] == 自定义 时有效
  List<int> _repeatDays = <int>[];""", 1),
    (u"""    _ahead = t.aheadMinutes;
    _remindOff = t.remindOff;""",
     u"""    _ahead = t.aheadMinutes;
    _remindOff = t.remindOff;
    _repeatDays = List<int>.of(t.repeatDays);""", 1),
    (u"""    t.aheadMinutes = _ahead;
    t.remindOff = _remindOff;""",
     u"""    t.aheadMinutes = _ahead;
    t.remindOff = _remindOff;
    t.repeatDays = List<int>.of(_repeatDays);""", 1),
    (u"""              trailing: DropdownButton<String>(
                value: repeatValue,
                underline: const SizedBox.shrink(),
                items: RepeatRule.all
                    .map((String e) => DropdownMenuItem<String>(
                          value: e,
                          child: Text(RepeatRule.labelOf(e), style: const TextStyle(fontSize: 14)),
                        ))
                    .toList(),
                onChanged: (String? v) {
                  if (v != null) setState(() => _repeat = v);
                },
              ),""",
     u"""              trailing: DropdownButton<String>(
                value: repeatValue,
                underline: const SizedBox.shrink(),
                items: <DropdownMenuItem<String>>[
                  for (final String e in RepeatRule.all)
                    DropdownMenuItem<String>(
                      value: e,
                      child: Text(
                        e == RepeatRule.custom
                            ? (_repeat == RepeatRule.custom
                                ? customRepeatLabel(_repeatDays)
                                : '自定义…')
                            : RepeatRule.labelOf(e),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                ],
                onChanged: (String? v) {
                  if (v == null) return;
                  if (v == RepeatRule.custom) {
                    _pickRepeatDaysPanel();
                  } else {
                    setState(() {
                      _repeat = v;
                      _repeatDays = const <int>[];
                    });
                  }
                },
              ),""", 1),
    (u"""  // ---------------- 截止面板 ----------------""",
     u"""  // ---------------- 自定义执行日期面板 ----------------

  /// 弹天号选择面板。选空 = 退回「仅今天」，选了 = repeat 切到「自定义」
  Future<void> _pickRepeatDaysPanel() async {
    final List<int>? picked = await showModalBottomSheet<List<int>>(
      context: context,
      builder: (BuildContext c) => _RepeatDaysPanel(initial: List<int>.of(_repeatDays)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (picked.isEmpty) {
        _repeat = RepeatRule.none;
        _repeatDays = const <int>[];
      } else {
        _repeat = RepeatRule.custom;
        _repeatDays = picked;
      }
    });
  }

  // ---------------- 截止面板 ----------------""", 1),
])

# ---------------- 3. detail_page.dart 尾部追加面板组件 ----------------
PANEL = u'''

/// 自定义执行日期面板：奇数日 / 偶数日一键，或 1~31 手选多个天号。
/// 「完成」把选好的天号列表带回详情页；空列表 = 退回「仅今天」。
class _RepeatDaysPanel extends StatefulWidget {
  const _RepeatDaysPanel({required this.initial});

  final List<int> initial;

  @override
  State<_RepeatDaysPanel> createState() => _RepeatDaysPanelState();
}

class _RepeatDaysPanelState extends State<_RepeatDaysPanel> {
  static const List<int> _odd = <int>[1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31];
  static const List<int> _even = <int>[2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30];

  final List<int> _days = List<int>.of(widget.initial);

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Widget _pill(String text, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: on ? const Color(0xFF185FA5) : const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(16),
          border: on ? null : Border.all(color: const Color(0xFFDFE2E8)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: on ? const Color(0xFFFFFFFF) : const Color(0xFF3C3C3C),
          ),
        ),
      ),
    );
  }

  Widget _dayCell(int d) {
    final bool on = _days.contains(d);
    return GestureDetector(
      onTap: () => setState(() => on ? _days.remove(d) : _days.add(d)),
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? const Color(0xFF185FA5) : const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? const Color(0xFF185FA5) : const Color(0xFFDFE2E8)),
        ),
        child: Text(
          '$d',
          style: TextStyle(
            fontSize: 12,
            color: on ? const Color(0xFFFFFFFF) : const Color(0xFF3C3C3C),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<int> sorted = _days.toList()..sort();
    final String picked =
        sorted.isEmpty ? '还没选天号' : '已选：${sorted.join('、')} 号';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '自定义执行日期',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                _pill('奇数日', _same(sorted, _odd), () {
                  setState(() {
                    _days
                      ..clear()
                      ..addAll(_odd);
                  });
                }),
                const SizedBox(width: 8),
                _pill('偶数日', _same(sorted, _even), () {
                  setState(() {
                    _days
                      ..clear()
                      ..addAll(_even);
                  });
                }),
                const SizedBox(width: 8),
                _pill('清空', sorted.isEmpty, () => setState(_days.clear)),
              ],
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 7,
              mainAxisSpacing: 5,
              crossAxisSpacing: 5,
              childAspectRatio: 1.1,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: <Widget>[
                for (int d = 1; d <= 31; d++) _dayCell(d),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              picked,
              style: const TextStyle(fontSize: 12, color: Color(0xFF185FA5)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(List<int>.of(_days)..sort()),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF185FA5),
                ),
                child: const Text(
                  '完成',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
'''
s = load(DET)
assert not s.count('_RepeatDaysPanel extends StatefulWidget')
s = s.rstrip() + '\n' + PANEL
save(DET, s)
print('OK detail_page.dart 面板组件已追加')
print('ALL DONE')
