# -*- coding: utf-8 -*-
"""日历按用户截图规则重做：默认态白底纯日期格；展开态宽最多3倍、高无限延伸"""
import io

P = r'D:\chaomu\lib\pages\calendar_page.dart'
s = io.open(P, 'r', encoding='utf-8').read()

pairs = []

# ---- 1. 星期表头：色片 → 灰字（参照系统日历） ----
pairs.append((
    u"""    final Widget legend = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: List<Widget>.generate(
          7,
          (int i) => Expanded(
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _weekdayBg[i],
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0xFFDFE2E8)),
                ),
                child: Text(
                  _weekdayNames[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _weekdayInk(i),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );""",
    u"""    // 星期表头：纯灰字（参照系统日历的简洁样式）
    final Widget legend = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: List<Widget>.generate(
          7,
          (int i) => Expanded(
            child: Center(
              child: Text(
                _weekdayNames[i],
                style: const TextStyle(fontSize: 13, color: Color(0xFF888780)),
              ),
            ),
          ),
        ),
      ),
    );""",
    1,
))

# ---- 2. 默认态小格：白底、只有日期数字（待办文字全在下半列表里） ----
old_trad = u"""  /// 传统排版的一个小格：只有日期数字 + 最多 2 条小字，不放阳历 / 节气等标注
  Widget _dayCellTrad(
    DateTime d, {
    required bool isSel,
    required bool isToday,
    required List<Todo> items,
  }) {
    final List<Todo> show = _showOf(items);
    final int tint = isSel ? 1 : d.weekday;
    final Color bg = isSel ? const Color(0xFFE8F0F8) : _weekdayBg[tint - 1];

    return GestureDetector(
      onTap: () => setState(() => _selected = d),
      child: Container(
        margin: const EdgeInsets.all(1),
        padding: const EdgeInsets.fromLTRB(3, 2, 3, 2),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSel
                ? const Color(0xFF185FA5)
                : (isToday ? const Color(0xFF9CC0E0) : const Color(0xFFDFE2E8)),
            width: isSel ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  '${d.day}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: (isSel || isToday) ? FontWeight.w700 : FontWeight.w500,
                    color: (isSel || isToday)
                        ? const Color(0xFF185FA5)
                        : const Color(0xFF2B2B2B),
                  ),
                ),
                const Spacer(),
                if (items.isNotEmpty)
                  const Text('+', style: TextStyle(fontSize: 9, color: Color(0xFF8E8E93))),
              ],
            ),
            const SizedBox(height: 2),
            for (int i = 0; i < show.length && i < 2; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Text(
                  show[i].title.isEmpty ? '（未命名）' : show[i].title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    height: 1.25,
                    color: show[i].done
                        ? const Color(0xFFBFBFBF)
                        : _todoColors[_todoIdx(items, show[i], i, tint)],
                    decoration:
                        show[i].done ? TextDecoration.lineThrough : TextDecoration.none,
                    decorationColor: const Color(0xFFBFBFBF),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }"""
new_trad = u"""  /// 传统排版的一个小格：**只有日期数字**（参照系统日历截图，
  /// 不放农历 / 节气 / 待办文字 —— 待办统一在下半部分的当日列表里看）。
  /// 选中 = 蓝色实底白字，其余白底。
  Widget _dayCellTrad(
    DateTime d, {
    required bool isSel,
    required bool isToday,
    required List<Todo> items,
  }) {
    return GestureDetector(
      onTap: () => setState(() => _selected = d),
      child: Container(
        margin: const EdgeInsets.all(3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF185FA5) : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${d.day}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isSel
                ? const Color(0xFFFFFFFF)
                : (isToday ? const Color(0xFF185FA5) : const Color(0xFF2B2B2B)),
          ),
        ),
      ),
    );
  }"""
pairs.append((old_trad, new_trad, 1))

# ---- 3. 展开态测量：宽最多 3 倍、高无限延伸（去掉 3 档上限与 +N 截断） ----
old_m = u"""  /// 展开态测量：返回 (横跨几列, 纵跨几档, 能完整放几条)。
  ///
  /// 规则（用户拍板）：长度最多 3 倍、宽度最多 2 倍。
  (int, int, int) _measureExp(List<Todo> show, double cellW, double unit) {
    const double head = 33;
    const double lineH = _todoFontSize * _todoLineHeight;
    const double gap = 4;

    if (show.isEmpty) return (1, 1, 0);

    double needH(double w) {
      double h = head;
      for (final Todo t in show) {
        h += _linesOf(t.title, w - 8) * lineH + gap;
      }
      return h;
    }

    int shownIn(double w, double h) {
      double cur = head;
      int n = 0;
      for (final Todo t in show) {
        final double need = _linesOf(t.title, w - 8) * lineH + gap;
        if (n > 0 && cur + need > h) break;
        cur += need;
        n++;
      }
      return n;
    }

    final int span1 = (needH(cellW) / unit).ceil();
    final int span2 = (needH(cellW * 2) / unit).ceil();

    if (span1 <= 1) return (1, 1, show.length);
    if (span2 <= 1) return (2, 1, show.length);
    if (span2 <= _maxSpanExp) return (2, span2, show.length);
    if (span1 <= _maxSpanExp) {
      return (1, span1, shownIn(cellW, span1 * unit));
    }
    return (2, _maxSpanExp, shownIn(cellW * 2, _maxSpanExp * unit));
  }"""
