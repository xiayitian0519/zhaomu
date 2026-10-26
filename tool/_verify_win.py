# -*- coding: utf-8 -*-
"""实测标题栏那两个新按钮：点「−」窗口该最小化，点「×」窗口该隐藏（收托盘）。

坐标不靠猜：先拿客户区原点（ClientToScreen）+ 客户区尺寸，
再把 834x1729 那张截图里的像素位置按比例映射到屏幕上。

只用于验证，不进产物。
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
        targets.append(hwnd)
    return True


user32.EnumWindows(WNDENUMPROC(enum_cb), 0)
if not targets:
    print("NO_WINDOW")
    sys.exit(1)

hwnd = targets[0]

wr = wintypes.RECT()
user32.GetWindowRect(hwnd, ctypes.byref(wr))
cr = wintypes.RECT()
user32.GetClientRect(hwnd, ctypes.byref(cr))
origin = wintypes.POINT(0, 0)
user32.ClientToScreen(hwnd, ctypes.byref(origin))

cw, ch = cr.right, cr.bottom
print(f"window  rect {wr.right - wr.left}x{wr.bottom - wr.top} at ({wr.left},{wr.top})")
print(f"client  rect {cw}x{ch} origin ({origin.x},{origin.y})")

# 截图 shot-home3.png 是 834x1729，就是客户区；按比例折算到屏幕
SHOT_W, SHOT_H = 834, 1729


def shot_to_screen(sx, sy):
    return (
        origin.x + int(sx * cw / SHOT_W),
        origin.y + int(sy * ch / SHOT_H),
    )


def click(px, py):
    """点两次：第一下可能只用来把窗口拉到前台（Windows 前台锁），
    第二下才真正落到按钮上。"""
    user32.SetCursorPos(px, py)
    time.sleep(0.35)
    for _ in range(2):
        user32.mouse_event(0x0002, 0, 0, 0, 0)
        time.sleep(0.08)
        user32.mouse_event(0x0004, 0, 0, 0, 0)
        time.sleep(0.45)
    time.sleep(0.9)


# 截图里：「−」中心 (455,36)，「×」中心 (502,36)
x_min, y_bar = shot_to_screen(455, 36)
x_close, _ = shot_to_screen(502, 36)
print(f"map   最小化=({x_min},{y_bar})  关闭=({x_close},{y_bar})")

user32.SetForegroundWindow(hwnd)
time.sleep(0.5)

click(x_min, y_bar)
print(f"[1] 点「−」-> IsIconic={bool(user32.IsIconic(hwnd))}")

user32.ShowWindow(hwnd, 9)  # SW_RESTORE
time.sleep(1.2)
user32.SetForegroundWindow(hwnd)
time.sleep(0.6)
print(f"[2] 恢复 -> IsIconic={bool(user32.IsIconic(hwnd))}")

click(x_close, y_bar)
time.sleep(1.3)
print(
    f"[3] 点「×」-> IsWindowVisible={bool(user32.IsWindowVisible(hwnd))} "
    f"IsIconic={bool(user32.IsIconic(hwnd))}"
)
