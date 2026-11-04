import 'package:flutter/material.dart';

import '../ai_tdl.dart';
import '../app_state.dart';
import '../models.dart';

/// 导入 TDL —— 粘一段文字，AI 拆成待办，预览后确认。
///
/// 流程：粘贴 → 点「AI 整理」→ 出预览（可勾选、可改标题和日期）→ 点「导入」。
class ImportTdlPage extends StatefulWidget {
  const ImportTdlPage({super.key});

  @override
  State<ImportTdlPage> createState() => _ImportTdlPageState();
}

class _ImportTdlPageState extends State<ImportTdlPage> {
  static const Color _blue = Color(0xFF185FA5);
  static const Color _grey = Color(0xFF8A91A0);
  static const Color _line = Color(0xFFE6E9EF);

  final TextEditingController _input = TextEditingController();

  bool _busy = false;
  String? _error;
  List<AiTodo> _result = <AiTodo>[];

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  AppState get st => AppState.I;

  String get _key => st.aiKey.trim().isNotEmpty ? st.aiKey.trim() : kBuiltinKey;

  int get _left => kDailyLimit - st.aiUsedToday;

  Future<void> _runAi() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final AiParseResult r = await AiTdl.parse(
        text: _input.text,
        apiKey: _key,
        usedToday: st.aiUsedToday,
      );
      await st.bumpAiCount();
      if (!mounted) return;
      setState(() {
        _result = r.todos;
        _busy = false;
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '出错了：$e';
        _busy = false;
      });
    }
  }

  Future<void> _import() async {
    final List<AiTodo> picked =
        _result.where((AiTodo t) => t.picked).toList();
    if (picked.isEmpty) {
      setState(() => _error = '一条都没勾，勾几条再导入。');
      return;
    }
    for (final AiTodo a in picked) {
      final String title = a.editableTitle.trim().isEmpty
          ? a.title
          : a.editableTitle.trim();
      final Todo t = await st.add(
        title,
        due: a.due,
        priority: AiTdl.priorityOf(a.priority),
      );
      final String rep = AiTdl.repeatOf(a.repeat);
      if (rep != RepeatRule.none) {
        t.repeat = rep;
        await st.update(t);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(picked.length);
  }

  @override
  Widget build(BuildContext ctx) {
    final int pickedCount = _result.where((AiTodo t) => t.picked).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('导入 TDL', style: TextStyle(fontSize: 16)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _KeyPage()),
            ),
            style: TextButton.styleFrom(foregroundColor: _blue),
            child: Text(_key.isEmpty ? '填 Key' : '换 Key'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          const Text(
            '把 TDL、会议记录、聊天里的一段话粘进来，AI 会拆成一条条待办。',
            style: TextStyle(fontSize: 12.5, color: _grey, height: 1.6),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _line),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              controller: _input,
              maxLines: 10,
              minLines: 6,
              style: const TextStyle(fontSize: 14, height: 1.6),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '例：\n1. 明天下午三点跟 Zoya 对课程表\n2. 周五前把 demo 录完\n3. 每天早上背单词 30 分钟',
                hintStyle: TextStyle(fontSize: 13, color: Color(0xFFB4BAC6)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _runAi,
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    minimumSize: const Size(0, 44),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('AI 整理'),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _key.isEmpty ? '还没填 Key' : '今天还剩 $_left 次',
                style: TextStyle(
                  fontSize: 12,
                  color: _key.isEmpty ? const Color(0xFFC0392B) : _grey,
                ),
              ),
            ],
          ),

          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFDF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF3D3D3)),
              ),
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF8A2A2A)),
              ),
            ),
          ],

          if (_result.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Text(
                  '拆出 ${_result.length} 条，已选 $pickedCount 条',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    final bool all = pickedCount < _result.length;
                    setState(() {
                      for (final AiTodo t in _result) {
                        t.picked = all;
                      }
                    });
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: _blue,
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 12.5),
                  ),
                  child: Text(pickedCount < _result.length ? '全选' : '全不选'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (int i = 0; i < _result.length; i++) _row(i, _result[i]),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: pickedCount == 0 ? null : _import,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2C9A56),
                minimumSize: const Size(0, 46),
              ),
              child: Text('导入 $pickedCount 条待办'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(int i, AiTodo a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Checkbox(
                value: a.picked,
                onChanged: (bool? v) => setState(() => a.picked = v ?? false),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 10),
                  child: TextFormField(
                    initialValue: a.editableTitle,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 14, height: 1.45),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (String v) => a.editableTitle = v,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(44, 0, 10, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                _tag(
                  a.due == null ? '不限日期' : _dateText(a.due!),
                  a.due == null ? const Color(0xFFB4BAC6) : _blue,
                  () => _pickDate(i, a),
                ),
                _tag(AiTdl.priorityLabel(a.priority), const Color(0xFF8A6D1E),
                    () => setState(() => a.priority = _nextPriority(a.priority))),
                if (a.repeat != 'none')
                  _tag(_repeatText(a.repeat), const Color(0xFF2C9A56), () {
                    setState(() => a.repeat = _nextRepeat(a.repeat));
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: TextStyle(fontSize: 11.5, color: color)),
      ),
    );
  }

  static String _dateText(DateTime d) {
    final DateTime now = DateTime.now();
    final DateTime day = DateTime(d.year, d.month, d.day);
    final DateTime today = DateTime(now.year, now.month, now.day);
    final int diff = day.difference(today).inDays;
    final String hm = d.hour == 0 && d.minute == 0
        ? ''
        : ' ${d.hour.toString().padLeft(2, '0')}:'
            '${d.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return '今天$hm';
    if (diff == 1) return '明天$hm';
    if (diff == 2) return '后天$hm';
    if (diff == -1) return '昨天$hm';
    return '${d.month}月${d.day}日$hm';
  }

  static String _repeatText(String r) => const <String, String>{
        '每天': '每天',
        '每周': '每周',
        '每月': '每月',
        '每年': '每年',
      }[r] ??
      '';

  static String _nextPriority(String p) {
    const List<String> order = <String>['gray', 'yellow', 'blue', 'red'];
    final int i = order.indexOf(p);
    return order[(i + 1) % order.length];
  }

  static String _nextRepeat(String r) {
    const List<String> order = <String>['none', '每天', '每周', '每月', '每年'];
    final int i = order.indexOf(r);
    return order[(i + 1) % order.length];
  }

  Future<void> _pickDate(int i, AiTodo a) async {
    final DateTime now = DateTime.now();
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: a.due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: '选截止日期（取消 = 不限）',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (!mounted) return;
    setState(() {
      a.due = d;
    });
  }
}

