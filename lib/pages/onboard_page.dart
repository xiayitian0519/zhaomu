import 'package:flutter/material.dart';

import '../app_state.dart';
import '../notifier.dart';
import '../permissions.dart';

/// 首次启动的权限引导：**一步一步弹窗，一条一确认**。
///
/// 设计原则：
/// 1. **一次只问一条**。用户点「去开启」→ 跳到系统页 → 回来点「我开好了」→
///    才弹下一条。一股脑列四条用户会直接划走。
/// 2. **只卡 4 条真·必需项**（通知 / 精确闹钟 / 省电无限制 / 自启动）。
///    其他的（锁屏显示、后台弹出）放最后一块「不卡流程」提示里。
/// 3. **能查状态的查了再让过**。通知 / 精确闹钟 / 省电三项系统能查；
///    自启动看机型 —— 部分 ROM 挂在 AppOps 上能读到，读到就按真实状态卡，
///    读不到（`null`）就让用户自己确认一句「我开好了」放行。
/// 4. 全程可以退出，退出时弹一次警告说清后果。
class OnboardPage extends StatefulWidget {
  const OnboardPage({super.key});

  @override
  State<OnboardPage> createState() => _OnboardPageState();
}

/// 一条引导项
///
/// 闭包不接 state 参数 —— 需要 toast 的场景（自启动跳不进去）改成让 [open]
/// 返回一句要给用户看的提示，由 state 统一弹。
class _Step {
  const _Step({
    required this.title,
    required this.why,
    required this.how,
    required this.open,
    required this.check,
  });

  final String title;

  /// 为什么需要它 —— 不批会怎样
  final String why;

  /// 去系统页之后具体点哪里
  final String how;

  /// 跳到系统页。返回一句要提示用户的话（null = 不用提示）。
  final Future<String?> Function() open;

  /// 查这条过没过。返回 true = 过了。
  /// 返回 null = 系统查不到（自启动），交给用户自己确认。
  final Future<bool?> Function() check;
}

class _OnboardPageState extends State<OnboardPage> {
  /// 当前问到第几步（0 起）
  int _index = 0;

  /// 当前这步的状态：null = 正在查 / 查不到
  bool? _state = false;
  bool _busy = false;

  late final List<_Step> _steps = <_Step>[
    _Step(
      title: '允许通知',
      why: '不开的话，提醒到点系统直接把它丢掉，屏幕上什么都没有。',
      how: '在系统页把「允许通知」打开，并把「横幅」也选上。',
      open: () async {
        // 先走官方请求框（Android 13+ 会弹系统授权），批了就不用跳系统页
        final bool granted = await Notifier.I.requestPermission();
        if (granted) return null;
        await Permissions.openNotificationSettings();
        return null;
      },
      check: () async => Notifier.I.hasPermission(),
    ),
    _Step(
      title: '闹钟和提醒',
      why: '不批的话只能用「大概时间」的闹钟，系统会攒着凑一批再发，晚几十分钟很正常 —— '
          '这就是提醒像没响的原因。',
      how: '在系统页把「闹钟和提醒」打开。',
      open: () async {
        await Notifier.I.requestExactAlarm();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await Permissions.openExactAlarm();
        return null;
      },
      check: () async {
        final bool? v = await Notifier.I.canScheduleExact();
        // 系统低于 12 或问不出来 -> null，当「过」处理
        return v ?? true;
      },
    ),
    _Step(
      title: '省电策略改成「无限制」',
      why: '不设的话系统会把朝暮冻在后台，到点也不唤醒，提醒就不来。',
      how: '在系统页选「无限制」，或关掉「优化」开关。',
      open: () async {
        // 优先跳「朝暮的应用信息」页 —— 这一页里同时有「省电策略」和「自启动」，
        // 而且走的是 Android 标准 action，换任何品牌的手机都能跳。
        // 各家省电专页是拼组件名硬跳的，只在跳不进应用信息页时才试。
        final bool ok = await Notifier.I.openAppDetails() ||
            await Notifier.I.openPowerSaving() ||
            await Permissions.openBatteryOptimization() ||
            await Permissions.openBatteryOptimizationList();
        if (!ok) return '跳不进去，手动点：设置 → 应用管理 → 朝暮 → 省电策略 → 无限制';
        return null;
      },
      check: () async {
        final bool? v = await Notifier.I.isIgnoringBatteryOptimization();
        // 查不到（null）当「过」，别卡住用户
        return v ?? true;
      },
    ),
    _Step(
      title: '打开自启动',
      why: '不开的话手机重启后提醒不会自动重排，重启或重装后全丢。',
      how: '在系统页把朝暮的「自启动」打开。这一页里同时有「自启动」和「省电策略」，'
          '和省电那一步跳的是同一个地方。',
      open: () async {
        // 和省电那步跳同一个地方 ——「朝暮的应用信息」页。
        // 这一页里**同时有「自启动」和「省电策略」**，而且走的是 Android 标准
        // action，换任何品牌都能跳。各家自启动专页是拼组件名硬跳的，
        // 换台手机可能就没有，所以只当兜底。
        final bool ok =
            (await Notifier.I.openAppDetails()) || (await Permissions.openAutoStart()) != null;
        if (!ok) return '跳不进去，手动点：设置 → 应用管理 → 朝暮 → 自启动';
        return null;
      },
      // 部分 ROM 把这个开关挂在 AppOps 上，能读到真实状态；
      // 读不到就返回 null，按钮变成「我开好了，下一步」，交给用户自己确认。
      check: () async => Notifier.I.isAutoStartEnabled(),
    ),
  ];

