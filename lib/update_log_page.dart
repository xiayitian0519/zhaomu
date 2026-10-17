import 'package:flutter/material.dart';

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
