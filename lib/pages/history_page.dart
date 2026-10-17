import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';

/// 历史记录：统计以往每天 / 每周 / 每月做了多少事
///
/// 三种口径：按月看（一个月里的每一天）、多月看（自己勾选几个月对比）、
/// 按年看（12 个月柱状图 + 全年月份清单）。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final PageController _monthPc = PageController(initialPage: 1200);

  late DateTime _anchorMonth;

  /// 当前显示的月份（只用于标题）
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final DateTime n = DateTime.now();
    _anchorMonth = DateTime(n.year, n.month, 1);
    _month = DateTime(n.year, n.month, 1);
  }

  @override
  void dispose() {
    _monthPc.dispose();
    super.dispose();
  }

  static String _two(int v) => v < 10 ? '0$v' : '$v';
  static String _mk(DateTime d) => '${d.year}-${_two(d.month)}';

  // ---------------- 三种口径的数据 ----------------

  /// 多月：把选中的每个月汇总成一根柱
  List<_Bar> _monthsData() {
    final AppState st = AppState.I;
    final List<String> ms = st.historyMonths.toList()..sort();
    final List<_Bar> r = <_Bar>[];
    for (final String k in ms) {
      final DateTime? d = DateTime.tryParse('$k-01');
      if (d == null) continue;
      final StatSum s = AppState.sumOf(st.statsOfMonth(d.year, d.month));
      r.add(_Bar(label: '${d.month}月', sum: s, sub: '${d.year}'));
    }
    return r;
  }

  /// 按年：12 个月各一根柱
  List<_Bar> _yearData(int year) {
    final AppState st = AppState.I;
    final List<_Bar> r = <_Bar>[];
    for (int m = 1; m <= 12; m++) {
      final StatSum s = AppState.sumOf(st.statsOfMonth(year, m));
      r.add(_Bar(label: '$m月', sum: s, sub: ''));
    }
    return r;
  }

  // ---------------- 月份选择器 ----------------

  Future<void> _pickMonths() async {
    final AppState st = AppState.I;
    final Set<String> temp = Set<String>.from(st.historyMonths);
    final int nowYear = DateTime.now().year;
    final List<int> years = <int>[nowYear, nowYear - 1, nowYear - 2, nowYear - 3];

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => StatefulBuilder(
        builder: (BuildContext c, void Function(void Function()) setInner) => AlertDialog(
          title: const Text('选择要统计的月份', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final int y in years) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
                      child: Text(
                        '$y 年',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF5F5E5A)),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (int m = 1; m <= 12; m++)
                          FilterChip(
                            label: Text('$m月', style: const TextStyle(fontSize: 12)),
                            selected: temp.contains('$y-${_two(m)}'),
                            onSelected: (bool v) => setInner(() {
                              final String k = '$y-${_two(m)}';
                              if (v) {
                                temp.add(k);
                              } else {
                                temp.remove(k);
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => setInner(() {
                temp
                  ..clear()
                  ..addAll(<String>[
                    _mk(DateTime.now()),
                    _mk(DateTime(DateTime.now().year, DateTime.now().month - 1, 1)),
                  ]);
              }),
              child: const Text('近两个月'),
            ),
            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('确定')),
          ],
        ),
      ),
    );

    if (ok != true) return;
    st.historyMonths
      ..clear()
      ..addAll(temp);
    st.notifyListeners();
    await st.save();
  }

  Future<void> _pickYear() async {
    final AppState st = AppState.I;
    final int nowYear = DateTime.now().year;
    final List<int> years = <int>[nowYear, nowYear - 1, nowYear - 2, nowYear - 3, nowYear - 4];
    final int? y = await showDialog<int>(
      context: context,
      builder: (BuildContext c) => SimpleDialog(
        title: const Text('看哪一年', style: TextStyle(fontSize: 16)),
        children: <Widget>[
          for (final int v in years)
            SimpleDialogOption(
              onPressed: () => Navigator.of(c).pop(v),
              child: Text('$v 年', style: const TextStyle(fontSize: 14)),
            ),
        ],
      ),
    );
    if (y == null) return;
    st.historyYear = y;
    st.notifyListeners();
    await st.save();
  }

  Future<void> _setMode(String mode) async {
    final AppState st = AppState.I;
    if (st.historyMode == mode) return;
    st.historyMode = mode;
    if (mode == 'months' && st.historyMonths.isEmpty) {
      final DateTime n = DateTime.now();
      st.historyMonths.addAll(<String>[
        _mk(n),
        _mk(DateTime(n.year, n.month - 1, 1)),
      ]);
    }
    st.notifyListeners();
    await st.save();
  }

  // ---------------- 界面 ----------------

  @override
  Widget build(BuildContext context) {
    final AppState st = AppState.I;

    return Scaffold(
      appBar: AppBar(
        title: const Text('历史记录', style: TextStyle(fontSize: 16)),
        actions: <Widget>[
          if (st.historyMode == 'months')
            TextButton(
              onPressed: _pickMonths,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF185FA5),
                textStyle: const TextStyle(fontSize: 13),
              ),
              child: const Text('选月份'),
            ),
          if (st.historyMode == 'year')
            TextButton(
              onPressed: _pickYear,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF185FA5),
                textStyle: const TextStyle(fontSize: 13),
              ),
              child: Text('${st.historyYear} 年'),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: AnimatedBuilder(
        animation: st,
        builder: (BuildContext context, Widget? _) {
          return Column(
            children: <Widget>[
              _modeTabs(st),
              Expanded(
                child: st.historyMode == 'month'
                    ? _monthView(st)
                    : (st.historyMode == 'months' ? _multiMonthView(st) : _yearView(st)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _modeTabs(AppState st) {
    Widget tab(String mode, String label) {
      final bool on = st.historyMode == mode;
      return Expanded(
        child: InkWell(
          onTap: () => _setMode(mode),
          child: Container(
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? const Color(0xFF185FA5) : const Color(0xFFFFFFFF),
              border: Border.all(color: const Color(0xFFE4E4E6)),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                color: on ? const Color(0xFFFFFFFF) : const Color(0xFF5F5E5A),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: <Widget>[
          tab('month', '按月'),
          tab('months', '多月对比'),
          tab('year', '按年'),
        ],
      ),
    );
  }

  // ---- 按月：柱状图是每天完成数；左右翻月份 ----

  Widget _monthView(AppState st) {
    return Column(
      children: <Widget>[
        _monthNav(),
        Expanded(
          child: PageView.builder(
            controller: _monthPc,
            onPageChanged: (int i) => setState(() => _month = _monthOfPage(i)),
            itemBuilder: (BuildContext c, int page) => _monthPage(_monthOfPage(page)),
          ),
        ),
      ],
    );
  }

  DateTime _monthOfPage(int page) {
    final int diff = page - 1200;
    return DateTime(_anchorMonth.year, _anchorMonth.month + diff, 1);
  }

  Widget _monthPage(DateTime m) {
    final List<DayStat> days = AppState.I.statsOfMonth(m.year, m.month);
    final StatSum sum = AppState.sumOf(days);
    final List<DayStat> active = days
        .where((DayStat d) => d.total > 0 || d.finished > 0)
        .toList()
      ..sort((DayStat a, DayStat b) => b.day.compareTo(a.day));

    const double chartH = 244;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        SizedBox(
          height: chartH,
          child: _barCard(
            title: '${m.year}年${m.month}月',
            sub: '登记 ${sum.total} 条 · 完成 ${sum.done} 条 · 执行力 ${(sum.ratio * 100).round()}%',
            bars: <_Bar>[
              for (final DayStat d in days)
                _Bar(
                  label: '${d.day.day}',
                  sum: StatSum(total: d.total, done: d.done, finished: d.finished),
                  sub: '',
                ),
            ],
            dense: true,
          ),
        ),
        if (active.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 50),
            child: Text(
              '这个月还没有记录',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF9A9A9A)),
            ),
          )
        else
          for (final DayStat d in active) _dayRow(d),
      ],
    );
  }

  Widget _monthNav() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: '上一月',
            onPressed: () => _monthPc.previousPage(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            ),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Center(
              child: Text(
                '${_month.year}年${_month.month}月 · 左右滑动换月',
                style: const TextStyle(fontSize: 12, color: Color(0xFF5F5E5A)),
              ),
            ),
          ),
          IconButton(
            tooltip: '下一月',
            onPressed: () => _monthPc.nextPage(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            ),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _dayRow(DayStat d) {
    final AppState st = AppState.I;
    final String note = st.reviewNoteOf(d.day);
    return InkWell(
      onTap: () => _showDayDetail(d),
      child: Container(
        color: const Color(0xFFFFFFFF),
        margin: const EdgeInsets.only(bottom: 1),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 52,
              child: Text(
                '${d.day.month}/${d.day.day}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF2B2B2B)),
              ),
            ),
            Text(
              '星期${'一二三四五六日'[d.day.weekday - 1]}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9A9A9A)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    d.total == 0 ? '没有登记的待办' : '登记 ${d.total} 条 · 完成 ${d.done} 条（执行力 ${(d.ratio * 100).round()}%）',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF5F5E5A)),
                  ),
                  if (note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '有总结：${note.replaceAll('\n', ' ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF3F7D42)),
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBFBFBF)),
          ],
        ),
      ),
    );
  }

  void _showDayDetail(DayStat d) {
    final AppState st = AppState.I;
    final List<Todo> items = st.onDay(d.day);
    final String note = st.reviewNoteOf(d.day);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (BuildContext c2, ScrollController ctl) => ListView(
          controller: ctl,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            Text(
              '${dayLabel(d.day)} · 星期${'一二三四五六日'[d.day.weekday - 1]}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '登记 ${d.total} 条 · 完成 ${d.done} 条 · 当天勾掉 ${d.finished} 条',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)),
            ),
            const SizedBox(height: 16),
            if (note.isNotEmpty) ...<Widget>[
              const Text('那天的总结', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7FA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(note, style: const TextStyle(fontSize: 13, height: 1.65)),
              ),
              const SizedBox(height: 16),
            ],
            const Text('那天的待办', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (items.isEmpty)
              const Text('没有登记待办', style: TextStyle(fontSize: 13, color: Color(0xFF9A9A9A)))
            else
              for (final Todo t in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        t.done ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 16,
                        color: t.done ? const Color(0xFF185FA5) : const Color(0xFFBFBFBF),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t.title,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: t.done ? const Color(0xFF9A9A9A) : const Color(0xFF2B2B2B),
                          ),
                        ),
                      ),
                      Text(
                        Priority.nameOf(t.priority),
                        style: TextStyle(fontSize: 11, color: st.colorOf(t.priority)),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  // ---- 多月对比 ----

  Widget _multiMonthView(AppState st) {
    final List<_Bar> bars = _monthsData();
    if (bars.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                '还没选月份\n点右上角「选月份」，勾上想对比的月份',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF9A9A9A), height: 1.8),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _pickMonths, child: const Text('去选月份')),
            ],
          ),
        ),
      );
    }

    int total = 0;
    int done = 0;
    for (final _Bar b in bars) {
      total += b.sum.total;
      done += b.sum.done;
    }
    final double ratio = total == 0 ? 0 : done / total;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        SizedBox(
          height: 260,
          child: _barCard(
            title: '${bars.length} 个月对比',
            sub: '合计登记 $total 条 · 完成 $done 条 · 执行力 ${(ratio * 100).round()}%',
            bars: bars,
            dense: false,
          ),
        ),
        for (final _Bar b in bars)
          Container(
            color: const Color(0xFFFFFFFF),
            margin: const EdgeInsets.only(bottom: 1),
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 64,
                  child: Text(
                    '${b.sub} ${b.label}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: Text(
                    '登记 ${b.sum.total} 条 · 完成 ${b.sum.done} 条',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF5F5E5A)),
                  ),
                ),
                Text(
                  '${(b.sum.ratio * 100).round()}%',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF185FA5)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---- 按年 ----

  Widget _yearView(AppState st) {
    final List<_Bar> bars = _yearData(st.historyYear);
    int total = 0;
    int done = 0;
    for (final _Bar b in bars) {
      total += b.sum.total;
      done += b.sum.done;
    }
    final double ratio = total == 0 ? 0 : done / total;

    final List<_Bar> active = bars.where((_Bar b) => b.sum.total > 0).toList()
      ..sort((_Bar a, _Bar b) => b.sum.total.compareTo(a.sum.total));

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        SizedBox(
          height: 260,
          child: _barCard(
            title: '${st.historyYear} 年',
            sub: '全年登记 $total 条 · 完成 $done 条 · 执行力 ${(ratio * 100).round()}%',
            bars: bars,
            dense: false,
          ),
        ),
        if (active.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Text(
              '这一年还没有记录',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF9A9A9A)),
            ),
          )
        else
          for (final _Bar b in active)
            Container(
              color: const Color(0xFFFFFFFF),
              margin: const EdgeInsets.only(bottom: 1),
              padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 52,
                    child: Text(
                      b.label,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '登记 ${b.sum.total} 条 · 完成 ${b.sum.done} 条',
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF5F5E5A)),
                    ),
                  ),
                  Text(
                    '${(b.sum.ratio * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF185FA5),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  // ---- 柱状图 ----

  Widget _barCard({
    required String title,
    required String sub,
    required List<_Bar> bars,
    required bool dense,
  }) {
    double maxY = 1;
    for (final _Bar b in bars) {
      final double v = b.sum.done.toDouble();
      if (v > maxY) maxY = v;
    }
    maxY = maxY * 125 / 100; // 顶部留一点空间

    return Container(
      color: const Color(0xFFFFFFFF),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.fromLTRB(8, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 2),
            child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 10),
            child: Text(sub, style: const TextStyle(fontSize: 11.5, color: Color(0xFF9A9A9A))),
          ),
          Expanded(
            child: bars.isEmpty
                ? const Center(
                    child: Text('没有数据', style: TextStyle(fontSize: 13, color: Color(0xFF9A9A9A))),
                  )
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxY,
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (
                            BarChartGroupData group,
                            int groupIndex,
                            BarChartRodData rod,
                            int rodIndex,
                          ) {
                            final _Bar b = bars[group.x];
                            return BarTooltipItem(
                              '${b.sub.isEmpty ? '' : '${b.sub} '}${b.label}\n'
                              '登记 ${b.sum.total} · 完成 ${b.sum.done}',
                              const TextStyle(fontSize: 12, color: Color(0xFFFFFFFF)),
                            );
                          },
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxY <= 5 ? 1 : (maxY / 4).ceilToDouble(),
                        getDrawingHorizontalLine: (double v) => const FlLine(
                          color: Color(0xFFEDEDED),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 26,
                            interval: maxY <= 5 ? 1 : (maxY / 4).ceilToDouble(),
                            getTitlesWidget: (double v, TitleMeta meta) => Text(
                              v.toInt().toString(),
                              style: const TextStyle(fontSize: 10, color: Color(0xFF9A9A9A)),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            getTitlesWidget: (double v, TitleMeta meta) {
                              final int i = v.toInt();
                              if (i < 0 || i >= bars.length) return const SizedBox.shrink();
                              final String label = bars[i].label;
                              if (dense) {
                                // 一个月的每一天：只标 1/5/10/... 免得糊成一团
                                final int day = int.tryParse(label) ?? 0;
                                if (day % 5 != 1 && day != 1) return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  label,
                                  style: const TextStyle(fontSize: 9.5, color: Color(0xFF9A9A9A)),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: <BarChartGroupData>[
                        for (int i = 0; i < bars.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: <BarChartRodData>[
                              BarChartRodData(
                                toY: bars[i].sum.done.toDouble(),
                                width: dense ? 5 : 16,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                                color: bars[i].sum.done > 0
                                    ? const Color(0xFF185FA5)
                                    : const Color(0xFFE4E4E6),
                              ),
                            ],
                          ),
                      ],
                    ),
                    duration: const Duration(milliseconds: 220),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Bar {
  const _Bar({required this.label, required this.sum, required this.sub});
  final String label;
  final StatSum sum;
  final String sub;
}
