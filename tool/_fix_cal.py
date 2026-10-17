# -*- coding: utf-8 -*-
"""修 _dayCell 的 st_ 笔误：加 weekTag 参数，两个调用点补传"""
import io

P = r'D:\chaomu\lib\pages\calendar_page.dart'
with io.open(P, 'r', encoding='utf-8') as f:
    s = f.read()

pairs = [
    # 签名加参数
    (
        u"""  Widget _dayCell(
    DateTime d, {
    required bool isSel,
    required bool isToday,
    required List<Todo> items,
    required int maxShown,
  }) {""",
        u"""  Widget _dayCell(
    DateTime d, {
    required bool isSel,
    required bool isToday,
    required List<Todo> items,
    required int maxShown,
    required bool weekTag,
  }) {""",
    ),
    # 修掉 st_ 残留
    (
        u"""                // 展开态：右上角写中文星期（顶部图例已删，用户 2026-10-16 定的）
                if (!st_) ...<Widget>[_weekTag(d, isSel)],""",
        u"""                // 展开态：右上角写中文星期（顶部图例已删，用户 2026-10-16 定的）
                if (weekTag) _weekTag(d, isSel),""",
    ),
    # 收起态调用点
    (
        u"""                    child: _dayCell(
                      p.day,
                      isSel: sameDay(p.day, _selected),
                      isToday: sameDay(p.day, today),
                      items: st.onDay(p.day),
                      maxShown: p.maxShown,
                    ),""",
        u"""                    child: _dayCell(
                      p.day,
                      isSel: sameDay(p.day, _selected),
                      isToday: sameDay(p.day, today),
                      items: st.onDay(p.day),
                      maxShown: p.maxShown,
                      weekTag: false,
                    ),""",
    ),
    # 展开态调用点
    (
        u"""                            child: _dayCell(
                              p.day,
                              isSel: sameDay(p.day, _selected),
                              isToday: sameDay(p.day, today),
                              items: st.onDay(p.day),
                              maxShown: p.maxShown,
                            ),""",
        u"""                            child: _dayCell(
                              p.day,
                              isSel: sameDay(p.day, _selected),
                              isToday: sameDay(p.day, today),
                              items: st.onDay(p.day),
                              maxShown: p.maxShown,
                              weekTag: true,
                            ),""",
    ),
]

for old, new in pairs:
    n = s.count(old)
    assert n == 1, u'命中 %d 次: %s...' % (n, old[:60])
    s = s.replace(old, new)

with io.open(P, 'w', encoding='utf-8', newline='') as f:
    f.write(s)
print('OK: 4 处修正完成')
