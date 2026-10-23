import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../notifier.dart';
import '../widgets.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.todo});

  final Todo todo;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late final TextEditingController _title;
  late final TextEditingController _note;

  DateTime? _due;
  bool _dueHasTime = false;
  DateTime? _remind;
  int _priority = Priority.none;
  String _listName = '生活';
  String _repeat = RepeatRule.none;

  /// 这条单独提前多少分钟；-1 = 跟随设置默认
  int _ahead = -1;

  /// 用户明确点了「不提醒」。
  ///
  /// 光清空 [_remind] 不够 —— 排程里有兜底「截止带时刻就按截止提醒」
  /// （见 Notifier.scheduleFor），这个开关把那条兜底也关掉。
  bool _remindOff = false;

  /// 「自定义」执行日期：每月哪几号（升序）。只有 [_repeat] == 自定义 时有效
  List<int> _repeatDays = <int>[];

  @override
  void initState() {
    super.initState();
    final Todo t = widget.todo;
    _title = TextEditingController(text: t.title);
    _note = TextEditingController(text: t.note);
    _due = t.due;
    _dueHasTime = t.dueHasTime;
    _remind = t.remind;
    _priority = t.priority;
    _listName = t.listName;
    _repeat = t.repeat;
    _ahead = t.aheadMinutes;
    _remindOff = t.remindOff;
    _repeatDays = List<int>.of(t.repeatDays);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  // ---------------- 保存 / 删除 ----------------

  Future<void> _save() async {
    final AppState st = AppState.I;
    final Todo t = widget.todo;
    final String title = _title.text.trim();

    t.title = title.isEmpty ? '（未命名）' : title;
    t.note = _note.text;
    t.due = _due;
    t.dueHasTime = _dueHasTime;
    t.remind = _remind;
    t.priority = _priority;
    t.listName = _listName;
    t.repeat = _repeat;
    t.aheadMinutes = _ahead;
    t.remindOff = _remindOff;
    t.repeatDays = List<int>.of(_repeatDays);

    await st.update(t);
    await Notifier.I.scheduleFor(
      t,
      // 「默认打开铃声」关掉 → 只弹不响，这里必须传下去
      soundOn: st.defaultRemindOn,
      // -1 = 跟随设置；否则用这条自己的值
      aheadMinutes: _ahead < 0 ? st.defaultAheadMinutes : _ahead,
      style: st.remindStyle,
    );
    if (!mounted) return;
    // 保存返回前收起键盘，避免回到列表页时停留在输入栏打字状态
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final AppState st = AppState.I;
    final Todo t = widget.todo;
    final int index = st.todos.indexOf(t);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState nav = Navigator.of(context);

    await st.remove(t);
    if (!mounted) return;
    nav.pop();

    messenger.hideCurrentSnackBar();
    showUndo(nav.context, '已删除：${t.title}', () {
      st.insertAt(index, t);
    });
  }

  // ---------------- 提醒时刻推算 ----------------

  /// 这条实际会在几点几分响。
  ///
  /// 基准 = 自选提醒时刻，没有就用带时刻的截止；再往前减提前量。
  /// 和 Notifier.scheduleFor 里的算法保持一致。
  DateTime? _fireAt(AppState st) {
    if (_remindOff) return null;
    DateTime? base = _remind;
    if (base == null && _due != null && _dueHasTime) base = _due;
    if (base == null) return null;
    final int ahead = _ahead < 0 ? st.defaultAheadMinutes : _ahead;
    return base.subtract(Duration(minutes: ahead));
  }

  /// 提醒那一行的副标题文案
  String _remindSummary(AppState st) {
    if (_remindOff) return '不提醒';
    final DateTime? f = _fireAt(st);
    if (f == null) return '还没定下提醒时刻';
    return '会在 ${listDueLabel(f, true)} 提醒你';
  }

  // ---------------- 底层选择器（面板里「其他…」点进来用） ----------------

  Future<void> _pickDueDate() async {
    final DateTime base = _due ?? DateTime.now();
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择截止日期',
    );
    if (d == null) return;
    setState(() {
      _due = DateTime(d.year, d.month, d.day, _due?.hour ?? 0, _due?.minute ?? 0);
    });
  }

  Future<void> _pickDueTime() async {
    final TimeOfDay? t = await pickTime(
      context,
      initial: TimeOfDay.fromDateTime(_due ?? DateTime.now()),
      helpText: '选择截止时刻',
    );
    if (t == null) return;
    setState(() {
      final DateTime base = _due ?? DateTime.now();
      _due = DateTime(base.year, base.month, base.day, t.hour, t.minute);
      _dueHasTime = true;
    });
  }

  /// 自选一个提醒时刻（面板里「挑个提醒时刻」点进来用）
  Future<void> _pickRemindAt() async {
    final DateTime base = _remind ?? (_due ?? DateTime.now());
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择提醒日期',
    );
    if (d == null || !mounted) return;
    final TimeOfDay? t = await pickTime(
      context,
      initial: TimeOfDay.fromDateTime(base),
      helpText: '选择提醒时刻',
    );
    if (t == null || !mounted) return;
    setState(() {
      _remind = DateTime(d.year, d.month, d.day, t.hour, t.minute);
      _remindOff = false;
    });
  }

  /// 提前量的完整列表（面板里「自定义」点进来用）
  Future<void> _pickAheadCustom() async {
    final AppState st = AppState.I;
    const List<int> opts = <int>[-1, 0, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240];
    final int? picked = await showModalBottomSheet<int>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '这条提前多久提醒',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              for (final int m in opts)
                ListTile(
                  title: Text(
                    m < 0
                        ? '跟随设置（${aheadLabel(st.defaultAheadMinutes)}）'
                        : aheadLabel(m),
                    style: const TextStyle(fontSize: 14),
                  ),
                  trailing: _ahead == m
                      ? const Icon(Icons.check, size: 18, color: Color(0xFF185FA5))
                      : null,
                  onTap: () => Navigator.of(c).pop(m),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _ahead = picked;
      _remindOff = false;
    });
  }

  // ---------------- 自定义执行日期面板 ----------------

  /// 弹天号选择面板。选空 = 退回「仅今天」，选了 = repeat 切到「自定义」
  Future<void> _pickRepeatDaysPanel() async {
    final List<int>? picked = await showModalBottomSheet<List<int>>(
      context: context,
      builder: (BuildContext c) => _RepeatDaysPanel(initial: List<int>.of(_repeatDays)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (picked.isEmpty) {
        _repeat = RepeatRule.none;
        _repeatDays = const <int>[];
      } else {
        _repeat = RepeatRule.custom;
        _repeatDays = picked;
      }
    });
  }

  // ---------------- 截止面板 ----------------

  Future<void> _pickDuePanel() async {
    final DateTime now = DateTime.now();
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext c) => StatefulBuilder(
        builder: (BuildContext c, void Function(void Function()) sheetSet) {
          void setDay(DateTime d) {
            sheetSet(() {
              _due = DateTime(
                d.year,
                d.month,
                d.day,
                _dueHasTime ? (_due?.hour ?? 9) : 0,
                _dueHasTime ? (_due?.minute ?? 0) : 0,
              );
            });
          }

          void setTime(int h, int m) {
            sheetSet(() {
              final DateTime b = _due ?? now;
              _due = DateTime(b.year, b.month, b.day, h, m);
              _dueHasTime = true;
            });
          }

          final String big = _due == null
              ? '还没设截止日期'
              : (_dueHasTime
                  ? '${relativeDayLabel(_due!)} ${timeLabel(_due!)}'
                  : relativeDayLabel(_due!));

          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _sheetTitle('截止时间'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      big,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ),
                  _pillSection('日期', <Widget>[
                    _pill('今天',
                        on: _due != null && sameDay(_due!, now), onTap: () => setDay(now)),
                    _pill('明天',
                        on: _due != null && sameDay(_due!, now.add(const Duration(days: 1))),
                        onTap: () => setDay(now.add(const Duration(days: 1)))),
                    _pill('后天',
                        on: _due != null && sameDay(_due!, now.add(const Duration(days: 2))),
                        onTap: () => setDay(now.add(const Duration(days: 2)))),
                    _pill('下周一', onTap: () {
                      int add = (8 - now.weekday) % 7;
                      if (add == 0) add = 7;
                      setDay(now.add(Duration(days: add)));
                    }),
                    _pill('月底', onTap: () => setDay(DateTime(now.year, now.month + 1, 0))),
                    _pill('其他日期', onTap: () {
                      Navigator.of(c).pop();
                      _pickDueDate();
                    }),
                    _pill('清除', onTap: () {
                      sheetSet(() {
                        _due = null;
                        _dueHasTime = false;
                      });
                    }),
                  ]),
                  _pillSection('时刻', <Widget>[
                    _pill('不带时刻',
                        on: _due != null && !_dueHasTime,
                        onTap: () => sheetSet(() => _dueHasTime = false)),
                    for (final int hm in <int>[9 * 60, 12 * 60, 18 * 60, 21 * 60])
                      _pill(
                        tdlLabel(hm),
                        on: _dueHasTime &&
                            _due != null &&
                            (_due!.hour * 60 + _due!.minute == hm),
                        onTap: () => setTime(hm ~/ 60, hm % 60),
                      ),
                    _pill('其他时刻', onTap: () {
                      Navigator.of(c).pop();
                      _pickDueTime();
                    }),
                  ]),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Row(
                      children: <Widget>[
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.of(c).pop(),
                          style: TextButton.styleFrom(foregroundColor: const Color(0xFF185FA5)),
                          child: const Text('完成'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  // ---------------- 提醒面板 ----------------

  Future<void> _pickRemindPanel() async {
    final AppState st = AppState.I;
    const List<int> quick = <int>[60, 30, 10, 0];
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext c) => StatefulBuilder(
        builder: (BuildContext c, void Function(void Function()) sheetSet) {
          final DateTime? f = _fireAt(st);
          final String big = _remindOff
              ? '这条不会提醒'
              : (f == null ? '还没定下提醒时刻' : '会在 ${listDueLabel(f, true)} 提醒你');

          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _sheetTitle('提醒'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      big,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ),
                  _pillSection('提前多久', <Widget>[
                    _pill('跟随设置',
                        on: !_remindOff && _ahead < 0,
                        onTap: () => sheetSet(() {
                              _remindOff = false;
                              _ahead = -1;
                            })),
                    for (final int m in quick)
                      _pill(
                        aheadLabel(m),
                        on: !_remindOff && _ahead == m,
                        onTap: () => sheetSet(() {
                              _remindOff = false;
                              _ahead = m;
                            }),
                      ),
                    _pill('自定义',
                        on: !_remindOff && _ahead > 0 && !quick.contains(_ahead),
                        onTap: () {
                          Navigator.of(c).pop();
                          _pickAheadCustom();
                        }),
                    _pill('不提醒',
                        on: _remindOff,
                        onTap: () => sheetSet(() {
                              _remindOff = true;
                              _remind = null;
                            })),
                  ]),
                  _pillSection('提醒基准', <Widget>[
                    _pill(
                      '跟截止走',
                      on: !_remindOff && _remind == null && _dueHasTime,
                      onTap: (_due != null && _dueHasTime)
                          ? () => sheetSet(() {
                                _remind = null;
                                _remindOff = false;
                              })
                          : null,
                    ),
                    _pill(
                      _remind == null ? '挑个提醒时刻' : '改提醒时刻',
                      onTap: () {
                        Navigator.of(c).pop();
                        _pickRemindAt();
                      },
                    ),
                    if (_remind != null)
                      _pill('清除自选时刻', onTap: () => sheetSet(() => _remind = null)),
                  ]),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      _remind != null
                          ? '自选提醒时刻 ${dateTimeLabel(_remind!)}，再往前提。'
                          : ((_due != null && _dueHasTime)
                              ? '按截止时刻 ${shortDayLabel(_due!)} ${timeLabel(_due!)} 往前提。'
                              : '截止没带时刻：要么给截止加上时刻，要么自选一个提醒时刻。'),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF9A9A9A), height: 1.5),
                    ),
                  ),
                  // 铃声入口（2026-10-21 用户要求）：本地音乐和系统自带的都在
                  // 系统那个「待办提醒」渠道页里挑，跳过去由系统来选。
                  //
                  // 只对手机显示 —— Windows 的提醒走系统 Toast，响不响、响什么
                  // 由系统的提示音设置管，没有「按 App 挑铃声」这回事。
                  if (!Platform.isWindows)
                    InkWell(
                      onTap: () => _openRingtone(c),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
                        child: Row(
                          children: const <Widget>[
                            Icon(
                              Icons.music_note_outlined,
                              size: 18,
                              color: Color(0xFF185FA5),
                            ),
                            SizedBox(width: 8),
                            Text(
                              '铃声',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '本地音乐 / 系统自带，所有提醒统一用',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF9A9A9A),
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: Color(0xFF9A9A9A),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Text(
                      '到点怎么弹（横幅 / 全屏）在「设置 → 提醒」里统一切换。',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  /// 跳系统的「待办提醒」通知渠道页去挑铃声。
  ///
  /// 铃声归通知渠道管（渠道号 chaomu_remind_v8），不是逐条待办的字段 ——
  /// 系统只给到「按渠道换声音」这一层，逐条换需要为每条待办开一个渠道，
  /// 渠道一多用户的通知设置页就炸了，所以做成全局统一。
  ///
  /// 跳不过去（部分 ROM 把这个 Intent 屏蔽了）就退回手动路径，
  /// 和设置页那一行说的完全一样，免得用户在两处看到两种说法。
  Future<void> _openRingtone(BuildContext c) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(c);
    final bool ok = await Notifier.I.openChannelSettings();
    if (ok) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('跳不过去。手动路径：设置 → 应用管理 → 朝暮 → 通知 → 待办提醒'),
        duration: Duration(seconds: 8),
      ),
    );
  }

  // ---------------- 小组件 ----------------

  Widget _card(List<Widget> children) => Container(
        color: const Color(0xFFFFFFFF),
        margin: const EdgeInsets.only(bottom: 8),
        child: Column(children: children),
      );

  /// 截止 / 提醒那两行 —— 左边带 3px 蓝竖条，点开底部面板
  Widget _accentRow(String label, String value, VoidCallback onTap, {VoidCallback? onClear}) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFF185FA5), width: 3)),
      ),
      child: ListTile(
        title: Text(label, style: const TextStyle(fontSize: 14)),
        subtitle: Text(value, style: const TextStyle(fontSize: 13)),
        trailing: onClear != null
            ? IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClear,
              )
            : const Icon(Icons.chevron_right, size: 18),
        onTap: onTap,
      ),
    );
  }

  Widget _sheetTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            t,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      );

  Widget _pill(String text, {bool on = false, VoidCallback? onTap}) {
    final bool disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: on ? const Color(0xFF185FA5) : const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(18),
          border: on ? null : Border.all(color: const Color(0xFFDFE2E8)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: on
                ? const Color(0xFFFFFFFF)
                : (disabled ? const Color(0xFFB9B9BD) : const Color(0xFF3C3C3C)),
          ),
        ),
      ),
    );
  }

  Widget _pillSection(String label, List<Widget> pills) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
            ),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: pills),
        ],
      ),
    );
  }

  /// 2×2 方阵里的一个格子（重要且紧急 / 重要不紧急 / 不重要但紧急 / 不重要不紧急）
  Widget _priorityChip(int q) {
    final bool on = _priority == q;
    final Color c = AppState.I.colorOf(q);
    return GestureDetector(
      onTap: () => setState(() => _priority = on ? Priority.none : q),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? c : const Color(0xFFFFFFFF),
          border: Border.all(color: c, width: 1.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          Priority.names[q],
          style: TextStyle(fontSize: 13, color: on ? const Color(0xFFFFFFFF) : c),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppState st = AppState.I;
    final String repeatValue = RepeatRule.all.contains(_repeat) ? _repeat : RepeatRule.none;

    final String dueText = _due == null ? '点这里挑日期和时刻' : listDueLabel(_due!, _dueHasTime);
    final String remindText = _remindSummary(st);

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑待办', style: TextStyle(fontSize: 16)),
        actions: <Widget>[
          TextButton(
            onPressed: _save,
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF185FA5)),
            child: const Text('保存'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: <Widget>[
          _card(<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _title,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: '标题',
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: TextField(
                controller: _note,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '备注',
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ]),
          _card(<Widget>[
            _accentRow(
              '截止时间',
              dueText,
              _pickDuePanel,
              onClear: _due == null
                  ? null
                  : () => setState(() {
                        _due = null;
                        _dueHasTime = false;
                      }),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _accentRow(
              '提醒',
              remindText,
              _pickRemindPanel,
              onClear: (_remind == null && !_remindOff)
                  ? null
                  : () => setState(() {
                        _remind = null;
                        _remindOff = false;
                      }),
            ),
          ]),
          _card(<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '优先级（列表里长按待办也能直接划象限）',
                    style: TextStyle(fontSize: 13, color: Color(0xFF5F5E5A)),
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    childAspectRatio: 3.6,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: <Widget>[
                      for (int i = 0; i < Priority.names.length; i++) _priorityChip(i),
                    ],
                  ),
                ],
              ),
            ),
          ]),
          _card(<Widget>[
            ListTile(
              title: const Text('重复', style: TextStyle(fontSize: 14)),
              subtitle: _repeat == RepeatRule.none
                  ? null
                  : const Text(
                      '说明：完成后自动生成下一条的逻辑还没定，这一版只记录规则。',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)),
                    ),
              trailing: DropdownButton<String>(
                value: repeatValue,
                underline: const SizedBox.shrink(),
                items: <DropdownMenuItem<String>>[
                  for (final String e in RepeatRule.all)
                    DropdownMenuItem<String>(
                      value: e,
                      child: Text(
                        e == RepeatRule.custom
                            ? (_repeat == RepeatRule.custom
                                ? customRepeatLabel(_repeatDays)
                                : '自定义…')
                            : RepeatRule.labelOf(e),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                ],
                onChanged: (String? v) {
                  if (v == null) return;
                  if (v == RepeatRule.custom) {
                    _pickRepeatDaysPanel();
                  } else {
                    setState(() {
                      _repeat = v;
                      _repeatDays = const <int>[];
                    });
                  }
                },
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: OutlinedButton(
              onPressed: _delete,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFA32D2D),
                side: const BorderSide(color: Color(0xFFA32D2D)),
                minimumSize: const Size.fromHeight(46),
              ),
              child: const Text('删除这条待办'),
            ),
          ),
        ],
      ),
    );
  }
}


