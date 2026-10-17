# -*- coding: utf-8 -*-
"""日历第 2 步：展开态改为「3/4 顶对齐总览页 + 可变长宽格子（宽≤3列、高不限、文字全显）」"""
import io

P = r'D:\chaomu\lib\pages\calendar_page.dart'
s = io.open(P, 'r', encoding='utf-8').read()

pairs = []

# ---- 1. _Placed 加 cols（展开态跨列用） ----
pairs.append((
    u"""class _Placed {
  const _Placed(this.day, this.row, this.col, this.span, this.maxShown);

  final DateTime day;
  final int row;
  final int col;

  /// 纵跨几档（1 档 = `_cellUnit` 那么高）
  final int span;""",
    u"""class _Placed {
  const _Placed(this.day, this.row, this.col, this.cols, this.span, this.maxShown);

  final DateTime day;
  final int row;
  final int col;

  /// 横跨几列（默认态恒为 1；展开态最多 3 —— 宽最大变 3 倍）
  final int cols;

  /// 纵跨几档（1 档 = 档高；展开态高不限档数）
  final int span;""", 1,
))

# ---- 2. state 字段：去 PageView 三件套 ----
pairs.append((
    u"""  static const int _basePage = 2400;
  static const List<String> _weekdayNames""",
    u"""  static const List<String> _weekdayNames""", 1,
))
pairs.append((
    u"""  final TextEditingController _input = TextEditingController();
  final PageController _pc = PageController(initialPage: _basePage);

  late final DateTime _anchor; // 固定锚点月，永不改变
  late DateTime _month; // 当前显示的月（1 号）
  late DateTime _selected; // 选中的日期

  @override
  void initState() {
    super.initState();
    final DateTime n = DateTime.now();
    _anchor = DateTime(n.year, n.month, 1);
    _month = _anchor;
    _selected = dayOf(n);
  }

  @override
  void dispose() {
    _pc.dispose();
    _input.dispose();
    super.dispose();
  }

  DateTime _monthOfPage(int page) => DateTime(_anchor.year, _anchor.month + (page - _basePage), 1);

  int _pageOfMonth(DateTime m) =>
      _basePage + (m.year - _anchor.year) * 12 + (m.month - _anchor.month);""",
    u"""  final TextEditingController _input = TextEditingController();

  late DateTime _month; // 当前显示的月（1 号）
  late DateTime _selected; // 选中的日期

  @override
  void initState() {
    super.initState();
    final DateTime n = DateTime.now();
    _month = DateTime(n.year, n.month, 1);
    _selected = dayOf(n);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }""", 1,
))
pairs.append((
    u"""  void _shiftMonth(int delta) {
    final DateTime next = DateTime(_month.year, _month.month + delta, 1);
    setState(() => _month = next);
    if (!_pc.hasClients) return;
    _pc.animateToPage(
      _pageOfMonth(next),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }""",
    u"""  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
    });
  }""", 1,
))
pairs.append((
    u"""  void _toggleCollapsed() {
    final AppState st = AppState.I;
    final bool willExpand = st.calendarListCollapsed;
    st.setCalendarListCollapsed(!st.calendarListCollapsed);
    if (!willExpand) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pc.hasClients) _pc.jumpToPage(_pageOfMonth(_month));
    });
  }""",
    u"""  void _toggleCollapsed() {
    final AppState st = AppState.I;
    st.setCalendarListCollapsed(!st.calendarListCollapsed);
  }""", 1,
))

