import 'package:audioplayers/audioplayers.dart';

import 'sound_lib.dart';

/// 提醒铃声播放器。
///
/// 只有一个实例：提醒是单发的，同时响两款没有意义，反而会叠音。
/// 试听也走这里，所以试听会打断正在响的提醒 —— 这是有意的，用户点试听
/// 就是要立刻听到，不是要两首合唱。
class SoundPlayer {
  SoundPlayer._();

  static final AudioPlayer _p = AudioPlayer()
    ..setReleaseMode(ReleaseMode.stop);

  /// 正在播的 id，界面拿来判断要不要显示「停止」
  static String playingId = '';

  /// 按 id 播。preset:* 这一类交给系统通知，这里直接跳过（返回 false）。
  /// 文件找不到（引用的本机文件被删）也返回 false，由调用方决定要不要提示。
  static Future<bool> playId(String id) async {
    if (id.isEmpty) return false;
    final SoundItem? s = SoundLib.byId(id);
    if (s == null) return false;
    return playItem(s);
  }

  /// [force] = true 表示「试听」：preset 类也由 App 播一份同音色的系统 wav。
  /// 到点提醒走 [playId]（force = false），preset 交给 Toast，避免双声。
  static Future<bool> playItem(SoundItem s, {bool force = false}) async {
    if (s.systemPlay && !force) return false;

    final String? asset = s.asset;
    final String? file = s.file;
    if (asset == null && file == null) return false;

    try {
      await _p.stop();
      playingId = s.id;
      if (asset != null) {
        await _p.play(AssetSource(asset));
      } else {
        await _p.play(DeviceFileSource(file!));
      }
      return true;
    } catch (_) {
      playingId = '';
      return false;
    }
  }

  static Future<void> stop() async {
    playingId = '';
    try {
      await _p.stop();
    } catch (_) {}
  }

  /// 释放（进后台/退出时调，避免占着音频设备）
  static Future<void> dispose() async {
    try {
      await _p.dispose();
    } catch (_) {}
  }
}
