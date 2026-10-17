import 'package:flutter/material.dart';

import '../app_state.dart';
import '../guide.dart';
import '../models.dart';
import '../notifier.dart';
import '../updates.dart';
import '../widgets.dart';
import 'calendar_page.dart';
import 'detail_page.dart';
import 'done_page.dart';
import 'history_page.dart';
import 'review_page.dart';
import 'settings_page.dart';
import 'tdl_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 版本号变了 → 首次打开弹一次更新内容（见 updates.dart）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      maybeShowUpdateDialog(context);
      _maybeStartGuide();
    });
  }

  /// 首次进入主页时放一次界面引导（见 lib/guide.dart）。
  /// 延迟 700ms 是为了等列表布局稳定、更新弹窗让位。
  Future<void> _maybeStartGuide() async {
    if (AppState.I.guideDone) return;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    await GuideController.I.start();
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---------------- 动作 ----------------

  Future<void> _quickAdd() async {
    final String s = _input.text.trim();
    if (s.isEmpty) return;
    _input.clear();
    final AppState st = AppState.I;
    await st.add(s);
    if (!mounted) return;
    _focus.requestFocus();
    _maybePromptReview();
  }

  Future<void> _toggle(Todo t) async {
    final AppState st = AppState.I;
    final bool wasDone = t.done;
    final DateTime? wasDoneAt = t.doneAt;

    await st.toggleDone(t);
    if (!mounted) return;

    // 勾掉就撤掉提醒，复原就重新排
    if (t.done) {
      await Notifier.I.cancelFor(t);
    } else {
      _schedule(t);
    }
    if (!mounted) return;

    if (!wasDone) {
      showUndo(context, '已完成：${t.title}', () async {
        t.done = wasDone;
        t.doneAt = wasDoneAt;
        await st.update(t);
        _schedule(t);
      });
      _maybePromptReview();
    }
  }

  /// 按当前设置给一条待办排提醒（提前量跟随设置或这条自己的值）
  void _schedule(Todo t) {
    final AppState st = AppState.I;
    Notifier.I.scheduleFor(
      t,
      soundOn: st.defaultRemindOn,
      aheadMinutes: t.aheadMinutes < 0 ? st.defaultAheadMinutes : t.aheadMinutes,
      style: st.remindStyle,
    );
  }

  Future<void> _longPressPriority(Todo t) async {
    final int? q = await showQuadrantPicker(context, current: t.priority);
    if (q == null || !mounted) return;

    final AppState st = AppState.I;
    final int old = t.priority;
    t.priority = q;
    await st.update(t);
    if (!mounted) return;

    showUndo(context, '已标为「${Priority.nameOf(q)}」', () {
      t.priority = old;
      st.update(t);
    });
  }

  Future<void> _delete(Todo t) async {
    final AppState st = AppState.I;
    final int index = st.todos.indexOf(t);
    await st.remove(t);
    await Notifier.I.cancelFor(t);
    if (!mounted) return;
    showUndo(context, '已删除：${t.title}', () async {
      await st.insertAt(index, t);
      _schedule(t);
    });
  }

  void _maybePromptReview() {
    final AppState st = AppState.I;
    final int total = st.todayTotal();
    if (total == 0) return;
    if (st.todayDone() < total) return;

    final String key = dateKey(DateTime.now());
    if (st.lastReviewPrompt == key) return;
    st.lastReviewPrompt = key;
    st.save();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
          title: const Text('今天的都做完了'),
          content: const Text('要不要看一眼今天的复盘？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(c).pop(),
              child: const Text('稍后'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(c).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ReviewPage()),
                );
              },
              child: const Text('进入复盘'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _openDetail(Todo t) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DetailPage(todo: t)),
    );
  }

  // ---------------- 界面 ----------------

  ButtonStyle _actionStyle() => TextButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: const Color(0xFF185FA5),
        textStyle: const TextStyle(fontSize: 13),
      );

  PreferredSizeWidget _appBar(AppState st) {
    return AppBar(
      titleSpacing: 16,
      title: Row(
        children: <Widget>[
          const Text(
            '朝暮',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              headerDate(DateTime.now()),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A8A), fontWeight: FontWeight.w400),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: GuideKeys.calBtn,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const CalendarPage()),
          ),
          style: _actionStyle(),
          child: const Text('日历'),
        ),
        TextButton(
          onPressed: () => st.setNoStrike(!st.noStrike),
          style: _actionStyle(),
          child: Text(st.noStrike ? '加划线' : '无划线'),
        ),
        PopupMenuButton<String>(
          tooltip: '更多',
          onSelected: (String v) {
            if (v == 'done') {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DonePage()),
              );
            } else if (v == 'review') {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ReviewPage()),
              );
            } else if (v == 'history') {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const HistoryPage()),
              );
            } else if (v == 'tdl') {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const TdlPage()),
              );
            } else if (v == 'settings') {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              );
            }
          },
          itemBuilder: (BuildContext c) => const <PopupMenuEntry<String>>[
            PopupMenuItem<String>(value: 'tdl', child: Text('TDL 时间轴')),
            PopupMenuItem<String>(value: 'done', child: Text('已完成')),
            PopupMenuItem<String>(value: 'review', child: Text('今日复盘')),
            PopupMenuItem<String>(value: 'history', child: Text('历史记录')),
            PopupMenuItem<String>(value: 'settings', child: Text('设置')),
          ],
        ),
      ],
    );
  }

  /// 本月组里的「今日」小卡片（2026-10-16 用户选的方案 C）。
  ///
  /// 独立圆角卡片 + 自己的小标题，把今天的待办从本月其余里拎出来。
  /// 卡片后面由调用方补一个 [SizedBox] 当"空一行"。
  Widget _todayCard(String title, List<Todo> items, {bool anchorEdit = false}) => Container(
        margin: const EdgeInsets.fromLTRB(10, 4, 10, 0),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFB5D4F4)),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: double.infinity,
              color: const Color(0xFFE8F0F8),
              padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF185FA5),
                ),
              ),
            ),
            for (int i = 0; i < items.length; i++)
              _tile(items[i], anchorEdit: anchorEdit && i == 0),
          ],
        ),
      );

  Widget _tile(Todo t, {bool anchorEdit = false}) {
    final AppState st = AppState.I;
    final Color textColor = t.done ? const Color(0xFF9A9A9A) : const Color(0xFF1F1F1F);

    return Dismissible(
      key: ValueKey<String>(t.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: const Color(0xFFA32D2D),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Text('删除', style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 15)),
      ),
      onDismissed: (DismissDirection _) => _delete(t),
      child: InkWell(
        onTap: () => _toggle(t),
        onLongPress: () => _longPressPriority(t),
        child: Container(
          // 方案 C（2026-10-17 用户拍板）：已标优先级的整行染象限色浅底，色条配 6px 粗
          color: t.done
              ? const Color(0xFFF4F4F5)
              : (t.priority >= 0
                  ? st.colorOf(t.priority).withOpacity(0.08)
                  : const Color(0xFFFFFFFF)),
          padding: const EdgeInsets.fromLTRB(14, 11, 6, 11),
          child: Row(
            children: <Widget>[
              DoneCircle(done: t.done),
              const SizedBox(width: 12),
              PriorityBar(priority: t.priority),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      t.title,
                      style: TextStyle(
                        fontSize: 16,
                        color: textColor,
                        decoration: (t.done && !st.noStrike)
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: const Color(0xFF9A9A9A),
                      ),
                    ),
                    // 只要设了截止就一定出这行日期（带不带时刻都出）——
                    // 用户 2026-10-16：「不带具体时刻也要显示日期」。
                    // 逾期那几条的日期行用红字。
                    if (t.due != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          listDueLabel(t.due!, t.dueHasTime),
                          style: TextStyle(
                            fontSize: 12,
                            color: t.done
                                ? const Color(0xFFB8B8B8)
                                : (dayOf(t.due!).isBefore(dayOf(DateTime.now()))
                                    ? const Color(0xFFA32D2D)
                                    : const Color(0xFF9A9A9A)),
                          ),
                        ),
                      )
                    else if (t.remind != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          '提醒 ${dateTimeLabel(t.remind!)}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                // 引导锚点：挂在"当前显示的第一行"上。
                // 这里必须常挂，不能只在引导进行中挂 —— 引导启动时主页不会重建，
                // 那时挂 key 来不及，第 2 步会找不到目标。
                key: anchorEdit ? GuideKeys.firstEdit : null,
                onPressed: () => _openDetail(t),
                icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFFB0B0B0)),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      key: GuideKeys.inputBar,
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
                focusNode: _focus,
                textInputAction: TextInputAction.done,
                onSubmitted: (String _) => _quickAdd(),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '记点什么…（回车存为今天）',
                  hintStyle: TextStyle(fontSize: 14, color: Color(0xFFAAAAAA)),
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 15),
              ),
            ),
            TextButton(
              onPressed: _quickAdd,
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
    return AnimatedBuilder(
      animation: st,
      builder: (BuildContext context, Widget? _) {
        final List<TodoGroup> groups = st.groups();
        final List<Widget> children = <Widget>[];

        if (groups.isEmpty) {
          children.add(
            const Padding(
              padding: EdgeInsets.only(top: 130, left: 40, right: 40),
              child: Text(
                '还没有待办\n在下面输入框打字，回车就记下了',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 15, height: 1.9),
              ),
            ),
          );
        } else {
          bool first = true;
          // 引导要指"第一条待办的铅笔"，只在第一个画出来的行上挂锚点
          bool anchorGiven = false;
          for (final TodoGroup g in groups) {
            children.add(
              GroupHeader(
                title: g.title,
                colorValue: g.colorValue,
                showSort: first,
              ),
            );
            first = false;
            // 本月组：先画「今日」小卡片，空一行，再画本月其余
            final List<Todo>? pin = g.pinItems;
            if (pin != null && pin.isNotEmpty) {
              children.add(_todayCard(g.pinTitle ?? '今天', pin, anchorEdit: !anchorGiven));
              anchorGiven = true;
              children.add(const SizedBox(height: 10));
            }
            for (final Todo t in g.items) {
              children.add(_tile(t, anchorEdit: !anchorGiven));
              anchorGiven = true;
            }
          }
        }

        return Scaffold(
          appBar: _appBar(st),
          body: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: children,
                ),
              ),
              _inputBar(),
            ],
          ),
        );
      },
    );
  }
}