# ---- 3. 新增展开态排布（行优先、宽 1→2→3、档位无限） ----
pairs.append((
    u"""  /// 这条标题在 [textW] 宽度下会折几行（和实际渲染同一套排版参数）""",
    u"""  /// 展开态测量：返回 (横跨几列, 纵跨几档)。
  ///
  /// 规则（2026-10-17 定稿）：最小矩形 x = 1 列宽 × 1 档高；
  /// 字数超出 → **先宽 +1（步长 1 列，最大 3 列）→ 宽到顶还装不下 → 长 +1（无限）**。
  /// 待办文字全部显示，无省略号。
  (int, int) _measureExp(List<Todo> show, double cellW, double unitH) {
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

    final int span1 = (needH(cellW) / unitH).ceil();
    if (span1 <= 1) return (1, 1);
    final int span2 = (needH(cellW * 2) / unitH).ceil();
    if (span2 <= 1) return (2, 1);
    final int span3 = (needH(cellW * 3) / unitH).ceil();
    if (span3 <= 1) return (3, 1);
    // 宽到顶（3 列）还装不下 → 长无限延伸
    return (3, span3);
  }

  /// 展开态排布：从 1 号起**从左到右、从上往下**，被大格占掉的位置跳过。
  /// 返回 (排好的格子, 网格总行数)。
  (List<_Placed>, int) _layoutExp(DateTime m, double cellW, double unitH) {
    final AppState st = AppState.I;
    final int days = DateTime(m.year, m.month + 1, 0).day;

    final Map<int, Set<int>> taken = <int, Set<int>>{}; // 行 -> 被占的列
    bool free(int r, int c) => !(taken[r]?.contains(c) ?? false);

    final List<_Placed> out = <_Placed>[];
    int r = 0;
    int c = 0;
    int maxRow = 0;
    for (int d = 1; d <= days; d++) {
      while (c > 6 || !free(r, c)) {
        c++;
        if (c > 6) {
          c = 0;
          r++;
        }
      }
      final DateTime day = DateTime(m.year, m.month, d);
      final List<Todo> show = _showOf(st.onDay(day));
      final (int cols, int span) = _measureExp(show, cellW, unitH);
      out.add(_Placed(day, r, c, cols, span, show.length));
      for (int dr = 0; dr < span; dr++) {
        for (int dc = 0; dc < cols; dc++) {
          (taken[r + dr] ??= <int>{}).add(c + dc);
        }
      }
      c += cols;
      if (r + span > maxRow) maxRow = r + span;
    }
    return (out, maxRow);
  }

  /// 这条标题在 [textW] 宽度下会折几行（和实际渲染同一套排版参数）""", 1,
))

