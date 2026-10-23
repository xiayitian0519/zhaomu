import json
import os
import shutil

p = r'C:\Users\18814\Documents\chaomu\chaomu.json'
bak = p + '.bak'

if not os.path.exists(bak):
    if os.path.exists(p):
        shutil.copy(p, bak)
        print('已备份到', bak)
else:
    print('备份已存在，跳过')


def todo(i, title, due, done=False, priority=0, listname='生活'):
    return {
        'id': f'test{i}',
        'title': title,
        'note': '',
        'due': due,
        'dueHasTime': False,
        'remind': None,
        'priority': priority,
        'list': listname,
        'repeat': 'none',
        'done': done,
        'created': '2026-10-01T08:00:00.000',
        'doneAt': '2026-10-18T09:00:00.000' if done else None,
        'aheadMinutes': 60,
        'remindOff': False,
        'repeatDays': '',
    }


todos = [
    todo(1, '读书写总结', '2026-10-12T10:00:00.000'),            # 逾期 6 天，未完成
    todo(2, '要AI部成员同频信息', '2026-10-15T10:00:00.000'),      # 逾期 3 天，未完成
    todo(3, '记单词0.5h', '2026-10-14T10:00:00.000', done=True),  # 逾期已完成，应隐藏
    todo(4, '哦可能那就睡觉', '2026-10-18T09:00:00.000'),          # 今天
    todo(5, '爱心经常经济学教授', '2026-10-18T10:00:00.000'),      # 今天
    todo(6, '多久放假解放军上课', '2026-10-18T11:00:00.000'),      # 今天
    todo(7, '1010010', '2026-10-08T09:00:00.000'),               # 8 号，5 条触发「还有 N 条」
    todo(8, '08888888964', '2026-10-08T10:00:00.000'),
    todo(9, '77777777', '2026-10-08T11:00:00.000'),
    todo(10, '6666666666', '2026-10-08T12:00:00.000'),
    todo(11, '的的', '2026-10-08T13:00:00.000'),
    todo(12, '复习口语', '2026-10-20T09:00:00.000'),               # 未来
]

data = {
    'app': '朝暮',
    'version': 1,
    'exportedAt': '2026-10-18T16:00:00.000',
    'todos': todos,
    'lists': ['工作', '生活', '学习'],
    'quadrantColors': [4283215696, 4294198070, 4294956800, 4293215696],
    'sortMode': 'time',
    'noStrike': False,
    'dayStartHour': 0,
    'dayStartMinute': 0,
    'reviewNotes': {},
    'lastReviewPrompt': '',
    'onboarded': True,
    'guideDone': True,
    'calendarListCollapsed': False,
    'overdueCollapsed': False,
    'lastSeenVersion': '2.17.1+30',
    'remindOnMigrated': False,
    'historyMode': 'month',
    'historyMonths': [],
    'historyYear': 2026,
    'tdl': {},
    'tdlStartMin': 420,
    'tdlEndMin': 1380,
    'tdlStep': 60,
    'defaultRemindOn': True,
    'defaultAheadMinutes': 60,
    'remindStyle': 'banner',
}

os.makedirs(os.path.dirname(p), exist_ok=True)
with open(p, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print('测试数据已写入', p)
