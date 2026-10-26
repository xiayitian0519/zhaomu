"""启动 chaomu.exe 并抓它的窗口，一条命令内完成（GUI 进程离开会话会被回收）。

用法：python tool/_shot_sound.py <输出png> [启动参数...]
"""
import ctypes
import subprocess
import sys
import time
from ctypes import wintypes

from PIL import ImageGrab

EXE = r"D:\workbuddy01\chaomu\build\windows\x64\runner\Release\chaomu.exe"
WORKDIR = r"D:\workbuddy01\chaomu\build\windows\x64\runner\Release"

out = sys.argv[1]
args = sys.argv[2:] or ["--sound"]

user32 = ctypes.windll.user32
CB = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)


def windows():
    res = []
    u = user32

    def cb(h, _):
        if not u.IsWindowVisible(h):
            return True
        n = u.GetWindowTextLengthW(h)
        if n == 0:
            return True
        b = ctypes.create_unicode_buffer(n + 1)
        u.GetWindowTextW(h, b, n + 1)
        c = ctypes.create_unicode_buffer(256)
        u.GetClassNameW(h, c, 256)
        r = wintypes.RECT()
        u.GetWindowRect(h, ctypes.byref(r))
        res.append((h, b.value, c.value, r))
        return True

    u.EnumWindows(CB(cb), 0)
    return res


proc = subprocess.Popen([EXE] + args, cwd=WORKDIR)
print(f"pid={proc.pid} args={args}")

hwnd = None
for i in range(40):
    time.sleep(0.5)
    for h, title, cls, r in windows():
        w = r.right - r.left
        hh = r.bottom - r.top
        if w > 200 and hh > 200 and "FLUTTER" in cls.upper():
            hwnd = h
            print(f"found: {title!r} cls={cls} {w}x{hh} at ({r.left},{r.top})")
            break
    if hwnd:
        break

if not hwnd:
    print("NO_WINDOW; 当前可见窗口：")
    for h, title, cls, r in windows():
        w, hh = r.right - r.left, r.bottom - r.top
        if w > 200 and hh > 200:
            print(f"  {title!r} | {cls} | {w}x{hh}")
    proc.kill()
    sys.exit(1)

user32.ShowWindow(hwnd, 9)
user32.SetForegroundWindow(hwnd)
ctypes.windll.user32.SwitchToThisWindow(hwnd, True)
time.sleep(1.5)

img = ImageGrab.grab(window=hwnd)
img.save(out)
print(f"saved {out} {img.size[0]}x{img.size[1]}")

time.sleep(0.3)
proc.kill()
print("killed")
