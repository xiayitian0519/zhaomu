import 'dart:async';

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models.dart';

// ---------------- 撤销提示 ----------------

/// 当前正在显示的撤销提示，同一时间只留一条
_UndoToast? _currentToast;

/// 撤销回调：可以是同步的，也可以是 async（返回值忽略）
typedef UndoAction = dynamic Function();

/// 底部弹 3 秒撤销提示。
///
/// 和其它 SnackBar 不同：这一条浮在底部输入框上方，不会挡住打字；
/// 点屏幕上任意空白处立即关掉。用 Overlay 实现，不依赖 Scaffold 层级，
/// 所以切页 / 关键盘都不会残留。
void showUndo(BuildContext context, String message, UndoAction onUndo) {
  final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _currentToast?.remove();

  late final _UndoToast toast;
  toast = _UndoToast(
    overlay: overlay,
    message: message,
    onUndo: onUndo,
    onClosed: () {
      if (identical(_currentToast, toast)) _currentToast = null;
    },
  );
  _currentToast = toast;
  toast.show();
}

/// 主动关掉当前撤销提示（进入别的页面时调用，避免残留）
void dismissUndo() {
  _currentToast?.remove();
  _currentToast = null;
}

class _UndoToast {
  _UndoToast({
    required this.overlay,
    required this.message,
    required this.onUndo,
    required this.onClosed,
  });

  final OverlayState overlay;
  final String message;
  final UndoAction onUndo;
  final VoidCallback onClosed;

  OverlayEntry? _entry;
  Timer? _timer;
  bool _gone = false;

  void show() {
    _entry = OverlayEntry(builder: _build);
    overlay.insert(_entry!);
    _timer = Timer(const Duration(seconds: 3), remove);
  }

  void remove() {
    if (_gone) return;
    _gone = true;
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
    onClosed();
  }

  void _undo() {
    onUndo();
    remove();
  }

