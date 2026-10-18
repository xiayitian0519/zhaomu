import ctypes
import sys
import time

x, y = int(sys.argv[1]), int(sys.argv[2])

user32 = ctypes.windll.user32
user32.SetCursorPos(x, y)
time.sleep(0.3)
# 左键按下 + 抬起
user32.mouse_event(0x0002, 0, 0, 0, 0)
time.sleep(0.08)
user32.mouse_event(0x0004, 0, 0, 0, 0)
print(f"clicked ({x},{y})")
