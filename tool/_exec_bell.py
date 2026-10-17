# -*- coding: utf-8 -*-
"""执行力B + 铃声方案A 批量改动。每处替换断言命中数，不符立即中止。"""
import io

def load(p):
    return io.open(p, 'r', encoding='utf-8').read()

def save(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)

def apply(path, pairs):
    s = load(path)
    for old, new, cnt in pairs:
        n = s.count(old)
        assert n == cnt, '%s 命中 %d 次(期望 %d): %s...' % (path, n, cnt, old[:60])
        s = s.replace(old, new)
    save(path, s)
    print('OK %-52s %d 处' % (path.split('\\')[-1], len(pairs)))

# ---------------- 1. notifier.dart ----------------
NOT = r'D:\chaomu\lib\notifier.dart'
s = load(NOT)
# 1a. 整删 Ringtone 类（含类注释）
a = s.index(u'/// 内置铃声。都是 app 自带的 wav')
b = s.index(u'/// 本地通知：负责把待办提醒排进系统闹钟')
s = s[:a] + s[b:]
# 1b. _details 签名与注释
pairs_not = [
    (
        u"""  fln.NotificationDetails _details({
    required String ringtone,
    required bool fullScreen,
    bool soundOn = true,
    String title = '',
    String body = '',
  }) {
    // 两层开关同时为真才出声：
    //   1. soundOn —— 设置里的「默认打开铃声」，关掉就整条静音
    //   2. ringtone != none —— 选的是「不响铃」这一款
    // 之前只判了第 2 条，所以「默认打开铃声」关掉也照响（那个开关是个摆设）。
    final bool ring = soundOn && ringtone != Ringtone.none;""",
        u"""  fln.NotificationDetails _details({
    required bool fullScreen,
    bool soundOn = true,
    String title = '',
    String body = '',
  }) {
    // 出声 = 设置里的「默认打开铃声」开着。响哪首歌由系统通知渠道设置决定
    // （2026-10-16 起铃声全部交给系统渠道：在渠道声音里挑本地/在线铃声），
    // 这里不再指定 sound，playSound: true 就是「用渠道里选的那首」。
    final bool ring = soundOn;""",
        1,
    ),
    (
        u"""        playSound: ring,
        // 内嵌铃声（res/raw/ring_*.wav，16-bit PCM），不受系统通知音设置影响。
        // 渠道那边故意不带 sound，所以这里传什么就响什么。
        sound: ring
            ? fln.RawResourceAndroidNotificationSound(Ringtone.androidSound(ringtone))
            : null,
        // 震动独立于铃声：选「不响铃」也要震
        enableVibration: true,""",
        u"""        playSound: ring,
        // 铃声不在这指定 —— 用系统渠道设置里选的那首（方案 A，2026-10-16）。
        // 渠道 v8 本来就没写死 sound，不传 sound 就是渠道配置的声音。
        // 震动独立于铃声：不出声也要震
        enableVibration: true,""",
        1,
    ),
    (u"""  Future<void> scheduleFor(
    Todo t, {
    required String ringtone,
    bool soundOn = true,""",
     u"""  Future<void> scheduleFor(
    Todo t, {
    bool soundOn = true,""", 1),
    (u"""        _details(
          ringtone: ringtone,
""", u"""        _details(
""", 4),
    (u"  Future<bool> showNow({required String ringtone, bool soundOn = true}) async {",
     u"  Future<bool> showNow({bool soundOn = true}) async {", 1),
    (u"  Future<bool> showNowFullScreen({required String ringtone, bool soundOn = true}) async {",
     u"  Future<bool> showNowFullScreen({bool soundOn = true}) async {", 1),
]
for old, new, cnt in pairs_not:
    n = s.count(old)
    assert n == cnt, 'notifier 命中 %d(期望 %d): %s...' % (n, cnt, old[:50])
    s = s.replace(old, new)
# 1c. 整删 preview / stopPreview 方法
a = s.index(u'  /// 试听某一款内置铃声。')
b = s.index(u'  /// 跳到系统里「朝暮 → 通知 → 待办提醒」这个渠道的设置页。')
s = s[:a] + s[b:]
# 1d. rescheduleAll 去掉 ringtone
old = u"""        ringtone: t.remindRingtone.isEmpty ? st.defaultRingtone : t.remindRingtone,
        // 「默认打开铃声」关掉 → 只弹不响。不传这个的话那个开关就是个摆设"""
new = u"""        // 「默认打开铃声」关掉 → 只弹不响。不传这个的话那个开关就是个摆设"""
n = s.count(old)
assert n == 1, 'rescheduleAll ringtone 命中 %d' % n
s = s.replace(old, new)
save(NOT, s)
print('OK notifier.dart')

