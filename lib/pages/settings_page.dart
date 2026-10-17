import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../guide.dart';
import '../models.dart';
import '../notifier.dart';
import '../permissions.dart';
import '../store.dart';
import '../update_log_page.dart';
import '../widgets.dart';
import 'review_history_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  /// 鲜艳色板（2026-10-17 用户要求加一组更鲜艳的，原 12 色保留）
  static const List<int> _paletteVivid = <int>[
    0xFFFF3B30,
    0xFFFF6B00,
    0xFFFFC300,
    0xFF2ECC40,
    0xFF00C8A0,
    0xFF00A8E8,
    0xFF3D5AFE,
    0xFF9C27B0,
    0xFFF5008D,
  ];

  static const List<int> _palette = <int>[
    0xFFA32D2D,
    0xFFD24B3E,
    0xFFE08A2E,
    0xFF854F0B,
    0xFFB8860B,
    0xFF3F7D42,
    0xFF185FA5,
    0xFF2C6FB5,
    0xFF5B4B8A,
    0xFF7D5BA6,
    0xFF5F5E5A,
    0xFF2B2B2B,
  ];

  static String _hhmm(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  Widget _card(List<Widget> children) => Container(
        color: const Color(0xFFFFFFFF),
        margin: const EdgeInsets.only(bottom: 8),
        child: Column(children: children),
      );

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF8A8A8A)),
        ),
      );

  Future<void> _pickDayStart(BuildContext context) async {
    final AppState st = AppState.I;
    final TimeOfDay? t = await pickTime(
      context,
      initial: TimeOfDay(hour: st.dayStartHour, minute: st.dayStartMinute),
      helpText: '几点之后算明天',
    );
    if (t == null) return;
    await st.setDayStart(t.hour, t.minute);
  }

  /// 一排色圆（点哪个选哪个）
  List<Widget> _swatches(BuildContext c, List<int> colors, int current) {
    return colors
        .map(
          (int v) => GestureDetector(
            onTap: () => Navigator.of(c).pop(v),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Color(v),
                shape: BoxShape.circle,
                border: Border.all(
                  color: v == current ? const Color(0xFF2B2B2B) : const Color(0x22000000),
                  width: v == current ? 3 : 1,
                ),
              ),
            ),
          ),
        )
        .toList();
  }

  Future<void> _pickQuadrantColor(BuildContext context, int index) async {
    final AppState st = AppState.I;
    final int current = st.quadrantColorValues[index];
    final int? picked = await showDialog<int>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text('${Priority.names[index]} 的颜色', style: const TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('鲜艳', style: TextStyle(fontSize: 12, color: Color(0xFF9A9A9A))),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 12, children: _swatches(c, _paletteVivid, current)),
              const SizedBox(height: 14),
              const Text('原有', style: TextStyle(fontSize: 12, color: Color(0xFF9A9A9A))),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 12, children: _swatches(c, _palette, current)),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('取消')),
        ],
      ),
    );
    if (picked == null) return;
    await st.setQuadrantColor(index, picked);
  }

  // ---------------- 导出 ----------------

  static String _stampName() {
    final DateTime n = DateTime.now();
    String two(int v) => v < 10 ? '0$v' : '$v';
    return '${n.year}${two(n.month)}${two(n.day)}';
  }

  /// 导出分两份文件：复盘总结 / 历史待办。写完直接弹系统分享面板。
  Future<void> _export(BuildContext context) async {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '导出哪一份？',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note, color: Color(0xFF185FA5)),
              title: const Text('复盘总结', style: TextStyle(fontSize: 14)),
              subtitle: const Text('每天的总结文字 + 当天完成情况，适合发给知识库', style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.of(c).pop('review'),
            ),
            ListTile(
              leading: const Icon(Icons.checklist, color: Color(0xFF3F7D42)),
              title: const Text('历史待办', style: TextStyle(fontSize: 14)),
              subtitle: const Text('已完成 + 未完成的全部待办明细', style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.of(c).pop('history'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.ios_share, color: Color(0xFF5F5E5A)),
              title: const Text('两份一起导出', style: TextStyle(fontSize: 14)),
              subtitle: const Text('生成两个文件，一起分享', style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.of(c).pop('both'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    final AppState st = AppState.I;
    final String stamp = _stampName();
    final List<String> paths = <String>[];
    final List<String> errs = <String>[];

    Future<void> writeOne(String name, Map<String, dynamic> data) async {
      try {
        final String p = await Store.writeExport('$name.json', const JsonEncoder.withIndent('  ').convert(data));
        paths.add(p);
      } catch (e) {
        errs.add('$name：$e');
      }
    }

    if (choice == 'review' || choice == 'both') {
      await writeOne('朝暮-复盘总结-$stamp', st.reviewExportData());
    }
    if (choice == 'history' || choice == 'both') {
      await writeOne('朝暮-历史待办-$stamp', st.historyExportData());
    }

    if (!context.mounted) return;

    if (paths.isEmpty) {
      showDialog<void>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
          title: const Text('导出失败', style: TextStyle(fontSize: 16)),
          content: Text('写入文件出错了：\n${errs.join('\n')}', style: const TextStyle(fontSize: 13, height: 1.6)),
          actions: <Widget>[
            FilledButton(onPressed: () => Navigator.of(c).pop(), child: const Text('知道了')),
          ],
        ),
      );
      return;
    }

    // 调起系统分享面板；分享失败（模拟器 / 无可用应用）就退回「看路径」弹窗
    bool shared = false;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: paths.map((String p) => XFile(p)).toList(),
          subject: '朝暮数据备份',
        ),
      );
      shared = true;
    } catch (_) {
      shared = false;
    }

    if (!context.mounted) return;
    if (!shared) {
      _showPaths(context, paths);
    }
  }

  void _showPaths(BuildContext context, List<String> paths) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('已生成文件', style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Text(
            '文件已写好，可以在文件管理器里找到：\n\n${paths.join('\n\n')}\n\n'
            '也可以点下面「复制内容」，把 json 文本直接发过去。',
            style: const TextStyle(fontSize: 12.5, height: 1.6),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              final StringBuffer sb = StringBuffer();
              try {
                for (final String p in paths) {
                  sb.writeln(await File(p).readAsString());
                }
              } catch (_) {}
              await Clipboard.setData(ClipboardData(text: sb.toString()));
              if (!c.mounted) return;
              Navigator.of(c).pop();
              messenger.showSnackBar(
                const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 2)),
              );
            },
            child: const Text('复制内容'),
          ),
          FilledButton(onPressed: () => Navigator.of(c).pop(), child: const Text('知道了')),
        ],
      ),
    );
  }

  /// 导入：从文件管理器选一个 json 文件读进来。
  ///
  /// 关键点：**不能用 File(path).readAsString()**。安卓上用户通过系统文件选择器
  /// 选的常常是 SAF「文档」URI，path 是 null 或者不可直读，必须走 readAsBytes()。
  Future<void> _import(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final AppState st = AppState.I;

    // 先问用哪种方式选。多这一步是因为部分机型对 .json 过滤太严，
    // 文件在选择器里会显示成灰色点不动，需要「显示全部文件」这条退路。
    if (!context.mounted) return;
    final String? mode = await _askPickMode(context);
    if (mode == null) return;

    PlatformFile? picked;
    try {
      picked = mode == 'any'
          ? await FilePicker.pickFile(
              dialogTitle: '选朝暮导出的 json（显示全部文件）',
              type: FileType.any,
            )
          : await FilePicker.pickFile(
              dialogTitle: '选朝暮导出的 json',
              type: FileType.custom,
              allowedExtensions: <String>['json'],
            );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('打开文件选择器失败：$e')));
      return;
    }

    if (picked == null) return; // 用户取消了
    if (!context.mounted) return;

    String text;
    try {
      final Uint8List bytes = await picked.readAsBytes();
      text = utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('读文件失败：$e')));
      return;
    }

    final Map<String, dynamic>? data = Store.parse(text.trim());
    if (data == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('这个文件不是有效的朝暮数据（应该是一份导出的 json）')),
      );
      return;
    }

    // 覆盖前先问一声，导入是破坏性的
    if (!context.mounted) return;
    final bool ok = await _confirmImport(context, picked.name, data);
    if (!ok) return;

    final bool done = await st.applyData(data);
    messenger.showSnackBar(
      SnackBar(content: Text(done ? '导入完成，已覆盖当前数据' : '导入失败：里面没有待办数据')),
    );
  }

  /// 选导入方式：只显示 json / 显示全部文件
  Future<String?> _askPickMode(BuildContext context) async {
    return showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '从文件里导入',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined, color: Color(0xFF185FA5)),
              title: const Text('选 json 文件', style: TextStyle(fontSize: 14)),
              subtitle: const Text('只列出 .json，最常用的方式', style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.of(c).pop('json'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open, color: Color(0xFF5F5E5A)),
              title: const Text('显示全部文件', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                '上面那种方式看不到你的文件时用这个',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.of(c).pop('any'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 弹窗确认导入。顺便把文件里的内容摘要给用户看一眼，避免导错文件。
  Future<bool> _confirmImport(
    BuildContext context,
    String fileName,
    Map<String, dynamic> data,
  ) async {
    final int todoCount =
        (data['todos'] is List) ? (data['todos'] as List<dynamic>).length : 0;
    final int tdlDays = (data['tdl'] is Map) ? (data['tdl'] as Map<dynamic, dynamic>).length : 0;
    final int reviewCount =
        (data['reviewNotes'] is Map) ? (data['reviewNotes'] as Map<dynamic, dynamic>).length : 0;
    final String stamp = '${data['exportedAt'] ?? '未知时间'}';

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('确认导入？', style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Text(
            '文件：$fileName\n'
            '导出时间：$stamp\n\n'
            '里面有：\n'
            '· 待办 $todoCount 条\n'
            '· TDL 时间表 $tdlDays 天\n'
            '· 复盘总结 $reviewCount 篇\n\n'
            '导入会覆盖当前所有数据，覆盖之后没法撤销。',
            style: const TextStyle(fontSize: 13, height: 1.7),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFA32D2D)),
            child: const Text('覆盖导入'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// 权限中心：逐条列出来，能跳的给按钮，跳不了的给手动路径
  Future<void> _openPermissionCenter(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const _PermissionCenterPage()),
    );
  }

  /// 选提醒提前量
  Future<void> _pickAhead(BuildContext context) async {
    final AppState st = AppState.I;
    // 0 / 5 / 10 / 15 / 30 / 60 / 120 分钟
    const List<int> opts = <int>[0, 5, 10, 15, 30, 60, 120];
    final int? picked = await showModalBottomSheet<int>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '提前多久提醒',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '比如「提前 10 分钟」，就是 09:00 的待办在 08:50 提醒你。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)),
                ),
              ),
            ),
            for (final int m in opts)
              ListTile(
                title: Text(
                  aheadLabel(m),
                  style: const TextStyle(fontSize: 14),
                ),
                trailing: st.defaultAheadMinutes == m
                    ? const Icon(Icons.check, size: 18, color: Color(0xFF185FA5))
                    : null,
                onTap: () => Navigator.of(c).pop(m),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await st.setDefaultAheadMinutes(picked);
  }

  /// 选提醒方式。
  ///
  /// 目前**只有横幅真的能用**；全屏闹钟那项保留但点了弹「开发中」——
  /// 全屏要额外的「后台弹出界面」权限，在部分机型上还会被系统拦，
  /// 不如先老老实实做横幅。
  Future<void> _pickRemindStyle(BuildContext context) async {
    final AppState st = AppState.I;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '提醒方式',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            for (final String s in RemindStyle.all)
              ListTile(
                leading: Icon(
                  s == RemindStyle.fullScreen ? Icons.fullscreen : Icons.notifications_active_outlined,
                  size: 20,
                  color: s == RemindStyle.fullScreen
                      ? const Color(0xFFB0B0B0)
                      : const Color(0xFF185FA5),
                ),
                title: Text(RemindStyle.displayOf(s), style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  s == RemindStyle.fullScreen
                      ? '功能开发中，敬请期待'
                      : '顶部弹一条横幅 + 响铃震动，几秒后自动消失',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: st.remindStyle == s && s != RemindStyle.fullScreen
                    ? const Icon(Icons.check, size: 18, color: Color(0xFF185FA5))
                    : null,
                // 全屏那项点了不选，只提示
                onTap: () => Navigator.of(c).pop(s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    if (picked == RemindStyle.fullScreen) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('功能开发中，敬请期待'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    await st.setRemindStyle(picked);
  }

  /// 立刻弹一条测试通知，验证链路通不通
  Future<void> _testNotify(BuildContext context, {required bool fullScreen}) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final AppState st = AppState.I;
    final bool ok = fullScreen
        ? await Notifier.I.showNowFullScreen(soundOn: st.defaultRemindOn)
        : await Notifier.I.showNow(soundOn: st.defaultRemindOn);
    if (!ok) {
      // 把真实原因带出来，别再说「可能是没给通知权限」这种猜的话
      final String why = Notifier.I.lastScheduleError;
      messenger.showSnackBar(
        SnackBar(
          content: Text(why.isEmpty ? '发不出去，但没拿到具体原因' : '发送失败：$why'),
          duration: const Duration(seconds: 10),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(fullScreen ? '已发出全屏测试，看屏幕' : '已发出测试提醒，看屏幕顶部'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// 跳到系统的「待办提醒」渠道设置页
  Future<void> _openChannelSettings(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool ok = await Notifier.I.openChannelSettings();
    if (ok) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('跳不过去。手动路径：设置 → 应用管理 → 朝暮 → 通知 → 待办提醒'),
        duration: Duration(seconds: 8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppState st = AppState.I;

    return Scaffold(
      appBar: AppBar(title: const Text('设置', style: TextStyle(fontSize: 16))),
      body: AnimatedBuilder(
        animation: st,
        builder: (BuildContext context, Widget? _) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: <Widget>[
              _sectionTitle('记待办'),
              _card(<Widget>[
                ListTile(
                  title: const Text('几点之后记的算明天', style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    _hhmm(st.dayStartHour, st.dayStartMinute) == '00:00'
                        ? '00:00（不偏移，什么时候记都算今天）'
                        : '${_hhmm(st.dayStartHour, st.dayStartMinute)}（之后记的算明天）',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _pickDayStart(context),
                ),
              ]),

              _sectionTitle('四象限颜色'),
              _card(<Widget>[
                for (int i = 0; i < Priority.names.length; i++)
                  ListTile(
                    title: Text(Priority.names[i], style: const TextStyle(fontSize: 14)),
                    trailing: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: st.colorOf(i),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onTap: () => _pickQuadrantColor(context, i),
                  ),
              ]),

              // 「清单」设置区块已于 2026-10-16 删除，见 app_state.dart 的说明
              _sectionTitle('数据'),
              _card(<Widget>[
                FutureBuilder<String>(
                  future: Store.dataFilePath(),
                  builder: (BuildContext c, AsyncSnapshot<String> snap) => ListTile(
                    title: const Text('数据文件位置', style: TextStyle(fontSize: 14)),
                    subtitle: Text(snap.data ?? '读取中…', style: const TextStyle(fontSize: 11)),
                  ),
                ),
                ListTile(
                  title: const Text('历史总结', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('看所有写过的复盘总结', style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const ReviewHistoryPage()),
                  ),
                ),
                ListTile(
                  title: const Text('导出数据', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('复盘总结 / 历史待办分开导出，可直接分享', style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _export(context),
                ),
                ListTile(
                  title: const Text('导入数据', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('从文件管理器选一份导出的 json，覆盖当前数据', style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _import(context),
                ),
              ]),

              _sectionTitle('提醒'),
              _card(<Widget>[
                ListTile(
                  title: const Text('权限中心', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    '通知 / 精确闹钟 / 后台弹出 / 自启动 / 省电策略，逐条检查',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _openPermissionCenter(context),
                ),
                ListTile(
                  title: const Text('提醒方式', style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    st.remindStyle == RemindStyle.fullScreen
                        ? '全屏闹钟（功能开发中）'
                        : '顶部横幅（弹一条 + 响铃，几秒后消失）',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _pickRemindStyle(context),
                ),
                ListTile(
                  title: const Text('提前多久提醒', style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    '${aheadLabel(st.defaultAheadMinutes)}（单条待办里可单独改）',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _pickAhead(context),
                ),
                SwitchListTile(
                  title: const Text('默认打开铃声', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    '关掉后提醒只弹横幅 + 震动，不出声',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: st.defaultRemindOn,
                  onChanged: (bool v) async {
                    await st.setDefaultRemindOn(v);
                  },
                ),
                ListTile(
                  title: const Text('测试提醒', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    '立刻发一条横幅通知，验证到底通不通',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.play_circle_outline, size: 18),
                  onTap: () => _testNotify(context, fullScreen: false),
                ),
                ListTile(
                  title: const Text('测试全屏提醒', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    '立刻发一条全屏卡片，验证全屏权限',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.play_circle_outline, size: 18),
                  onTap: () => _testNotify(context, fullScreen: true),
                ),
              ]),

              _sectionTitle('铃声'),
              _card(<Widget>[
                ListTile(
                  // 新手引导第 3 步的锚点（会先自动滚到这一行）
                  key: GuideKeys.ringTile,
                  title: const Text('通知铃声', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    '在系统铃声页挑本地音乐 / 在线铃声，所有提醒统一用它',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _openChannelSettings(context),
                ),
              ]),

              _sectionTitle('关于朝暮'),
              _card(<Widget>[
                ListTile(
                  title: const Text('重看新手引导', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    '再走一遍主页、铃声、日历的引导',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () async {
                    await AppState.I.replayGuide();
                    if (!context.mounted) return;
                    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
                    await Future<void>.delayed(const Duration(milliseconds: 350));
                    await GuideController.I.start();
                  },
                ),
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
              const _VersionLabel(),
            ],
          );
        },
      ),
    );
  }
}

/// 权限中心：把该开的权限逐条列出来
///
/// 设计取舍：**只显示真查得到的状态**。
/// 「通知」「精确闹钟」有标准 API，直接查；「自启动」在部分 ROM 上挂在
/// AppOps（`android:auto_start`）里，也能查 —— 但查不到时一律不显示状态，
/// 不硬猜（硬猜成「已开启」会让用户跳过这一步）。
/// 除此之外这一页只做三件事：
/// ① 讲清为什么需要 ② 给一键跳转（跳前探测，探不到就不跳）
/// ③ 跳不进去时给手动路径文字。
class _PermissionCenterPage extends StatefulWidget {
  const _PermissionCenterPage();

  @override
  State<_PermissionCenterPage> createState() => _PermissionCenterPageState();
}

class _PermissionCenterPageState extends State<_PermissionCenterPage> {
  /// 系统能查出来的真实状态
  bool? _notifyOk;
  bool? _exactOk;

  /// 自启动。null = 这台机型查不到（不显示状态标）
  bool? _autoOk;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _checking = true);
    final bool n = await Notifier.I.hasPermission();
    final bool? e = await Notifier.I.canScheduleExact();
    final bool? a = await Notifier.I.isAutoStartEnabled();
    if (!mounted) return;
    setState(() {
      _notifyOk = n;
      _exactOk = e;
      _autoOk = a;
      _checking = false;
    });
  }

  Future<void> _jump(String id) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    bool ok = false;
    String? landed;

    switch (id) {
      case 'notify':
        // 先试着走官方请求（Android 13+ 会弹授权框）
        final bool granted = await Notifier.I.requestPermission();
        if (granted) {
          messenger.showSnackBar(const SnackBar(content: Text('通知已允许')));
          await _refresh();
          return;
        }
        ok = await Permissions.openNotificationSettings();
        break;
      case 'channel':
        // 直接落到「待办提醒」渠道页 —— 声音 / 震动 / 悬浮通知都在这一页，
        // 挑本地铃声也在这儿。和设置里那个「本地铃声」是同一个跳转。
        ok = await Notifier.I.openChannelSettings();
        break;
      case 'exact':
        await Notifier.I.requestExactAlarm();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        ok = await Permissions.openExactAlarm();
        break;
      case 'fullscreen':
        await Notifier.I.requestFullScreenIntent();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await _refresh();
        messenger.showSnackBar(
          const SnackBar(content: Text('已请求「后台弹出界面」权限，看系统弹窗')),
        );
        return;
      case 'battery':
        // 第一优先跳「朝暮的应用信息」页（截图里那个「应用信息」）。
        //
        // 为什么它排第一，而不是先试各家省电专页：
        // - 这一页里**同时有「省电策略」和「自启动」**，用户在一页里就能都设完
        // - 它走的是 Android 标准 action（ACTION_APPLICATION_DETAILS_SETTINGS），
        //   **任何品牌都能跳**；各家省电专页是拼组件名硬跳的，换台手机就不一定了
        // 之前顺序反了，会落到小米的省电专页 —— 那页只有省电策略，没有自启动。
        ok = await Notifier.I.openAppDetails();
        if (!ok) ok = await Notifier.I.openPowerSaving();
        if (!ok) ok = await Permissions.openBatteryOptimization();
        if (!ok) ok = await Permissions.openBatteryOptimizationList();
        break;
      case 'autostart':
        // 和省电那步跳同一个地方 ——「朝暮的应用信息」页，这一页里就有「自启动」开关，
        // 走的是 Android 标准 action，换任何品牌都能跳。
        // 各家自启动专页只是兜底（拼组件名硬跳，换台手机可能就没有）。
        ok = await Notifier.I.openAppDetails();
        if (!ok) {
          landed = await Permissions.openAutoStart();
          ok = landed != null;
        }
        break;
      case 'dnd':
        ok = await Permissions.openNotificationPolicy();
        break;
      default:
        break;
    }

    if (!mounted) return;
    if (ok) {
      if (id == 'autostart' && landed != null) {
        messenger.showSnackBar(SnackBar(content: Text('已跳到「$landed」，把朝暮打开')));
      }
      // 从系统页切回来再刷一次状态
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (mounted) await _refresh();
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('这台机型跳不进去，照下面的路径手动点一下')),
      );
    }
  }

  Widget _statusChip(String id) {
    if (_checking) return const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2));
    bool? v;
    if (id == 'notify') v = _notifyOk;
    if (id == 'exact') v = _exactOk;
    if (id == 'autostart') v = _autoOk;
    if (v == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: v ? const Color(0xFFE6F4EA) : const Color(0xFFFDE7E7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        v ? '已开启' : '未开启',
        style: TextStyle(
          fontSize: 11,
          color: v ? const Color(0xFF3F7D42) : const Color(0xFFA32D2D),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<PermItem> items = Permissions.allItems();

    return Scaffold(
      appBar: AppBar(
        title: const Text('权限中心', style: TextStyle(fontSize: 16)),
        actions: <Widget>[
          IconButton(
            tooltip: '重新检查',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: <Widget>[
          Container(
            color: const Color(0xFFFFF8E6),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: const Text(
              '国产手机系统会把后台应用杀掉，提醒就会晚到或者干脆不来。\n'
              '下面每一条点进去打开就行。右上角「重新检查」可以刷新状态：'
              '系统查得到的项（通知、精确闹钟、部分机型上的自启动）会显示「已开启 / 未开启」，'
              '没显示状态的就是这台机型查不到，打开后自己确认一下即可。',
              style: TextStyle(fontSize: 12.5, height: 1.7, color: Color(0xFF7A5B12)),
            ),
          ),
          for (final PermItem it in items) _tile(it),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              '全部打开之后，回到设置页点「测试提醒」和「测试全屏提醒」各试一次，'
              '能弹出来就说明配好了。',
              style: TextStyle(fontSize: 12, color: Color(0xFF9A9A9A), height: 1.7),
            ),
          ),
          _diagnoseCard(),
        ],
      ),
    );
  }

  /// 排程诊断：看不到提醒时，先看这里到底卡在哪。
  Widget _diagnoseCard() {
    final Notifier n = Notifier.I;
    final String err = n.lastScheduleError;
    final bool bad = err.isNotEmpty;
    // 待办里有多少条真的带了提醒时刻
    int withRemind = 0;
    for (final Todo t in AppState.I.todos) {
      final bool has = (t.remind != null) || (t.due != null && t.dueHasTime);
      if (!t.done && has) withRemind++;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '排程诊断',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _diagRow('系统时区', n.tzName),
          _diagRow(
            '时区偏移',
            'UTC${n.tzOffsetHours >= 0 ? '+' : ''}${n.tzOffsetHours} '
                '（应为 +8，若显示 0 说明时区没设上）',
          ),
          _diagRow('带提醒的待办', '$withRemind 条'),
          _diagRow('排程结果', bad ? err : '没有报错'),
          const SizedBox(height: 6),
          const Text(
            '如果「时区偏移」不是 +8，或者「排程结果」有报错，把这两行截图发我。',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF9A9A9A), height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _diagRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 78,
            child: Text(
              k,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF7A7A7A)),
            ),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontSize: 12.5, height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _tile(PermItem it) {
    // 能查到真实状态的才挂状态标。自启动只在部分 ROM 上查得到，
    // 查不到时 _autoOk 是 null，_statusChip 会返回空 —— 不会显示假状态。
    final bool showStatus =
        it.id == 'notify' || it.id == 'exact' || it.id == 'autostart';
    return Container(
      color: const Color(0xFFFFFFFF),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  it.title,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
              ),
              if (showStatus) _statusChip(it.id),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            it.why,
            style: const TextStyle(fontSize: 12.5, height: 1.6, color: Color(0xFF5F5E5A)),
          ),
          const SizedBox(height: 8),
          Text(
            '手动路径：${it.manualPath}',
            style: const TextStyle(fontSize: 12, height: 1.6, color: Color(0xFF9A9A9A)),
          ),
          if (it.jumpNote != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              it.jumpNote!,
              style: const TextStyle(fontSize: 12, height: 1.6, color: Color(0xFF185FA5)),
            ),
          ],
          if (it.canJump) ...<Widget>[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _jump(it.id),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('去打开', style: TextStyle(fontSize: 13)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 设置页底部的版本号。
///
/// 从系统 PackageManager 读真实的 versionName + versionCode，
/// 方便核对装的是哪一版 —— 之前版本号写死在 pubspec 里、
/// 打包时又没同步进 local.properties，导致装上去看到的永远是旧号。
class _VersionLabel extends StatefulWidget {
  const _VersionLabel();

  @override
  State<_VersionLabel> createState() => _VersionLabelState();
}

class _VersionLabelState extends State<_VersionLabel> {
  String _v = '';

  @override
  void initState() {
    super.initState();
    Notifier.I.appVersion().then((String v) {
      if (mounted) setState(() => _v = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Text(
        _v.isEmpty
            ? '朝暮 · 待办与日程\n数据全部存在本机，不上传任何服务器。'
            : '朝暮 · 待办与日程  v$_v\n数据全部存在本机，不上传任何服务器。',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: Color(0xFF9A9A9A), height: 1.7),
      ),
    );
  }
}
