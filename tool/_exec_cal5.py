# -*- coding: utf-8 -*-
"""展开态按定稿示意图实现：先宽后长、步长1、无缝紧贴、严格整数倍对齐"""
import io

P = r'D:\chaomu\lib\pages\calendar_page.dart'
s = io.open(P, 'r', encoding='utf-8').read()

pairs = []

# ---- 1. _Placed：回到整数档 ----
pairs.append((
    u"""  /// 横跨几列（默认态恒为 1；展开态 1~3）
  final int cols;

  /// 格子实际高度（像素，贴合内容不留大片空白）
  final double height;

  /// 占位行数（= height 向上取整 / 档高），后续日期按它跳过被占位置
  final int occupy;
}""",
    u"""  /// 横跨几列（默认态恒为 1；展开态最多 3）
  final int cols;

  /// 纵跨几档（1 档 = 初始矩形 x 的高），严格整数倍对齐
  final int span;
}""", 1,
))
pairs.append((
    u"""    this.cols,
    this.height,
    this.occupy,
  );""",
    u"""    this.cols,
    this.span,
  );""", 1,
))

# ---- 2. _measureExp：先宽后长、档位制 ----
old = u"""  /// 展开态测量：返回 (横跨几列, 格子精确高度)。
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
new = u"""  /// 展开态测量：返回 (横跨几列, 纵跨几档)。
  ///
  /// 规则（2026-10-17 示意图定稿）：装不下 → **先宽 +1（步长 1，最大 3 列）**
  /// → 宽到顶还装不下 → **长 +1（无限）**。步长恒为 1，边全部落在 x 的整数倍线上。
  /// 待办文字全部显示，无省略号。
  (int, int) _measureExp(List<Todo> show, double cellW, double unit) {
    const double head = 26; // 上下 padding + 日期行 + 间隔
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
    // 宽到顶（3 列）还装不下 → 长无限延伸
    return (3, span3);
  }"""
pairs.append((old, new, 1))

# ---- 3. _layoutExp：span 整数档 ----
old = u"""      final (int cols, double height) = _measureExp(show, cellW, unit);
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
new = u"""      final (int cols, int span) = _measureExp(show, cellW, unit);
      out.add(_Placed(day, r, c, cols, span, show.length));
      for (int dr = 0; dr < span; dr++) {
        for (int dc = 0; dc < cols; dc++) {
          (taken[r + dr] ??= <int>{}).add(c + dc);
        }
      }
      c += cols;
      if (r + span > maxRow) maxRow = r + span;"""
pairs.append((old, new, 1))

# ---- 4. Positioned 高度 = span * unit ----
old = u"""                              top: p.row * unit,
                              width: p.cols * cellW,
                              height: p.height,"""
new = u"""                              top: p.row * unit,
                              width: p.cols * cellW,
                              height: p.span * unit,"""
pairs.append((old, new, 1))

# ---- 5. _dayCell：无缝紧贴（去 margin）+ 去边框（线之前用户就删过） ----
old = u"""      child: Container(
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFFE8F0F8) : cellBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSel
                ? const Color(0xFF185FA5)
                : (isToday ? const Color(0xFF9CC0E0) : const Color(0xFFDFE2E8)),
            width: isSel ? 1.6 : 1,
          ),
        ),"""
new = u"""      child: Container(
        // 无缝紧贴：格子间不留空隙（2026-10-17 用户要求，只有四角圆角）
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFFE8F0F8) : cellBg,
          borderRadius: BorderRadius.circular(8),
        ),"""
pairs.append((old, new, 1))

for old, new, cnt in pairs:
    n = s.count(old)
    assert n == cnt, u'命中 %d(期望 %d): %s...' % (n, cnt, old[:60])
    s = s.replace(old, new)

io.open(P, 'w', encoding='utf-8', newline='').write(s)
c = {ch: s.count(ch) for ch in '(){}[]'}
assert c['('] == c[')'] and c['{'] == c['}'] and c['['] == c[']'], '括号不平衡'
print('OK 全部替换完成，括号配平')
