import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../guide.dart';
import '../models.dart';
import '../widgets.dart';
import 'detail_page.dart';

/// 网格里一个格子的位置：第几行、第几列、横跨几列、纵跨几档、能放几条待办
class _Placed {
  const _Placed(this.day, this.row, this.col, this.cols, this.span, this.maxShown);

  final DateTime day;
  final int row;
  final int col;

  /// 横跨几列（默认态恒为 1；展开态最多 3 —— 宽最大变 3 倍）
  final int cols;

  /// 纵跨几档（1 档 = 档高；展开态高不限档数）
  final int span;

  /// 这个高度里能完整放下几条待办（现全量显示，恒等于条数）
  final int maxShown;
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  static const List<String> _weekdayNames = <String>['一', '二', '三', '四', '五', '六', '日'];

  /// 收起时的**基础格高**（一档）。
  ///
  /// 收起态每个格子的高度永远是这个值的整数倍（1~4 档），
  /// 所以整块网格的纵向节奏统一，跨行留下的空白也正好是整数个格子。
  static const double _cellUnit = 44;

  /// 收起时最多跨几档（4 档 = 176dp）。
  static const int _maxSpan = 4;

  /// 每条待办最多占几行（排版参数，量高度和渲染必须同一套）
  static const int _todoWrapLines = 4;

  /// [TextStyle] 排版参数 —— 量高度和实际渲染必须用**同一套**
  static const double _todoFontSize = 10.5;
  static const double _todoLineHeight = 1.3;

  /// 同一天里不同待办用不同字色（见 [_todoIdx]）
  static const List<Color> _todoColors = <Color>[
    Color(0xFF185FA5), // 蓝   —— 与 _weekdayBg[0] 同色系
    Color(0xFF993C1D), // 赭红 —— 与 _weekdayBg[3] 同色系
    Color(0xFF3B6D11), // 绿   —— 与 _weekdayBg[2] 同色系
    Color(0xFF854F0B), // 棕   —— 与 _weekdayBg[1] 同色系
    Color(0xFF5B4B8A), // 紫   —— 与 _weekdayBg[4] 同色系
    Color(0xFF993556), // 玫红 —— 与 _weekdayBg[6] 同色系
    Color(0xFF0F6E56), // 青   —— 与 _weekdayBg[5] 同色系
  ];

  /// 周一 ~ 周日的格子底色（全是浅色）。
  ///
  /// 两个态都是跨行流式排布，列不代表星期几，用颜色把"这天是周几"补回来。
  static const List<Color> _weekdayBg = <Color>[
    Color(0xFFE8F1FA), // 周一 浅蓝
    Color(0xFFFDF1E3), // 周二 浅橙
    Color(0xFFEBF3E4), // 周三 浅绿
    Color(0xFFFBEBEB), // 周四 浅红
    Color(0xFFEFEDFA), // 周五 浅紫
    Color(0xFFE4F3F0), // 周六 浅青
    Color(0xFFFBEAF1), // 周日 浅粉
  ];

  /// 每个星期底色对应的 [_todoColors] **同色系**下标 —— 待办文字取色时要跳过它。
  static const List<int> _weekdaySkip = <int>[0, 3, 2, 1, 4, 6, 5];

  /// 中文星期数字的颜色（展开态格子右上角那个）：底色的同色系深色。
  static Color _weekdayInk(int i) => _todoColors[_weekdaySkip[i]];

  /// 这条待办用哪种字色：按原始位置取（勾掉一条其他不跳色），跳过底色同档
  static int _todoIdx(List<Todo> items, Todo t, int fallback, int weekday) {
    final int at = items.indexOf(t);
    int idx = at < 0 ? fallback : at;
    final int skip = _weekdaySkip[weekday - 1];
    if (idx >= skip) idx++;
    return idx % _todoColors.length;
  }

  static int _rowsOf(DateTime m) {
    final int leading = DateTime(m.year, m.month, 1).weekday - 1;
    final int days = DateTime(m.year, m.month + 1, 0).day;
    return ((leading + days) / 7).ceil();
  }

  /// 格子里实际要显示的待办：没完成的优先；全完成了就显示全部
  static List<Todo> _showOf(List<Todo> items) {
    final List<Todo> undone = items.where((Todo t) => !t.done).toList();
    return undone.isEmpty ? items : undone;
  }

