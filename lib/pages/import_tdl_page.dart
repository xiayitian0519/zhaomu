import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ai_tdl.dart';
import '../app_state.dart';
import '../models.dart';

/// 导入 TDL —— 粘一段文字，AI 拆成待办，预览后确认。
///
/// 流程：粘贴 → 点「AI 整理」→ 出预览（可勾选、可改标题和日期）→ 点「导入」。
class ImportTdlPage extends StatefulWidget {
  const ImportTdlPage({super.key});

  @override
  State<ImportTdlPage> createState() => _ImportTdlPageState();
}

class _ImportTdlPageState extends State<ImportTdlPage> {
  static const Color _blue = Color(0xFF185FA5);
  static const Color _grey = Color(0xFF8A91A0);
  static const Color _line = Color(0xFFE6E9EF);

  final TextEditingController _input = TextEditingController();

  bool _busy = false;
  String? _error;
  List<AiTodo> _result = <AiTodo>[];

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  AppState get st => AppState.I;

  // 2026-11-04 用户拍板：不给用户填 Key 的入口，统一用代码里的内置 Key
  String get _key => kBuiltinKey;

  int get _left => kDailyLimit - st.aiUsedToday;

  Future<void> _runAi() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final AiParseResult r = await AiTdl.parse(
        text: _input.text,
        apiKey: _key,
        usedToday: st.aiUsedToday,
      );
      await st.bumpAiCount();
      if (!mounted) return;
      setState(() {
        _result = r.todos;
        _busy = false;
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '出错了：$e';
        _busy = false;
      });
    }
  }

  Future<void> _import() async {
    final List<AiTodo> picked =
        _result.where((AiTodo t) => t.picked).toList();
    if (picked.isEmpty) {
      setState(() => _error = '一条都没勾，勾几条再导入。');
      return;
    }
    for (final AiTodo a in picked) {
      final String title = a.editableTitle.trim().isEmpty
          ? a.title
          : a.editableTitle.trim();
      final Todo t = await st.add(
        title,
        due: a.due,
        priority: AiTdl.priorityOf(a.priority),
      );

      // add() 只接 title/due/priority/listName，其余细则补在这儿。
      // 2026-11-04：之前漏了 dueHasTime —— AI 算出「下午三点」，
      // 但 dueHasTime 是 false，列表只显示日期、详情页还显示「加个时间」。
      bool dirty = false;

      if (a.due != null && (a.due!.hour != 0 || a.due!.minute != 0)) {
        t.dueHasTime = true;
        dirty = true;
      }

      final String rep = AiTdl.repeatOf(a.repeat);
      if (rep != RepeatRule.none) {
        t.repeat = rep;
        dirty = true;
      }

      final String nt = a.note.trim();
      if (nt.isNotEmpty) {
        t.note = nt;
        dirty = true;
      }

      if (a.remind != null) {
        t.remind = a.remind;
        t.remindOff = false;
        dirty = true;
      }

      if (dirty) await st.update(t);
    }
    if (!mounted) return;
    Navigator.of(context).pop(picked.length);
  }

  @override
  Widget build(BuildContext ctx) {
    final int pickedCount = _result.where((AiTodo t) => t.picked).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('导入 TDL', style: TextStyle(fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          const Text(
            '把 TDL、会议记录、聊天里的一段话粘进来，AI 会拆成一条条待办。',
            style: TextStyle(fontSize: 12.5, color: _grey, height: 1.6),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _line),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              controller: _input,
              maxLines: 10,
              minLines: 6,
              style: const TextStyle(fontSize: 14, height: 1.6),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '例：\n1. 明天下午三点跟 Zoya 对课程表\n2. 周五前把 demo 录完\n3. 每天早上背单词 30 分钟',
                hintStyle: TextStyle(fontSize: 13, color: Color(0xFFB4BAC6)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _runAi,
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    minimumSize: const Size(0, 44),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('AI 整理'),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _key.isEmpty ? '还没填 Key' : '今天还剩 $_left 次',
                style: TextStyle(
                  fontSize: 12,
                  color: _key.isEmpty ? const Color(0xFFC0392B) : _grey,
                ),
              ),
            ],
          ),

          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFDF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF3D3D3)),
              ),
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF8A2A2A)),
              ),
            ),
          ],

          if (_result.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Text(
                  '拆出 ${_result.length} 条，已选 $pickedCount 条',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    final bool all = pickedCount < _result.length;
                    setState(() {
                      for (final AiTodo t in _result) {
                        t.picked = all;
                      }
                    });
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: _blue,
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 12.5),
                  ),
                  child: Text(pickedCount < _result.length ? '全选' : '全不选'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (int i = 0; i < _result.length; i++) _row(i, _result[i]),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: pickedCount == 0 ? null : _import,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2C9A56),
                minimumSize: const Size(0, 46),
              ),
              child: Text('导入 $pickedCount 条待办'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(int i, AiTodo a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Checkbox(
                value: a.picked,
                onChanged: (bool? v) => setState(() => a.picked = v ?? false),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 10),
                  child: TextFormField(
                    initialValue: a.editableTitle,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 14, height: 1.45),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (String v) => a.editableTitle = v,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(44, 0, 10, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                _tag(
                  a.due == null ? '不限日期' : _dateText(a.due!),
                  a.due == null ? const Color(0xFFB4BAC6) : _blue,
                  () => _pickDate(i, a),
                ),
                // 提醒时间（2026-11-04 加）：AI 能识别，也能手点改
                _tag(
                  a.remind == null ? '不提醒' : _remindText(a.remind!),
                  a.remind == null
                      ? const Color(0xFFB4BAC6)
                      : const Color(0xFFC0392B),
                  () => _pickRemind(i, a),
                ),
                _tag(AiTdl.priorityLabel(a.priority), const Color(0xFF8A6D1E),
                    () => _pickPriority(a)),
                if (a.repeat != 'none')
                  _tag(_repeatText(a.repeat), const Color(0xFF2C9A56), () {
                    setState(() => a.repeat = _nextRepeat(a.repeat));
                  }),
              ],
            ),
          ),
          // 备注（2026-11-04 加）：AI 从原文里抽的补充信息，也能手改
          Padding(
            padding: const EdgeInsets.fromLTRB(44, 0, 12, 8),
            child: TextFormField(
              initialValue: a.note,
              maxLines: 2,
              minLines: 1,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7280), height: 1.5),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: '备注（可选）',
                hintStyle: TextStyle(fontSize: 12, color: Color(0xFFC4C9D4)),
              ),
              onChanged: (String v) => a.note = v,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: TextStyle(fontSize: 11.5, color: color)),
      ),
    );
  }

  static String _dateText(DateTime d) {
    final DateTime now = DateTime.now();
    final DateTime day = DateTime(d.year, d.month, d.day);
    final DateTime today = DateTime(now.year, now.month, now.day);
    final int diff = day.difference(today).inDays;
    final String hm = d.hour == 0 && d.minute == 0
        ? ''
        : ' ${d.hour.toString().padLeft(2, '0')}:'
            '${d.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return '今天$hm';
    if (diff == 1) return '明天$hm';
    if (diff == 2) return '后天$hm';
    if (diff == -1) return '昨天$hm';
    return '${d.month}月${d.day}日$hm';
  }

  /// 提醒时间的显示：今天/明天/几号 + 时分
  static String _remindText(DateTime d) {
    final DateTime now = DateTime.now();
    final DateTime day = DateTime(d.year, d.month, d.day);
    final DateTime today = DateTime(now.year, now.month, now.day);
    final int diff = day.difference(today).inDays;
    final String hm = '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return '提醒 今天 $hm';
    if (diff == 1) return '提醒 明天 $hm';
    if (diff == 2) return '提醒 后天 $hm';
    return '提醒 ${d.month}月${d.day}日 $hm';
  }

  /// 点提醒 chip：先选日期（可选「不提醒」），再选时分
  Future<void> _pickRemind(int i, AiTodo a) async {
    final DateTime now = DateTime.now();

    // 已经设了提醒的话，再点一次就问要不要清掉
    if (a.remind != null) {
      final String? act = await showDialog<String>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
          title: const Text('提醒'),
          content: Text(
            _remindText(a.remind!).replaceFirst('提醒 ', ''),
            style: const TextStyle(fontSize: 14),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(c).pop('edit'),
              child: const Text('改时间'),
            ),
            TextButton(
              onPressed: () => Navigator.of(c).pop('clear'),
              child: const Text('不提醒'),
            ),
          ],
        ),
      );
      if (!mounted || act == null) return;
      if (act == 'clear') {
        setState(() => a.remind = null);
        return;
      }
    }

    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: a.remind ?? a.due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: '提醒日期',
      cancelText: '取消',
      confirmText: '下一步',
    );
    if (!mounted || d == null) return;

    final TimeOfDay? t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(a.remind ?? a.due ?? now),
      helpText: '提醒时间',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (!mounted || t == null) return;

    setState(() {
      a.remind = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  static String _repeatText(String r) => const <String, String>{
        '每天': '每天',
        '每周': '每周',
        '每月': '每月',
        '每年': '每年',
      }[r] ??
      '';

  static String _nextRepeat(String r) {
    const List<String> order = <String>['none', '每天', '每周', '每月', '每年'];
    final int i = order.indexOf(r);
    return order[(i + 1) % order.length];
  }

  /// 点日期 chip。
  ///
  /// 2026-11-04 用户要求：**如果这条待办就是今天，直接弹时间轮，跳过选天数**。
  /// 时间轮的取消按钮改成「改日期」，点了才去选日期，这样今天的待办也能换天。
  Future<void> _pickDate(int i, AiTodo a) async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime? cur = a.due;
    final bool isToday = cur != null &&
        cur.year == today.year &&
        cur.month == today.month &&
        cur.day == today.day;

    if (isToday) {
      // ---- 今天：只问几点 ----
      final TimeOfDay? t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(cur),
        helpText: '选时间',
        cancelText: '改日期',
        confirmText: '确定',
      );
      if (!mounted) return;
      if (t != null) {
        setState(() {
          a.due = DateTime(cur.year, cur.month, cur.day, t.hour, t.minute);
        });
        return;
      }
      // 点了「改日期」→ 往下走选日期流程
    }

    // ---- 不是今天 / 没日期 / 用户点了改日期：先选哪天 ----
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: a.due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: '选截止日期（取消 = 不限）',
      cancelText: '不限',
      confirmText: '下一步',
    );
    if (!mounted) return;
    if (d == null) {
      setState(() => a.due = null);
      return;
    }

    // 再问几点（可跳过，取消 = 只要日期不要时刻）
    final TimeOfDay? t2 = await showTimePicker(
      context: context,
      initialTime: a.due != null
          ? TimeOfDay.fromDateTime(a.due!)
          : const TimeOfDay(hour: 9, minute: 0),
      helpText: '选时间（取消 = 只定日期）',
      cancelText: '只要日期',
      confirmText: '确定',
    );
    if (!mounted) return;
    setState(() {
      a.due = t2 == null
          ? DateTime(d.year, d.month, d.day)
          : DateTime(d.year, d.month, d.day, t2.hour, t2.minute);
    });
  }

  /// 点优先级 chip：弹滚轮选四象限（2026-11-04 用户要求）。
  Future<void> _pickPriority(AiTodo a) async {
    const List<String> order = <String>['red', 'yellow', 'blue', 'gray'];
    int idx = order.indexOf(a.priority);
    if (idx < 0) idx = 3;

    final String? picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext c) {
        int cur = idx;
        return SizedBox(
          height: 288,
          child: Column(
            children: <Widget>[
              // 顶部按钮条
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(c).pop(),
                      child: const Text('取消',
                          style: TextStyle(fontSize: 14, color: Color(0xFF8A91A0))),
                    ),
                    const Spacer(),
                    const Text('重要性',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(c).pop(order[cur]),
                      child: const Text('确定',
                          style: TextStyle(fontSize: 14, color: Color(0xFF185FA5))),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: CupertinoPicker(
                  itemExtent: 44,
                  scrollController: FixedExtentScrollController(initialItem: idx),
                  onSelectedItemChanged: (int i) => cur = i,
                  children: <Widget>[
                    for (final String p in order)
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _priorityColor(p),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AiTdl.priorityLabel(p),
                              style: const TextStyle(fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null) setState(() => a.priority = picked);
  }

  static Color _priorityColor(String p) => const <String, Color>{
        'red': Color(0xFFD63A3A),
        'yellow': Color(0xFFC8871A),
        'blue': Color(0xFF2B6CD4),
        'gray': Color(0xFF5A6270),
      }[p] ??
      const Color(0xFF5A6270);
}
