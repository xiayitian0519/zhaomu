import 'dart:async';

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models.dart';

/// 新手指引的锚点 Key
///
/// 每个要"亮出来"的控件挂一个。挂在固定位置的控件上没问题；
/// [firstEdit] 挂在列表第一行，属于会移动的 Key —— 所以它只在引导进行中才挂
/// （见 home_page.dart），平时为 null，避免 GlobalKey 在重建时冲突。
class GuideKeys {
  GuideKeys._();

  /// 主页底部输入栏整条
  static final GlobalKey inputBar = GlobalKey(debugLabel: 'guide_inputBar');

  /// 主页第一条待办行尾的铅笔
  static final GlobalKey firstEdit = GlobalKey(debugLabel: 'guide_firstEdit');

  /// 主页 AppBar 的「日历」按钮
  static final GlobalKey calBtn = GlobalKey(debugLabel: 'guide_calBtn');

  /// 详情页里「时钟」那一行
  static final GlobalKey clockRow = GlobalKey(debugLabel: 'guide_clockRow');

  /// 日历页 AppBar 的「展开 / 收起」按钮
  static final GlobalKey collapseBtn = GlobalKey(debugLabel: 'guide_collapseBtn');
}

/// 这一步开始前要先切到哪个页面
enum GuideRoute {
  /// 原地不动
  none,

  /// 退回主页（popUntil first）
  home,

  /// 推入日历页
  calendar,
}

/// 这一步怎么才算过（2026-10-24 改：从"点按钮就过"改成"真做了才过"）
enum GuideGate {
  /// 点气泡上的按钮就过
  tapNext,

  /// 等用户真的新增了一条待办
  todoAdded,

  /// 等用户真的点开了一条待办的详情
  detailOpened,

  /// 等用户真的进了日历页
  calendarOpened,

  /// 等用户真的点了「展开」
  expanded,
}

/// 一步引导
class GuideStep {
  const GuideStep({
    required this.text,
    required this.btn,
    this.key,
    this.route = GuideRoute.none,
    this.gate = GuideGate.tapNext,
    this.noMask = false,
    this.page = 'home',
  });

  /// 要亮出来的控件。null = 不挖洞（配合 [noMask] 只浮一个气泡）
  final GlobalKey? key;

  /// 气泡里那句话
  final String text;

  /// 按钮文字
  final String btn;

  /// 进这一步之前先切到哪个页面
  final GuideRoute route;

  /// 这一步怎么算过
  final GuideGate gate;

  /// true = 不压暗屏幕、不拦点击，只浮一个气泡
  /// （用户原话：「这一条的不用灰屏，要给用户看一下月待办界面」）
  final bool noMask;

  /// 这一步应该在哪个页面：home / detail / calendar。
  /// 用户跑去别的页面时用来提醒回来。
  final String page;
}

/// 引导控制器
///
/// 全局单例。页面只负责在合适的时候 [start] / 上报页面变化，其余状态都由它管。
class GuideController extends ChangeNotifier {
  GuideController._();

  static final GuideController I = GuideController._();

  /// 步骤表。GlobalKey 不是常量，所以这里只能是 final 不能是 const。
  ///
  /// 2026-10-24 按用户逐条要求重排：
  /// 1. 必须真的加一条待办
  /// 2. 真的点铅笔进详情
  /// 3. 在详情页介绍「时钟」
  /// 4. 真的点日历进日历页
  /// 5. 日历页只浮气泡、不灰屏
  /// 6. 真的点展开
  /// 7. 展开后不再拦截，提示返回
  static final List<GuideStep> steps = <GuideStep>[
    GuideStep(
      key: GuideKeys.inputBar,
      text: '先在下面输入框里打一条待办，按回车或者点右边的 ✓ 加进来。加好这条自动往下走。',
      btn: '先跳过',
      gate: GuideGate.todoAdded,
      page: 'home',
    ),
    GuideStep(
      key: GuideKeys.firstEdit,
      text: '点这一行的铅笔，进去看看这条待办的细则。',
      btn: '点不进去？',
      gate: GuideGate.detailOpened,
      page: 'home',
    ),
    GuideStep(
      key: GuideKeys.clockRow,
      text: '时间都在这儿设：点它可以选日期和具体时刻、挑提前多久提醒，还能设每天 / 每周重复。',
      btn: '明白了',
      gate: GuideGate.tapNext,
      page: 'detail',
    ),
    GuideStep(
      key: GuideKeys.calBtn,
      text: '点右上角这个日历，看看整月的安排。',
      btn: '点不进去？',
      gate: GuideGate.calendarOpened,
      route: GuideRoute.home,
      page: 'home',
    ),
    GuideStep(
      text: '这里能总览月待办哦',
      btn: '下一步',
      gate: GuideGate.tapNext,
      noMask: true,
      page: 'calendar',
    ),
    GuideStep(
      key: GuideKeys.collapseBtn,
      text: '点这个箭头，把整月铺开来看看。',
      btn: '展开不了？',
      gate: GuideGate.expanded,
      page: 'calendar',
    ),
    GuideStep(
      text: '铺开了。点左上角的返回箭头就能回主页，引导到这儿就结束啦。',
      btn: '完成了',
      gate: GuideGate.tapNext,
      noMask: true,
      page: 'calendar',
    ),
  ];

