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

  /// 设置页「铃声 → 通知铃声」那一行
  static final GlobalKey ringTile = GlobalKey(debugLabel: 'guide_ringTile');

  /// 日历页 AppBar 的「展开 / 收起」按钮
  static final GlobalKey collapseBtn = GlobalKey(debugLabel: 'guide_collapseBtn');
}

/// 这一步开始前要去哪个页面
enum GuideRoute {
  /// 原地不动
  none,

  /// 推入设置页
  settings,

  /// 推入日历页
  calendar,

  /// 退回主页（popUntil first）
  home,
}

/// 一步引导
class GuideStep {
  const GuideStep({
    required this.key,
    required this.text,
    required this.btn,
    this.route = GuideRoute.none,
  });

  /// 要亮出来的控件
  final GlobalKey key;

  /// 气泡里那句话
  final String text;

  /// 按钮文字
  final String btn;

  /// 进这一步之前先切到哪个页面
  final GuideRoute route;
}

/// 引导控制器
///
/// 全局单例。页面只负责在合适的时候 [start]，其余状态都由它管。
class GuideController extends ChangeNotifier {
  GuideController._();

  static final GuideController I = GuideController._();

  /// 步骤表。GlobalKey 不是常量，所以这里只能是 final 不能是 const。
  static final List<GuideStep> steps = <GuideStep>[
    GuideStep(
      key: GuideKeys.inputBar,
      text: '从这里新增一条今日待办哦。',
      btn: '下一步',
    ),
    GuideStep(
      key: GuideKeys.firstEdit,
      text: '点这里来设置事件细则哦',
      btn: '下一步',
    ),
    GuideStep(
      key: GuideKeys.ringTile,
      text: '所有提醒用哪个铃声，在这挑哦',
      btn: '下一步',
      route: GuideRoute.settings,
    ),
    GuideStep(
      key: GuideKeys.calBtn,
      text: '这里能总览和添加月待办哦',
      btn: '下一步',
      route: GuideRoute.home,
    ),
    GuideStep(
      key: GuideKeys.collapseBtn,
      text: '这里可以展开来总览本月待办哦',
      btn: '知道了',
      route: GuideRoute.calendar,
    ),
  ];

  /// -1 = 未开始
  int index = -1;

  bool get active => index >= 0;

  GuideStep get current => steps[index];

  /// 现在是不是最后一步
  bool get isLast => index >= steps.length - 1;

  /// 页面跳转回调 —— 由 main.dart 注入，避免 guide.dart 反向依赖 pages
  void Function()? pushSettings;
  void Function()? pushCalendar;
  void Function()? goHome;

  /// 空列表时临时插的示例待办，引导结束要删掉
  Todo? _temp;

  /// 首次进入主页时调用
  Future<void> start() async {
    if (active) return;

    // 一条待办都没有时，"编辑细则"那步没有可以指的东西 ——
    // 临时插一条示例，引导结束（或跳过）时删掉。
    if (AppState.I.todos.isEmpty) {
      _temp = await AppState.I.add('示例待办：点右边的铅笔改我');
    }

    await goTo(0);
  }

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
      case GuideRoute.settings:
        pushSettings?.call();
        await Future<void>.delayed(const Duration(milliseconds: 450));
        await _ensureVisible(GuideKeys.ringTile);
        break;
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

    // 让目标控件再长一帧，然后重算位置
    await Future<void>.delayed(const Duration(milliseconds: 80));
    notifyListeners();
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

  Future<void> _ensureVisible(GlobalKey k) async {
    final BuildContext? c = k.currentContext;
    if (c == null) return;
    try {
      await Scrollable.ensureVisible(
        c,
        duration: const Duration(milliseconds: 280),
        alignment: 0.5,
      );
    } catch (_) {
      // 目标不在可滚动区域内就算了，位置照常算
    }
    await Future<void>.delayed(const Duration(milliseconds: 320));
  }
}

/// 引导外壳：包在 MaterialApp.builder 里，永远盖在 Navigator 之上
///
/// 这样切页面（push 设置 / 日历）时引导层不会被新页面盖住。
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

  Rect? _rectOf(GlobalKey key) {
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
        const double tipH = 124;
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
            // 遮罩（视觉）
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _MaskPainter(hole: hole),
                ),
              ),
            ),

            // 点击拦截：用四块拼成"回"字形，中间的洞不拦截 ——
            // 这样用户能真的点到底下那个亮着的控件
            _blocker(Rect.fromLTRB(0, 0, w, hole.top)),
            _blocker(Rect.fromLTRB(0, hole.bottom, w, h)),
            _blocker(Rect.fromLTRB(0, hole.top, hole.left, hole.bottom)),
            _blocker(Rect.fromLTRB(hole.right, hole.top, w, hole.bottom)),

            // 气泡
            Positioned(
              left: left,
              top: top,
              width: tipW,
              child: _Tip(
                text: step.text,
                btn: step.btn,
                showSkip: true,
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

  /// 一块透明的点击拦截区（吃掉点击，防止误触底层）
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

    // 洞的一圈白边，让"亮出来"更明显
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
    required this.showSkip,
    required this.arrowX,
    required this.arrowAbove,
    required this.onNext,
    required this.onSkip,
  });

  final String text;
  final String btn;
  final bool showSkip;
  final double arrowX;

  /// true = 箭头在气泡上边缘（气泡在目标下方）
  final bool arrowAbove;

  final Future<void> Function() onNext;
  final Future<void> Function() onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (arrowAbove)
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
              BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2)),
              BoxShadow(color: Color(0x59000000), blurRadius: 30, offset: Offset(0, 14)),
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
                  _Dots(current: GuideController.I.index, total: GuideController.steps.length),
                  const Spacer(),
                  if (showSkip)
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
                      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                    ),
                    child: Text(btn),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!arrowAbove)
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
            color: i == current ? const Color(0xFF1F1F1F) : const Color(0xFFDCDCDC),
          ),
        ),
      ),
    );
  }
}
