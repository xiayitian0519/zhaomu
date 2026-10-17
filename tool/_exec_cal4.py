# -*- coding: utf-8 -*-
"""展开态：去省略号（文字全显）+ 格子高度贴合内容（不强制取整档、无大片空白）"""
import io

P = r'D:\chaomu\lib\pages\calendar_page.dart'
s = io.open(P, 'r', encoding='utf-8').read()

pairs = []

# ---- 1. _Placed：span(档数) → height(实际像素高) + occupy(占位行数) ----
pairs.append((
    u"""  /// 横跨几列（默认态恒为 1；展开态最多 2）
  final int cols;

  /// 纵跨几档（默认态 1 档；展开态 1 档 = 动态档高）
  final int span;

  /// 这个高度里能完整放下几条待办，放不下的折成 +N
  final int maxShown;
}""",
    u"""  /// 横跨几列（默认态恒为 1；展开态 1~3）
  final int cols;

  /// 格子实际高度（像素，贴合内容不留大片空白）
  final double height;

  /// 占位行数（= height 向上取整 / 档高），后续日期按它跳过被占位置
  final int occupy;
}""", 1,
))
pairs.append((
    u"""class _Placed {
  const _Placed(
    this.day,
    this.row,
    this.col,
    this.cols,
    this.span,
    this.maxShown,
  );""",
    u"""class _Placed {
  const _Placed(
    this.day,
    this.row,
    this.col,
    this.cols,
    this.height,
    this.occupy,
  );""", 1,
))

# ---- 2. _measureExp：返回 (cols, 精确高度)；宽度 1~3 列选最贴的 ----
old = u"""  /// 展开态测量：返回 (横跨几列, 纵跨几档)。
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
new = u"""  /// 展开态测量：返回 (横跨几列, 格子精确高度)。
  ///
  /// 规则（用户 2026-10-17 定稿）：最小矩形为 x，
  /// 宽根据字数最多变 3 倍（跨 3 列，步长 = 1 列），高按内容**无限延伸**；
  /// **文字全部显示（无省略号），格子高度贴合内容**，只留边缘 padding。
  (int, double) _measureExp(List<Todo> show, double cellW, double unit) {
    const double head = 26; // 上下 padding + 日期行 + 间隔
    const double lineH = _todoFontSize * _todoLineHeight;
    const double gap = 4;
    const double emptyH = 28; // 空格子：日期行自己的高度

    if (show.isEmpty) return (1, emptyH);

    double needH(double w) {
      double h = head;
      for (final Todo t in show) {
        h += _linesOf(t.title, w - 8) * lineH + gap;
      }
      return h;
    }

    final double h1 = needH(cellW);
    if (h1 <= unit) return (1, h1);
    final double h2 = needH(cellW * 2);
    if (h2 <= unit) return (2, h2);
    final double h3 = needH(cellW * 3);
    if (h3 <= unit) return (3, h3);
    // 三种宽度都超 1 档：选内容最紧（总高最小）的宽度
    if (h1 <= h2 && h1 <= h3) return (1, h1);
    if (h2 <= h3) return (2, h2);
    return (3, h3);
  }"""
pairs.append((old, new, 1))

# ---- 3. _layoutExp：占位行数按 ceil(height/unit)，格子高度用精确值 ----
old = u"""      final DateTime day = DateTime(m.year, m.month, d);
      final List<Todo> show = _showOf(st.onDay(day));
      final (int cols, int span) = _measureExp(show, cellW, unit);
      out.add(_Placed(day, r, c, cols, span, show.length));
      for (int dr = 0; dr < span; dr++) {
        for (int dc = 0; dc < cols; dc++) {
          (taken[r + dr] ??= <int>{}).add(c + dc);
        }
      }
      c += cols;
      if (r + span > maxRow) maxRow = r + span;"""
new = u"""      final DateTime day = DateTime(m.year, m.month, d);
      final List<Todo> show = _showOf(st.onDay(day));
      final (int cols, double height) = _measureExp(show, cellW, unit);
      // 占位行数 = 高度按档高向上取整（后续日期跳过被占位置）；
      // 格子自身高度用精确值，贴合内容
      final int occupy = (height / unit).ceil();
      out.add(_Placed(day, r, c, cols, height, occupy));
      for (int dr = 0; dr < occupy; dr++) {
        for (int dc = 0; dc < cols; dc++) {
          (taken[r + dr] ??= <int>{}).add(c + dc);
        }
      }
      c += cols;
      if (r + occupy > maxRow) maxRow = r + occupy;"""
pairs.append((old, new, 1))

# ---- 4. _expandedMonth：Positioned 用精确高度 ----
old = u"""                              top: p.row * unit,
                              width: p.cols * cellW,
                              height: p.span * unit,"""
new = u"""                              top: p.row * unit,
                              width: p.cols * cellW,
                              height: p.height,"""
pairs.append((old, new, 1))

# ---- 5. _dayCell：文字完整显示（去 maxLines / ellipsis） ----
old = u"""                child: Text(
                  show[i].title.isEmpty ? '（未命名）' : show[i].title,
                  maxLines: _todoWrapLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: _todoFontSize,"""
new = u"""                child: Text(
                  show[i].title.isEmpty ? '（未命名）' : show[i].title,
                  // 文字完整显示，不许有省略号（2026-10-17 用户要求）
                  style: TextStyle(
                    fontSize: _todoFontSize,"""
pairs.append((old, new, 1))

for old, new, cnt in pairs:
    n = s.count(old)
    assert n == cnt, u'命中 %d(期望 %d): %s...' % (n, cnt, old[:60])
    s = s.replace(old, new)

io.open(P, 'w', encoding='utf-8', newline='').write(s)
c = {ch: s.count(ch) for ch in '(){}[]'}
assert c['('] == c[')'] and c['{'] == c['}'] and c['['] == c[']'], '括号不平衡'
print('OK 全部替换完成，括号配平')
