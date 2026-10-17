# -*- coding: utf-8 -*-
"""pickTime 滚轮改双向环绕：00 之上是 59、之下是 01（用户 2026-10-16 定的方向）"""
import io

P = r'D:\chaomu\lib\widgets.dart'
with io.open(P, 'r', encoding='utf-8') as f:
    s = f.read()

pairs = [
    # 1) delegate 去掉 childCount = 无限滚动，label 按 count 取模
    (
        u"""        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count,
          builder: (BuildContext c, int i) {
            if (i < 0 || i >= count) return null;
            return _wheelItem(controller, i, labelOf(i));
          },
        ),""",
        u"""        childDelegate: ListWheelChildBuilderDelegate(
          // 不给 childCount = 上下都无限滚，label 按 count 取模环绕：
          // 00 之上是 59、之下是 01（用户 2026-10-16 定的双向滚轮），
          // 想选 59 从 00 往回拨一格就到，不用一路划到底
          builder: (BuildContext c, int i) {
            final int v = ((i % count) + count) % count;
            return _wheelItem(controller, i, labelOf(v));
          },
        ),""",
    ),
    # 2) 小时 onChanged 归一化
    (
        u"onChanged: (int i) => setState(() => _hour = i),",
        u"onChanged: (int i) => setState(() => _hour = ((i % 24) + 24) % 24),",
    ),
    # 3) 分钟 onChanged 归一化
    (
        u"onChanged: (int i) => setState(() => _minute = _minuteOptions[i]),",
        u"""onChanged: (int i) => setState(() {
                          final int n = _minuteOptions.length;
                          _minute = _minuteOptions[((i % n) + n) % n];
                        }),""",
    ),
]

for old, new in pairs:
    n = s.count(old)
    assert n == 1, u'命中 %d 次: %s...' % (n, old[:50])
    s = s.replace(old, new)

with io.open(P, 'w', encoding='utf-8', newline='') as f:
    f.write(s)
print('OK: 滚轮环绕 3 处改完')
