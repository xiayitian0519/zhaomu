"""启动 → 等更新弹窗 → 用键盘操作 → 截图 + 查存档。

鼠标点击送不进 Flutter 窗口（连 hover 高亮都没有），改试键盘。
用法：python tool/_key_upd.py <out.png> <键1> [键2] ...
键名：tab / enter / esc / space
"""
import ctypes
import json
import os
import subprocess
import sys
import time
from ctypes import wintypes

from PIL import ImageGrab

try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
except Exception:
    ctypes.windll.user32.SetProcessDPIAware()

EXE = r"D:\workbuddy01\chaomu\build\windows\x64\runner\Release\chaomu.exe"
WORKDIR = r"D:\workbuddy01\chaomu\build\windows\x64\runner\Release"
DATA = os.path.expanduser(r"~\Documents\chaomu\chaomu.json")

KEYS = {'tab': 0x09, 'enter': 0x0D, 'esc': 0x1B, 'space': 0x20,
        'left': 0x25, 'up': 0x26, 'right': 0x27, 'down': 0x28}

out = sys.argv[1]
keys = sys.argv[2:]

user32 = ctypes.windll.user32


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [('wVk', ctypes.c_ushort), ('wScan', ctypes.c_ushort),
                ('dwFlags', ctypes.c_ulong), ('time', ctypes.c_ulong),
                ('dwExtraInfo', ctypes.POINTER(ctypes.c_ulong))]


class INPUT(ctypes.Structure):
    class _U(ctypes.Union):
        _fields_ = [('ki', KEYBDINPUT)]
    _anonymous_ = ('u',)
    _fields_ = [('type', ctypes.c_ulong), ('u', _U)]


def key(vk):
    for flag in (0, 2):  # 0 = KEYDOWN, 2 = KEYUP
        inp = INPUT()
        inp.type = 1
        inp.ki = KEYBDINPUT(vk, 0, flag, 0, None)
        user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))
        time.sleep(0.05)


CB = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)


def find_window(want="朝暮"):
    hit = []

    def cb(h, _):
        if not user32.IsWindowVisible(h):
            return True
        n = user32.GetWindowTextLengthW(h)
        if n == 0:
            return True
        b = ctypes.create_unicode_buffer(n + 1)
        user32.GetWindowTextW(h, b, n + 1)
        if want in b.value:
            hit.append(h)
        return True

    user32.EnumWindows(CB(cb), 0)
    return hit[0] if hit else None


def seen():
    if not os.path.exists(DATA):
        return '<无文件>'
    try:
        d = json.load(open(DATA, encoding='utf-8'))
        return repr(d.get('lastSeenVersion'))
    except Exception as e:
        return f'<读不了 {e}>'


print('点击前 lastSeenVersion =', seen())
proc = subprocess.Popen([EXE], cwd=WORKDIR)

hwnd = None
for _ in range(40):
    time.sleep(0.5)
    hwnd = find_window()
    if hwnd:
        break
if not hwnd:
    print('NO_WINDOW')
    proc.kill()
    sys.exit(1)

user32.ShowWindow(hwnd, 9)
user32.keybd_event(0x12, 0, 0, 0)
user32.keybd_event(0x12, 0, 2, 0)
user32.SetForegroundWindow(hwnd)
time.sleep(3.5)  # 等弹窗动画结束

for k in keys:
    vk = KEYS.get(k.lower())
    if vk is None:
        print(f'未知键 {k}')
        continue
    print(f'按键 {k}')
    key(vk)
    time.sleep(1.2)

time.sleep(1.5)
img = ImageGrab.grab(window=hwnd)
img.save(out)
print(f'saved {out} {img.size[0]}x{img.size[1]}')
print('操作后 lastSeenVersion =', seen())

proc.kill()
print('killed')