# ---- 4. _dayCell：展开态 = 彩底 + 中文星期 + 文字全显 ----
pairs.append((
    u"""    final List<Todo> show = _showOf(items);
    // 收起态的条数预算由 [_measure] 按"这个格子实际有多高"算出来传进来；
    // 展开态固定一行一条，最多 3 条
    final int maxShow = collapsed ? (maxShown ?? show.length) : _maxLinesExpanded;
    final int extra = show.length - maxShow;

    // 底色按"这天是周几"取 —— 注意**不是按第几列**。
    // 收起态是跨行流式排布，列早就跟星期没关系了（见 [_layoutCollapsed]），
    // 所以只能拿日期自己的 `weekday` 上色，顺便把"今天周几"这个信息补回来。
    // 选中格固定浅蓝，就按"周一"那一档避让文字色。
    final int tint = isSel ? 1 : d.weekday;
    final Color cellBg = collapsed ? _weekdayBg[tint - 1] : const Color(0xFFFFFFFF);""",
    u"""    final List<Todo> show = _showOf(items);
    // 收起态的条数预算由 [_measure] 按"这个格子实际有多高"算出来传进来；
    // 展开态高不限档数，全部完整显示
    final int maxShow = maxShown ?? show.length;
    final int extra = show.length - maxShow;

    // 底色按"这天是周几"取 —— 注意**不是按第几列**。
    // 两个态都是跨行流式排布，列跟星期没关系，只能拿日期自己的 `weekday` 上色。
    // 选中格固定浅蓝，就按"周一"那一档避让文字色。
    final int tint = isSel ? 1 : d.weekday;
    final Color cellBg = _weekdayBg[tint - 1];""", 1,
))
pairs.append((
    u"""            Row(
              children: <Widget>[
                Text(
                  '${d.day}',
                  style: TextStyle(
                    fontSize: (isSel || isToday) ? 14 : 13,
                    fontWeight: (isSel || isToday) ? FontWeight.w700 : FontWeight.w500,
                    color: isSel
                        ? const Color(0xFF185FA5)
                        : (isToday ? const Color(0xFF185FA5) : const Color(0xFF2B2B2B)),
                  ),
                ),
                const Spacer(),
                if (items.isNotEmpty)""",
    u"""            Row(
              children: <Widget>[
                Text(
                  '${d.day}',
                  style: TextStyle(
                    fontSize: (isSel || isToday) ? 14 : 13,
                    fontWeight: (isSel || isToday) ? FontWeight.w700 : FontWeight.w500,
                    color: isSel
                        ? const Color(0xFF185FA5)
                        : (isToday ? const Color(0xFF185FA5) : const Color(0xFF2B2B2B)),
                  ),
                ),
                const Spacer(),
                // 展开态：右上角写中文星期（跨行排布列不对齐，靠它+底色认星期）
                if (!collapsed) _weekTag(d, isSel),
                if (items.isNotEmpty)""", 1,
))
pairs.append((
    u"""            SizedBox(height: collapsed ? 4 : 3),
            for (int i = 0; i < show.length && i < maxShow; i++)
              Padding(
                padding: EdgeInsets.only(bottom: collapsed ? 4 : 2),
                child: Text(
                  show[i].title.isEmpty ? '（未命名）' : show[i].title,
                  // 收起时放开换行（格子只有 1/7 屏宽，一行放不下几个字）；
                  // 展开时保持一行省略，免得把月历撑变形
                  maxLines: collapsed ? _todoWrapLines : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    // 这几个值必须和 [_linesOf] 量高度时用的一模一样，
                    // 差一点就会"量出来放得下、实际显示却溢出"
                    fontSize: collapsed ? _todoFontSize : 9.5,
                    height: _todoLineHeight,
                    fontWeight: collapsed ? FontWeight.w500 : FontWeight.w400,""",
    u"""            const SizedBox(height: 4),
            for (int i = 0; i < show.length && i < maxShow; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  show[i].title.isEmpty ? '（未命名）' : show[i].title,
                  // 两个态都完整显示，不打省略号（2026-10-17 用户要求）
                  maxLines: collapsed ? _todoWrapLines : null,
                  overflow: collapsed ? TextOverflow.ellipsis : TextOverflow.visible,
                  style: TextStyle(
                    // 这几个值必须和 [_linesOf] 量高度时用的一模一样，
                    // 差一点就会"量出来放得下、实际显示却溢出"
                    fontSize: _todoFontSize,
                    height: _todoLineHeight,
                    fontWeight: FontWeight.w500,""", 1,
))
pairs.append((
    u"""            if (extra > 0)
              Text(
                '+$extra',
                style: TextStyle(
                  fontSize: 9.5,
                  color: collapsed ? const Color(0xFF8E8E93) : const Color(0xFFAAAAAA),
                ),
              ),""",
    u"""            if (extra > 0)
              const Text('+N', style: TextStyle(fontSize: 9.5, color: Color(0xFF8E8E93))),""", 1,
))
# _dayCell 去边框（紧贴无缝后边框会变成 2px 网格线）
pairs.append((
    u"""        decoration: BoxDecoration(
          // 展开态保持白底（一屏要装全月，上色反而花）；
          // 收起态按星期上浅色，一眼能看出这格是周几
          color: isSel ? const Color(0xFFE8F0F8) : cellBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSel
                ? const Color(0xFF185FA5)
                : (isToday
                    ? const Color(0xFF9CC0E0)
                    // 浅色底上原来的 0xFFEDEDEF 几乎看不见 → 稍微加深一档
                    : (collapsed ? const Color(0xFFDFE2E8) : const Color(0xFFEDEDEF))),
            width: isSel ? 1.6 : 1,
          ),
        ),""",
    u"""        decoration: BoxDecoration(
          // 按星期上浅色；选中格浅蓝。格子紧贴无缝，不再画边框线
          color: isSel ? const Color(0xFFE8F0F8) : cellBg,
          borderRadius: BorderRadius.circular(8),
        ),""", 1,
))
# _dayCell margin 归零（无缝）
pairs.append((
    u"""      onTap: () => setState(() => _selected = d),
      child: Container(
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),""",
    u"""      onTap: () => setState(() => _selected = d),
      child: Container(
        // 无缝紧贴：格子间不留空隙（2026-10-17 用户要求，只有四角圆角）
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),""", 1,
))
# _weekTag 方法追加（挂在 _dayCell 之后）
pairs.append((
    u"""  // ---------------- 当天列表 ----------------""",
    u"""  /// 展开态格子右上角的中文星期。选中格用蓝色。
  Widget _weekTag(DateTime d, bool isSel) {
    final int i = d.weekday - 1;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Text(
        _weekdayNames[i],
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: isSel ? const Color(0xFF185FA5) : _weekdayInk(i),
        ),
      ),
    );
  }

  // ---------------- 当天列表 ----------------""", 1,
))

