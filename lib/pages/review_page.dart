import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'review_history_page.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final TextEditingController _note = TextEditingController();
  Timer? _debounce;

  /// 最近一次真正落盘的内容，用于判断「有没有未保存的改动」
  String _saved = '';
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _saved = AppState.I.reviewNoteOf(DateTime.now());
    _note.text = _saved;
    _note.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _note.removeListener(_onChanged);
    // 兜底：离开页面时如果还有改动没落盘，补一次
    if (_note.text != _saved) {
      AppState.I.setReviewNote(DateTime.now(), _note.text);
    }
    _note.dispose();
    super.dispose();
  }

  void _onChanged() {
    final bool dirty = _note.text != _saved;
    if (dirty != _dirty) {
      setState(() => _dirty = dirty);
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _commit);
  }

  Future<void> _commit() async {
    final String text = _note.text;
    await AppState.I.setReviewNote(DateTime.now(), text);
    _saved = text;
    if (mounted && _dirty) setState(() => _dirty = false);
  }

  Future<void> _saveNow() async {
    _debounce?.cancel();
    await _commit();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('总结已保存'), duration: Duration(seconds: 2)),
      );
  }

  Widget _card(List<Widget> children) => Container(
        color: const Color(0xFFFFFFFF),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _cardTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF2B2B2B)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final AppState st = AppState.I;

    return Scaffold(
      appBar: AppBar(
        title: const Text('今日复盘', style: TextStyle(fontSize: 16)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ReviewHistoryPage()),
            ),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF185FA5),
              textStyle: const TextStyle(fontSize: 13),
            ),
            child: const Text('历史总结'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: AnimatedBuilder(
        animation: st,
        builder: (BuildContext context, Widget? _) {
          final int total = st.todayTotal();
          final int done = st.todayDone();
          final double ratio = total == 0 ? 0.0 : done / total;
          final List<Todo> finished = st.doneToday();
          final List<Todo> missed = st.yesterdayUndone();

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: <Widget>[
              _card(<Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      '$done',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF185FA5),
                        height: 1.1,
                      ),
                    ),
                    Text(
                      ' / $total',
                      style: const TextStyle(fontSize: 16, color: Color(0xFF8A8A8A)),
                    ),
                    const Spacer(),
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
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${dayLabel(DateTime.now())} · ${headerDate(DateTime.now())}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFEDEDED),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF185FA5)),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  total == 0
                      ? '今天还没有登记待办'
                      : (done == total ? '今天全部做完了' : '还剩 ${total - done} 条没做'),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)),
                ),
              ]),
              _card(<Widget>[
                _cardTitle('今日完成（${finished.length}）'),
                if (finished.isEmpty)
                  const Text('今天还没勾掉任何一条', style: TextStyle(fontSize: 13, color: Color(0xFF9A9A9A)))
                else
                  for (final Todo t in finished)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.check_circle, size: 16, color: Color(0xFF185FA5)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(t.title, style: const TextStyle(fontSize: 14)),
                          ),
                          if (t.doneAt != null)
                            Text(
                              timeLabel(t.doneAt!),
                              style: const TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)),
                            ),
                        ],
                      ),
                    ),
              ]),
              _card(<Widget>[
                _cardTitle('昨天没做完（${missed.length}）'),
                if (missed.isEmpty)
                  const Text('昨天没有遗留', style: TextStyle(fontSize: 13, color: Color(0xFF9A9A9A)))
                else
                  for (final Todo t in missed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.error_outline, size: 16, color: Color(0xFFA32D2D)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(t.title, style: const TextStyle(fontSize: 14)),
                          ),
                          Text(
                            Priority.nameOf(t.priority),
                            style: TextStyle(fontSize: 11, color: st.colorOf(t.priority)),
                          ),
                        ],
                      ),
                    ),
              ]),
              _card(<Widget>[
                Row(
                  children: <Widget>[
                    _cardTitle('今天想说点什么'),
                    const Spacer(),
                    if (_dirty)
                      const Text(
                        '未保存…',
                        style: TextStyle(fontSize: 11, color: Color(0xFF854F0B)),
                      )
                    else if (_saved.isNotEmpty)
                      const Text(
                        '已保存',
                        style: TextStyle(fontSize: 11, color: Color(0xFF3F7D42)),
                      ),
                  ],
                ),
                TextField(
                  controller: _note,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    hintText: '随便写，可以留空',
                    hintStyle: TextStyle(fontSize: 13, color: Color(0xFFAAAAAA)),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saveNow,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF185FA5),
                          side: const BorderSide(color: Color(0xFF185FA5)),
                          minimumSize: const Size.fromHeight(42),
                        ),
                        child: const Text('保存总结'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const ReviewHistoryPage()),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF5F5E5A),
                          side: const BorderSide(color: Color(0xFFBFBFBF)),
                          minimumSize: const Size.fromHeight(42),
                        ),
                        child: const Text('查看历史总结'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '边打边自动保存，也可以手动点「保存总结」。',
                  style: TextStyle(fontSize: 11, color: Color(0xFF9A9A9A)),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }
}