  /// -1 = 未开始
  int index = -1;

  bool get active => index >= 0;

  GuideStep get current => steps[index];

  /// 现在是不是最后一步
  bool get isLast => index >= steps.length - 1;

  /// 当前所在页面，由各页面的 initState / dispose 上报
  String page = 'home';

  final List<String> _stack = <String>['home'];

  /// 页面跳转回调 —— 由 main.dart 注入，避免 guide.dart 反向依赖 pages
  void Function()? pushCalendar;
  void Function()? goHome;

  /// 有没有被用户跑题跑到别的页面
  bool get offTrack => active && !current.noMask && current.page != page;

  /// 首次进入主页时调用
  Future<void> start() async {
    if (active) return;
    _stack
      ..clear()
      ..add('home');
    page = 'home';
    await goTo(0);
  }

  /// 某一步要"真的有内容才能指" —— 没有待办时先垫一条，引导结束删掉
  Todo? _temp;

  Future<void> next() async {
    if (!active) return;
    await goTo(index + 1);
  }

  Future<void> goTo(int i) async {
    if (i < 0) i = 0;
    if (i >= steps.length) {
      await finish();
      return;
    }

    index = i;
    notifyListeners();

    switch (steps[i].route) {
      case GuideRoute.calendar:
        pushCalendar?.call();
        await Future<void>.delayed(const Duration(milliseconds: 450));
        break;
      case GuideRoute.home:
        goHome?.call();
        await Future<void>.delayed(const Duration(milliseconds: 450));
        break;
      case GuideRoute.none:
        break;
    }

    // 第 1 步要求用户真的加一条待办；如果列表还是空的，
    // 用户可能连输入框都不敢碰 —— 垫一条示例让他有得看，引导结束删掉。
    if (steps[i].gate == GuideGate.detailOpened && AppState.I.todos.isEmpty) {
      _temp = await AppState.I.add('示例待办：点右边的铅笔改我');
    }

    // 让目标控件再长一帧，然后重算位置
    await Future<void>.delayed(const Duration(milliseconds: 80));
    notifyListeners();
  }

  // ---------------- 页面 / 动作上报 ----------------

  /// 页面进来时调（DetailPage / CalendarPage 的 initState）
  void enter(String p) {
    if (_stack.isNotEmpty && _stack.last == p) return;
    _stack.add(p);
    page = p;
    notifyListeners();
    _autoGate();
  }

  /// 页面销毁时调（dispose）
  void leave(String p) {
    if (_stack.isNotEmpty && _stack.last == p) {
      _stack.removeLast();
    } else {
      _stack.remove(p);
    }
    page = _stack.isEmpty ? 'home' : _stack.last;
    notifyListeners();
    _autoGate();
  }

  /// 用户真的新增了一条待办（home_page 的 _quickAdd 成功后调）
  void onTodoAdded() => _autoGate();

  /// 用户真的点了展开（calendar_page 调）—— 这一步没有别的过关方式
  void onExpanded() {
    if (!active) return;
    if (current.gate == GuideGate.expanded) {
      next();
    }
  }