  final TextEditingController _input = TextEditingController();

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
  }

  /// 翻月（两个态都是整块布局，翻月走标题栏箭头）
  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
    });
  }

  /// 默认态（跨行流式 + 当日列表）↔ 展开态（3/4 可变长宽总览页、无列表）
  void _toggleCollapsed() {
    final AppState st = AppState.I;
    st.setCalendarListCollapsed(!st.calendarListCollapsed);
  }

  Future<void> _addToSelected() async {
    final String s = _input.text.trim();
    if (s.isEmpty) return;
    _input.clear();
    await AppState.I.add(s, due: _selected);
  }

  // ---------------- 展开态排布 ----------------

  /// 展开态测量：返回 (横跨几列, 纵跨几档)。
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

  /// 这条标题在 [textW] 宽度下会折几行（和实际渲染同一套排版参数）
  static int _linesOf(String title, double textW) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: title.isEmpty ? '（未命名）' : title,
        style: const TextStyle(
          fontSize: _todoFontSize,
          height: _todoLineHeight,
          fontWeight: FontWeight.w500,
        ),
      ),
      maxLines: _todoWrapLines,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: textW < 8 ? 8 : textW);
    return tp.computeLineMetrics().length;
  }

  // ---------------- 收起态网格（跨行流式） ----------------

  /// 收起态排布（做法 B：跨行 + 后面的日期补空，从上往下、从左往右）
  List<_Placed> _layoutCollapsed(DateTime m, double cellW) {
    final AppState st = AppState.I;
    final int days = DateTime(m.year, m.month + 1, 0).day;
    final double textW = cellW - 8;

    final Map<int, Set<int>> taken = <int, Set<int>>{};
    bool free(int r, int c) => !(taken[r]?.contains(c) ?? false);

    final List<_Placed> out = <_Placed>[];
    int r = 0;
    int c = 0;
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
      final (int span, int maxShown) = _measure(show, textW);
      out.add(_Placed(day, r, c, 1, span, maxShown));
      for (int k = 0; k < span; k++) {
        (taken[r + k] ??= <int>{}).add(c);
      }
      c++;
    }
    return out;
  }

  /// 量一天需要占几档、这个高度里能完整放下几条待办（收起态）
  (int, int) _measure(List<Todo> show, double textW) {
    const double head = 33;
    const double lineH = _todoFontSize * _todoLineHeight;
    const double gap = 4;
    final double limit = _cellUnit * _maxSpan;

    double h = head;
    int shown = 0;
    for (final Todo t in show) {
      final double need = _linesOf(t.title, textW) * lineH + gap;
      if (shown > 0 && h + need > limit) break;
      h += need;
      shown++;
    }
    int span = (h / _cellUnit).ceil();
    if (span < 1) span = 1;
    if (span > _maxSpan) span = _maxSpan;
    return (span, shown);
  }

  /// 收起态月历：跨行流式网格，`Stack` + `Positioned` 手工定位
  Widget _monthGrid(DateTime m) {
    final AppState st = AppState.I;
    final DateTime today = dayOf(DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints cons) {
          final double cellW = cons.maxWidth / 7;
          final List<_Placed> placed = _layoutCollapsed(m, cellW);
          int rows = 0;
          for (final _Placed p in placed) {
            rows = math.max(rows, p.row + p.span);
          }
          return SizedBox(
            height: rows * _cellUnit,
            child: Stack(
              children: <Widget>[
                for (final _Placed p in placed)
                  Positioned(
                    left: p.col * cellW,
                    top: p.row * _cellUnit,
                    width: cellW,
                    height: p.span * _cellUnit,
                    child: _dayCell(
                      p.day,
                      isSel: sameDay(p.day, _selected),
                      isToday: sameDay(p.day, today),
                      items: st.onDay(p.day),
                      collapsed: true,
                      maxShown: p.maxShown,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------- 格子 ----------------

  /// collapsed = 收起态小格（彩底、文字最多 4 行省略、超了 +N）
  /// !collapsed = 展开态大格（彩底、右上角中文星期、文字全部完整显示）
  Widget _dayCell(
    DateTime d, {
    required bool isSel,
    required bool isToday,
    required List<Todo> items,
    required bool collapsed,
    int? maxShown,
  }) {
    final List<Todo> show = _showOf(items);
    final int maxShow = maxShown ?? show.length;
    final int extra = show.length - maxShow;

    final int tint = isSel ? 1 : d.weekday;
    final Color cellBg = _weekdayBg[tint - 1];

    return GestureDetector(
      onTap: () => setState(() => _selected = d),
      child: Container(
        // 默认态格间留 2px 缝（原样）；展开态无缝紧贴
        // 两个态格子间都留 2px 缝（2026-10-17 恢复）
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFFE8F0F8) : cellBg,
          borderRadius: BorderRadius.circular(8),
          // 默认态保留边框（原样）；展开态无缝无边框
          border: collapsed
              ? Border.all(
                  color: isSel
                      ? const Color(0xFF185FA5)
                      : (isToday ? const Color(0xFF9CC0E0) : const Color(0xFFDFE2E8)),
                  width: isSel ? 1.6 : 1,
                )
              : null,
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
                    fontSize: (isSel || isToday) ? 14 : 13,
                    fontWeight: (isSel || isToday) ? FontWeight.w700 : FontWeight.w500,
                    color: (isSel || isToday)
                        ? const Color(0xFF185FA5)
                        : const Color(0xFF2B2B2B),
                  ),
                ),
                const Spacer(),
                // 展开态：右上角写中文星期（跨行排布列不对齐，靠它 + 底色认星期）
                if (!collapsed) _weekTag(d, isSel),
                if (items.isNotEmpty)
                  const Text('+', style: TextStyle(fontSize: 10, color: Color(0xFF8E8E93))),
              ],
            ),
            const SizedBox(height: 4),
            for (int i = 0; i < show.length && i < maxShow; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  show[i].title.isEmpty ? '（未命名）' : show[i].title,
                  // 两个态都完整显示，不打省略号（2026-10-17 用户要求）
                  maxLines: collapsed ? _todoWrapLines : null,
                  overflow: collapsed ? TextOverflow.ellipsis : TextOverflow.visible,
                  style: TextStyle(
                    // 这几个值必须和 [_linesOf] 量高度时用的一模一样
                    fontSize: _todoFontSize,
                    height: _todoLineHeight,
                    fontWeight: FontWeight.w500,
                    color: show[i].done
                        ? const Color(0xFFBFBFBF)
                        : _todoColors[_todoIdx(items, show[i], i, tint)],
                    decoration:
                        show[i].done ? TextDecoration.lineThrough : TextDecoration.none,
                    decorationColor: const Color(0xFFBFBFBF),
                  ),
                ),
              ),
            if (extra > 0)
              const Align(
                alignment: Alignment.centerRight,
                child: Text('⋮', style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
              ),
          ],
        ),
      ),
    );
  }

  /// 展开态格子右上角的中文星期。选中格用蓝色。
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

  // ---------------- 当天列表（默认态） ----------------

  Widget _row(Todo t) {
    final AppState st = AppState.I;
    return InkWell(
      onTap: () async {
        await st.toggleDone(t);
      },
      onLongPress: () async {
        final int? q = await showQuadrantPicker(context, current: t.priority);
        if (q == null || !mounted) return;
        t.priority = q;
        await st.update(t);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 6, 11),
        child: Row(
          children: <Widget>[
            DoneCircle(done: t.done),
            const SizedBox(width: 12),
            PriorityBar(priority: t.priority),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    t.title,
                    style: TextStyle(
                      fontSize: 15,
                      color: t.done ? const Color(0xFF9A9A9A) : const Color(0xFF1F1F1F),
                      decoration: (t.done && !st.noStrike)
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      decorationColor: const Color(0xFF9A9A9A),
                    ),
                  ),
                  if (t.dueHasTime && t.due != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        timeLabel(t.due!),
                        style: TextStyle(
                          fontSize: 12,
                          color: t.done
                              ? const Color(0xFFB8B8B8)
                              : const Color(0xFF9A9A9A),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => DetailPage(todo: t)),
              ),
              icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFFB0B0B0)),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayList() {
    final AppState st = AppState.I;
    final List<Todo> items = st.onDay(_selected);
    st.sortGroup(items);

    if (items.isEmpty) {
      return const Center(
        child: Text('这天还没有待办', style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 14)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      itemCount: items.length,
      itemBuilder: (BuildContext c, int i) => _row(items[i]),
    );
  }

  Widget _inputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(top: BorderSide(color: Color(0xFFE8E8EA))),
      ),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _input,
                textInputAction: TextInputAction.done,
                onSubmitted: (String _) => _addToSelected(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '加到 ${shortDayLabel(_selected)}…',
                  hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFAAAAAA)),
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 15),
              ),
            ),
            TextButton(
              onPressed: _addToSelected,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                foregroundColor: const Color(0xFF185FA5),
              ),
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppState st = AppState.I;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_month.year}年${_month.month}月',
          style: const TextStyle(fontSize: 16),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '上一月',
            onPressed: () => _shiftMonth(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
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
        ],
      ),
      body: AnimatedBuilder(
        animation: st,
        builder: (BuildContext context, Widget? _) {
          try {
            return _calBody(st);
          } catch (e) {
            return _calErrBox('日历页构建出错', e);
          }
        },
      ),
    );
  }

  /// 日历页主体（包 try/catch 做白屏诊断）
  Widget _calBody(AppState st) {
    final bool collapsed = st.calendarListCollapsed;

    // 星期图例（色片）：只在默认态显示（展开态格子右上角有中文星期）
    final Widget legend = Padding(
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
    );

    // 折叠条（选中日期 + 切换）：只在默认态显示
    final Widget toggleBar = Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: InkWell(
        key: GuideKeys.collapseBtn,
        onTap: _toggleCollapsed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF5FB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFCFE0F0)),
          ),
          child: Row(
            children: <Widget>[
              Text(
                dayLabel(_selected),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF5F5E5A),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                relativeDayLabel(_selected),
                style: const TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)),
              ),
              const Spacer(),
              Text(
                '展开待办',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF185FA5),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down, size: 20, color: Color(0xFF185FA5)),
            ],
          ),
        ),
      ),
    );

    return Column(
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
    );
  }

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
        '$where\n\n$e',
        style: const TextStyle(fontSize: 13, color: Color(0xFFA32D2D), height: 1.6),
      ),
    );
  }
}
