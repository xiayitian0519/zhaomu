# -*- coding: utf-8 -*-
"""把朝暮窗口里的列表滚到最顶，方便截主页第一屏。

只用于截图验证，不进产物。
"""
import ctypes
import sys
import time
from ctypes import wintypes

# 不声明 DPI aware 的话系统会把坐标虚拟化，指针落点和窗口实际位置对不上
try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
except Exception:
    ctypes.windll.user32.SetProcessDPIAware()

user32 = ctypes.windll.user32
WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

targets = []


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
    if cls.value == "FLUTTER_RUNNER_WIN32_WINDOW" and "朝暮" in buf.value:
        rect = wintypes.RECT()
        user32.GetWindowRect(hwnd, ctypes.byref(rect))
        targets.append((hwnd, rect))
    return True


user32.EnumWindows(WNDENUMPROC(enum_cb), 0)
if not targets:
    print("NO_WINDOW")
    sys.exit(1)

hwnd, rect = targets[0]
user32.ShowWindow(hwnd, 9)  # SW_RESTORE
user32.SetForegroundWindow(hwnd)
time.sleep(0.6)

cx = (rect.left + rect.right) // 2
cy = (rect.top + rect.bottom) // 2
user32.SetCursorPos(cx, cy)
time.sleep(0.2)

# MOUSEEVENTF_WHEEL = 0x0800，正 delta 是向上滚
for _ in range(60):
    user32.mouse_event(0x0800, 0, 0, 120, 0)
    time.sleep(0.01)
time.sleep(0.8)
print(f"scrolled at ({cx},{cy})")