  /// 到达当前步骤该在的页面 / 做完了该做的动作，就自动往下走
  void _autoGate() {
    if (!active) return;
    final GuideGate g = current.gate;
    if (g == GuideGate.todoAdded &&
        page == 'home' &&
        AppState.I.todos.isNotEmpty) {
      next();
      return;
    }
    if (g == GuideGate.detailOpened && page == 'detail') {
      next();
      return;
    }
    if (g == GuideGate.calendarOpened && page == 'calendar') {
      next();
      return;
    }
  }

  /// 跑题了，点一下回到该在的地方
  ///
  /// 「该在详情页」这种情况没法自动重进（不知道是哪条待办），
  /// 所以退回第 2 步，让用户重新点一次铅笔 —— 不然会卡死在提示上。
  void backOnTrack() {
    if (!active) return;
    switch (current.page) {
      case 'calendar':
        pushCalendar?.call();
        break;
      case 'detail':
        goHome?.call();
        goTo(1);
        break;
      default:
        goHome?.call();
    }
  }

  /// 引导结束：跳过、走完、或用户退出
  Future<void> finish() async {
    if (!active) return;
    index = -1;
    notifyListeners();

    final Todo? t = _temp;
    _temp = null;
    if (t != null) {
      await AppState.I.remove(t);
    }

    await AppState.I.setGuideDone(true);
  }

  /// 强制重算（目标还没渲染出来时由 GuideHost 触发）
  void refresh() => notifyListeners();
}

/// 引导外壳：包在 MaterialApp.builder 里，永远盖在 Navigator 之上
///
/// 这样切页面（push 日历）时引导层不会被新页面盖住。
class GuideHost extends StatefulWidget {
  const GuideHost({super.key, required this.child});

  final Widget child;

  @override
  State<GuideHost> createState() => _GuideHostState();
}

