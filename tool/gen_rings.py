# -*- coding: utf-8 -*-
"""
生成四款内置铃声 -> android/app/src/main/res/raw/*.wav

关键(踩过的坑)：
  Android 的 MediaPlayer / Ringtone 对 8-bit PCM WAV 支持极差，
  8bit 会让通知加载失败 —— 表现就是「选了内嵌铃声提醒直接失败」。
  必须输出 16-bit PCM（sampwidth=2）。采样率 22050 兼容性最好。

音色设计（按用户审美定的）：
  chime 风铃：不谐和泛音比 + 长衰减
  wood  木琴：快起音 + 极短衰减
  bell  钟声：低频基音 + 不谐和分音（strike tone）
  guqin 古琴：多次谐波 + 拨弦噪声瞬态
禁止：音高微颤(vibrato)、频率滑音（用户明确否掉）
"""
import wave, struct, math, os, random

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   '..', 'android', 'app', 'src', 'main', 'res', 'raw')


def env_ad(t, attack, decay, sustain=0.0, release=None):
    """attack-decay(-sustain-release) 包络，返回 0..1"""
    if t < attack:
        return t / attack if attack > 0 else 1.0
    t2 = t - attack
    if release is None:
        return math.exp(-t2 / decay)
    if t2 < decay:
        return math.exp(-t2 * 0.0)  # 保持在 1（占位，实际走下面）
    return 0.0


def render(samples_count, fn, norm=0.9):
    """fn(i, t) -> -1..1"""
    buf = []
    for i in range(samples_count):
        t = i / SR
        v = fn(i, t)
        if v > 1.0:
            v = 1.0
        elif v < -1.0:
            v = -1.0
        buf.append(int(v * 32767 * norm))
    return buf


def write_wav(name, buf):
    path = os.path.join(OUT, name)
    w = wave.open(path, 'wb')
    w.setnchannels(1)
    w.setsampwidth(2)          # 16-bit，必须
    w.setframerate(SR)
    w.writeframes(b''.join(struct.pack('<h', s) for s in buf))
    w.close()
    return path, os.path.getsize(path)


def partials(t, base, ratios, amps, decay, attack=0.002, detune=0.0):
    """多个分音叠加。ratios 是不谐和的比例（风铃/钟声靠这个出味）"""
    s = 0.0
    for r, a in zip(ratios, amps):
        f = base * r
        if f > SR * 0.45:
            continue
        s += a * math.sin(2 * math.pi * f * t)
    return s * math.exp(-max(0.0, t - attack) / decay)


def make_chime():
    """风铃：不谐和泛音比，空灵悠长 1.1s，单音"""
    base = 880.0
    ratios = [1.0, 2.76, 5.40, 8.93, 13.34]
    amps   = [1.0, 0.62, 0.40, 0.22, 0.11]
    n = int(SR * 1.1)

    def f(i, t):
        a = 0.0
        for r, am in zip(ratios, amps):
            fr = base * r
            if fr > SR * 0.45:
                continue
            # 高次分音衰减更快
            d = 0.55 / (1.0 + (r - 1.0) * 0.13)
            a += am * math.sin(2 * math.pi * fr * t) * math.exp(-t / d)
        # 起音瞬态
        a *= min(1.0, t / 0.0015)
        return a * 0.34

    return render(n, f)


def make_wood():
    """木琴：快起音 + 极短衰减，清脆利落 0.45s"""
    base = 1046.5  # C6
    n = int(SR * 0.45)

    def f(i, t):
        if t < 0.0008:
            return 0.0
        # 木琴基音 + 一个八度上方的弱分音
        a = math.sin(2 * math.pi * base * t) * math.exp(-t / 0.085)
        a += 0.32 * math.sin(2 * math.pi * base * 3.0 * t) * math.exp(-t / 0.030)
        a += 0.15 * math.sin(2 * math.pi * base * 5.4 * t) * math.exp(-t / 0.018)
        # 敲击噪声（极短）
        if t < 0.004:
            a += random.uniform(-0.5, 0.5) * math.exp(-t / 0.0012) * 0.6
        a *= min(1.0, t / 0.0008)
        return a * 0.62

    return render(n, f)


def make_bell():
    """钟声：低频基音 + 不谐和分音(strike tone)，低沉厚实 1.3s"""
    base = 349.23  # F4
    n = int(SR * 1.3)
    # 钟的特征：hum / prime / tierce(小三度) / quint / nominal
    parts = [
        (0.5,  0.55, 1.35),   # hum（低八度）
        (1.0,  1.00, 1.00),   # prime
        (1.19, 0.62, 0.75),   # tierce 小三度 -> 钟味来源
        (1.50, 0.42, 0.60),   # quint
        (2.00, 0.30, 0.48),   # nominal
        (2.51, 0.16, 0.32),
        (3.01, 0.10, 0.24),
    ]

    def f(i, t):
        a = 0.0
        for r, am, d in parts:
            fr = base * r
            if fr > SR * 0.45:
                continue
            a += am * math.sin(2 * math.pi * fr * t) * math.exp(-t / d)
        if t < 0.006:
            a += random.uniform(-0.4, 0.4) * math.exp(-t / 0.002) * 0.5
        a *= min(1.0, t / 0.002)
        return a * 0.42

    return render(n, f)


def make_guqin():
    """古琴：多次谐波 + 拨弦噪声瞬态，拨弦余韵 1.3s"""
    base = 587.33  # D5
    n = int(SR * 1.3)
    # 谐波 1..8，高次更快衰减
    harms = [(k, 1.0 / (k ** 1.35), 1.05 / (1 + (k - 1) * 0.42)) for k in range(1, 9)]

    def f(i, t):
        a = 0.0
        for k, am, d in harms:
            fr = base * k
            if fr > SR * 0.45:
                continue
            a += am * math.sin(2 * math.pi * fr * t) * math.exp(-t / d)
        # 拨弦的指甲噪声
        if t < 0.010:
            a += random.uniform(-0.5, 0.5) * math.exp(-t / 0.0028) * 0.7
        a *= min(1.0, t / 0.0012)
        return a * 0.40

    return render(n, f)


if __name__ == '__main__':
    random.seed(20261013)
    os.makedirs(OUT, exist_ok=True)
    jobs = [
        ('ring_chime.wav', make_chime),
        ('ring_wood.wav',  make_wood),
        ('ring_bell.wav',  make_bell),
        ('ring_guqin.wav', make_guqin),
    ]
    for name, fn in jobs:
        p, size = write_wav(name, fn())
        print('%-16s %7d bytes  %s' % (name, size, p))
