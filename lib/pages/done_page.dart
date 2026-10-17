import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets.dart';
import 'review_page.dart';

class DonePage extends StatelessWidget {
  const DonePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState st = AppState.I;

    return Scaffold(
      appBar: AppBar(title: const Text('已完成', style: TextStyle(fontSize: 16))),
      body: AnimatedBuilder(
        animation: st,
        builder: (BuildContext context, Widget? _) {
          final int total = st.todayTotal();
          final int done = st.todayDone();
          final double ratio = total == 0 ? 0.0 : done / total;

          final List<Todo> all = st.todos
              .where((Todo t) => t.done && t.doneAt != null)
              .toList()
            ..sort((Todo a, Todo b) => b.doneAt!.compareTo(a.doneAt!));

          final List<String> keys = <String>[];
          final Map<String, List<Todo>> map = <String, List<Todo>>{};
          for (final Todo t in all) {
            final String k = dateKey(t.doneAt!);
            if (!map.containsKey(k)) {
              map[k] = <Todo>[];
              keys.add(k);
            }
            map[k]!.add(t);
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: <Widget>[
              // ---- 复盘区块（进入复盘页的主入口）----
              Container(
                color: const Color(0xFFFFFFFF),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      '今日复盘',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          '$done',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF185FA5),
                            height: 1.1,
                          ),
                        ),
                        Text(' / $total',
                            style: const TextStyle(fontSize: 15, color: Color(0xFF8A8A8A))),
                        const Spacer(),
                        Text(
                          '${(ratio * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF185FA5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 8,
                        backgroundColor: const Color(0xFFEDEDED),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF185FA5)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const ReviewPage()),
                        ),
                        child: const Text('进入今日复盘'),
                      ),
                    ),
                  ],
                ),
              ),

              // ---- 已完成清单 ----
              if (keys.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Text(
                    '还没有任何已完成的待办',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Color(0xFF9A9A9A)),
                  ),
                )
              else
                for (final String k in keys)
                  Container(
                    color: const Color(0xFFFFFFFF),
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            '${relativeDayLabel(DateTime.parse(k))} · $k  ·  ${map[k]!.length} 条',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6E6E6E),
                            ),
                          ),
                        ),
                        for (final Todo t in map[k]!) _row(context, st, t),
                      ],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, AppState st, Todo t) {
    return InkWell(
      onTap: () async {
        await st.toggleDone(t);
        if (!context.mounted) return;
        showUndo(context, '已复原：${t.title}', () => st.toggleDone(t));
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: <Widget>[
            const Icon(Icons.check_circle, size: 16, color: Color(0xFF185FA5)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                t.title,
                style: const TextStyle(fontSize: 14, color: Color(0xFF6E6E6E)),
              ),
            ),
            if (t.doneAt != null)
              Text(
                timeLabel(t.doneAt!),
                style: const TextStyle(fontSize: 12, color: Color(0xFFAAAAAA)),
              ),
          ],
        ),
      ),
    );
  }
}