# ---------------- 2. models.dart ----------------
MOD = r'D:\chaomu\lib\models.dart'
pairs_mod = [
    (u"""  /// 这条待办单独的铃声；空字符串 = 跟随设置里的默认铃声
  String remindRingtone;

  /// 这条待办单独提前多少分钟提醒；-1 = 跟随设置里的默认提前量""",
     u"""  /// 这条待办单独提前多少分钟提醒；-1 = 跟随设置里的默认提前量""", 1),
    (u"    this.remindRingtone = '',\n", u"", 1),
    (u"        'remindRingtone': remindRingtone,\n", u"", 1),
    (u"        remindRingtone: _migrateRingtone('${m['remindRingtone'] ?? ''}'),\n", u"", 1),
]
s = load(MOD)
# _migrateRingtone 方法整删
a = s.index(u"  /// 老存档里的铃声键（「铃声 1」这类）映射到新的内置铃声键。")
b = s.index(u'  static DateTime? _parseDt(Object? v) {')
s = s[:a] + s[b:]
for old, new, cnt in pairs_mod:
    n = s.count(old)
    assert n == cnt, 'models 命中 %d(期望 %d): %s...' % (n, cnt, old[:50])
    s = s.replace(old, new)
save(MOD, s)
print('OK models.dart')

# ---------------- 3. app_state.dart ----------------
APP = r'D:\chaomu\lib\app_state.dart'
s = load(APP)
pairs_app = [
    (u"""  /// 默认提醒铃声（内置四款，见 Ringtone.all）。'none' = 关掉铃声
  String defaultRingtone = 'chime';

  /// 默认提醒开关""", u"""  /// 默认提醒开关""", 1),
    (u"""        'defaultRingtone': defaultRingtone,\n""", u"", 1),
    (u"""
  Future<void> setDefaultRingtone(String name) async {
    defaultRingtone = name;
    notifyListeners();
    await save();
  }
""", u"", 1),
]
for old, new, cnt in pairs_app:
    n = s.count(old)
    assert n == cnt, 'app_state 命中 %d(期望 %d): %s...' % (n, cnt, old[:50])
    s = s.replace(old, new)
# _consume 里 defaultRingtone 解析块整删
a = s.index(u"    if (m['defaultRingtone'] is String) {")
b = s.index(u"    // 「默认打开铃声」的开关。")
s = s[:a] + s[b:]
save(APP, s)
print('OK app_state.dart')

# ---------------- 4. home_page.dart ----------------
apply(r'D:\chaomu\lib\pages\home_page.dart', [
    (u"""      t,
      ringtone: t.remindRingtone.isEmpty ? st.defaultRingtone : t.remindRingtone,
      soundOn: st.defaultRemindOn,""",
     u"""      t,
      soundOn: st.defaultRemindOn,""", 1),
])

# ---------------- 5. settings_page.dart ----------------
SET = r'D:\chaomu\lib\pages\settings_page.dart'
s = load(SET)
# 5a. _pickDefaultRingtone 整删
a = s.index(u'  Future<void> _pickDefaultRingtone(BuildContext context) async {')
b = s.index(u'  @override\n  Widget build(BuildContext context) {')
s = s[:a] + s[b:]
pairs_set = [
    (u"""    final bool ok = fullScreen
        ? await Notifier.I.showNowFullScreen(
            ringtone: st.defaultRingtone,
            soundOn: st.defaultRemindOn,
          )
        : await Notifier.I.showNow(
            ringtone: st.defaultRingtone,
            soundOn: st.defaultRemindOn,
          );""",
     u"""    final bool ok = fullScreen
        ? await Notifier.I.showNowFullScreen(soundOn: st.defaultRemindOn)
        : await Notifier.I.showNow(soundOn: st.defaultRemindOn);""", 1),
]
for old, new, cnt in pairs_set:
    n = s.count(old)
    assert n == cnt, 'settings 命中 %d(期望 %d): %s...' % (n, cnt, old[:50])
    s = s.replace(old, new)
# 5b. 铃声区块：删默认铃声行，本地铃声行改名通知铃声
a = s.index(u"              _sectionTitle('铃声'),")
b = s.index(u"              const _VersionLabel(),")
new_block = u"""              _sectionTitle('铃声'),
              _card(<Widget>[
                ListTile(
                  title: const Text('通知铃声', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    '在系统铃声页挑本地音乐 / 在线铃声，所有提醒统一用它',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _openChannelSettings(context),
                ),
              ]),

"""
s = s[:a] + new_block + s[b:]
save(SET, s)
print('OK settings_page.dart')

