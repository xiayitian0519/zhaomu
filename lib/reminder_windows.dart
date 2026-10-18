import 'dart:async';

/// 多久查一次到点。15 秒 = 提醒最晚晚 15 秒，
/// 换成 1 分钟的话用户会觉得「明明 9:00 却 9:00 过半才响」。
const Duration _tick = Duration(seconds: 15);

/// 一条排着的提醒
class _Slot {
  _Slot({required this.title, required this.body, required this.when});
  final String title;
  final String body;
  final DateTime when;
}

/// Windows 版提醒调度器：App 内自己比对时间，到点弹即时 Toast。
///
/// 为什么不走系统排程（三条都是查证过的硬限制，不是偷懒）：
/// 1. 非 MSIX 打包的 exe，flutter_local_notifications 的 cancel() 是空操作，
///    用户改了提醒时间，旧的排程撤不回来；
/// 2. 官方 README 明确写 Windows 不支持周期性通知；
/// 3. Windows 的定时 Toast 在关机 / 休眠期间不保证补发。
///
/// 代价：朝暮必须一直在跑。靠「点关闭 → 收进托盘」+ 开机自启来保证。
class WindowsReminder {
  WindowsReminder(this._fire);

  /// 真正弹通知的动作，由 Notifier 注入 —— 复用同一个插件实例，
  /// 免得两个 FlutterLocalNotificationsPlugin 互相覆盖 AUMID 注册。
  final Future<void> Function(String todoId, String title, String body) _fire;

  final Map<String, _Slot> _slots = <String, _Slot>{};

  /// 启动时发现「已经过点」的待办先收在这里，由 flushMissed 汇总成一条弹，
  /// 不逐条弹 —— 隔一夜开机弹 8 条通知会淹掉用户。
  final Map<String, _Slot> _missed = <String, _Slot>{};

  Timer? _timer;

  /// 现在排着几条（设置页用来显示调度器是否活着）
  int get count => _slots.length;

  bool get running => _timer != null;

  void start() {
    _timer ??= Timer.periodic(_tick, (_) {
      // ignore: avoid_print
      print('[win-timer] tick, 待弹 $count 条');
      _tickOnce();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 排一条。同 id 直接覆盖（改时间就是覆盖）。
  void put({
    required String todoId,
    required String title,
    required String body,
    required DateTime when,
  }) {
    _slots[todoId] = _Slot(title: title, body: body, when: when);
  }

  void remove(String todoId) => _slots.remove(todoId);

  void clear() {
    _slots.clear();
    _missed.clear();
  }

  /// 启动时发现这条已经过了提醒时间（关机 / 休眠时错过的），先记下，
  /// 最后统一由 [flushMissed] 汇总弹一条。
  void putMissed({
    required String todoId,
    required String title,
    required String body,
    required DateTime when,
  }) {
    _missed[todoId] = _Slot(title: title, body: body, when: when);
  }

  /// 把 [putMissed] 收下的错过的提醒汇总成一条弹出去。
  /// 返回补了几条；0 表示没有错过的。
  Future<int> flushMissed() async {
    if (_missed.isEmpty) return 0;
    final List<String> titles =
        _missed.values.take(3).map((_Slot s) => s.title).toList();
    final int n = _missed.length;
    _missed.clear();
    final String head = n == 1 ? '错过 1 条提醒' : '错过 $n 条提醒';
    final String body =
        titles.join(' · ') + (n > titles.length ? ' 等' : '');
    await _fire('', head, body);
    return n;
  }

  Future<void> _tickOnce() async {
    final DateTime now = DateTime.now();
    final List<String> due = <String>[];
    _slots.forEach((String id, _Slot s) {
      if (!s.when.isAfter(now)) due.add(id);
    });
    for (final String id in due) {
      final _Slot? s = _slots.remove(id);
      if (s == null) continue;
      await _fire(id, s.title, s.body);
    }
  }
}
