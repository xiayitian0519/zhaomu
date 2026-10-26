import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../sound_lib.dart';
import '../sound_player.dart';

/// 铃声选择页。
///
/// - [single] = false：设置里的「全局默认铃声」，选完直接写进 AppState；
/// - [single] = true ：单条待办的「这条的铃声」，`Navigator.pop(id)` 返回，
///   空串表示跟随全局默认。
///
/// 为什么不做成弹窗：选项太多（7 内置 + 5 预设 + 70 个系统 wav + 自己导入的），
/// 底部 sheet 里塞不下，滚起来也别扭。
class SoundPage extends StatefulWidget {
  const SoundPage({super.key, this.single = false, this.initial = ''});

  final bool single;
  final String initial;

  @override
  State<SoundPage> createState() => _SoundPageState();
}

class _SoundPageState extends State<SoundPage> {
  static const Color _blue = Color(0xFF185FA5);
  static const Color _ink = Color(0xFF1A1F2B);
  static const Color _grey = Color(0xFF8A91A0);
  static const Color _line = Color(0xFFEDEFF3);

  late String _selected = widget.single
      ? widget.initial
      : AppState.I.defaultSoundId;

  List<SoundItem> _imported = SoundLib.importedCache;
  bool _openPreset = false;
  bool _openSys = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadImported();
  }

  Future<void> _loadImported() async {
    final List<SoundItem> list = await SoundLib.refreshImported();
    if (!mounted) return;
    setState(() => _imported = list);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  /// 选一款。全局模式下立刻落盘；两种模式都会试听一下。
  Future<void> _pick(String id) async {
    setState(() => _selected = id);
    if (!widget.single) await AppState.I.setDefaultSoundId(id);
    await _preview();
  }

  /// 试听「当前选中」那一款
  Future<void> _preview() async {
    if (_selected.isEmpty) {
      await SoundPlayer.stop();
      _toast('「跟随默认」没有自己的声音，先在下面挑一款');
      return;
    }
    final SoundItem? s = SoundLib.byId(_selected);
    if (s == null) {
      _toast('这一款找不到文件了（可能是引用的本机文件被移动或删除）');
      return;
    }
    final bool ok = await SoundPlayer.playItem(s, force: true);
    if (!ok) _toast('「${s.name}」播不出来，可能格式不受支持');
  }

  /// 导入：复制一份到数据目录，换机 / 备份都跟着走
  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final PlatformFile? picked = await FilePicker.pickFile(
        dialogTitle: '选一个音频当铃声（mp3 / wav / m4a / flac）',
        type: FileType.custom,
        allowedExtensions: const <String>[
          'mp3',
          'wav',
          'm4a',
          'flac',
          'aac',
          'ogg',
        ],
      );
      if (picked == null) return;
      final String? p = picked.path;
      if (p == null) {
        _toast('这个文件拿不到本地路径（可能是系统授选的虚拟文件），换一个试试');
        return;
      }
      final File src = File(p);
      if (!await src.exists()) {
        _toast('这个文件读不到');
        return;
      }

      final Directory dir = await SoundLib.ringtoneDir();
      final String base = src.uri.pathSegments.last;
      final int dot = base.lastIndexOf('.');
      final String stem = dot <= 0 ? base : base.substring(0, dot);
      final String ext = dot <= 0 ? '' : base.substring(dot);

      File dst = File('${dir.path}${Platform.pathSeparator}$base');
      if (await dst.exists()) {
        // 重名就加时间戳，绝不覆盖用户已有的那一份
        dst = File(
          '${dir.path}${Platform.pathSeparator}'
          '$stem-${DateTime.now().millisecondsSinceEpoch}$ext',
        );
      }
      await src.copy(dst.path);

      final List<SoundItem> list = await SoundLib.refreshImported();
      if (!mounted) return;
      final String newId = '${SoundLib.libPrefix}${dst.uri.pathSegments.last}';
      setState(() {
        _imported = list;
        _selected = newId;
      });
      if (!widget.single) await AppState.I.setDefaultSoundId(newId);
      await _preview();
      _toast('已导入「${dst.uri.pathSegments.last}」');
    } catch (e) {
      _toast('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 引用本机文件：只记路径，不复制
  Future<void> _linkLocal() async {
    try {
      final PlatformFile? picked = await FilePicker.pickFile(
        dialogTitle: '选电脑上已有的音频（只记路径，不复制）',
        type: FileType.custom,
        allowedExtensions: const <String>[
          'mp3',
          'wav',
          'm4a',
          'flac',
          'aac',
          'ogg',
        ],
      );
      if (picked == null) return;
      final String? p = picked.path;
      if (p == null) {
        _toast('这个文件拿不到本地路径，换一个试试');
        return;
      }
      await _pick('${SoundLib.filePrefix}$p');
    } catch (e) {
      _toast('打开文件选择器失败：$e');
    }
  }

  Future<void> _deleteImported(SoundItem s) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('删除这款铃声？'),
        content: Text('「${s.name}」的副本会被删掉，你原来的文件不受影响。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFC6403A)),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final File f = File(s.file ?? '');
      if (await f.exists()) await f.delete();
    } catch (_) {}
    if (_selected == s.id) {
      _selected = '';
      if (!widget.single) await AppState.I.setDefaultSoundId('');
    }
    final List<SoundItem> list = await SoundLib.refreshImported();
    if (!mounted) return;
    setState(() => _imported = list);
  }

  @override
  Widget build(BuildContext context) {
    final List<SoundItem> sys = SoundLib.systemMedia();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _ink),
          onPressed: () => Navigator.of(context).pop(_selected),
        ),
        title: Text(
          widget.single ? '这条的铃声' : '铃声 · 默认',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: _ink,
          ),
        ),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _preview,
            icon: const Icon(Icons.volume_up_outlined, size: 18),
            label: const Text('试听'),
            style: TextButton.styleFrom(foregroundColor: _blue),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Text(
              widget.single
                  ? '只影响这一条待办，不动其他；想听全局的选「跟随默认」。'
                  : '所有提醒默认响这一款。单条想不同，到那条待办的「时钟」面板里改。',
              style: const TextStyle(fontSize: 12, color: _grey, height: 1.5),
            ),
          ),

          // 「跟随默认」只在单条模式出现
          if (widget.single) ...<Widget>[
            _tile(
              id: '',
              name: '跟随默认',
              note: '当前全局默认：${SoundLib.nameOf(AppState.I.defaultSoundId)}',
              showPlay: false,
            ),
            const SizedBox(height: 8),
          ],

          _groupTitle('内置铃声 · ${SoundLib.builtin.length} 款'),
          for (final SoundItem s in SoundLib.builtin) _tile(
            id: s.id,
            name: s.name,
            note: s.note,
          ),

          const SizedBox(height: 8),
          _groupTitle('系统铃声'),
          _folder(
            'Windows 通知预设',
            '${SoundLib.presets.length} 个 · 由系统播放',
            _openPreset,
            () => setState(() => _openPreset = !_openPreset),
          ),
          if (_openPreset)
            for (final SoundItem s in SoundLib.presets) _tile(
              id: s.id,
              name: s.name,
              note: s.note,
            ),
          _folder(
            '系统声音文件',
            Platform.isWindows
                ? '${sys.length} 个 · C:\\Windows\\Media'
                : '只有电脑版才有',
            _openSys,
            () => setState(() => _openSys = !_openSys),
          ),
          if (_openSys)
            if (sys.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: Text(
                  '这个平台没有可读的系统声音目录。',
                  style: TextStyle(fontSize: 12, color: _grey),
                ),
              )
            else
              for (final SoundItem s in sys) _tile(
                id: s.id,
                name: s.name,
                note: '',
              ),

          const SizedBox(height: 8),
          _groupTitle('我自己的'),
          _action(
            icon: Icons.library_music_outlined,
            title: '导入音频文件',
            note: '复制进朝暮的数据目录，换机 / 备份都带着走',
            onTap: _import,
          ),
          _action(
            icon: Icons.link,
            title: '引用本机文件',
            note: '只记路径不复制；文件被删或移动就自动回退系统默认',
            onTap: _linkLocal,
          ),
          if (_imported.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Text(
                '还没有导入过铃声。',
                style: TextStyle(fontSize: 12, color: _grey),
              ),
            )
          else
            for (final SoundItem s in _imported) _tile(
              id: s.id,
              name: s.name,
              note: s.note,
              onDelete: () => _deleteImported(s),
            ),

          // 引用了但文件已消失的那一项，单独提示一行
          if (_selected.startsWith(SoundLib.filePrefix) &&
              SoundLib.byId(_selected) == null)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFDF1F0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE3A9A4)),
              ),
              child: const Text(
                '当前选中的本机文件已经找不到了，到点会自动回退成系统默认。'
                '重新「引用本机文件」或换成内置的就不会再出问题。',
                style: TextStyle(fontSize: 12, color: Color(0xFF8B3A34), height: 1.5),
              ),
            ),

          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Text(
              widget.single
                  ? '优先级：这一条的设置 > 全局默认 > 系统提示音。'
                  '选回「跟随默认」就重新听全局的。'
                  : '想恢复系统提示音，选「系统铃声 → Windows 通知预设 → 系统默认」。',
              style: const TextStyle(fontSize: 11.5, color: _grey, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- 小组件 ----------------

  Widget _groupTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
        child: Text(
          t,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _grey,
          ),
        ),
      );

  Widget _tile({
    required String id,
    required String name,
    String note = '',
    bool showPlay = true,
    VoidCallback? onDelete,
  }) {
    final bool on = _selected == id;
    return Material(
      color: on ? const Color(0xFFEAF0FF) : Colors.white,
      child: InkWell(
        onTap: () => _pick(id),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _line, width: 1)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                        color: _ink,
                      ),
                    ),
                    if (note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          note,
                          style: const TextStyle(fontSize: 11.5, color: _grey),
                        ),
                      ),
                  ],
                ),
              ),
              if (showPlay)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  color: on ? _blue : _grey,
                  tooltip: '试听',
                  onPressed: () async {
                    final SoundItem? s = SoundLib.byId(id);
                    if (s == null) {
                      _toast('这一款找不到文件了');
                      return;
                    }
                    final bool ok = await SoundPlayer.playItem(s, force: true);
                    if (!ok) _toast('「${s.name}」播不出来');
                  },
                ),
              if (onDelete != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  color: const Color(0xFFC6403A),
                  tooltip: '删除',
                  onPressed: onDelete,
                ),
              Icon(
                on ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: on ? _blue : const Color(0xFFCBD2DE),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _folder(
    String title,
    String note,
    bool open,
    VoidCallback onTap,
  ) =>
      Material(
        color: const Color(0xFFF1F3F7),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 13, 16, 13),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _line, width: 1)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: const TextStyle(fontSize: 14, color: _ink),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          note,
                          style: const TextStyle(fontSize: 11.5, color: _grey),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: _grey,
                ),
              ],
            ),
          ),
        ),
      );

  Widget _action({
    required IconData icon,
    required String title,
    required String note,
    required VoidCallback onTap,
  }) =>
      Material(
        color: Colors.white,
        child: InkWell(
          onTap: _busy ? null : onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 13, 16, 13),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _line, width: 1)),
            ),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 18, color: _blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: const TextStyle(fontSize: 14, color: _blue),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          note,
                          style: const TextStyle(fontSize: 11.5, color: _grey),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: _grey),
              ],
            ),
          ),
        ),
      );
}
