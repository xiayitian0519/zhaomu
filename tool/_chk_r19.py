# -*- coding: utf-8 -*-
"""第 19-22 轮改版校验：括号配平 + 新符号在位 + 旧符号清干净"""
import io, sys

FILES = {
    'detail':  r'D:\chaomu\lib\pages\detail_page.dart',
    'models':  r'D:\chaomu\lib\models.dart',
    'appst':   r'D:\chaomu\lib\app_state.dart',
    'home':    r'D:\chaomu\lib\pages\home_page.dart',
    'cal':     r'D:\chaomu\lib\pages\calendar_page.dart',
    'set':     r'D:\chaomu\lib\pages\settings_page.dart',
    'notif':   r'D:\chaomu\lib\notifier.dart',
}

ok = True
src = {}
for name, path in FILES.items():
    with io.open(path, 'r', encoding='utf-8') as f:
        s = f.read()
    src[name] = s
    counts = {c: s.count(c) for c in '(){}[]'}
    bal = (counts['('] == counts[')'] and
           counts['{'] == counts['}'] and
           counts['['] == counts[']'])
    print('%-7s ()=%d/%d {}=%d/%d []=%d/%d  %s' % (
        name, counts['('], counts[')'], counts['{'], counts['}'],
        counts['['], counts[']'], 'OK' if bal else '**UNBALANCED**'))
    if not bal:
        ok = False

def has(name, needle, want=True):
    global ok
    got = needle in src[name]
    mark = 'OK' if got == want else '**FAIL**'
    if got != want:
        ok = False
    print('%-7s %-42s %s (want %s)' % (name, needle[:42], mark, 'in' if want else 'out'))

print('---- 新符号在位 ----')
has('models', 'static String labelOf')
has('models', 'String aheadLabel(int m)')
has('models', 'String listDueLabel(DateTime due, bool hasTime)')
has('models', 'bool remindOff')
has('appst', 'pinItems')
has('appst', 'pinTitle')
has('appst', 'int defaultAheadMinutes = 60')
has('appst', 'String? pinTitle')
has('home', '_todayCard')
has('home', 'listDueLabel')
has('home', '逾期')
has('cal', 'timeLabel')
has('set', 'aheadLabel')
has('notif', 't.remindOff')
has('notif', '不提醒')
has('detail', '_accentRow')
has('detail', '_pickDuePanel')
has('detail', '_pickRemindPanel')
has('detail', '_pickAheadCustom')
has('detail', '_fireAt')
has('detail', 'GridView.count')
has('detail', 'RepeatRule.labelOf')
has('detail', 'soundOn: st.defaultRemindOn')
has('detail', 't.remindOff = _remindOff')
has('detail', '_remindOff = t.remindOff')

print('---- 旧符号清干净 ----')
has('appst', 'Future<void> addList', want=False)
has('appst', 'Future<void> removeList', want=False)
has('set', "_sectionTitle('清单')", want=False)
has('set', '_addList', want=False)
has('set', '_confirmRemoveList', want=False)
has('detail', '清单', want=False)
has('detail', 'listValue', want=False)
has('detail', "title: const Text('清单')", want=False)
has('set', "m == 0 ? '到点提醒' : '提前 $m 分钟'", want=False)

print('---- 结果 ----')
print('ALL PASS' if ok else 'HAS FAILURES')
sys.exit(0 if ok else 1)