class _GuideHostState extends State<GuideHost> {
  Timer? _retry;

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  Rect? _rectOf(GlobalKey? key) {
    if (key == null) return null;
    final BuildContext? c = key.currentContext;
    if (c == null) return null;
    final RenderObject? ro = c.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return null;
    final Offset o = ro.localToGlobal(Offset.zero);
    return o & ro.size;
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: GuideController.I,
      builder: (BuildContext ctx, Widget? _) {
        final GuideController c = GuideController.I;
        if (!c.active) return widget.child;
        return Stack(
          children: <Widget>[
            widget.child,
            Positioned.fill(child: _buildGuide(c)),
          ],
        );
      },
    );
  }

  Widget _buildGuide(GuideController c) {
    final GuideStep step = c.current;

    // 不灰屏的步骤（看月待办 / 最后提示返回）：只浮一个气泡，
    // 底下随便点随便看，不挖洞也不拦截
    if (step.noMask) {
      return _floatTip(c, step);
    }

    // 用户跑题了（返回了、滑走了）—— 先提示回来
    if (c.offTrack) {
      return _offTrackTip(c);
    }

    final Rect? raw = _rectOf(step.key);
    if (raw == null) {
      // 目标还没渲染出来（多半是刚切完页）——先只铺遮罩，稍后重试
      _scheduleRetry();
      return IgnorePointer(child: Container(color: const Color(0x8C000000)));
    }

    const double pad = 6;
    final Rect hole = Rect.fromLTWH(
      raw.left - pad,
      raw.top - pad,
      raw.width + pad * 2,
      raw.height + pad * 2,
    );

    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints cons) {
        final double w = cons.maxWidth;
        final double h = cons.maxHeight;

        const double tipW = 268;
        const double tipH = 132;
        const double gap = 16;

        final double below = h - hole.bottom;
        final double above = hole.top;
        final bool putAbove = below < tipH + gap + 10 && above >= tipH + gap + 10;

        double top = putAbove ? (hole.top - gap - tipH) : (hole.bottom + gap);
        top = top.clamp(12.0, h - tipH - 12);

        double left = hole.center.dx - tipW / 2;
        left = left.clamp(12.0, w - tipW - 12);

        final double arrowX =
            (hole.center.dx - left - 7).clamp(20.0, tipW - 34.0);

        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _MaskPainter(hole: hole),
                ),
              ),
            ),
            // 四块拼成"回"字形，中间的洞不拦截 —— 用户能真的点到底下那个控件
            _blocker(Rect.fromLTRB(0, 0, w, hole.top)),
            _blocker(Rect.fromLTRB(0, hole.bottom, w, h)),
            _blocker(Rect.fromLTRB(0, hole.top, hole.left, hole.bottom)),
            _blocker(Rect.fromLTRB(hole.right, hole.top, w, hole.bottom)),
            Positioned(
              left: left,
              top: top,
              width: tipW,
              child: _Tip(
                text: step.text,
                btn: step.btn,
                arrowX: arrowX,
                arrowAbove: !putAbove,
                onNext: c.next,
                onSkip: c.finish,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 不灰屏的气泡：固定在页面上方，带一个「知道了 / 下一步」
  Widget _floatTip(GuideController c, GuideStep step) {
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints cons) {
        final double w = cons.maxWidth;
        final double width = w - 28 > 340 ? 340 : w - 28;
        return Stack(
          children: <Widget>[
            Positioned(
              left: (w - width) / 2,
              top: 84,
              width: width,
              child: _Tip(
                text: step.text,
                btn: step.btn,
                arrowX: 0,
                arrowAbove: false,
                showArrow: false,
                onNext: c.next,
                onSkip: c.finish,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 跑题提示：告诉用户回主页继续
  Widget _offTrackTip(GuideController c) {
    return ColoredBox(
      color: const Color(0x8C000000),
      child: Center(
        child: Container(
          width: 280,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '引导还没走完哦，先回主页继续',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.6,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1F1F1F),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  _Dots(
                    current: c.index,
                    total: GuideController.steps.length,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => c.finish(),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: const Color(0xFF9A9A9A),
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                    child: const Text('退出引导'),
                  ),
                  const SizedBox(width: 2),
                  FilledButton(
                    onPressed: () => c.backOnTrack(),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF185FA5),
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w500),
                    ),
                    child: const Text('回去继续'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _blocker(Rect r) {
    if (r.width <= 0 || r.height <= 0) return const SizedBox.shrink();
    return Positioned(
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
      ),
    );
  }
}

/// 遮罩：整屏压暗，中间挖一个圆角洞
class _MaskPainter extends CustomPainter {
  _MaskPainter({required this.hole});

  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rr = RRect.fromRectAndRadius(hole, const Radius.circular(12));

    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x8C000000));
    canvas.drawRRect(rr, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x59FFFFFF),
    );
  }

  @override
  bool shouldRepaint(covariant _MaskPainter old) => old.hole != hole;
}

/// 气泡
class _Tip extends StatelessWidget {
  const _Tip({
    required this.text,
    required this.btn,
    required this.arrowX,
    required this.arrowAbove,
    required this.onNext,
    required this.onSkip,
    this.showArrow = true,
  });

  final String text;
  final String btn;
  final double arrowX;

  /// true = 箭头在气泡上边缘（气泡在目标下方）
  final bool arrowAbove;

  final Future<void> Function() onNext;
  final Future<void> Function() onSkip;

  /// 浮在页面上方（不挖洞）时不画箭头
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showArrow && arrowAbove)
          Padding(
            padding: EdgeInsets.only(left: arrowX),
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(width: 14, height: 14, color: Colors.white),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                  color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2)),
              BoxShadow(
                  color: Color(0x59000000),
                  blurRadius: 30,
                  offset: Offset(0, 14)),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                text,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.6,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1F1F1F),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  _Dots(
                      current: GuideController.I.index,
                      total: GuideController.steps.length),
                  const Spacer(),
                  TextButton(
                    onPressed: () => onSkip(),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: const Color(0xFF9A9A9A),
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                    child: const Text('跳过'),
                  ),
                  const SizedBox(width: 2),
                  FilledButton(
                    onPressed: () => onNext(),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF185FA5),
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w500),
                    ),
                    child: Text(btn),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (showArrow && !arrowAbove)
          Padding(
            padding: EdgeInsets.only(left: arrowX),
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(width: 14, height: 14, color: Colors.white),
            ),
          ),
      ],
    );
  }
}

/// 进度点
class _Dots extends StatelessWidget {
  const _Dots({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List<Widget>.generate(
        total,
        (int i) => Container(
          width: 5,
          height: 5,
          margin: const EdgeInsets.only(right: 5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                i == current ? const Color(0xFF1F1F1F) : const Color(0xFFDCDCDC),
          ),
        ),
      ),
    );
  }
}
