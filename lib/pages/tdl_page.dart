import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets.dart';

/// TDL 时间轴：每天一张时间表，点格子写内容，自动算时长
class TdlPage extends StatefulWidget {
  const TdlPage({super.key});

  @override
  State<TdlPage> createState() => _TdlPageState();
}

class _TdlPageState extends State<TdlPage> {
  DateTime _day = dayOf(DateTime.now());

  /// 刻度候选：以当前刻度为中心，给几个"改时长"的快捷值
  List<int> _durationPresets() {
    final int step = AppState.I.tdlStep;
    final Set<int> s = <int>{step, step * 2, step * 3};
    // 补几个常用值，去掉不合理的
    s.addAll(<int>[10, 15, 30, 45, 60, 90, 120]);
    final List<int> l = s.where((int v) => v >= 1 && v <= 720).toList()..sort();
    return l;
  }

  /// 时长的中文说法
  String _lenLabel(int m) {
    if (m < 60) return '$m 分钟';
    final int h = m ~/ 60;
    final int mm = m % 60;
    if (mm == 0) return '$h 小时';
    return '$h 小时 $mm 分';
  }

  Future<void> _pickDay() async {
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '写哪一天的 TDL',
    );
    if (d == null) return;
    setState(() => _day = dayOf(d));
  }

  Future<void> _closeBar() async {
    final AppState st = AppState.I;
    final List<TdlBlock> l = st.tdlOf(_day);
    if (l.isEmpty) return;

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('关掉整天？', style: TextStyle(fontSize: 16)),
        content: const Text(
          '会在这天末尾加一条「22:00-23:00 休息」的收尾段，方便收工。\n只影响这一天。',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('不用')),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('加上')),
        ],
      ),
    );
    if (ok != true) return;

    await st.tdlAdd(
      _day,
      TdlBlock(
        id: st.newId(),
        startMin: 22 * 60,
        endMin: 23 * 60,
        text: '收尾 · 复盘今天',
      ),
    );
  }

  Future<void> _editBar(TdlBlock b) async {
    final AppState st = AppState.I;
    // 滚轮选择器要用**页面的 context**（下面的 _pageCtx）。
    // 不能用 showDialog 的 builder context（下面叫 dlg）—— 那个 context 的
    // 最近 Navigator 是 dialog 自己的，弹 bottom sheet 会被压在弹窗下面看不见。
    final BuildContext _pageCtx = context;
    final TextEditingController ctl = TextEditingController(text: b.text);
    final _TimePair range = _TimePair(b.startMin, b.endMin);

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dlg) => StatefulBuilder(
        builder: (BuildContext dlg, void Function(void Function()) setInner) => AlertDialog(
          title: Text(
            '${tdlLabel(range.start)}-${tdlLabel(range.end)}',
            style: const TextStyle(fontSize: 15),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: ctl,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: '这段时间做什么？例如：练口语',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  const Text('开始', style: TextStyle(fontSize: 12, color: Color(0xFF5F5E5A))),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: () async {
                      final TimeOfDay? t = await pickTime(
                        _pageCtx,
                        initial: TimeOfDay(hour: range.start ~/ 60, minute: range.start % 60),
                        helpText: '开始时刻',
                      );
                      if (t != null) setInner(() => range.start = t.hour * 60 + t.minute);
                    },
                    child: Text(tdlLabel(range.start), style: const TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 14),
                  const Text('结束', style: TextStyle(fontSize: 12, color: Color(0xFF5F5E5A))),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: () async {
                      final TimeOfDay? t = await pickTime(
                        _pageCtx,
                        initial: TimeOfDay(hour: range.end ~/ 60, minute: range.end % 60),
                        helpText: '结束时刻',
                      );
                      if (t != null) setInner(() => range.end = t.hour * 60 + t.minute);
                    },
                    child: Text(tdlLabel(range.end), style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '按开始时间往后改时长',
                style: TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  for (final int m in _durationPresets())
                    ActionChip(
                      label: Text(_lenLabel(m), style: const TextStyle(fontSize: 12)),
                      onPressed: () => setInner(() => range.end = range.start + m),
                    ),
                ],
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                ctl.text = '';
                Navigator.of(dlg).pop(true);
              },
              child: const Text('清空', style: TextStyle(color: Color(0xFFA32D2D))),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dlg).pop(false);
                await st.tdlRemove(_day, b);
              },
              child: const Text('删掉这段', style: TextStyle(color: Color(0xFFA32D2D))),
            ),
            FilledButton(onPressed: () => Navigator.of(dlg).pop(true), child: const Text('保存')),
          ],
        ),
      ),
    );

    final String v = ctl.text;
    ctl.dispose();
    if (ok != true) return;

    b.text = v;
    b.startMin = range.start;
    b.endMin = range.end;
    await st.tdlUpdate(_day, b);
  }

  /// 添加一条日程。
  ///
  /// 之前这里叫「加一段」，而且时间段是**写死的**（固定沿用时间表的起始 +
  /// 一个刻度），加出来的每一条时间都一样 —— 看起来就像「加了没反应」。
  /// 现在改成可以自己挑起止时刻，加进去的每条都是独立时间段。
  Future<void> _addFreeBar() async {
    final AppState st = AppState.I;
    // 滚轮要用页面 context，不能用 dialog 的 builder context（会叠在弹窗下面）
    final BuildContext _pageCtx = context;
    final TextEditingController ctl = TextEditingController();
    final _TimePair range = _TimePair(st.tdlStartMin, st.tdlStartMin + st.tdlStep);

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dlg) => StatefulBuilder(
        builder: (BuildContext dlg, void Function(void Function()) setInner) => AlertDialog(
          title: const Text('添加日程', style: TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: ctl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '这段时间做什么？',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 14),
              const Text(
                '时间段',
                style: TextStyle(fontSize: 12, color: Color(0xFF5F5E5A)),
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  OutlinedButton(
                    onPressed: () async {
                      final TimeOfDay? t = await pickTime(
                        _pageCtx,
                        initial: TimeOfDay(hour: range.start ~/ 60, minute: range.start % 60),
                        helpText: '开始时刻',
                      );
                      if (t != null) setInner(() => range.start = t.hour * 60 + t.minute);
                    },
                    child: Text(tdlLabel(range.start), style: const TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 8),
                  const Text('到', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      final TimeOfDay? t = await pickTime(
                        _pageCtx,
                        initial: TimeOfDay(hour: range.end ~/ 60, minute: range.end % 60),
                        helpText: '结束时刻',
                      );
                      if (t != null) setInner(() => range.end = t.hour * 60 + t.minute);
                    },
                    child: Text(tdlLabel(range.end), style: const TextStyle(fontSize: 14)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '点时刻可以改。加好之后，点每条左边的时间也能再调。',
                style: TextStyle(fontSize: 11, color: Color(0xFF9A9A9A)),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(dlg).pop(false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.of(dlg).pop(true), child: const Text('添加')),
          ],
        ),
      ),
    );

    final String v = ctl.text;
    ctl.dispose();
    if (ok != true || v.trim().isEmpty) return;

    await st.tdlAdd(
      _day,
      TdlBlock(
        id: st.newId(),
        startMin: range.start,
        // 结束早于开始就补一份默认时长，别存出负数
        endMin: range.end <= range.start ? range.start + st.tdlStep : range.end,
        text: v.trim(),
      ),
    );
  }

  /// 单独调某一条的时间段。点列表里每条左边的时间会调这个。
  ///
  /// 比如把 07:00-09:00 改成 07:00-08:00，在这儿改完立刻生效。
  Future<void> _editTimeRange(TdlBlock b) async {
    final AppState st = AppState.I;
    final BuildContext _pageCtx = context;
    final _TimePair range = _TimePair(b.startMin, b.endMin);
    final bool ok = await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (BuildContext dlg) => StatefulBuilder(
            builder: (BuildContext dlg, void Function(void Function()) setInner) => Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFFFFFF),
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 2),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '调整时间段',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '点下面两个时刻可以改',
                          style: TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)),
                        ),
                      ),
                    ),
                    ListTile(
                      title: const Text('开始时刻', style: TextStyle(fontSize: 14)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            tdlLabel(range.start),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF185FA5),
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 18),
                        ],
                      ),
                      onTap: () async {
                        final TimeOfDay? t = await pickTime(
                          _pageCtx,
                          initial: TimeOfDay(hour: range.start ~/ 60, minute: range.start % 60),
                          helpText: '开始时刻',
                        );
                        if (t != null) setInner(() => range.start = t.hour * 60 + t.minute);
                      },
                    ),
                    ListTile(
                      title: const Text('结束时刻', style: TextStyle(fontSize: 14)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            tdlLabel(range.end),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF185FA5),
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 18),
                        ],
                      ),
                      onTap: () async {
                        final TimeOfDay? t = await pickTime(
                          _pageCtx,
                          initial: TimeOfDay(hour: range.end ~/ 60, minute: range.end % 60),
                          helpText: '结束时刻',
                        );
                        if (t != null) setInner(() => range.end = t.hour * 60 + t.minute);
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: SizedBox(
                              height: 46,
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(dlg).pop(false),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  side: const BorderSide(color: Color(0xFFD5DFEA)),
                                ),
                                child: const Text('取消', style: TextStyle(fontSize: 15)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SizedBox(
                              height: 46,
                              child: FilledButton(
                                onPressed: () => Navigator.of(dlg).pop(true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF185FA5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  '确定',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;
    if (!ok) return;
    await st.tdlUpdate(
      _day,
      TdlBlock(
        id: b.id,
        startMin: range.start,
        endMin: range.end <= range.start ? range.start + st.tdlStep : range.end,
        text: b.text,
        done: b.done,
      ),
    );
  }

  Future<void> _settings() async {
    final AppState st = AppState.I;
    // 同上：滚轮要用页面 context，不用 dialog 的 builder context
    final BuildContext _pageCtx = context;
    int start = st.tdlStartMin;
    int end = st.tdlEndMin;
    int step = st.tdlStep;
    final TextEditingController stepCtl = TextEditingController(text: '$step');

    await showDialog<void>(
      context: context,
      builder: (BuildContext dlg) => StatefulBuilder(
        builder: (BuildContext dlg, void Function(void Function()) setInner) => AlertDialog(
          title: const Text('时间表设置', style: TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('一天从几点到几点', style: TextStyle(fontSize: 13, color: Color(0xFF5F5E5A))),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: () async {
                        final TimeOfDay? t = await pickTime(
                          _pageCtx,
                          initial: TimeOfDay(hour: start ~/ 60, minute: start % 60),
                          helpText: '一天从几点开始',
                        );
                        if (t != null) setInner(() => start = t.hour * 60 + t.minute);
                      },
                      child: Text(tdlLabel(start), style: const TextStyle(fontSize: 13)),
                    ),
                    const SizedBox(width: 10),
                    const Text('到', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () async {
                        final TimeOfDay? t = await pickTime(
                          _pageCtx,
                          initial: TimeOfDay(hour: end ~/ 60, minute: end % 60),
                          helpText: '一天到几点结束',
                        );
                        if (t != null) setInner(() => end = t.hour * 60 + t.minute);
                      },
                      child: Text(tdlLabel(end), style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('时间刻度', style: TextStyle(fontSize: 13, color: Color(0xFF5F5E5A))),
                const SizedBox(height: 4),
                const Text(
                  '随便填分钟数（1~720），比如 7 分钟、45 分钟、100 分钟都行。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 96,
                      child: TextField(
                        controller: stepCtl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          isDense: true,
                          suffixText: '分',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        ),
                        style: const TextStyle(fontSize: 14),
                        onChanged: (String v) {
                          final int? n = int.tryParse(v.trim());
                          if (n != null && n >= 1 && n <= 720) {
                            setInner(() => step = n);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        step < 1 || step > 720 ? '超出范围（1~720）' : '当前 $step 分钟一段',
                        style: TextStyle(
                          fontSize: 12,
                          color: (step < 1 || step > 720)
                              ? const Color(0xFFA32D2D)
                              : const Color(0xFF5F5E5A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final int s in AppState.tdlStepPresets)
                      ChoiceChip(
                        label: Text(_lenLabel(s), style: const TextStyle(fontSize: 12)),
                        selected: step == s,
                        onSelected: (bool v) {
                          if (!v) return;
                          stepCtl.text = '$s';
                          setInner(() => step = s);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  (end - start) <= 0
                      ? '结束时间要在开始之后。'
                      : '按这个刻度，一天能切成 ${(end - start) ~/ (step < 1 ? 1 : step)} 段。',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                stepCtl.dispose();
                Navigator.of(dlg).pop();
              },
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                // 以输入框里的数字为准（用户可能输了没触发 onChanged 的边界值）
                final int? typed = int.tryParse(stepCtl.text.trim());
                final int finalStep = (typed != null && typed >= 1 && typed <= 720) ? typed : step;
                await st.setTdlRange(start, end);
                await st.setTdlStep(finalStep);
                stepCtl.dispose();
                if (!dlg.mounted) return;
                Navigator.of(dlg).pop();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  /// 生成一段空的时间表（按刻度铺满）
  Future<void> _generateSlots() async {
    final AppState st = AppState.I;
    final List<int> slots = st.tdlSlots();
    if (slots.isEmpty) return;

    final List<TdlBlock> exist = st.tdlOf(_day);
    final Set<int> used = exist.map((TdlBlock e) => e.startMin).toSet();

    int added = 0;
    for (final int s in slots) {
      if (used.contains(s)) continue;
      await st.tdlAdd(_day, st.tdlBlockAt(s));
      added++;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(added == 0 ? '这一天已经按刻度排好了' : '已排出 $added 段，点每一段写内容'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  // ---------------- 界面 ----------------

  @override
  Widget build(BuildContext context) {
    final AppState st = AppState.I;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TDL 时间轴', style: TextStyle(fontSize: 16)),
        actions: <Widget>[
          IconButton(
            tooltip: '时间表设置',
            onPressed: _settings,
            icon: const Icon(Icons.tune),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AnimatedBuilder(
        animation: st,
        builder: (BuildContext context, Widget? _) {
          final List<TdlBlock> bars = st.tdlOf(_day);
          final int totalMin = bars.fold<int>(0, (int a, TdlBlock b) => a + b.minutes);
          final int doneCount = bars.where((TdlBlock b) => b.done).length;

          return Column(
            children: <Widget>[
              _dayBar(st, bars.length, totalMin, doneCount),
              Expanded(
                child: bars.isEmpty
                    ? _empty()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        itemCount: bars.length,
                        itemBuilder: (BuildContext c, int i) => _barRow(st, bars[i]),
                      ),
              ),
              _bottomBar(),
            ],
          );
        },
      ),
    );
  }

  Widget _dayBar(AppState st, int count, int totalMin, int doneCount) {
    final int h = totalMin ~/ 60;
    final int m = totalMin % 60;
    final String totalLabel = h == 0 ? '${m}m' : (m == 0 ? '${h}h' : '${h}h${m}m');
    return Container(
      color: const Color(0xFFFFFFFF),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                tooltip: '前一天',
                onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_left),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: InkWell(
                  onTap: _pickDay,
                  child: Column(
                    children: <Widget>[
                      Text(
                        '${shortDayLabel(_day)} · 星期${'一二三四五六日'[_day.weekday - 1]}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        relativeDayLabel(_day),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF9A9A9A)),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: '后一天',
                onPressed: () => setState(() => _day = _day.add(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_right),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              _pill('$count 段'),
              const SizedBox(width: 6),
              _pill('共 $totalLabel'),
              const SizedBox(width: 6),
              _pill('划掉 $doneCount'),
              const Spacer(),
              TextButton(
                onPressed: _generateSlots,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor: const Color(0xFF185FA5),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('按刻度铺满'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F1F3),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11, color: Color(0xFF5F5E5A))),
      );

  Widget _empty() {
    final AppState st = AppState.I;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              '这一天还没有时间表\n\n时间表按刻度把一天切开，你只要往每段里写字，\n时长会自动算出来',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF9A9A9A), height: 1.9),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _generateSlots,
              child: Text('按 ${st.tdlStep} 分钟刻度铺满一天'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _settings,
              child: const Text('先改一下起止时间和刻度'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barRow(AppState st, TdlBlock b) {
    final bool empty = b.text.trim().isEmpty;
    return InkWell(
      onTap: () => _editBar(b),
      onLongPress: () async {
        await st.tdlUpdate(
          _day,
          TdlBlock(
            id: b.id,
            startMin: b.startMin,
            endMin: b.endMin,
            text: b.text,
            done: !b.done,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEDEDEF)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 左：时间段（如 07:00-09:00）。点这里单独改起止时刻，
            // 不会连带打开「编辑内容」那个弹窗。
            GestureDetector(
              // opaque 保证整块都能点中（不被内层 Column 的空隙吃掉）
              behavior: HitTestBehavior.opaque,
              onTap: () => _editTimeRange(b),
              child: Container(
                width: 90,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                decoration: const BoxDecoration(
                  color: Color(0xFFF7F8FA),
                  borderRadius: BorderRadius.horizontal(left: Radius.circular(10)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      '${tdlLabel(b.startMin)}-${tdlLabel(b.endMin)}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2B2B2B),
                      ),
                    ),
                    if (b.durationLabel.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          b.durationLabel,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF185FA5)),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Text(
                        '点此改',
                        style: TextStyle(fontSize: 9.5, color: Color(0xFFAAAAAA)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                child: Text(
                  empty ? '点一下填内容' : b.text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: empty
                        ? const Color(0xFFBFBFBF)
                        : (b.done ? const Color(0xFF9A9A9A) : const Color(0xFF1F1F1F)),
                    decoration: b.done ? TextDecoration.lineThrough : TextDecoration.none,
                    decorationColor: const Color(0xFF9A9A9A),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                b.done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18,
                color: b.done ? const Color(0xFF185FA5) : const Color(0xFFD5D5D5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(top: BorderSide(color: Color(0xFFE8E8EA))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: _addFreeBar,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加日程'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: () => _closeBar(),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF5F5E5A),
                side: const BorderSide(color: Color(0xFFBFBFBF)),
                minimumSize: const Size(0, 44),
              ),
              child: const Text('收尾'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimePair {
  _TimePair(this.start, this.end);
  int start;
  int end;
}
