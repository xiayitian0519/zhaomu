# -*- coding: utf-8 -*-
"""按窗口内相对坐标点朝暮窗口，用 PostMessage 投递鼠标消息。

为什么不用真实鼠标：调试期间别的窗口（小程序开发者工具全屏）压在上面，
真实点击会打到人家的窗口上。PostMessage 直接把消息塞给 Flutter 的子窗口，
不管被谁挡着都不影响。

用法：
    python tool/tap_win.py 0.45 0.347
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

top = []


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
    if cls.value == "FLUTTER_RUNNER_WIN32_WINDOW" and buf.value == "朝暮":
        top.append(hwnd)
    return True


user32.EnumWindows(WNDENUMPROC(enum_cb), 0)
if not top:
    raise SystemExit("找不到朝暮窗口")
hwnd = top[0]

# Flutter 真正吃鼠标消息的是它的子窗口，先找 FLUTTERVIEW
target = []
CHILDPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)


def child_cb(h, _):
    cls = ctypes.create_unicode_buffer(256)
    user32.GetClassNameW(h, cls, 256)
    if cls.value == "FLUTTERVIEW":
        target.append(h)
    return True


user32.EnumChildWindows(hwnd, CHILDPROC(child_cb), 0)
tgt = target[0] if target else hwnd

rect = wintypes.RECT()
user32.GetClientRect(tgt, ctypes.byref(rect))
cw, ch = rect.right - rect.left, rect.bottom - rect.top

fx, fy = float(sys.argv[1]), float(sys.argv[2])
x, y = int(fx * cw), int(fy * ch)

lparam = (y << 16) | (x & 0xFFFF)
user32.PostMessageW(tgt, 0x0200, 0, lparam)          # WM_MOUSEMOVE
time.sleep(0.05)
user32.PostMessageW(tgt, 0x0201, 0x0001, lparam)     # WM_LBUTTONDOWN
time.sleep(0.08)
user32.PostMessageW(tgt, 0x0202, 0, lparam)          # WM_LBUTTONUP
print("tap (%.3f, %.3f) -> client (%d,%d)  size %dx%d" % (fx, fy, x, y, cw, ch))
