import 'package:flutter/material.dart';

import 'app_state.dart';
import 'notifier.dart';
import 'update_log_page.dart';
import 'update_model.dart';
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
