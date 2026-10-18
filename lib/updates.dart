/// 朝暮的更新内容（内置数据）。
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
  AppUpdate('2.17.0', '2026-10-18', <String>[
    'Windows 桌面版能装了，窗口按手机比例打开，界面跟手机一模一样',
    'Windows 提醒：关窗口收进托盘继续跑，到点弹系统通知',
    '关机期间错过的提醒，下次开机会汇总成一条提醒你',
  ]),
  AppUpdate('2.16.0', '2026-10-17', <String>[
    '日历默认态改传统排版：格子等大、待办每条一行、容量满显示省略号',
    '展开态大格恢复格子间隙',
  ]),
  AppUpdate('2.15.3', '2026-10-17', <String>[
    '日历恢复到之前的版本（今天的日历新排版尝试已撤回）',
  ]),
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
