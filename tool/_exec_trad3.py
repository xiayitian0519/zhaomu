# -*- coding: utf-8 -*-
"""从当前状态重放剩余补丁：删跨行段换传统网格 + calBody + margin"""
import io

P = r'D:\chaomu\lib\pages\calendar_page.dart'
s = io.open(P, 'r', encoding='utf-8').read()

done = 0

# ---- 1. 删跨行段（_layoutCollapsed + _measure + 旧 _monthGrid），换传统网格 ----
a_marker = u'  // ---------------- 收起态网格（跨行流式） ----------------'
b_marker = u'  // ---------------- 格子 ----------------'
if a_marker in s:
    a = s.index(a_marker)
    b = s.index(b_marker)
    new_grid = u"""  // ---------------- 默认态网格（传统排版） ----------------

  /// 默认态月历：**传统排版**（2026-10-17 用户定的）。
  ///
  /// 列对齐星期（1 号落在自己的星期列）、每行等高、**所有格子尺寸一致**
  /// （不随待办数量变化）。格内：日期 + 每条待办一行（省略号），容量满 ⋮。
  Widget _monthGrid(DateTime m, double rowH) {
    final AppState st = AppState.I;
    final DateTime today = dayOf(DateTime.now());
    final int leading = DateTime(m.year, m.month, 1).weekday - 1;
    final int daysInMonth = DateTime(m.year, m.month + 1, 0).day;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: <Widget>[
          for (int r = 0; r < _rowsOf(m); r++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int c = 0; c < 7; c++)
                  Expanded(
                    child: SizedBox(
                      height: rowH,
                      child: Builder(
                        builder: (BuildContext c2) {
                          final int idx = r * 7 + c;
                          if (idx < leading || idx >= leading + daysInMonth) {
                            return const SizedBox.shrink();
                          }
                          final DateTime d =
                              DateTime(m.year, m.month, idx - leading + 1);
                          return _dayCell(
                            d,
                            isSel: sameDay(d, _selected),
                            isToday: sameDay(d, today),
                            items: st.onDay(d),
                            collapsed: true,
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

"""
    s = s[:a] + new_grid + s[b:]
    done += 1
    print('OK 1: 传统网格已替换')

# ---- 2. _calBody 默认态：LayoutBuilder 算行高 ----
old = u"""          final Widget monthView = _monthGrid(_month);"""
if old in s:
    # 找到整个 monthArea 定义段（从 monthView 注释前到 Column 前）——先确认
    pass

# 实际结构：_calBody 里 monthView 定义已被上一轮替换成 monthArea？
# 检查当前状态
if u'final Widget monthView = _monthGrid(_month);' in s:
    # 旧结构还在：monthView 定义 + if(collapsed) Expanded(scroll(monthView)) else Flexible(AC)
    # 替换 monthView 定义行
    old_mv = u'          final Widget monthView = _monthGrid(_month);'
    # 保留行，只改使用处
old_cal = u"""        if (collapsed) ...<Widget>[
          const SizedBox(height: 8),
          legend,
          const SizedBox(height: 4),
          Expanded(child: SingleChildScrollView(child: _monthGrid(_month))),
          const Divider(height: 1),
          toggleBar,
          Expanded(child: _dayList()),
          _inputBar(),
        ]"""
new_cal = u"""        if (collapsed) ...<Widget>[
          const SizedBox(height: 8),
          legend,
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext ctx, BoxConstraints cons) {
                final double areaH =
                    cons.maxHeight.isFinite ? cons.maxHeight : 300.0;
                final double rowH = areaH / _rowsOf(_month);
                return _monthGrid(_month, rowH);
              },
            ),
          ),
          const Divider(height: 1),
          toggleBar,
          Expanded(child: _dayList()),
          _inputBar(),
        ]"""
n = s.count(old_cal)
assert n == 1, 'cal 默认段命中 %d' % n
s = s.replace(old_cal, new_cal)
done += 1
print('OK 2: cal 默认态 LayoutBuilder 行高')

# ---- 3. 展开态 margin 恢复 2px ----
old = u"""      child: Container(
        // 无缝紧贴：格子间不留空隙（只有四角圆角）
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),"""
new = u"""      child: Container(
        // 展开态：格子四周留 2px 间隙（2026-10-17 用户要求恢复）
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),"""
n = s.count(old)
assert n == 1, 'margin 命中 %d' % n
s = s.replace(old, new)
done += 1
print('OK 3: 展开态间隙')

io.open(P, 'w', encoding='utf-8', newline='').write(s)
c = {ch: s.count(ch) for ch in '(){}[]'}
assert c['('] == c[')'] and c['{'] == c['}'] and c['['] == c[']'], '括号不平衡'
print('ALL DONE (%d 处)' % done)
