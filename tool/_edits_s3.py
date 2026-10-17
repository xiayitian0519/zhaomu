# -*- coding: utf-8 -*-
"""朝暮 2.7.13 第 3 批：settings_page.dart —— 删掉「清单」全部入口 + 提前量文案用 aheadLabel。"""
import sys, pathlib

EDITS = []


def add(path, old, new, count=1):
    EDITS.append((path, old, new, count))


S = r'D:\chaomu\lib\pages\settings_page.dart'

# 1) 删掉 _addList
add(S, """  Future<void> _addList(BuildContext context) async {
    final TextEditingController ctl = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('新增清单', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：家务'),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('添加')),
        ],
      ),
    );
    final String name = ctl.text;
    ctl.dispose();
    if (ok != true) return;
    await AppState.I.addList(name);
  }

  // ---------------- 导出 ----------------""",
    """  // ---------------- 导出 ----------------""")

# 2) 删掉清单设置区块
add(S, """              _sectionTitle('清单'),
              _card(<Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final String name in st.lists)
                        Chip(
                          label: Text(name),
                          onDeleted: st.lists.length > 1
                              ? () => _confirmRemoveList(context, name)
                              : null,
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: const Text('新增'),
                        onPressed: () => _addList(context),
                      ),
                    ],
                  ),
                ),
              ]),

              _sectionTitle('数据'),""",
    """              // 「清单」设置区块已于 2026-10-16 删除，见 app_state.dart 的说明
              _sectionTitle('数据'),""")

# 3) 提前量面板的选项文案
add(S, """                  m == 0 ? '到点提醒' : '提前 $m 分钟',""",
    """                  aheadLabel(m),""")

# 4) 设置页「提前多久提醒」的副标题
add(S, """                    st.defaultAheadMinutes == 0
                        ? '到点提醒'
                        : '提前 ${st.defaultAheadMinutes} 分钟（单条待办里可单独改）',""",
    """                    '${aheadLabel(st.defaultAheadMinutes)}（单条待办里可单独改）',""")

# 5) 删掉 _confirmRemoveList（它是类里最后一个方法）
add(S, """
  Future<void> _confirmRemoveList(BuildContext context, String name) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('删掉这个清单？', style: TextStyle(fontSize: 16)),
        content: Text('「$name」里的待办不会被删掉，会挪到第一个清单里。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) await AppState.I.removeList(name);
  }
}
""", """}
""")


def main():
    bad = 0
    for path, old, new, count in EDITS:
        p = pathlib.Path(path)
        src = p.read_text(encoding='utf-8')
        n = src.count(old)
        if n != count:
            print(f'[FAIL] {p.name}: 期望命中 {count} 次，实际 {n} 次')
            print(f'       原文前 70 字：{old[:70]!r}')
            bad += 1
            continue
        src = src.replace(old, new, count)
        p.write_text(src, encoding='utf-8')
        print(f'[OK]   {p.name}: 替换 {n} 处 <- {old.strip().splitlines()[0][:48]!r}')

    if bad:
        print(f'\n共 {bad} 处未通过，已中止。')
        sys.exit(1)

    s = pathlib.Path(S).read_text(encoding='utf-8')
    print(f'[检查] settings_page.dart: import models = {"import \'../models.dart\';" in s}')
    for k in ('_addList', '_confirmRemoveList', 'st.lists', 'addList', 'removeList'):
        print(f'[检查] 残留 {k}: {s.count(k)} 处')
    for k in ('aheadLabel'): 
        print(f'[检查] 用到 {k}: {s.count(k)} 处')
    print(f'\n全部 {len(EDITS)} 处替换完成。')


main()