# ---- 5. build：AppBar 加切换按钮 + 两态重构 ----
pairs.append((
    u"""          IconButton(
            tooltip: '下一月',
            onPressed: () => _shiftMonth(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],""",
    u"""          IconButton(
            tooltip: '下一月',
            onPressed: () => _shiftMonth(1),
            icon: const Icon(Icons.chevron_right),
          ),
          TextButton(
            onPressed: _toggleCollapsed,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF185FA5),
              textStyle: const TextStyle(fontSize: 13),
            ),
            child: Text(st.calendarListCollapsed ? '展开' : '收起'),
          ),
          const SizedBox(width: 4),
        ],""", 1,
))
pairs.append((
    u"""          // 收起时行高由内容决定（待办要换行，高度事先算不出来），
          // **塞不进 PageView** —— PageView 必须有确定高度。所以收起态直接
          // 渲染当前月，外面套 Expanded + 可滚：月历能上下滚，翻月用标题栏箭头。
          // 展开态每格固定一行、高度可算，才用 PageView 保留左右滑动手感。
          final Widget monthView = _monthGrid(_month);""",
    u"""          // 收起：跨行流式（有事的那天变长），Expanded + 可滚
          // 展开：可变长宽大格总览页，占屏幕 3/4 顶对齐，装不下向下延伸可滚
          final Widget monthArea = collapsed
              ? Expanded(child: SingleChildScrollView(child: _monthGrid(_month)))
              : Expanded(child: SingleChildScrollView(child: _expandedGrid(st)));""", 1,
))
pairs.append((
    u"""          return Column(
            children: <Widget>[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: List<Widget>.generate(
                    7,
                    (int i) => Expanded(
                      child: Center(
                        child: Container(
                          width: _weekdayChip,
                          height: _weekdayChip,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            // 方片填的就是这一天格子底色的原色 —— 和下面格子完全一致，
                            // 不用记「什么颜色代表周几」，直接对色就行
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
              ),
              const SizedBox(height: 4),

              // 月历整块。
              //
              // 收起：只有"有事的那天"自己变长，行的总高 = 该行最高的那格，
              // 所以整块高度事先算不出来 —— 用 Expanded 占满剩余空间、内部可滚。
              // **不能定高**：之前估了个高度塞定值，6 行溢出就把下面
              // 「展开待办」那一行挤出屏幕，用户找不到展开键。
              // 展开：行高固定（每格一行省略号），高度 = 行数 × 行高。
              if (collapsed)
                Expanded(
                  child: SingleChildScrollView(child: monthView),
                )
              else
                Flexible(
                  flex: 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    height: _rowsOf(_month) * _rowHeight,
                    child: monthView,
                  ),
                ),

              const Divider(height: 1),""",
    u"""          return Column(
            children: <Widget>[
              if (collapsed) ...<Widget>[
                const SizedBox(height: 8),
                legend,
                const SizedBox(height: 4),
              ],

              monthArea,

              if (!collapsed) const Divider(height: 1),""", 1,
))
# 折叠行只在收起态有（展开态无列表、无折叠条、无输入栏）
pairs.append((
    u"""              // 这一行是「选中日期 + 折叠按钮」。
              // 点右边的箭头把下面的待办列表收起来，月历就变高、每格能多显示几条。
              // 折叠时整行加浅底 + 描边，让「展开待办」一眼能找到
              // （之前太素，用户收起来之后找不到展开的地方）。
              Padding(""",
    u"""              // 这一行是「选中日期 + 折叠按钮」（只在默认态显示；
              // 展开态是纯总览页，切换入口在标题栏「收起」）。
              Padding(""", 1,
))
pairs.append((
    u"""                padding: EdgeInsets.fromLTRB(10, 6, 10, st.calendarListCollapsed ? 10 : 4),
                child: InkWell(
                  key: GuideKeys.collapseBtn,""",
    u"""                padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                child: InkWell(
                  key: GuideKeys.collapseBtn,""", 1,
))
pairs.append((
    u"""              // 折叠时这块整个收走，把高度让给月历
              if (!st.calendarListCollapsed) ...<Widget>[
                Expanded(child: _dayList()),
                _inputBar(),
              ],""",
    u"""              // 展开态才有当日待办列表和输入栏（总览时整块让给月历）
              if (!st.calendarListCollapsed) ...<Widget>[
                Expanded(child: _dayList()),
                _inputBar(),
              ],""", 1,
))

