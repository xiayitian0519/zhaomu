import ctypes
import sys
import time
from ctypes import wintypes

from PIL import ImageGrab

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
    title = buf.value
    if "朝暮" in title or "chaomu" in title.lower():
        rect = wintypes.RECT()
        user32.GetWindowRect(hwnd, ctypes.byref(rect))
        w = rect.right - rect.left
        h = rect.bottom - rect.top
        if w > 100 and h > 100:
            targets.append((hwnd, title, rect, w, h))
    return True


user32.EnumWindows(WNDENUMPROC(enum_cb), 0)

if not targets:
    print("NO_WINDOW")
    sys.exit(1)

hwnd, title, rect, w, h = targets[0]
print(f"window: {title} {w}x{h} at ({rect.left},{rect.top})")

# 置前再截，避免被别的窗口盖住
user32.ShowWindow(hwnd, 9)  # SW_RESTORE
user32.SetForegroundWindow(hwnd)
ctypes.windll.user32.SwitchToThisWindow(hwnd, True)
time.sleep(1.0)

out = sys.argv[1] if len(sys.argv) > 1 else "shot_win.png"
# 优先用 PrintWindow 直接抓窗口内容：窗口即使被别的窗口盖住也能抓到真画面
try:
    img = ImageGrab.grab(window=hwnd)
    print("mode: PrintWindow")
except Exception as e:  # 老版本 Pillow 不支持 window 参数
    print(f"PrintWindow 不可用({e})，退回区域截图")
    img = ImageGrab.grab(bbox=(rect.left, rect.top, rect.right, rect.bottom))

img.save(out)
print(f"saved {out} {img.size[0]}x{img.size[1]}")
