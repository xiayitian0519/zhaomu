# -*- coding: utf-8 -*-
"""默认态改传统排版（格子等大 + 每条一行省略 + 容量满 ⋮）+ 展开态恢复间隙"""
import io

P = r'D:\chaomu\lib\pages\calendar_page.dart'
s = io.open(P, 'r', encoding='utf-8').read()

pairs = []

# ---- 1. _dayCell：默认态每条一行省略、固定最多 2 条、超出 ⋮ ----
pairs.append((
    u"""    final List<Todo> show = _showOf(items);
    final int maxShow = maxShown ?? show.length;
    final int extra = show.length - maxShow;""",
    u"""    final List<Todo> show = _showOf(items);
    // 默认态：每格固定最多 2 条（每条一行省略），第 3 条起显示 ⋮
    // 展开态：文字全部完整显示
    final int maxShow = collapsed ? 2 : (maxShown ?? show.length);
    final int extra = show.length - maxShow;""", 1,
))
pairs.append((
    u"""                child: Text(
                  show[i].title.isEmpty ? '（未命名）' : show[i].title,
                  // 两个态都完整显示，不打省略号（2026-10-17 用户要求）
                  maxLines: collapsed ? _todoWrapLines : null,
                  overflow: collapsed ? TextOverflow.ellipsis : TextOverflow.visible,""",
    u"""                child: Text(
                  show[i].title.isEmpty ? '（未命名）' : show[i].title,
                  // 每条待办只占一行，超宽部分三点省略号
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,""", 1,
))
pairs.append((
    u"""            if (extra > 0)
              const Text('+N', style: TextStyle(fontSize: 9.5, color: Color(0xFF8E8E93))),""",
    u"""            if (extra > 0)
              const Align(
                alignment: Alignment.centerRight,
                child: Text('⋮', style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
              ),""", 1,
))

# ---- 2. 删跨行流式排布与测量（默认态不再用） ----
a = s.index(u'  // ---------------- 收起态网格（跨行流式） ----------------')
b = s.index(u'  // ---------------- 格子 ----------------')
s = s[:a] + s[b:]

# ---- 3. _monthGrid 整体替换为传统网格 ----
a = s.index(u'  /// 收起态月历：跨行流式网格，`Stack` + `Positioned` 手工定位')
b = s.index(u'  // ---------------- 格子 ----------------')
new_grid = u"""  /// 默认态月历：**传统排版**（2026-10-17 用户定的）。
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

# ---- 4. _calBody 默认态：LayoutBuilder 算行高（格子等大） ----
old = u"""    return Column(
      children: <Widget>[
        // ---- 默认态：跨行流式月历（Expanded 可滚）+ 当日列表，Expanded 均分 ≈ 各半 ----
        if (collapsed) ...<Widget>[
          const SizedBox(height: 8),
          legend,
          const SizedBox(height: 4),
          Expanded(child: SingleChildScrollView(child: _monthGrid(_month))),
          const Divider(height: 1),
          toggleBar,
          Expanded(child: _dayList()),
          _inputBar(),
        ]
        // ---- 展开态：纯总览页，月历占 3/4 顶对齐，无当日列表 ----
        else ...<Widget>[
          Expanded(child: SingleChildScrollView(child: _expandedGrid(st))),
        ],
      ],
    );"""
new = u"""    return Column(
      children: <Widget>[
        // ---- 默认态：传统排版月历（格子等大）+ 当日列表，Expanded 均分 ≈ 各半 ----
        if (collapsed) ...<Widget>[
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
        ]
        // ---- 展开态：纯总览页，月历占 3/4 顶对齐，无当日列表 ----
        else ...<Widget>[
          Expanded(child: SingleChildScrollView(child: _expandedGrid(st))),
        ],
      ],
    );"""
pairs.append((old, new, 1))
for old, new, cnt in pairs:
    n = s.count(old)
    assert n == cnt, u'命中 %d(期望 %d): %s...' % (n, cnt, old[:60])
    s = s.replace(old, new)

# ---- 5. _expandedGrid 恢复格子 2px 间隙 ----
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

# ---- 6. 清理：_measureExp/_layoutExp/_expandedGrid 里的 maxShown 引用保留（展开态全显，占位）----
io.open(P, 'w', encoding='utf-8', newline='').write(s)
c = {ch: s.count(ch) for ch in '(){}[]'}
assert c['('] == c[')'] and c['{'] == c['}'] and c['['] == c[']'], '括号不平衡'
print('OK 全部替换完成，括号配平')
