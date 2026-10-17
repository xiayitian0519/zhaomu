# -*- coding: utf-8 -*-
"""执行力B + 铃声A 改动校验：括号配平 + 残留引用清干净 + 新样式在位"""
import io, sys

FILES = {
    'notif':  r'D:\chaomu\lib\notifier.dart',
    'models': r'D:\chaomu\lib\models.dart',
    'appst':  r'D:\chaomu\lib\app_state.dart',
    'home':   r'D:\chaomu\lib\pages\home_page.dart',
    'set':    r'D:\chaomu\lib\pages\settings_page.dart',
    'detail': r'D:\chaomu\lib\pages\detail_page.dart',
    'review': r'D:\chaomu\lib\pages\review_page.dart',
    'hist':   r'D:\chaomu\lib\pages\history_page.dart',
    'kt':     r'D:\chaomu\android\app\src\main\kotlin\com\xiayitian\chaomu\MainActivity.kt',
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
    print('%-7s %-48s %s' % (name, needle[:48], 'OK' if got == want else '**FAIL**'))

print('---- 残留引用清干净 ----')
for f in ('notif', 'models', 'appst', 'home', 'set', 'detail'):
    has(f, 'Ringtone', want=False)
    has(f, 'ringtone', want=False)
    has(f, 'defaultRingtone', want=False)
    has(f, 'remindRingtone', want=False)
for f in ('notif', 'set', 'detail'):
    has(f, 'preview', want=False)
has('kt', 'MediaPlayer', want=False)
has('kt', 'playRaw', want=False)
has('kt', 'preview', want=False)

print('---- 新内容在位 ----')
has('notif', 'final bool ring = soundOn;')
has('notif', '不传 sound 就是渠道配置的声音')
has('notif', 'openChannelSettings')
has('set', '通知铃声')
has('set', '本地音乐 / 在线铃声')
has('set', '_openChannelSettings(context)')
has('review', '执行力 ${(ratio * 100).round()}%')
has('review', 'Color(0xFFE6F1FB)')
has('hist', '执行力 ')
has('models', 'int aheadMinutes;')

print('---- 结果 ----')
print('ALL PASS' if ok else 'HAS FAILURES')
sys.exit(0 if ok else 1)