# ---- 6. 追加 _expandedGrid 与 _calErrBox ----
tail = u'''

  /// 展开态总览月历：占屏幕 3/4、顶对齐；格子可变长宽（宽≤3 列、高不限档），
  /// 待办文字全部显示；装不下整块向下延伸，可上下滚动。
  /// 没有当日待办列表（总览页，2026-10-17 用户定的）。
  Widget _expandedGrid(AppState st) {
    final DateTime today = dayOf(DateTime.now());
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints cons) {
        try {
          // ⚠️ 防御：万一拿到无穷高（本不该发生），兜成 600
          final double bodyH = cons.maxHeight.isFinite ? cons.maxHeight : 600.0;
          final double areaH = bodyH * 0.75;
          final double unitH = (areaH / _rowsOf(_month)).clamp(48.0, double.infinity);

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: LayoutBuilder(
              builder: (BuildContext c2, BoxConstraints wCons) {
                final double cellW = wCons.maxWidth / 7;
                final List<_Placed> placed;
                final int rows;
                try {
                  final (List<_Placed> pTmp, int rTmp) = _layoutExp(_month, cellW, unitH);
                  placed = pTmp;
                  rows = rTmp;
                } catch (e) {
                  return _calErrBox('展开态排布出错', e);
                }
                final double contentH = rows * unitH;
                // 顶对齐：内容不足 3/4 时块高仍为 3/4（底部留白）；
                // 内容超出 3/4 → 块高随内容（外层可滚）
                final double blockH = contentH < areaH ? areaH : contentH;

                return SizedBox(
                  height: blockH,
                  child: SingleChildScrollView(
                    child: SizedBox(
                      height: contentH,
                      child: Stack(
                        children: <Widget>[
                          for (final _Placed p in placed)
                            Positioned(
                              left: p.col * cellW,
                              top: p.row * unitH,
                              width: p.cols * cellW,
                              height: p.span * unitH,
                              child: _dayCell(
                                p.day,
                                isSel: sameDay(p.day, _selected),
                                isToday: sameDay(p.day, today),
                                items: st.onDay(p.day),
                                collapsed: false,
                                maxShown: p.maxShown,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        } catch (e) {
          return _calErrBox('展开态计算出错', e);
        }
      },
    );
  }

  /// 白屏诊断：任何构建 / 排布异常直接显示成红字（release 包也能看到）
  Widget _calErrBox(String where, Object e) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Text(
        '$where\\n\\n$e',
        style: const TextStyle(fontSize: 13, color: Color(0xFFA32D2D), height: 1.6),
      ),
    );
  }
}
'''
tail_anchor = u"""      ),
    );
  }
}
"""
n = s.count(tail_anchor)
assert n == 1, '文件尾锚点命中 %d' % n
s = s[: s.rindex(tail_anchor)] + tail

for old, new, cnt in pairs:
    n = s.count(old)
    assert n == cnt, u'命中 %d(期望 %d): %s...' % (n, cnt, old[:60])
    s = s.replace(old, new)

io.open(P, 'w', encoding='utf-8', newline='').write(s)
c = {ch: s.count(ch) for ch in '(){}[]'}
assert c['('] == c[')'] and c['{'] == c['}'] and c['['] == c[']'], '括号不平衡'
print('OK 全部替换完成，括号配平')
