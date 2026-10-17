import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';

/// 历史总结：把所有写过的复盘总结按月份列出来，能点开看 / 改
class ReviewHistoryPage extends StatefulWidget {
  const ReviewHistoryPage({super.key});

  @override
  State<ReviewHistoryPage> createState() => _ReviewHistoryPageState();
}

class _ReviewHistoryPageState extends State<ReviewHistoryPage> {
  final Set<String> _folded = <String>{}; // 收起来的月份，'YYYY-MM'

  static String _monthKey(DateTime d) => '${d.year}-${d.month < 10 ? '0' : ''}${d.month}';

  static String _monthLabel(DateTime d) => '${d.year}年${d.month}月';

  @override
  Widget build(BuildContext context) {
    final AppState st = AppState.I;

    return Scaffold(
      appBar: AppBar(title: const Text('历史总结', style: TextStyle(fontSize: 16))),
      body: AnimatedBuilder(
        animation: st,
        builder: (BuildContext context, Widget? _) {
          final List<MapEntry<DateTime, String>> notes = st.allReviewNotes();

          if (notes.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  '还没有写过复盘总结\n到「今日复盘」下面写一段，这里就会出现',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF9A9A9A), height: 1.8),
                ),
              ),
            );
          }

          // 按月份分组，月份倒序
          final Map<String, List<MapEntry<DateTime, String>>> byMonth =
              <String, List<MapEntry<DateTime, String>>>{};
          for (final MapEntry<DateTime, String> e in notes) {
            byMonth.putIfAbsent(_monthKey(e.key), () => <MapEntry<DateTime, String>>[]).add(e);
          }
          final List<String> keys = byMonth.keys.toList()
            ..sort((String a, String b) => b.compareTo(a));

          final List<Widget> children = <Widget>[];
          for (final String k in keys) {
            final List<MapEntry<DateTime, String>> items = byMonth[k]!;
            final bool folded = _folded.contains(k);
            children.add(
              InkWell(
                onTap: () => setState(() {
                  if (folded) {
                    _folded.remove(k);
                  } else {
                    _folded.add(k);
                  }
                }),
                child: Container(
                  color: const Color(0xFFF0F1F3),
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Row(
                    children: <Widget>[
                      Text(
                        _monthLabel(items.first.key),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2B2B2B),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${items.length} 篇',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)),
                      ),
                      const Spacer(),
                      Icon(
                        folded ? Icons.expand_more : Icons.expand_less,
                        size: 20,
                        color: const Color(0xFF9A9A9A),
                      ),
                    ],
                  ),
                ),
              ),
            );
            if (folded) continue;

            for (final MapEntry<DateTime, String> e in items) {
              children.add(_noteCard(st, e.key, e.value));
            }
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: children,
          );
        },
      ),
    );
  }

  Widget _noteCard(AppState st, DateTime day, String text) {
    final DayStat s = st.statOnDay(day);
    return InkWell(
      onTap: () => _edit(day, text),
      child: Container(
        color: const Color(0xFFFFFFFF),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  shortDayLabel(day),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF185FA5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '星期${'一二三四五六日'[day.weekday - 1]}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9A9A9A)),
                ),
                const Spacer(),
                Text(
                  '${s.done}/${s.total} 条完成',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9A9A9A)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, height: 1.65, color: Color(0xFF2B2B2B)),
            ),
            const SizedBox(height: 6),
            const Text(
              '点一下可以修改',
              style: TextStyle(fontSize: 11, color: Color(0xFFBFBFBF)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(DateTime day, String current) async {
    final TextEditingController ctl = TextEditingController(text: current);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text('${dayLabel(day)} 的总结', style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: ctl,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            style: const TextStyle(fontSize: 14, height: 1.6),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ctl.text = '';
              Navigator.of(c).pop(true);
            },
            child: const Text('清空', style: TextStyle(color: Color(0xFFA32D2D))),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final String v = ctl.text;
    ctl.dispose();
    if (ok != true) return;
    await AppState.I.setReviewNote(day, v);
  }
}
