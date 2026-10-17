# -*- coding: utf-8 -*-
"""更新弹窗 + 关于朝暮 + 更新日志页"""
import io

def load(p): return io.open(p, 'r', encoding='utf-8').read()
def save(p, s): io.open(p, 'w', encoding='utf-8', newline='').write(s)
def apply(path, pairs):
    s = load(path)
    for old, new, cnt in pairs:
        n = s.count(old)
        assert n == cnt, '%s 命中 %d(期望 %d): %s...' % (path, n, cnt, old[:60])
        s = s.replace(old, new)
    save(path, s)
    print('OK %s' % path.split('\\')[-1])

# ---------------- 1. 新建 lib/updates.dart ----------------
UPD = r'D:\chaomu\lib\updates.dart'
save(UPD, u'''/// 朝暮的更新内容（内置数据）。
///
/// 弹窗（版本变了首启弹一次）和「设置 → 关于朝暮 → 更新日志」共用这一份。
/// **每次发版在这里加一条新的 AppUpdate（放最上面）**，条目一行一条人话，最多 5 条。
/// 2026-10-17 起收录，更早的版本不列（用户定的）。
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'notifier.dart';

/// 一个版本的更新内容
class AppUpdate {
  const AppUpdate(this.version, this.date, this.items);

  final String version; // 不带构建号，如 '2.13.0'
  final String date; // '2026-10-17'
  final List<String> items; // 更新条目，一行一条
}

const List<AppUpdate> kUpdates = <AppUpdate>[
  AppUpdate('2.13.0', '2026-10-17', <String>[
    '新增「关于朝暮」：更新日志集中看每次改了什么',
    '版本更新后首次打开自动弹一次更新内容',
  ]),
  AppUpdate('2.12.1', '2026-10-17', <String>[
    '长按打优先级的界面再精简：只剩四个词和色块',
  ]),
  AppUpdate('2.12.0', '2026-10-17', <String>[
    '待办列表按优先级整行标色，更醒目',
    '四象限颜色新增 9 色鲜艳色板',
    '长按打优先级的界面更简洁',
  ]),
];

/// 版本号变了 → 首次打开弹一次更新内容。点「知道了」记进存档，不再弹。
Future<void> maybeShowUpdateDialog(BuildContext context) async {
  final AppState st = AppState.I;
  final String v = await Notifier.I.appVersion();
  if (v.isEmpty) return;
  if (st.lastSeenVersion == v) return;

  final bool hasEntry = kUpdates.any((AppUpdate u) => v.startsWith(u.version));
  if (!hasEntry) {
    // 没有这个版本的介绍数据（比如从很老的版本直接跳上来）：只记版本号不弹
    await st.setLastSeenVersion(v);
    return;
  }
  if (!context.mounted) return;

  final AppUpdate cur = kUpdates.first;
  final String name = v.split('+').first;
  await showDialog<void>(
    context: context,
    builder: (BuildContext c) => AlertDialog(
      title: Text('朝暮 $name 更新内容', style: const TextStyle(fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(cur.date, style: const TextStyle(fontSize: 11, color: Color(0xFF9A9A9A))),
          const SizedBox(height: 8),
          for (final String it in cur.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('· $it', style: const TextStyle(fontSize: 13, height: 1.5)),
            ),
        ],
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(c).pop(),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF185FA5)),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
  await st.setLastSeenVersion(v);
}
''')
print('OK updates.dart (新建)')

# ---------------- 2. 新建 lib/update_log_page.dart ----------------
LOG = r'D:\chaomu\lib\update_log_page.dart'
save(LOG, u'''import 'package:flutter/material.dart';

import 'updates.dart';

/// 设置 → 关于朝暮 → 更新日志：按版本倒序，一版一张卡
class UpdateLogPage extends StatelessWidget {
  const UpdateLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('更新日志', style: TextStyle(fontSize: 16))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: <Widget>[
          for (final AppUpdate u in kUpdates)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFDFE2E8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        'v${u.version}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF185FA5),
                        ),
                      ),
                      const Spacer(),
                      Text(u.date, style: const TextStyle(fontSize: 11, color: Color(0xFF9A9A9A))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (int i = 0; i < u.items.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '${i + 1}. ${u.items[i]}',
                        style: const TextStyle(fontSize: 12.5, height: 1.6),
                      ),
                    ),
                ],
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              '2.12.0 之前的版本没有记录',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Color(0xFFAAAAAA)),
            ),
          ),
        ],
      ),
    );
  }
}
''')
print('OK update_log_page.dart (新建)')

