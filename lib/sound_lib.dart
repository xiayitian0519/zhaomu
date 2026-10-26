import 'dart:io';

import 'store.dart';

/// 一款铃声。
///
/// 三种发声方式，靠 [systemPlay] 和能力字段区分：
/// 1. [asset] 非空 → App 自己播（内置七款，打在 exe 里）
/// 2. [file] 非空  → App 自己播（系统 wav / 导入的 / 引用的本机文件）
/// 3. [systemPlay] = true → 交给 Windows 通知自己播（preset:*），App 不播
class SoundItem {
  const SoundItem({
    required this.id,
    required this.name,
    this.note = '',
    this.asset,
    this.file,
    this.systemPlay = false,
  });

  /// 存进数据的 id。空串特指「跟随全局默认」，不在这里出现。
  final String id;

  /// 界面上显示的名字（原名太长，一律用短名）
  final String name;

  /// 右侧小字：时长 / 来源
  final String note;

  /// 相对 assets/ 的路径，如 `ringtones/alert.mp3`
  final String? asset;

  /// 绝对路径（系统 wav / 导入副本 / 引用的本机文件）
  final String? file;

  /// 由系统通知播放，App 不插手
  final bool systemPlay;

  /// 能不能真的出声（preset 交给系统也算能）
  bool get playable => asset != null || file != null || systemPlay;
}

/// 铃声库：内置七款 + Windows 系统声音 + 用户导入/引用的。
///
/// 为什么不把「声音」交给通知本身：见 notifier.dart `_winDetails()` 的注释 ——
/// 免安装 exe 下 Toast 根本播不了自定义音频。
class SoundLib {
  SoundLib._();

  static const String appPrefix = 'app:';
  static const String sysPrefix = 'sys:';
  static const String presetPrefix = 'preset:';
  static const String libPrefix = 'lib:';
  static const String filePrefix = 'file:';

  /// 内置七款。文件名与 [asset] 一一对应，改名要两边一起改。
  static const List<SoundItem> builtin = <SoundItem>[
    SoundItem(
      id: '${appPrefix}alert',
      name: '警报提示',
      note: '1.9s',
      asset: 'ringtones/alert.mp3',
    ),
    SoundItem(
      id: '${appPrefix}tech_ui',
      name: '科技感 UI',
      note: '2.0s',
      asset: 'ringtones/tech_ui.mp3',
    ),
    SoundItem(
      id: '${appPrefix}mail_sms',
      name: '邮件短信',
      note: '2.0s',
      asset: 'ringtones/mail_sms.mp3',
    ),
    SoundItem(
      id: '${appPrefix}charge',
      name: '充电上电',
      note: '2.1s',
      asset: 'ringtones/charge.mp3',
    ),
    SoundItem(
      id: '${appPrefix}lock_car',
      name: '锁车',
      note: '2.1s',
      asset: 'ringtones/lock_car.wav',
    ),
    SoundItem(
      id: '${appPrefix}playful',
      name: '活泼俏皮',
      note: '1.5s',
      asset: 'ringtones/playful.mp3',
    ),
    SoundItem(
      id: '${appPrefix}boot',
      name: '开关机提示',
      note: '3.0s',
      asset: 'ringtones/boot.mp3',
    ),
  ];

  /// Windows 通知自带的预设音。
  ///
  /// 只列 5 个**非循环**的。Alarm1-10 / Call1-10 是 looping 音，
  /// 拿来当提醒会在横幅停留的十几秒里一直响，等于半个闹钟 —— 故意不列。
  ///
  /// [SoundItem.file] 指向同音色的系统 wav，**只用于试听**：到点那一下仍由
  /// Toast 自己播（ms-winsoundevent 走系统路径，音量和音频流由系统管）。
  static const List<SoundItem> presets = <SoundItem>[
    SoundItem(
      id: '${presetPrefix}default',
      name: '系统默认',
      note: '通知默认音',
      systemPlay: true,
      file: r'C:\Windows\Media\Windows Notify System Generic.wav',
    ),
    SoundItem(
      id: '${presetPrefix}reminder',
      name: '系统提醒音',
      note: 'Reminder',
      systemPlay: true,
      file: r'C:\Windows\Media\Windows Notify Calendar.wav',
    ),
    SoundItem(
      id: '${presetPrefix}im',
      name: '系统消息音',
      note: 'IM',
      systemPlay: true,
      file: r'C:\Windows\Media\Windows Notify Messaging.wav',
    ),
    SoundItem(
      id: '${presetPrefix}mail',
      name: '系统邮件音',
      note: 'Mail',
      systemPlay: true,
      file: r'C:\Windows\Media\Windows Notify Email.wav',
    ),
    SoundItem(
      id: '${presetPrefix}sms',
      name: '系统短信音',
      note: 'SMS',
      systemPlay: true,
      file: r'C:\Windows\Media\Windows Notify Messaging.wav',
    ),
  ];

  static List<SoundItem>? _sysCache;

