# -*- coding: utf-8 -*-
"""按「窗口内相对坐标」点击朝暮窗口。

用法：
    python tool/click_win.py 0.5 0.42      # 横 50% / 纵 42% 的位置

为什么要相对坐标：截图是 2 倍像素、窗口矩形是逻辑像素，
直接按截图像素点会落到别处。这里统一从窗口矩形算。
"""
import ctypes
import sys
import time
from ctypes import wintypes

try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
except Exception:
    ctypes.windll.user32.SetProcessDPIAware()

user32 = ctypes.windll.user32
WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

found = []


def enum_cb(hwnd, _):
    if not user32.IsWindowVisible(hwnd):
        return True
    n = user32.GetWindowTextLengthW(hwnd)
    if n == 0:
        return True
    buf = ctypes.create_unicode_buffer(n + 1)
    user32.GetWindowTextW(hwnd, buf, n + 1)
    cls = ctypes.create_unicode_buffer(256)
    user32.GetClassNameW(hwnd, cls, 256)
    if cls.value == "FLUTTER_RUNNER_WIN32_WINDOW" and (
        "朝暮" in buf.value or "chaomu" in buf.value.lower()
    ):
        r = wintypes.RECT()
        user32.GetWindowRect(hwnd, ctypes.byref(r))
        found.append((hwnd, r))
    return True


user32.EnumWindows(WNDENUMPROC(enum_cb), 0)
if not found:
    raise SystemExit("找不到朝暮窗口")

hwnd, r = found[0]
w, h = r.right - r.left, r.bottom - r.top
print("window %dx%d at (%d,%d)" % (w, h, r.left, r.top))

fx, fy = float(sys.argv[1]), float(sys.argv[2])
x = int(r.left + fx * w)
y = int(r.top + fy * h)

user32.SetForegroundWindow(hwnd)
time.sleep(0.2)
user32.SetCursorPos(x, y)
time.sleep(0.2)
user32.mouse_event(0x0002, 0, 0, 0, 0)
time.sleep(0.05)
user32.mouse_event(0x0004, 0, 0, 0, 0)
print("clicked (%.2f, %.2f) -> (%d,%d)" % (fx, fy, x, y))
