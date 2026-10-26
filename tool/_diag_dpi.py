# -*- coding: utf-8 -*-
"""把坐标体系一次查清：屏幕分辨率、DPI 缩放、窗口 rect、客户区 rect。

只用于验证，不进产物。
"""
import ctypes
from ctypes import wintypes

u = ctypes.windll.user32

# 先不声明 DPI aware，看系统报什么
print(f"屏幕(虚拟化)  {u.GetSystemMetrics(0)}x{u.GetSystemMetrics(1)}")

try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
    print("DPI aware 设置成功 = per-monitor v2")
except Exception as e:
    print(f"DPI aware 失败: {e}")

print(f"屏幕(真实)    {u.GetSystemMetrics(0)}x{u.GetSystemMetrics(1)}")

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
    raise SystemExit(1)

hwnd = found[0]
wr = wintypes.RECT()
u.GetWindowRect(hwnd, ctypes.byref(wr))
cr = wintypes.RECT()
u.GetClientRect(hwnd, ctypes.byref(cr))
pt = wintypes.POINT(0, 0)
u.ClientToScreen(hwnd, ctypes.byref(pt))

try:
    dpi = ctypes.windll.user32.GetDpiForWindow(hwnd)
except Exception:
    dpi = 0

print(f"DPI for window = {dpi}  (96 = 100%, 144 = 150%, 192 = 200%)")
print(f"窗口 rect      {wr.right - wr.left}x{wr.bottom - wr.top} at ({wr.left},{wr.top})")
print(f"客户区 rect    {cr.right}x{cr.bottom}")
print(f"客户区屏幕原点 ({pt.x},{pt.y})")
print(f"系统度量 SM_CXSIZEFRAME={u.GetSystemMetrics(32)} SM_CYSIZEFRAME={u.GetSystemMetrics(33)} "
      f"SM_CYCAPTION={u.GetSystemMetrics(4)}")
