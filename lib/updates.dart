import 'package:flutter/material.dart';

import 'app_state.dart';
import 'notifier.dart';
import 'update_log_page.dart';
import 'update_model.dart';
import 'update_flow.dart';
import 'update_notes.dart';
import 'updater.dart';
import 'updates_gen.dart';

/// 更新内容（内置数据）。
///
/// ⚠️ **不要在这里手写条目**。数据来自 `lib/updates_gen.dart`，由
/// `tool/gen_updates.py` 从 `CHANGELOG.md` 的「### 更新摘要」段自动生成。
///
/// 以前这里是手写的，CHANGELOG 改了忘了改这里 → 找不到条目 → 静默跳过不弹。
/// 2.19.0 和 2.21.0 各栽过一次（2026-10-26 改成自动生成）。
const List<AppUpdate> kUpdates = kUpdatesGenerated;

/// 弹出「这一版改了什么」。规则（2026-10-26 用户拍板）：
///
/// 1. 版本号变了 → 首次启动弹一次；同一版不再弹
/// 2. **必须点「知道了」或「查看全部」才记账** —— 点外面、按 Esc 关掉，下次启动还会弹
/// 3. 找不到这一版的条目时**也要弹**，弹一个简版兜底，绝不静默跳过
Future<void> maybeShowUpdateDialog(BuildContext context) async {
  final AppState st = AppState.I;
  final String raw = await Notifier.I.appVersion();
  if (raw.isEmpty) return;

  // 只比「主.次.补丁」。构建号每次打包都变，拿它比会导致重装同版本又弹一遍。
  final String v = _main(raw);
  if (v.isEmpty) return;
  // 老存档存的是带构建号的（2.20.1+40），_main 之后一起兼容
  if (_main(st.lastSeenVersion) == v) return;

  AppUpdate? cur;
  for (final AppUpdate u in kUpdates) {
    if (u.version == v) {
      cur = u;
      break;
    }
  }

  if (!context.mounted) return;
  final String? action = await showDialog<String>(
    context: context,
    // 点外面不算看过 —— 否则手一滑关掉就再也不弹
    barrierDismissible: false,
    builder: (BuildContext c) => _UpdateDialog(update: cur, version: v),
  );

  // 被系统强制收起（切后台 / 杀进程）时不记账，下次还弹
  if (action == null) return;
  await st.setLastSeenVersion(v);

  if (action == 'all' && context.mounted) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const UpdateLogPage()),
    );
  }
}

String _main(String v) => v.split('+').first.trim();

/// 进首页后静默问一次远端：有没有比现在新的版本。
///
/// 2026-11-05 用户要求：当天首次进 App 就自动查，有新版就弹出来，
/// 写清楚「更新日期 / 版本号 / 这中间每一版改了什么（人话）」。
/// 一天只弹一次，同一天再进来不打扰。
Future<void> maybeCheckRemoteUpdate(BuildContext context) async {
  final AppState st = AppState.I;
  final String raw = await Notifier.I.appVersion();
  final String cur = _main(raw);
  if (cur.isEmpty) return;

  final UpdateInfo? info = await Updater.check(current: cur);
  if (info == null) return;
  if (!Updater.isNewer(cur, info.latest)) return;

  // 2026-11-05 用户明确要求「每次进软件都要检查」——
  // 所以不再按天限制提醒频率，只要远端比当前版本新就弹。
  if (!context.mounted) return;

  final List<AppUpdate> between = updatesBetween(cur, info.latest);
  final String? action = await showDialog<String>(
    context: context,
    builder: (BuildContext c) => _NewVersionDialog(
      current: cur,
      latest: info.latest,
      between: between,
      fallback: info.notes,
    ),
  );
  if (action == 'go' && context.mounted) {
    // 走 App 内下载（能增量就只下补丁），不要跳浏览器下完整包
    await runUpdateFlow(context, info, cur);
  }
}

/// 「发现新版本」：把从当前版本到最新版本之间的每一版都列出来。
///
/// 跨了好几个版本时，只看最新一版是不够的 —— 用户想知道中间都改了什么。
class _NewVersionDialog extends StatelessWidget {
  const _NewVersionDialog({
    required this.current,
    required this.latest,
    required this.between,
    required this.fallback,
  });

  final String current;
  final String latest;
  final List<AppUpdate> between;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final String date = between.isNotEmpty ? between.first.date : '';
    final int n = between.length;

    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Text('发现新版本', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF0FF),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              latest,
              style: const TextStyle(fontSize: 12, color: Color(0xFF185FA5)),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (date.isNotEmpty)
                Text(
                  '${shortDate(date)} 发布',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9A9A9A)),
                ),
              const SizedBox(height: 4),
              Text(
                n > 1
                    ? '你现在是 $current，中间跨了 $n 个版本'
                    : '你现在是 $current',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A8290)),
              ),
              const SizedBox(height: 12),
              if (between.isEmpty)
                Text(
                  fallback.isEmpty ? '这一版没写详细说明。' : fallback,
                  style: const TextStyle(fontSize: 13, height: 1.6),
                )
              else
                for (int i = 0; i < between.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        between[i].version,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF185FA5),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        shortDate(between[i].date),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9A9A9A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  for (final String it in userFacing(between[i].items))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            '·  ',
                            style: TextStyle(fontSize: 13, height: 1.55),
                          ),
                          Expanded(
                            child: Text(
                              it,
                              style: const TextStyle(fontSize: 13, height: 1.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop('later'),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF8A91A0)),
          child: const Text('稍后再说'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop('go'),
          style:
              FilledButton.styleFrom(backgroundColor: const Color(0xFF185FA5)),
          child: const Text('去更新'),
        ),
      ],
    );
  }
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.update, required this.version});

  final AppUpdate? update;
  final String version;

  @override
  Widget build(BuildContext context) {
    final AppUpdate? u = update;

    return PopScope(
      // 拦掉 Esc / 返回键：只有点按钮才算看过
      canPop: false,
      child: AlertDialog(
        title: Text(
          u == null ? '朝暮已更新到 $version' : '朝暮 $version 更新内容',
          style: const TextStyle(fontSize: 16),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380, maxHeight: 380),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (u != null)
                  Text(
                    u.date,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9A9A9A)),
                  ),
                const SizedBox(height: 8),
                if (u == null) ...<Widget>[
                  const Text(
                    '这一版没写详细说明。',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '去「设置 → 关于朝暮 → 更新日志」能看全部改动记录。',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                ] else
                  for (final String it in u.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '· $it',
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop('all'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF185FA5),
            ),
            child: const Text('查看全部'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('ok'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF185FA5),
            ),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
