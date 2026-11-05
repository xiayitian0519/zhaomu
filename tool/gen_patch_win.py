# -*- coding: utf-8 -*-
"""生成 Android / Windows 的增量补丁。

用法：
    python tool/gen_patch_win.py 2.27.10

Windows 版补丁命名 `<旧>-to-<新>-win.patch`，对的是 zip 包；
安卓那份仍叫 `<旧>-to-<新>.patch`，对的是 APK。
两者不能重名，否则 App 会拿错平台的文件去合成。

实测：14.2 MB 的 zip 差分出来 3.6 MB，省 75%。
"""
import hashlib
import os
import re
import sys

import bsdiff4

PC_DIR = r'C:\Users\18814\Desktop\朝暮\电脑安装包'


def ver_key(v):
    return [int(x) for x in v.split('.')]


def main():
    if len(sys.argv) < 2:
        raise SystemExit('用法：python tool/gen_patch_win.py 2.27.10')
    new_ver = sys.argv[1]
    new_path = os.path.join(PC_DIR, '朝暮-%s-windows.zip' % new_ver)
    if not os.path.isfile(new_path):
        raise SystemExit('找不到 %s' % new_path)

    olds = []
    for f in os.listdir(PC_DIR):
        m = re.match(r'^朝暮-([\d.]+)-windows\.zip$', f)
        if not m or m.group(1) == new_ver:
            continue
        olds.append(m.group(1))
    olds.sort(key=ver_key, reverse=True)
    if not olds:
        raise SystemExit('电脑安装包目录里没有旧版 zip，做不了差分')

    new_bytes = open(new_path, 'rb').read()
    print('新包 %s  %.2f MB' % (new_ver, len(new_bytes) / 1048576))

    made = []
    for old_ver in olds[:3]:
        out = os.path.join(PC_DIR, '%s-to-%s-win.patch' % (old_ver, new_ver))
        if os.path.isfile(out):
            print('已存在 %s' % os.path.basename(out))
            continue
        old_bytes = open(
            os.path.join(PC_DIR, '朝暮-%s-windows.zip' % old_ver), 'rb'
        ).read()
        patch = bsdiff4.diff(old_bytes, new_bytes)
        open(out, 'wb').write(patch)
        ok = hashlib.sha256(bsdiff4.patch(old_bytes, patch)).hexdigest() == \
            hashlib.sha256(new_bytes).hexdigest()
        print('%s → %s  %.2f MB  省 %.0f%%  合成一致=%s' % (
            old_ver, new_ver, len(patch) / 1048576,
            100 - len(patch) * 100 / len(new_bytes), ok))
        made.append(out)

    if not made:
        print('没有新生成的补丁')


if __name__ == '__main__':
    main()
