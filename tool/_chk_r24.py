# -*- coding: utf-8 -*-
"""滚轮环绕 + 日历展开态改版 校验"""
import io, sys

FILES = {
    'cal':    r'D:\chaomu\lib\pages\calendar_page.dart',
    'widgets': r'D:\chaomu\lib\widgets.dart',
}

ok = True
src = {}
for name, path in FILES.items():
    with io.open(path, 'r', encoding='utf-8') as f:
        s = f.read()
    src[name] = s
    counts = {c: s.count(c) for c in '(){}[]'}
    bal = (counts['('] == counts[')'] and counts['{'] == counts['}'] and counts['['] == counts[']'])
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
    print('%-7s %-46s %s' % (name, needle[:46], mark))

print('---- 新符号 ----')
has('cal', '_maxSpanExp = 3')
has('cal', '(int, int, int) _measureExp')
has('cal', '(List<_Placed>, int) _layoutExp')
has('cal', '_expandedMonth')
has('cal', '_weekTag(d, isSel)')
has('cal', 'required bool weekTag')
has('cal', 'weekTag: false')
has('cal', 'weekTag: true')
has('cal', 'final int cols;')
has('cal', 'baseline / _rowsOf(_month)')
has('cal', 'bodyH * 0.75')
has('widgets', '((i % count) + count) % count')
has('widgets', '((i % 24) + 24) % 24')
has('widgets', '((i % n) + n) % n')

print('---- 旧符号清干净 ----')
has('cal', 'st_', want=False)
has('cal', '_rowHeight', want=False)
has('cal', '_maxLinesExpanded', want=False)
has('cal', 'PageController', want=False)
has('cal', '_basePage', want=False)
has('cal', '_monthOfPage', want=False)
has('cal', '_pageOfMonth', want=False)
has('cal', 'animateToPage', want=False)
has('cal', 'jumpToPage', want=False)
has('widgets', 'childCount: count', want=False)

print('---- 结果 ----')
print('ALL PASS' if ok else 'HAS FAILURES')
sys.exit(0 if ok else 1)
