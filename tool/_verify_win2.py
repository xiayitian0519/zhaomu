# -*- coding: utf-8 -*-
"""把窗口先挪到屏幕左上角固定住，再点「−」和「×」。

窗口位置固定后坐标唯一的变量就只剩 DPI 映射，点了有没有反应一眼能看出来。

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

u = ctypes.windll.user32
WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
found = []


def cb(hwnd, _):
    if not u.IsWindowVisible(hwnd):
        return True
    n = u.GetWindowTextLengthW(hwnd)
    if n == 0:
        return True
    b = ctypes.create_unicode_buffer(n + 1)
    u.GetWindowTextW(hwnd, b, n + 1)
    c = ctypes.create_unicode_buffer(256)
    u.GetClassNameW(hwnd, c, 256)
    if c.value == "FLUTTER_RUNNER_WIN32_WINDOW" and "朝暮" in b.value:
        found.append(hwnd)
    return True


u.EnumWindows(WNDENUMPROC(cb), 0)
if not found:
    print("NO_WINDOW")
    sys.exit(1)

hwnd = found[0]

# SWP_NOSIZE=0x0001 SWP_NOZORDER=0x0004 → 只挪位置，尺寸和层级都不动
u.SetWindowPos(hwnd, 0, 0, 0, 0, 0, 0x0001 | 0x0004)
time.sleep(1.0)

wr = wintypes.RECT()
u.GetWindowRect(hwnd, ctypes.byref(wr))
cr = wintypes.RECT()
u.GetClientRect(hwnd, ctypes.byref(cr))
pt = wintypes.POINT(0, 0)
u.ClientToScreen(hwnd, ctypes.byref(pt))
print(f"窗口 {wr.right - wr.left}x{wr.bottom - wr.top} at ({wr.left},{wr.top})")
print(f"客户区 {cr.right}x{cr.bottom} 原点 ({pt.x},{pt.y})")

# 截图 shot-home3.png 是 834x1729，等于客户区尺寸，按 1:1 对应。
# 坐标是在截图上打红圈量出来的：「−」x=732、「×」x=772，标题栏中线 y=52。
sx_min, sy_bar = pt.x + 732, pt.y + 52
sx_close, _ = pt.x + 772, pt.y + 52
print(f"目标 最小化=({sx_min},{sy_bar})  关闭=({sx_close},{sy_bar})")


def click(px, py, times=1):
    u.SetCursorPos(px, py)
    time.sleep(0.4)
    for _ in range(times):
        u.mouse_event(0x0002, 0, 0, 0, 0)
        time.sleep(0.09)
        u.mouse_event(0x0004, 0, 0, 0, 0)
        time.sleep(0.5)
    time.sleep(0.8)


click(sx_min, sy_bar, times=1)
print(f"[1] 点「−」-> IsIconic={bool(u.IsIconic(hwnd))}")

u.ShowWindow(hwnd, 9)
time.sleep(1.2)
print(f"[2] 恢复 -> IsIconic={bool(u.IsIconic(hwnd))}")

u.SetCursorPos(pt.x + 200, sy_bar)  # 先挪开，避免 tooltip 干扰
time.sleep(0.5)
click(sx_close, sy_bar, times=1)
time.sleep(1.2)
print(f"[3] 点「×」-> IsWindowVisible={bool(u.IsWindowVisible(hwnd))}")
