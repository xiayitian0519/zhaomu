
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../guide.dart';
import '../models.dart';
import '../notifier.dart';
import '../sound_lib.dart';
import '../widgets.dart';
import 'sound_page.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.todo, this.autoClock = false});

  final Todo todo;

  /// 调试用：进页面后自动把「时钟」面板弹出来（`chaomu.exe --clock`）。
  /// 正常运行永远是 false。
  final bool autoClock;

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

  /// 这条专用的铃声 id（见 SoundLibrary）。空串 = 跟随设置里的默认铃声
  String _soundId = '';

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
    _soundId = t.soundId;
    // 引导要知道用户真的进了详情页（第 2 步「点进去才算」）
    GuideController.I.enter('detail');

    if (widget.autoClock) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickClockPanel();
      });
    }
  }

  @override
  void dispose() {
    GuideController.I.leave('detail');
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
    t.soundId = _soundId;

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

  // ---------------- 底层选择器（面板里「其他…」点进来用） ----------------

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

  // ---------------- 时钟面板（日期 + 提醒 + 频率三合一） ----------------

  /// 2026-10-23 晚按用户原型合并。
  ///
  /// 原来「截止时间」「提醒」是两个半屏面板，外加一个单独的「重复」下拉框，
  /// 设完一件事要开关三次。现在并成一个整屏：日期 / 提醒 / 频率。
  ///
  /// 「时刻」不再是单独一组 —— 用户原型里把它收进了「截止时间」，
  /// 点那一项会连着弹日期和时间。
  Future<void> _pickClockPanel() async {
    final AppState st = AppState.I;
    final DateTime now = DateTime.now();
    // 快捷提前量。用户原型里只留了 5 分钟和 10 分钟，其余走「自定义」
    const List<int> quick = <int>[5, 10];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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

          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _sheetTitle('时钟'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      _clockSummary(st),
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                    ),
                  ),
                  _pillSection('截止日期', <Widget>[
                    _pill('今天',
                        on: _due != null && sameDay(_due!, now),
                        onTap: () => setDay(now)),
                    _pill('明天',
                        on: _due != null &&
                            sameDay(_due!, now.add(const Duration(days: 1))),
                        onTap: () => setDay(now.add(const Duration(days: 1)))),
                    _pill('后天',
                        on: _due != null &&
                            sameDay(_due!, now.add(const Duration(days: 2))),
                        onTap: () => setDay(now.add(const Duration(days: 2)))),
                    // 2026-10-26：日期不在细则里选了。想指定某一天，去日历页
                    // 点那一天新建（用户原话：「要选日期就用日历功能加就行，
                    // 待办细则里面只管时间」）。所以这个 pill 只管时刻 ——
                    // 点了直接弹时间轮盘，不再先弹日期选择器。
                    _pill(
                        _dueHasTime && _due != null
                            ? timeLabel(_due!)
                            : '加个时间',
                        on: _dueHasTime,
                        onTap: () {
                          Navigator.of(c).pop();
                          _pickDueTime();
                        }),
                  ]),
                  _pillSection('提醒', <Widget>[
                    _pill('准时',
                        on: !_remindOff && _ahead == 0,
                        onTap: () => sheetSet(() {
                              _remindOff = false;
                              _ahead = 0;
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
                    _pill('跟随设置',
                        on: !_remindOff && _ahead < 0,
                        onTap: () => sheetSet(() {
                              _remindOff = false;
                              _ahead = -1;
                            })),
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
                  _pillSection('频率', <Widget>[
                    for (final String e in RepeatRule.all)
                      _pill(
                        e == RepeatRule.custom
                            ? (_repeat == RepeatRule.custom
                                ? customRepeatLabel(_repeatDays)
                                : '自定义')
                            : RepeatRule.labelOf(e),
                        on: _repeat == e,
                        onTap: () {
                          if (e == RepeatRule.custom) {
                            Navigator.of(c).pop();
                            _pickRepeatDaysPanel();
                          } else {
                            sheetSet(() {
                              _repeat = e;
                              _repeatDays = const <int>[];
                            });
                          }
                        },
                      ),
                  ]),
                  // 铃声 / 系统通知。
                  //
                  // 两端走了不同的路（2026-10-27 用户拍板）：
                  //   电脑：App 内七款铃声可选可试听，改完真能生效
                  //   手机：声音归系统通知渠道 chaomu_remind_v10 管，
                  //        App 里选什么都盖不过渠道 —— 所以这里只做一个跳转，
                  //        点了直接到系统的「待办提醒」页（声音/振动/悬浮通知都在那）
                  InkWell(
                    onTap: () async {
                      if (Platform.isWindows) {
                        Navigator.of(c).pop();
                        final String? picked =
                            await Navigator.of(context).push<String>(
                          MaterialPageRoute<String>(
                            builder: (BuildContext _) => SoundPage(
                              single: true,
                              initial: _soundId,
                            ),
                          ),
                        );
                        if (!mounted || picked == null) return;
                        setState(() => _soundId = picked);
                        return;
                      }
                      // 安卓：跳系统的渠道设置页
                      Navigator.of(c).pop();
                      final bool ok = await Notifier.I.openChannelSettings();
                      if (!ok && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('跳不过去，手动去：设置 → 通知 → 朝暮 → 待办提醒'),
                          ),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
                      child: Row(
                        children: <Widget>[
                          Text(
                            Platform.isWindows ? '铃声' : '系统通知',
                            style: const TextStyle(
                                fontSize: 14, color: Color(0xFF8A91A0)),
                          ),
                          const Spacer(),
                          Text(
                            Platform.isWindows
                                ? (_soundId.isEmpty
                                    ? '跟随默认（${SoundLib.nameOf(st.defaultSoundId)}）'
                                    : SoundLib.nameOf(_soundId))
                                : '声音 / 振动 / 悬浮通知',
                            style: const TextStyle(
                                fontSize: 14, color: Color(0xFF1A1F2B)),
                          ),
                          const Icon(Icons.chevron_right,
                              size: 18, color: Color(0xFF8A91A0)),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Row(
                      children: <Widget>[
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.of(c).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF185FA5),
                          ),
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

  /// 「时钟」那一行的大字摘要：`10月24日 09:00 · 提前 10 分钟 · 仅今天`
  String _clockSummary(AppState st) {
    final List<String> parts = <String>[];
    if (_due == null) {
      parts.add('还没设日期');
    } else {
      parts.add(_dueHasTime
          ? '${shortDayLabel(_due!)} ${timeLabel(_due!)}'
          : shortDayLabel(_due!));
    }
    if (_remindOff) {
      parts.add('不提醒');
    } else {
      final int ahead = _ahead < 0 ? st.defaultAheadMinutes : _ahead;
      parts.add(aheadLabel(ahead));
    }
    parts.add(_repeat == RepeatRule.custom
        ? customRepeatLabel(_repeatDays)
        : RepeatRule.labelOf(_repeat));
    return parts.join(' · ');
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

    final String clockText = _clockSummary(st);

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
            // 2026-10-23 晚合并：「截止时间」「提醒」原本两行两个半屏面板，
            // 加上单独的「重复」下拉，设完一件事要开关三次。
            // 现在只剩这一行，点开一个整屏面板设完（见 _pickClockPanel）。
            KeyedSubtree(
              key: GuideKeys.clockRow,
              child: _accentRow(
                '时钟',
                clockText,
                _pickClockPanel,
                onClear: (_due == null && _remind == null && !_remindOff)
                    ? null
                    : () => setState(() {
                          _due = null;
                          _dueHasTime = false;
                          _remind = null;
                          _remindOff = false;
                        }),
              ),
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
