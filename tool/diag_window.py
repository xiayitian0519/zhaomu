import ctypes
import subprocess
import sys
from ctypes import wintypes

user32 = ctypes.windll.user32
WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

# 找 chaomu.exe 的 PID
out = subprocess.run(
    ["tasklist", "/FI", "IMAGENAME eq chaomu.exe", "/FO", "CSV", "/NH"],
    capture_output=True, text=True, encoding="gbk", errors="ignore",
).stdout.strip()
pids = set()
for line in out.splitlines():
    parts = [p.strip('"') for p in line.split('","')]
    if len(parts) >= 2 and parts[1].isdigit():
        pids.add(int(parts[1]))
print("pids:", pids)
if not pids:
    sys.exit(1)

found = []


def cb(hwnd, _):
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    if pid.value in pids:
        n = user32.GetWindowTextLengthW(hwnd)
        buf = ctypes.create_unicode_buffer(n + 1)
        user32.GetWindowTextW(hwnd, buf, n + 1)
        rect = wintypes.RECT()
        user32.GetWindowRect(hwnd, ctypes.byref(rect))
        found.append({
            "hwnd": hwnd,
            "title": buf.value,
            "visible": bool(user32.IsWindowVisible(hwnd)),
            "size": (rect.right - rect.left, rect.bottom - rect.top),
            "class": _class_of(hwnd),
        })
    return True


def _class_of(hwnd):
    cls = ctypes.create_unicode_buffer(256)
    user32.GetClassNameW(hwnd, cls, 256)
    return cls.value


user32.EnumWindows(WNDENUMPROC(cb), 0)
for f in found:
    print(f)
if not found:
    print("NO_TOPLEVEL_WINDOW")
