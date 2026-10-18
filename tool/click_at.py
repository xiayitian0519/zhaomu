import ctypes
import sys
import time

# 必须 DPI aware：否则 SetCursorPos 收到的是被虚拟化的坐标，点不中
try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
except Exception:
    ctypes.windll.user32.SetProcessDPIAware()

x, y = int(sys.argv[1]), int(sys.argv[2])
u = ctypes.windll.user32
u.SetCursorPos(x, y)
time.sleep(0.25)
u.mouse_event(0x0002, 0, 0, 0, 0)
time.sleep(0.06)
u.mouse_event(0x0004, 0, 0, 0, 0)
print(f"clicked ({x},{y})")