new_m = u"""  /// 展开态测量：返回 (横跨几列, 纵跨几档)。
  ///
  /// 规则（用户 2026-10-17 截图定稿）：最小矩形为 x，
  /// **宽最多变为 3 倍（跨 3 列），长（高）按内容无限延伸**，步长 = x 的宽 / x 的高。
  /// 待办文字全部显示，不再截断 +N。
  (int, int) _measureExp(List<Todo> show, double cellW, double unit) {
    const double head = 33;
    const double lineH = _todoFontSize * _todoLineHeight;
    const double gap = 4;

    if (show.isEmpty) return (1, 1);

    double needH(double w) {
      double h = head;
      for (final Todo t in show) {
        h += _linesOf(t.title, w - 8) * lineH + gap;
      }
      return h;
    }

    final int span1 = (needH(cellW) / unit).ceil();
    if (span1 <= 1) return (1, 1);
    final int span2 = (needH(cellW * 2) / unit).ceil();
    if (span2 <= 1) return (2, 1);
    final int span3 = (needH(cellW * 3) / unit).ceil();
    if (span3 <= 1) return (3, 1);
    // 三种宽度都装不进 1 档：选档数最少（最省空间）的宽度，高无限延伸
    if (span1 <= span2 && span1 <= span3) return (1, span1);
    if (span2 <= span3) return (2, span2);
    return (3, span3);
  }"""
pairs.append((old_m, new_m, 1))

# ---- 4. _layoutExp 调用点适配（2 元组 + maxShown = 全部显示） ----
pairs.append((
    u"""      final (int cols, int span, int maxShown) = _measureExp(show, cellW, unit);
      out.add(_Placed(day, r, c, cols, span, maxShown));""",
    u"""      final (int cols, int span) = _measureExp(show, cellW, unit);
      out.add(_Placed(day, r, c, cols, span, show.length));""",
    1,
))

# ---- 5. _dayCell：去掉 +N 截断（全显示） ----
pairs.append((
    u"""    final List<Todo> show = _showOf(items);
    final int maxShow = maxShown < 0 ? show.length : maxShown;
    final int extra = show.length - maxShow;

    final int tint = isSel ? 1 : d.weekday;""",
    u"""    final List<Todo> show = _showOf(items);

    final int tint = isSel ? 1 : d.weekday;""", 1,
))
pairs.append((
    u"""            for (int i = 0; i < show.length && i < maxShow; i++)""",
    u"""            for (int i = 0; i < show.length; i++)""", 1,
))
pairs.append((
    u"""            if (extra > 0)
              const Text('+N', style: TextStyle(fontSize: 9.5, color: Color(0xFF8E8E93))),
          ],
        ),
      ),
    );
  }

  /// 展开态格子右上角的中文星期。选中格用蓝色。""",
    u"""          ],
        ),
      ),
    );
  }

  /// 展开态格子右上角的中文星期。选中格用蓝色。""", 1,
))

# ---- 6. 展开态整体高度：去掉 cap 截断，装不下向下延伸可滚 ----
pairs.append((
    u"""          final double baseline = bodyH * 0.75;
          // 底部输入栏至少留 70，月历不能无限往下长
          final double cap = (bodyH - 70).clamp(200.0, double.infinity);
          final double unit = (baseline / _rowsOf(_month)).clamp(56.0, double.infinity);""",
    u"""          final double baseline = bodyH * 0.75;
          final double unit = (baseline / _rowsOf(_month)).clamp(56.0, double.infinity);""", 1,
))
pairs.append((
    u"""                final double contentH = rows * unit;
                double blockH = contentH < baseline ? baseline : contentH;
                if (blockH > cap) blockH = cap;
                final DateTime today = dayOf(DateTime.now());""",
    u"""                final double contentH = rows * unit;
                // 装不下就向下延伸（整块可上下滚动），不再截断
                final double blockH = contentH < baseline ? baseline : contentH;
                final DateTime today = dayOf(DateTime.now());""", 1,
))

for old, new, cnt in pairs:
    n = s.count(old)
    assert n == cnt, u'命中 %d(期望 %d): %s...' % (n, cnt, old[:60])
    s = s.replace(old, new)

# _dayCell 的 maxShown 参数已无意义，删除参数与调用
old = u"""  Widget _dayCell(
    DateTime d, {
    required bool isSel,
    required bool isToday,
    required List<Todo> items,
    required int maxShown,
    required bool weekTag,
  }) {"""
new = u"""  Widget _dayCell(
    DateTime d, {
    required bool isSel,
    required bool isToday,
    required List<Todo> items,
    required bool weekTag,
  }) {"""
assert s.count(old) == 1
s = s.replace(old, new)
old = u"""                                items: st.onDay(p.day),
                                maxShown: p.maxShown,
                                weekTag: true,"""
new = u"""                                items: st.onDay(p.day),
                                weekTag: true,"""
assert s.count(old) == 1
s = s.replace(old, new)

io.open(P, 'w', encoding='utf-8', newline='').write(s)
c = {ch: s.count(ch) for ch in '(){}[]'}
assert c['('] == c[')'] and c['{'] == c['}'] and c['['] == c[']'], '括号不平衡'
print('OK 全部替换完成，括号配平')