/// 自定义执行日期面板：奇数日 / 偶数日一键，或 1~31 手选多个天号。
/// 「完成」把选好的天号列表带回详情页；空列表 = 退回「仅今天」。
class _RepeatDaysPanel extends StatefulWidget {
  const _RepeatDaysPanel({required this.initial});

  final List<int> initial;

  @override
  State<_RepeatDaysPanel> createState() => _RepeatDaysPanelState();
}

class _RepeatDaysPanelState extends State<_RepeatDaysPanel> {
  static const List<int> _odd = <int>[1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31];
  static const List<int> _even = <int>[2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30];

  // late：字段初始化器里不能直接访问 widget，late 初始化器可以
  late final List<int> _days = List<int>.of(widget.initial);

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Widget _pill(String text, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: on ? const Color(0xFF185FA5) : const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(16),
          border: on ? null : Border.all(color: const Color(0xFFDFE2E8)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: on ? const Color(0xFFFFFFFF) : const Color(0xFF3C3C3C),
          ),
        ),
      ),
    );
  }

  Widget _dayCell(int d) {
    final bool on = _days.contains(d);
    return GestureDetector(
      onTap: () => setState(() => on ? _days.remove(d) : _days.add(d)),
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? const Color(0xFF185FA5) : const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? const Color(0xFF185FA5) : const Color(0xFFDFE2E8)),
        ),
        child: Text(
          '$d',
          style: TextStyle(
            fontSize: 12,
            color: on ? const Color(0xFFFFFFFF) : const Color(0xFF3C3C3C),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<int> sorted = _days.toList()..sort();
    final String picked =
        sorted.isEmpty ? '还没选天号' : '已选：${sorted.join('、')} 号';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '自定义执行日期',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                _pill('奇数日', _same(sorted, _odd), () {
                  setState(() {
                    _days
                      ..clear()
                      ..addAll(_odd);
                  });
                }),
                const SizedBox(width: 8),
                _pill('偶数日', _same(sorted, _even), () {
                  setState(() {
                    _days
                      ..clear()
                      ..addAll(_even);
                  });
                }),
                const SizedBox(width: 8),
                _pill('清空', sorted.isEmpty, () => setState(_days.clear)),
              ],
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 7,
              mainAxisSpacing: 5,
              crossAxisSpacing: 5,
              childAspectRatio: 1.1,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: <Widget>[
                for (int d = 1; d <= 31; d++) _dayCell(d),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              picked,
              style: const TextStyle(fontSize: 12, color: Color(0xFF185FA5)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(List<int>.of(_days)..sort()),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF185FA5),
                ),
                child: const Text(
                  '完成',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