/// 填 AI Key 的小页（导入页右上角进去）。
class _KeyPage extends StatefulWidget {
  const _KeyPage();

  @override
  State<_KeyPage> createState() => _KeyPageState();
}

class _KeyPageState extends State<_KeyPage> {
  late final TextEditingController _c =
      TextEditingController(text: AppState.I.aiKey);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Key', style: TextStyle(fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          const Text(
            '去 open.bigmodel.cn 注册一个账号，控制台里能生成 API Key（形如 xxxxx.yyyyy）。',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF8A91A0), height: 1.7),
          ),
          const SizedBox(height: 6),
          const Text(
            '不填也能用，用我内置的额度（每天 50 次）。填了自己的就优先用你的，不限次数。',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF8A91A0), height: 1.7),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _c,
            maxLines: 3,
            style: const TextStyle(fontSize: 13.5),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '粘 Key 到这里',
              hintStyle: TextStyle(fontSize: 13, color: Color(0xFFB4BAC6)),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              await AppState.I.setAiKey(_c.text);
              if (!context.mounted) return;
              Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF185FA5),
              minimumSize: const Size(0, 46),
            ),
            child: const Text('保存'),
          ),
          if (AppState.I.aiKey.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            TextButton(
              onPressed: () async {
                await AppState.I.setAiKey('');
                if (!context.mounted) return;
                setState(() => _c.text = '');
              },
              child: const Text(
                '清空，改回用内置额度',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF8A91A0)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
