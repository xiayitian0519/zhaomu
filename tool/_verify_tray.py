# -*- coding: utf-8 -*-
"""找到托盘右键菜单（窗口类 #32768），点它最后一项「退出」。

菜单每次弹的位置跟着托盘图标走，所以不能写死坐标，
要拿菜单自己的窗口矩形来算。

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


def find_menu():
    out = []

    def cb(hwnd, _):
        cls = ctypes.create_unicode_buffer(256)
        u.GetClassNameW(hwnd, cls, 256)
        if cls.value == "#32768" and u.IsWindowVisible(hwnd):
            r = wintypes.RECT()
            u.GetWindowRect(hwnd, ctypes.byref(r))
            if r.right - r.left > 40 and r.bottom - r.top > 20:
                out.append((hwnd, r))
        return True

    u.EnumWindows(WNDENUMPROC(cb), 0)
    return out


menus = find_menu()
if not menus:
    print("NO_MENU")
    sys.exit(1)

hwnd, r = menus[0]
mw, mh = r.right - r.left, r.bottom - r.top
print(f"菜单 {mw}x{mh} at ({r.left},{r.top})")

# 最后一项「退出」：菜单底边往上挪半个菜单项高
px = r.left + mw // 2
py = r.bottom - 16
print(f"点「退出」({px},{py})")

u.SetCursorPos(px, py)
time.sleep(0.5)
u.mouse_event(0x0002, 0, 0, 0, 0)
time.sleep(0.09)
u.mouse_event(0x0004, 0, 0, 0, 0)
time.sleep(2.5)
print("已点击")