  Widget _build(BuildContext context) {
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Positioned.fill(
      child: Stack(
        children: <Widget>[
          // 透明遮罩：点在空白处即关掉提示
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: remove,
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            // 键盘弹出时跟着抬起来；没键盘时压在输入框（约 56 + 手势条）上方
            bottom: bottomInset + 68,
            child: Material(
              color: const Color(0x00000000),
              child: GestureDetector(
                // 点在提示条本体上不关，避免误触
                onTap: () {},
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2B2B2B),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFFF2F2F2), fontSize: 14, height: 1.4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _undo,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          foregroundColor: const Color(0xFF7FB2E0),
                          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        child: const Text('撤销'),
                      ),
                      IconButton(
                        onPressed: remove,
                        tooltip: '关闭',
                        icon: const Icon(Icons.close, size: 18, color: Color(0xFF9A9A9A)),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- 四象限盘 ----------------

/// 长按待办后弹出，手指滑到某个象限内松手即打标；松手在盘外 = 取消
Future<int?> showQuadrantPicker(BuildContext context, {int current = Priority.none}) {
  return showGeneralDialog<int>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'quadrant',
    barrierColor: const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (BuildContext c, Animation<double> a1, Animation<double> a2) =>
        QuadrantPad(current: current),
    transitionBuilder: (BuildContext c, Animation<double> a, Animation<double> b, Widget child) =>
        FadeTransition(opacity: a, child: child),
  );
}

class QuadrantPad extends StatefulWidget {
  const QuadrantPad({super.key, this.current = Priority.none});

  final int current;

  @override
  State<QuadrantPad> createState() => _QuadrantPadState();
}

class _QuadrantPadState extends State<QuadrantPad> {
  static const double _padSize = 300;

  Offset? _pos;
  bool _closed = false;

  Rect _rect(Size size) => Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: _padSize,
        height: _padSize,
      );

  int? _quadrantAt(Offset p, Rect r) {
    if (!r.contains(p)) return null;
    final bool left = p.dx < r.center.dx;
    final bool top = p.dy < r.center.dy;
    if (top && left) return Priority.urgentImportant;
    if (top && !left) return Priority.importantNotUrgent;
    if (!top && left) return Priority.urgentNotImportant;
    return Priority.notUrgentNotImportant;
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    final Offset? p = _pos;
    final Rect r = _rect(MediaQuery.sizeOf(context));
    final int? q = (p == null) ? null : _quadrantAt(p, r);
    Navigator.of(context).pop(q);
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final Rect r = _rect(size);
    final AppState st = AppState.I;

    Widget cell(int q) {
      final bool cur = widget.current == q;
      return Container(
        decoration: BoxDecoration(
          color: st.colorOf(q),
          // 2026-10-17 用户要求：只留四个词和色块，边框 / 白框一律不要
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                Priority.names[q],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
            if (cur)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('当前', style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 12)),
              ),
          ],
        ),
      );
    }

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (PointerDownEvent e) => setState(() => _pos = e.position),
      onPointerMove: (PointerMoveEvent e) => setState(() => _pos = e.position),
      onPointerUp: (PointerUpEvent e) {
        _pos = e.position;
        _finish();
      },
      onPointerCancel: (PointerCancelEvent e) => _finish(),
      child: Stack(
        children: <Widget>[
          Positioned(
            left: r.left,
            top: r.top,
            width: r.width,
            height: r.height,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Row(
                    children: <Widget>[
                      Expanded(child: cell(Priority.urgentImportant)),
                      Expanded(child: cell(Priority.importantNotUrgent)),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: <Widget>[
                      Expanded(child: cell(Priority.urgentNotImportant)),
                      Expanded(child: cell(Priority.notUrgentNotImportant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- 列表里的小组件 ----------------

/// 左侧优先级竖色条
class PriorityBar extends StatelessWidget {
  const PriorityBar({super.key, required this.priority});

  final int priority;

  @override
  Widget build(BuildContext context) {
    final bool none = priority < 0;
    return Container(
      width: 6,
      height: 32,
      decoration: BoxDecoration(
        color: none ? const Color(0xFFE0E0E0) : AppState.I.colorOf(priority),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// 分组标题行，右端可挂「排序」按钮
class GroupHeader extends StatelessWidget {
  const GroupHeader({
    super.key,
    required this.title,
    required this.colorValue,
    this.showSort = false,
  });

  final String title;
  final int colorValue;
  final bool showSort;

  @override
  Widget build(BuildContext context) {
    final AppState st = AppState.I;
    return Container(
      color: const Color(0xFFF7F7F8),
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 6),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(colorValue)),
          ),
          const Spacer(),
          if (showSort)
            TextButton(
              onPressed: () {
                st.setSortMode(st.sortMode == 'time' ? 'priority' : 'time');
              },
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: const Color(0xFF5F5E5A),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: Text(st.sortMode == 'time' ? '排序：时间' : '排序：优先级'),
            ),
        ],
      ),
    );
  }
}

/// 小圆勾选框
class DoneCircle extends StatelessWidget {
  const DoneCircle({super.key, required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    const Color blue = Color(0xFF185FA5);
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? blue : const Color(0xFFFFFFFF),
        border: Border.all(color: done ? blue : const Color(0xFFBFBFBF), width: 1.6),
      ),
      child: done ? const Icon(Icons.check, size: 14, color: Color(0xFFFFFFFF)) : null,
    );
  }
}

// ---------------- 时间滚轮选择器 ----------------

/// 上下滑动选时刻（24 小时制）。
///
/// 用法：
/// ```dart
/// final TimeOfDay? t = await pickTime(context, initial: TimeOfDay.now());
/// if (t == null) return;            // 用户取消
/// print('${t.hour}:${t.minute}');
/// ```
///
/// 为什么不用 Flutter 自带的 `showTimePicker`：
/// 它默认是**表盘式**（那个圆形钟面数字圈），选 23:47 得点两轮，
/// 而且和本项目其它下拉面板的交互不统一。滚轮更符合选时间的直觉。
///
/// [minuteStep] 分钟步进，设 5 就只出 00/05/10…（赶时间时更好选）。
/// [helpText] 面板顶部那句话。
Future<TimeOfDay?> pickTime(
  BuildContext context, {
  required TimeOfDay initial,
  String? helpText,
  int minuteStep = 1,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (BuildContext c) => _WheelTimeSheet(
      initial: initial,
      helpText: helpText,
      minuteStep: minuteStep < 1 ? 1 : minuteStep,
    ),
  );
}

class _WheelTimeSheet extends StatefulWidget {
  const _WheelTimeSheet({
    required this.initial,
    required this.helpText,
    required this.minuteStep,
  });

  final TimeOfDay initial;
  final String? helpText;
  final int minuteStep;

  @override
  State<_WheelTimeSheet> createState() => _WheelTimeSheetState();
}

class _WheelTimeSheetState extends State<_WheelTimeSheet> {
  /// 行高。滚轮的视觉节奏全看它，别随便改
  static const double _itemH = 44;

  /// 上下各露几行
  static const int _pad = 2;

  late int _hour;
  late int _minute;
  late final FixedExtentScrollController _hCtrl;
  late final FixedExtentScrollController _mCtrl;

  /// 分钟可选值（按步进生成）
  late final List<int> _minuteOptions;

  @override
  void initState() {
    super.initState();
    _hour = widget.initial.hour;
    _minute = widget.initial.minute;
    _hCtrl = FixedExtentScrollController(initialItem: _hour);

    _minuteOptions = <int>[];
    for (int m = 0; m < 60; m += widget.minuteStep) {
      _minuteOptions.add(m);
    }
    // 当前分钟不在步进序列里（步进 5 但当前 47）→ 取最近的
    int mi = _minuteOptions.indexOf(_minute);
    if (mi < 0) {
      int best = 0;
      int diff = 999;
      for (int i = 0; i < _minuteOptions.length; i++) {
        final int d = (_minuteOptions[i] - _minute).abs();
        if (d < diff) {
          diff = d;
          best = i;
        }
      }
      mi = best;
      _minute = _minuteOptions[best];
    }
    _mCtrl = FixedExtentScrollController(initialItem: mi);
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _mCtrl.dispose();
    super.dispose();
  }

  String get _hh => _hour < 10 ? '0$_hour' : '$_hour';
  String get _mm => _minute < 10 ? '0$_minute' : '$_minute';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 顶部：说明 + 大号当前值
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.helpText ?? '选择时刻',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF8A8A8A)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$_hh:$_mm',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF185FA5),
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    '上下滑动选择',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFFB0B0B0)),
                  ),
                ],
              ),
            ),

            // 滚轮区
            SizedBox(
              height: _itemH * (_pad * 2 + 1),
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  // 中间选中高亮条
                  Container(
                    height: _itemH,
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F5FB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      _wheel(
                        controller: _hCtrl,
                        count: 24,
                        labelOf: (int i) => i < 10 ? '0$i' : '$i',
                        onChanged: (int i) => setState(() => _hour = ((i % 24) + 24) % 24),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          ':',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFBFBFBF),
                          ),
                        ),
                      ),
                      _wheel(
                        controller: _mCtrl,
                        count: _minuteOptions.length,
                        labelOf: (int i) =>
                            _minuteOptions[i] < 10 ? '0${_minuteOptions[i]}' : '${_minuteOptions[i]}',
                        onChanged: (int i) => setState(() {
                          final int n = _minuteOptions.length;
                          _minute = _minuteOptions[((i % n) + n) % n];
                        }),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 底部按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
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
                        onPressed: () => Navigator.of(context)
                            .pop(TimeOfDay(hour: _hour, minute: _minute)),
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
    );
  }

  /// 单列滚轮
  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required String Function(int index) labelOf,
    required ValueChanged<int> onChanged,
  }) {
    return SizedBox(
      width: 84,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: _itemH,
        perspective: 0.003,
        diameterRatio: 1.7,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          // 不给 childCount = 上下都无限滚，label 按 count 取模环绕：
          // 00 之上是 59、之下是 01（用户 2026-10-16 定的双向滚轮），
          // 想选 59 从 00 往回拨一格就到，不用一路划到底
          builder: (BuildContext c, int i) {
            final int v = ((i % count) + count) % count;
            return _wheelItem(controller, i, labelOf(v));
          },
        ),
      ),
    );
  }

  /// 不带 controller 的滚动，用 AnimatedBuilder 跟着滚轮位置改字号/颜色。
  ///
  /// 不用 `controller.selectedItem` 是因为那只在停下来后更新，
  /// 滚动过程中字号不会变，看着很生硬。
  Widget _wheelItem(FixedExtentScrollController controller, int i, String text) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext c, Widget? _) {
        double dist = 0;
        if (controller.hasClients && controller.position.haveDimensions) {
          final double center = controller.position.pixels / _itemH;
          dist = (center - i).abs();
        }
        final bool selected = dist < 0.5;
        return Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: selected ? 21 : 16.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? const Color(0xFF1F1F1F) : const Color(0xFFB0B0B0),
            ),
          ),
        );
      },
    );
  }
}
