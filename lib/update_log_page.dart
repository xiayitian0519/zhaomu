import 'package:flutter/material.dart';

import 'notifier.dart';
import 'update_model.dart';
import 'updates_gen.dart';

/// 设置 → 关于朝暮 → 更新日志：按版本倒序，一版一张卡。
/// 当前版本那张会带一个「本版」小标签，方便一眼找到刚更新的内容。
class UpdateLogPage extends StatelessWidget {
  const UpdateLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('更新日志', style: TextStyle(fontSize: 16))),
      body: FutureBuilder<String>(
        future: Notifier.I.appVersion(),
        builder: (BuildContext context, AsyncSnapshot<String> snap) {
          // 只取主.次.补丁，构建号每次打包都变，拿来比会对不上
          final String cur = (snap.data ?? '').split('+').first.trim();

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: <Widget>[
              for (final AppUpdate u in kUpdatesGenerated)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: u.version == cur
                          ? const Color(0xFF9CC0E8)
                          : const Color(0xFFDFE2E8),
                    ),
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
                          if (u.version == cur)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF0FF),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '本版',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF185FA5),
                                ),
                              ),
                            ),
                          const Spacer(),
                          Text(
                            u.date,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9A9A9A),
                            ),
                          ),
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
                  '2.13.0 之前的版本没有记录',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Color(0xFFAAAAAA)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