# ---------------- 3. app_state.dart lastSeenVersion ----------------
A = r'D:\chaomu\lib\app_state.dart'
apply(A, [
    (u"""  /// 日历页：下面的「当日待办」列表有没有折叠起来。""",
     u"""  /// 上次见过更新弹窗的完整版本号（如 '2.13.0+15'）。
  /// 和当前版本不一致 → 首次打开弹一次更新内容（见 updates.dart）。
  String lastSeenVersion = '';

  /// 日历页：下面的「当日待办」列表有没有折叠起来。""", 1),
    (u"""    if (m['calendarListCollapsed'] is bool) {
      calendarListCollapsed = m['calendarListCollapsed'] as bool;
    }""",
     u"""    if (m['calendarListCollapsed'] is bool) {
      calendarListCollapsed = m['calendarListCollapsed'] as bool;
    }
    if (m['lastSeenVersion'] is String) {
      lastSeenVersion = m['lastSeenVersion'] as String;
    }""", 1),
    (u"""        'calendarListCollapsed': calendarListCollapsed,""",
     u"""        'calendarListCollapsed': calendarListCollapsed,
        'lastSeenVersion': lastSeenVersion,""", 1),
    (u"""  /// 日历页「当日待办」列表折叠 / 展开
  Future<void> setCalendarListCollapsed(bool v) async {""",
     u"""  /// 记下「这个版本的更新弹窗已经看过了」
  Future<void> setLastSeenVersion(String v) async {
    lastSeenVersion = v;
    await save();
  }

  /// 日历页「当日待办」列表折叠 / 展开
  Future<void> setCalendarListCollapsed(bool v) async {""", 1),
])

# ---------------- 4. home_page.dart 首启弹更新 ----------------
H = r'D:\chaomu\lib\pages\home_page.dart'
s = load(H)
pairs_h = [
    (u"""class _HomePageState extends State<HomePage> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {""",
     u"""class _HomePageState extends State<HomePage> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 版本号变了 → 首次打开弹一次更新内容（见 updates.dart）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      maybeShowUpdateDialog(context);
    });
  }

  @override
  void dispose() {""", 1),
]
# import 追加
if "import '../updates.dart';" not in s:
    s = s.replace(u"import '../widgets.dart';", u"import '../updates.dart';\nimport '../widgets.dart';", 1)
for old, new, cnt in pairs_h:
    n = s.count(old)
    assert n == cnt, 'home 命中 %d(期望 %d)' % (n, cnt)
    s = s.replace(old, new)
save(H, s)
print('OK home_page.dart')

# ---------------- 5. settings_page.dart 关于朝暮区块 ----------------
S = r'D:\chaomu\lib\pages\settings_page.dart'
apply(S, [
    (u"""              const _VersionLabel(),""",
     u"""              _sectionTitle('关于朝暮'),
              _card(<Widget>[
                ListTile(
                  title: const Text('检查更新', style: TextStyle(fontSize: 14)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('功能开发中，敬请期待'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                ListTile(
                  title: const Text('更新日志', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    '看每次更新了什么',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const UpdateLogPage()),
                  ),
                ),
              ]),
              const _VersionLabel(),""", 1),
])
s = load(S)
if "import '../update_log_page.dart';" not in s:
    s = s.replace(u"import '../widgets.dart';", u"import '../update_log_page.dart';\nimport '../widgets.dart';", 1)
    save(S, s)
    print('OK settings_page.dart import')
print('ALL DONE')
