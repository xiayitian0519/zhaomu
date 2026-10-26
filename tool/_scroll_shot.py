"""启动 → 置前 → 滚轮 → 截图。用来验证长列表页里的某个分组。

用法：python tool/_scroll_shot.py <out.png> <滚轮次数> [启动参数...]
滚轮次数为正 = 向下滚。
"""
import ctypes
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

out = sys.argv[1]
ticks = int(sys.argv[2])
args = sys.argv[3:] or ["--settings"]

user32 = ctypes.windll.user32
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


proc = subprocess.Popen([EXE] + args, cwd=WORKDIR)
print(f"pid={proc.pid} args={args}")

hwnd = None
for _ in range(40):
    time.sleep(0.5)
    hwnd = find_window()
    if hwnd:
        break
if not hwnd:
    print("NO_WINDOW")
    proc.kill()
    sys.exit(1)

user32.ShowWindow(hwnd, 9)
user32.keybd_event(0x12, 0, 0, 0)
user32.keybd_event(0x12, 0, 2, 0)
user32.SetForegroundWindow(hwnd)
time.sleep(1.8)

# 先把光标放到窗口中间，滚轮事件才会落到这个窗口上
cr = wintypes.RECT()
user32.GetClientRect(hwnd, ctypes.byref(cr))
pt = wintypes.POINT(0, 0)
user32.ClientToScreen(hwnd, ctypes.byref(pt))
cx = pt.x + (cr.right - cr.left) // 2
cy = pt.y + min((cr.bottom - cr.top) // 2, 600)
user32.SetCursorPos(cx, cy)
time.sleep(0.4)

for _ in range(ticks):
    # 负数 = 向下滚，120 是一个标准刻度
    user32.mouse_event(0x0800, 0, 0, -120, 0)
    time.sleep(0.18)
time.sleep(1.0)

img = ImageGrab.grab(window=hwnd)
img.save(out)
print(f"saved {out} {img.size[0]}x{img.size[1]}")

proc.kill()
print("killed")
