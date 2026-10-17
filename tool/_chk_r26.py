# -*- coding: utf-8 -*-
"""自定义执行日期校验"""
import io, sys

FILES = {
    'models': r'D:\chaomu\lib\models.dart',
    'detail': r'D:\chaomu\lib\pages\detail_page.dart',
}
ok = True
src = {}
for name, path in FILES.items():
    s = io.open(path, 'r', encoding='utf-8').read()
    src[name] = s
    counts = {c: s.count(c) for c in '(){}[]'}
    bal = counts['('] == counts[')'] and counts['{'] == counts['}'] and counts['['] == counts[']']
    print('%-7s ()=%d/%d {}=%d/%d []=%d/%d  %s' % (
        name, counts['('], counts[')'], counts['{'], counts['}'],
        counts['['], counts[']'], 'OK' if bal else '**UNBALANCED**'))
    if not bal:
        ok = False

def has(name, needle, want=True):
    global ok
    got = needle in src[name]
    if got != want:
        ok = False
    print('%-7s %-52s %s' % (name, needle[:52], 'OK' if got == want else '**FAIL**'))

print('---- 新符号 ----')
has('models', "static const String custom = '自定义';")
has('models', "['无', '每天', '每周', '每月', '每年', custom]")
has('models', 'List<int> repeatDays;')
has('models', 'this.repeatDays = const <int>[],')
has('models', "'repeatDays': repeatDays,")
has('models', 'repeatDays: _daysFromJson(m[\'repeatDays\']),')
has('models', 'String customRepeatLabel(List<int> days)')
has('detail', 'List<int> _repeatDays = <int>[];')
has('detail', '_repeatDays = List<int>.of(t.repeatDays);')
has('detail', 't.repeatDays = List<int>.of(_repeatDays);')
has('detail', '_pickRepeatDaysPanel')
has('detail', 'class _RepeatDaysPanel extends StatefulWidget')
has('detail', 'late final List<int> _days = List<int>.of(widget.initial);')
has('detail', 'customRepeatLabel(_repeatDays)')

print('---- 结果 ----')
print('ALL PASS' if ok else 'HAS FAILURES')
sys.exit(0 if ok else 1)