# ---------------- 6. detail_page.dart ----------------
DET = r'D:\chaomu\lib\pages\detail_page.dart'
s = load(DET)
# 6a. _pickRingtone 整删
a = s.index(u'  Future<void> _pickRingtone() async {')
b = s.index(u'  // ---------------- 截止面板 ----------------')
s = s[:a] + s[b:]
pairs_det = [
    (u"  String _ringtone = '';\n", u"", 1),
    (u"    _ringtone = t.remindRingtone;\n", u"", 1),
    (u"    t.remindRingtone = _ringtone;\n", u"", 1),
    (u"""    await Notifier.I.scheduleFor(
      t,
      ringtone: _ringtone.isEmpty ? st.defaultRingtone : _ringtone,
      // 「默认打开铃声」关掉 → 只弹不响，这里必须传下去""",
     u"""    await Notifier.I.scheduleFor(
      t,
      // 「默认打开铃声」关掉 → 只弹不响，这里必须传下去""", 1),
    (u"""          final String effective = _ringtone.isEmpty ? st.defaultRingtone : _ringtone;
""", u"", 1),
    (u"""                  IgnorePointer(
                    ignoring: _remindOff,
                    child: Opacity(
                      opacity: _remindOff ? 0.45 : 1.0,
                      child: ListTile(
                        leading: const Icon(Icons.music_note, size: 20, color: Color(0xFF5F5E5A)),
                        title: const Text('这条的铃声', style: TextStyle(fontSize: 14)),
                        subtitle: Text(
                          _ringtone.isEmpty
                              ? '跟随设置（${Ringtone.displayOf(st.defaultRingtone)}）'
                              : Ringtone.displayOf(_ringtone),
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (effective != Ringtone.none)
                              IconButton(
                                tooltip: '试听',
                                icon: const Icon(Icons.play_circle_outline, size: 20),
                                onPressed: () => Notifier.I.preview(effective),
                              ),
                            const Icon(Icons.chevron_right, size: 18),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(c).pop();
                          _pickRingtone();
                        },
                      ),
                    ),
                  ),
""", u"", 1),
]
for old, new, cnt in pairs_det:
    n = s.count(old)
    assert n == cnt, 'detail 命中 %d(期望 %d): %s...' % (n, cnt, old[:50])
    s = s.replace(old, new)
save(DET, s)
print('OK detail_page.dart')

# ---------------- 7. review_page.dart 执行力胶囊 ----------------
REV = r'D:\chaomu\lib\pages\review_page.dart'
apply(REV, [
    (u"""                    const Spacer(),
                    Text(
                      '${(ratio * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF185FA5),
                      ),
                    ),""",
     u"""                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F1FB),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: const Color(0xFFB5D4F4)),
                      ),
                      child: Text(
                        '执行力 ${(ratio * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF185FA5),
                        ),
                      ),
                    ),""", 1),
])

# ---------------- 8. history_page.dart 完成率 → 执行力 ----------------
HIS = r'D:\chaomu\lib\pages\history_page.dart'
apply(HIS, [
    (u'完成率 ', u'执行力 ', 3),
    (u'条（${(d.ratio * 100).round()}%）', u'条（执行力 ${(d.ratio * 100).round()}%）', 1),
])

# ---------------- 9. MainActivity.kt 删试听 ----------------
KT = r'D:\chaomu\android\app\src\main\kotlin\com\xiayitian\chaomu\MainActivity.kt'
s = load(KT)
pairs_kt = [
    (u"import android.media.MediaPlayer\n", u"", 1),
    (u"""/**
 * 只做两件事：试听铃声、跳通知渠道设置页。
 *
 * 为什么试听不用 flutter_local_notifications 的 show()？
 * 因为那条路依赖「通知渠道 + 通知权限 + 渠道声音设置」，任何一环坏了都听不到，
 * 而且渠道建好后声音被系统固化，改 wav 也未必立刻生效。
 * 这里直接用原生 MediaPlayer 播 res/raw 里的 wav，跟通知完全解耦：
 * 只要文件没问题、音量没静音，就一定能听到。
 *
""", u"""/**
 * 跳系统设置页（通知渠道 / 应用信息 / 省电策略）+ 读权限状态。
 * 试听铃声的原生 MediaPlayer 已随内置铃声一起退役
 * （2026-10-16 方案 A：铃声改由系统通知渠道设置决定）。
 *
""", 1),
    (u"    private var player: MediaPlayer? = null\n\n", u"", 1),
    (u"""                    "preview" -> {
                        val name = call.argument<String>("name") ?: ""
                        result.success(playRaw(name))
                    }
                    "stop" -> {
                        stop()
                        result.success(true)
                    }
""", u"", 1),
]
for old, new, cnt in pairs_kt:
    n = s.count(old)
    assert n == cnt, 'kt 命中 %d(期望 %d): %s...' % (n, cnt, old[:50])
    s = s.replace(old, new)
# playRaw 方法整删
a = s.index(u'    /** 播 res/raw/<name>。返回 true = 真的开始播了。 */')
b = s.index(u'    /**\n     * 跳到「朝暮 → 通知 → 待办提醒 vN」这个渠道的设置页。')
s = s[:a] + s[b:]
# stop() 方法与 onDestroy 整删
a = s.index(u'    private fun stop() {')
b = s.index(u'    companion object {')
s = s[:a] + s[b:]
save(KT, s)
print('OK MainActivity.kt')

print('ALL DONE')