  _Step get _step => _steps[_index];

  bool get _isLast => _index >= _steps.length - 1;

  @override
  void initState() {
    super.initState();
    _check();
  }

  /// 查当前这一步过没过
  Future<void> _check() async {
    final int at = _index;
    setState(() => _busy = true);
    final bool? v = await _step.check();
    if (!mounted || _index != at) return;
    setState(() {
      _state = v;
      _busy = false;
    });
  }

  Future<void> _goOpen() async {
    final String? tip = await _step.open();
    if (!mounted) return;
    if (tip != null) _toast(tip);
    // 跳完系统页回来，等一秒再查状态（系统页切回来会触发 resumed）
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) await _check();
  }

  Future<void> _next() async {
    // 系统查得到的项，没开就不放行
    if (_state == false) {
      _toast('还没开启，先去上面那把「${_step.title}」打开');
      return;
    }
    // 系统查不到的项（自启动）：按钮文案是「我开好了，下一步」，
    // 用户点了就是他自己确认过了，直接放行。

    if (_isLast) {
      await _finish();
      return;
    }
    setState(() {
      _index++;
      _state = false;
    });
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (mounted) await _check();
  }

  Future<void> _back() async {
    if (_index == 0) return;
    setState(() {
      _index--;
      _state = false;
    });
    await _check();
  }

  Future<void> _finish() async {
    await AppState.I.setOnboarded(true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: OnboardEntry.child!),
    );
  }

  /// 中途退出：弹一次警告说清后果
  Future<void> _quit() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('先不设置？', style: TextStyle(fontSize: 16)),
        content: const Text(
          '还没开的项，提醒很可能会晚到、或者干脆不响 —— '
          '这是国产系统杀后台导致的，不是朝暮的问题。\n\n'
          '之后可以在「设置 → 权限中心」随时补上。',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('继续设置')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('先退出')),
        ],
      ),
    );
    if (ok == true) {
      await AppState.I.setOnboarded(true);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: OnboardEntry.child!),
      );
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F8),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _progressBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
                child: _card(),
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  /// 顶部进度点 + 关闭按钮
  Widget _progressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 12, 0),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < _steps.length; i++)
            Container(
              width: i == _index ? 22 : 8,
              height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: i <= _index ? const Color(0xFF185FA5) : const Color(0xFFD5DFEA),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: _quit,
            child: const Text(
              '退出',
              style: TextStyle(fontSize: 13, color: Color(0xFF9A9A9A)),
            ),
          ),
        ],
      ),
    );
  }

  /// 当前这一步的主卡片
  Widget _card() {
    final bool unknown = _state == null;
    final bool done = _state == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '第 ${_index + 1} 步 / 共 ${_steps.length} 步',
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF9A9A9A)),
        ),
        const SizedBox(height: 8),
        Text(
          _step.title,
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, height: 1.3),
        ),
        const SizedBox(height: 14),

        // 为什么需要
        _block(
          icon: Icons.info_outline,
          color: const Color(0xFF185FA5),
          title: '为什么需要',
          body: _step.why,
        ),
        const SizedBox(height: 10),
        // 怎么开
        _block(
          icon: Icons.touch_app_outlined,
          color: const Color(0xFF3F7D42),
          title: '怎么开',
          body: '点下面的「去开启」会跳到系统页。\n${_step.how}',
        ),
        const SizedBox(height: 18),

        // 状态行
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            color: done
                ? const Color(0xFFE6F4EA)
                : (unknown ? const Color(0xFFFFFBF0) : const Color(0xFFFDE7E7)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: done
                  ? const Color(0xFFB7E0C0)
                  : (unknown ? const Color(0xFFF0E2BE) : const Color(0xFFF3C6C6)),
            ),
          ),
          child: Row(
            children: <Widget>[
              if (_busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  done
                      ? Icons.check_circle
                      : (unknown ? Icons.help_outline : Icons.error_outline),
                  size: 18,
                  color: done
                      ? const Color(0xFF3F7D42)
                      : (unknown ? const Color(0xFFBA7517) : const Color(0xFFA32D2D)),
                ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _busy
                      ? '正在检查…'
                      : (done
                          ? '已经开好了'
                          : (unknown
                              ? '这项系统查不到状态 —— 你自己确认一下开好了没'
                              : '还没开启')),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: done
                        ? const Color(0xFF3F7D42)
                        : (unknown ? const Color(0xFF7A5B12) : const Color(0xFFA32D2D)),
                  ),
                ),
              ),
              if (!_busy)
                IconButton(
                  tooltip: '重新检查',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: _check,
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _block({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E6E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(fontSize: 13, height: 1.75, color: Color(0xFF4A4A4A)),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final bool done = _state == true;
    final bool unknown = _state == null;
    final bool canNext = !_busy && (done || unknown);

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F7F8),
        border: Border(top: BorderSide(color: Color(0xFFEAEAEA))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (_index > 0) ...<Widget>[
                SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _back,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: Color(0xFFD5DFEA)),
                    ),
                    child: const Text('上一步', style: TextStyle(fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: FilledButton(
                    onPressed: _busy ? null : _goOpen,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE9EFF7),
                      foregroundColor: const Color(0xFF185FA5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      '去开启',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: canNext ? _next : null,
              style: FilledButton.styleFrom(
                backgroundColor:
                    canNext ? const Color(0xFF185FA5) : const Color(0xFFD5DFEA),
                foregroundColor: canNext ? Colors.white : const Color(0xFF7A8A9C),
                disabledBackgroundColor: const Color(0xFFD5DFEA),
                disabledForegroundColor: const Color(0xFF7A8A9C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                _isLast ? '完成，开始使用朝暮' : (unknown ? '我开好了，下一步' : '下一步'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 引导流程结束后要显示的页面。
///
/// 故意做成可注入的：main.dart 用 [OnboardEntry.child] 在 runApp 前设成 HomePage，
/// 避免 onboard_page 直接 import home_page 造成循环依赖。
class OnboardEntry extends StatelessWidget {
  const OnboardEntry({super.key});

  /// 引导完成后进哪个页面。main.dart 在 runApp 前设好。
  static WidgetBuilder? child;

  @override
  Widget build(BuildContext context) {
    final WidgetBuilder? b = child;
    if (b == null) {
      return const Scaffold(body: Center(child: Text('启动中…')));
    }
    return b(context);
  }
}
