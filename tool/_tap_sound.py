"""启动 → 点某一项 → 截图 → 读 json 验证。全程一个进程内完成。

用法：python tool/_tap_sound.py <out.png> <fx> <fy> [启动参数...]
fx / fy 是相对客户区的比例（0~1），例如点第 2 行用 0.3 0.12。
"""
import ctypes
import json
import os
import subprocess
import sys
import time
from ctypes import wintypes

from PIL import ImageGrab

# 让 Python 自身按物理像素工作，不然后面算出来的坐标会被系统再缩一次
try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
except Exception:
    ctypes.windll.user32.SetProcessDPIAware()

EXE = r"D:\workbuddy01\chaomu\build\windows\x64\runner\Release\chaomu.exe"
WORKDIR = r"D:\workbuddy01\chaomu\build\windows\x64\runner\Release"
DATA = os.path.expanduser(r"~\Documents\chaomu\chaomu.json")

out = sys.argv[1]
fx = float(sys.argv[2])
fy = float(sys.argv[3])
args = sys.argv[4:] or ["--sound"]

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


def before():
    if not os.path.exists(DATA):
        return {}
    try:
        with open(DATA, encoding="utf-8") as f:
            d = json.load(f)
        return {
            "defaultSoundId": d.get("defaultSoundId", "<无>"),
            "soundIds": [t.get("soundId", "") for t in d.get("todos", [])][:5],
        }
    except Exception as e:
        return {"err": str(e)}


proc = subprocess.Popen([EXE] + args, cwd=WORKDIR)
print(f"pid={proc.pid} args={args}")
print("点击前 json：", before())

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

def fg_title():
    h = user32.GetForegroundWindow()
    n = user32.GetWindowTextLengthW(h)
    b = ctypes.create_unicode_buffer(n + 1)
    user32.GetWindowTextW(h, b, n + 1)
    return b.value

print("置前之前的前台窗口：", repr(fg_title()))
# Alt 键敲一下再 SetForegroundWindow：绕开「非用户操作不许抢前台」的限制
user32.keybd_event(0x12, 0, 0, 0)
user32.keybd_event(0x12, 0, 2, 0)
user32.SetForegroundWindow(hwnd)
print("置前之后的前台窗口：", repr(fg_title()))
ctypes.windll.user32.SwitchToThisWindow(hwnd, True)
time.sleep(1.5)

img = ImageGrab.grab(window=hwnd)
img.save(out)
print(f"shot1 {out} {img.size[0]}x{img.size[1]}")

# ⚠️ 不能用 ClientToScreen：PrintWindow 抓的是**整个窗口**（含标题栏），
# 客户区原点比窗口左上角低了标题栏那 60 多像素，用客户区算会整体偏上，
# 结果点到上一行去（2026-10-25 因此误勾了一条待办）。
# 直接拿窗口 rect 做线性映射，截图坐标 = 窗口内坐标。
wr = wintypes.RECT()
user32.GetWindowRect(hwnd, ctypes.byref(wr))
ww, wh = wr.right - wr.left, wr.bottom - wr.top
print(f"window {ww}x{wh} at ({wr.left},{wr.top}) img={img.size[0]}x{img.size[1]}")

sx = wr.left + int(img.size[0] * fx)
sy = wr.top + int(img.size[1] * fy)
print(f"click at ({sx},{sy}) 目标窗口内=({int(img.size[0]*fx)},{int(img.size[1]*fy)})")

# 用 SendInput（mouse_event 已废弃，部分窗口会忽略）。
# 第一次点击只负责激活窗口，第二次才是真正点在控件上。
import ctypes as _c


class MOUSEINPUT(_c.Structure):
    _fields_ = [('dx', _c.c_long), ('dy', _c.c_long), ('mouseData', _c.c_ulong),
                ('dwFlags', _c.c_ulong), ('time', _c.c_ulong),
                ('dwExtraInfo', _c.POINTER(_c.c_ulong))]


class INPUT(_c.Structure):
    class _U(_c.Union):
        _fields_ = [('mi', MOUSEINPUT)]
    _anonymous_ = ('u',)
    _fields_ = [('type', _c.c_ulong), ('u', _U)]


def click_now(px, py):
    user32.SetCursorPos(px, py)
    time.sleep(0.25)
    for flag in (0x0002, 0x0004):
        inp = INPUT()
        inp.type = 0
        inp.mi = MOUSEINPUT(0, 0, 0, flag, 0, None)
        user32.SendInput(1, _c.byref(inp), _c.sizeof(INPUT))
        time.sleep(0.06)


for _ in range(2):
    click_now(sx, sy)
    time.sleep(1.0)
time.sleep(2.0)

img2 = ImageGrab.grab(window=hwnd)
out2 = out.replace(".png", "-after.png")
img2.save(out2)
print(f"shot2 {out2}")

time.sleep(1.0)
print("点击后 json：", before())

proc.kill()
print("killed")
