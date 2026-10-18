import ctypes
import subprocess
import sys
import time
from ctypes import wintypes

# 关键：不声明 DPI aware 的话，系统会把坐标虚拟化，
# GetWindowRect 和 SetCursorPos 拿到的不是同一套数字，点击就会点偏。
try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)  # PER_MONITOR_AWARE
except Exception:
    ctypes.windll.user32.SetProcessDPIAware()

user32 = ctypes.windll.user32
WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)


def find_window():
    out = subprocess.run(
        ["tasklist", "/FI", "IMAGENAME eq chaomu.exe", "/FO", "CSV", "/NH"],
        capture_output=True, text=True, encoding="gbk", errors="ignore",
    ).stdout
    pids = set()
    for line in out.splitlines():
        parts = [p.strip('"') for p in line.split('","')]
        if len(parts) >= 2 and parts[1].isdigit():
            pids.add(int(parts[1]))
    if not pids:
        return None, None
    hits = []

    def cb(hwnd, _):
        pid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value in pids:
            cls = ctypes.create_unicode_buffer(256)
            user32.GetClassNameW(hwnd, cls, 256)
            if cls.value == "FLUTTER_RUNNER_WIN32_WINDOW":
                r = wintypes.RECT()
                user32.GetWindowRect(hwnd, ctypes.byref(r))
                hits.append((hwnd, r))
        return True

    user32.EnumWindows(WNDENUMPROC(cb), 0)
    if not hits:
        return None, pids
    return hits[0], pids


win, pids = find_window()
if win is None:
    print(f"NO_WINDOW pids={pids}")
    sys.exit(1)

hwnd, r = win
print(f"rect=({r.left},{r.top})-({r.right},{r.bottom}) size={r.right - r.left}x{r.bottom - r.top}")

action = sys.argv[1] if len(sys.argv) > 1 else "info"

if action == "restore":
    user32.ShowWindow(hwnd, 9)  # SW_RESTORE
    time.sleep(0.6)
    user32.GetWindowRect(hwnd, ctypes.byref(r))
    print(f"restored size={r.right - r.left}x{r.bottom - r.top}")

elif action == "close":
    # 标题栏关闭按钮：物理像素下按钮约 46px 宽（200% DPI 时约 90px）
    dpi = user32.GetDpiForWindow(hwnd) if hasattr(user32, "GetDpiForWindow") else 96
    scale = dpi / 96.0
    btn_w = int(46 * scale)
    x = r.right - btn_w // 2 - int(6 * scale)
    y = r.top + int(16 * scale)
    print(f"dpi={dpi} scale={scale:.2f} click=({x},{y})")
    user32.SetCursorPos(x, y)
    time.sleep(0.3)
    user32.mouse_event(0x0002, 0, 0, 0, 0)
    time.sleep(0.08)
    user32.mouse_event(0x0004, 0, 0, 0, 0)
