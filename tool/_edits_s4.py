# -*- coding: utf-8 -*-
"""朝暮 2.7.13 第 4 批：给 Todo 加 remindOff 开关（让「不提醒」真的不响），并在排程里关掉兜底。"""
import sys, pathlib

EDITS = []


def add(path, old, new, count=1):
    EDITS.append((path, old, new, count))


M = r'D:\chaomu\lib\models.dart'
N = r'D:\chaomu\lib\notifier.dart'

add(M, """  /// 这条待办单独提前多少分钟提醒；-1 = 跟随设置里的默认提前量
  int aheadMinutes;
""", """  /// 这条待办单独提前多少分钟提醒；-1 = 跟随设置里的默认提前量
  int aheadMinutes;

  /// 用户明确点了「不提醒」。
  ///
  /// 为什么非要有这个字段：光把 [remind] 置空是不够的 —— 排程里有一条兜底
  /// 「没设提醒时间、但截止带时刻 → 就用截止时刻提醒」（见 Notifier.scheduleFor），
  /// 所以在"截止带时刻"的待办上，光清空 remind 它照样会响。
  /// 这个开关的作用就是把那条兜底关掉。
  bool remindOff;
""")

add(M, """    this.remindRingtone = '',
    this.aheadMinutes = -1,
  }) : created = created ?? DateTime.now();""",
    """    this.remindRingtone = '',
    this.aheadMinutes = -1,
    this.remindOff = false,
  }) : created = created ?? DateTime.now();""")

add(M, """        'aheadMinutes': aheadMinutes,
      };""", """        'aheadMinutes': aheadMinutes,
        'remindOff': remindOff,
      };""")

add(M, """        aheadMinutes: (m['aheadMinutes'] is num) ? (m['aheadMinutes'] as num).toInt() : -1,
      );""", """        aheadMinutes: (m['aheadMinutes'] is num) ? (m['aheadMinutes'] as num).toInt() : -1,
        remindOff: m['remindOff'] == true,
      );""")

add(N, """    // 没设提醒时间，但有截止时刻 -> 用截止时刻
    DateTime? when = t.remind;
    if (when == null && t.due != null && t.dueHasTime) when = t.due;
    if (when == null) {
      note('这条没填「提醒时间」，也没填带时刻的「截止时间」');
      return;
    }""", """    // 没设提醒时间，但有截止时刻 -> 用截止时刻。
    // 用户明确点过「不提醒」（remindOff）就不走这条兜底，否则那条待办还是会响。
    DateTime? when = t.remind;
    if (!t.remindOff && when == null && t.due != null && t.dueHasTime) when = t.due;
    if (when == null) {
      note(t.remindOff
          ? '这条设了「不提醒」'
          : '这条没填「提醒时间」，也没填带时刻的「截止时间」');
      return;
    }""")


def main():
    bad = 0
    for path, old, new, count in EDITS:
        p = pathlib.Path(path)
        src = p.read_text(encoding='utf-8')
        n = src.count(old)
        if n != count:
            print(f'[FAIL] {p.name}: 期望 {count} 次，实际 {n} 次：{old[:60]!r}')
            bad += 1
            continue
        p.write_text(src.replace(old, new, count), encoding='utf-8')
        print(f'[OK]   {p.name}: 替换 {n} 处 <- {old.strip().splitlines()[0][:48]!r}')
    if bad:
        print(f'\n共 {bad} 处未通过，已中止。')
        sys.exit(1)
    for f in (M, N):
        s = pathlib.Path(f).read_text(encoding='utf-8')
        print(f'[检查] {pathlib.Path(f).name}: remindOff 出现 {s.count("remindOff")} 处')
    print(f'\n全部 {len(EDITS)} 处替换完成。')


main()