  /// 扫 C:\Windows\Media 下的 wav。只在 Windows 上有内容。
  static List<SoundItem> systemMedia() {
    final List<SoundItem>? cached = _sysCache;
    if (cached != null) return cached;

    final List<SoundItem> out = <SoundItem>[];
    if (Platform.isWindows) {
      try {
        final Directory dir = Directory(r'C:\Windows\Media');
        if (dir.existsSync()) {
          final List<File> files = dir
              .listSync()
              .whereType<File>()
              .where((File f) => f.path.toLowerCase().endsWith('.wav'))
              .toList()
            ..sort((File a, File b) => a.path.compareTo(b.path));
          for (final File f in files) {
            final String base = f.uri.pathSegments.last;
            final String key = base.substring(0, base.length - 4);
            out.add(SoundItem(
              id: '$sysPrefix$key',
              name: key,
              note: '系统声音',
              file: f.path,
            ));
          }
        }
      } catch (_) {
        // 读不到就当没有，不阻塞界面
      }
    }
    _sysCache = out;
    return out;
  }

  /// 铃声副本目录：`<数据目录>/chaomu/ringtones/`
  static Future<Directory> ringtoneDir() async {
    final Directory base = await Store.dataDir();
    final Directory d = Directory(
      '${base.path}${Platform.pathSeparator}ringtones',
    );
    if (!await d.exists()) await d.create(recursive: true);
    _ringtoneDirPath = d.path;
    return d;
  }

  /// [byId] / [nameOf] 是同步的（界面每帧都要调），所以目录路径和
  /// 导入列表都要有缓存。启动时和导入/删除后各刷一次就够。
  static String? _ringtoneDirPath;
  static List<SoundItem> _importedCache = const <SoundItem>[];

  /// 重扫导入目录，刷新缓存。返回最新列表。
  static Future<List<SoundItem>> refreshImported() async {
    final List<SoundItem> out = <SoundItem>[];
    try {
      final Directory d = await ringtoneDir();
      final List<File> files = d
          .listSync()
          .whereType<File>()
          .where((File f) => _isAudio(f.path))
          .toList()
        ..sort((File a, File b) => b.path.compareTo(a.path));
      for (final File f in files) {
        final String base = f.uri.pathSegments.last;
        out.add(SoundItem(
          id: '$libPrefix$base',
          name: _stripExt(base),
          note: '已导入',
          file: f.path,
        ));
      }
    } catch (_) {}
    _importedCache = out;
    return out;
  }

  /// 已导入的铃声（缓存副本，同步可读）
  static List<SoundItem> get importedCache => _importedCache;

  /// 兼容旧调用：直接给异步结果
  static Future<List<SoundItem>> imported() => refreshImported();

  static bool _isAudio(String path) {
    final String p = path.toLowerCase();
    return p.endsWith('.mp3') ||
        p.endsWith('.wav') ||
        p.endsWith('.m4a') ||
        p.endsWith('.flac') ||
        p.endsWith('.aac') ||
        p.endsWith('.ogg');
  }

  static String _stripExt(String name) {
    final int i = name.lastIndexOf('.');
    return i <= 0 ? name : name.substring(0, i);
  }

  /// 按 id 还原成可播放的 [SoundItem]。
  ///
  /// 找不到（比如引用的本机文件被删了）返回 null，调用方应该回退到系统默认。
  static SoundItem? byId(String id) {
    if (id.isEmpty) return null;

    for (final SoundItem s in builtin) {
      if (s.id == id) return s;
    }
    for (final SoundItem s in presets) {
      if (s.id == id) return s;
    }
    if (id.startsWith(sysPrefix)) {
      for (final SoundItem s in systemMedia()) {
        if (s.id == id) return s;
      }
      // 缓存里没有就直接拼路径兜底（用户可能手动改过 json）
      final String key = id.substring(sysPrefix.length);
      final File f = File('${r'C:\Windows\Media'}${Platform.pathSeparator}$key.wav');
      if (f.existsSync()) {
        return SoundItem(id: id, name: key, note: '系统声音', file: f.path);
      }
      return null;
    }
    if (id.startsWith(libPrefix)) {
      for (final SoundItem s in _importedCache) {
        if (s.id == id) return s;
      }
      // 缓存还没刷（比如刚启动就弹提醒）→ 用缓存的目录路径同步拼一份
      final String dir = _ringtoneDirPath ?? '';
      if (dir.isEmpty) return null;
      final String base = id.substring(libPrefix.length);
      final File f = File('$dir${Platform.pathSeparator}$base');
      if (!f.existsSync()) return null;
      return SoundItem(id: id, name: _stripExt(base), note: '已导入', file: f.path);
    }
    if (id.startsWith(filePrefix)) {
      final String path = id.substring(filePrefix.length);
      final File f = File(path);
      if (f.existsSync()) {
        return SoundItem(
          id: id,
          name: _stripExt(f.uri.pathSegments.last),
          note: '本机文件',
          file: f.path,
        );
      }
      return null;
    }
    return null;
  }

  /// 给界面显示的名字。查不到就说「系统默认」，不要显示一串 id。
  static String nameOf(String id) {
    if (id.isEmpty) return '系统默认';
    final SoundItem? s = byId(id);
    if (s != null) return s.name;
    if (id.startsWith(libPrefix)) return _stripExt(id.substring(libPrefix.length));
    if (id.startsWith(filePrefix)) {
      final String p = id.substring(filePrefix.length);
      return _stripExt(p.split(RegExp(r'[\\/]')).last);
    }
    if (id.startsWith(sysPrefix)) return id.substring(sysPrefix.length);
    return '系统默认';
  }
}
