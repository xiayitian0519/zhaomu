# -*- coding: utf-8 -*-
"""build_apk.sh 产物改成固定名 zhaomu.apk（用户 2026-10-16 要求）+ 同步工程记忆"""
import io

SH = r'D:\chaomu\tool\build_apk.sh'
MEM = r'D:\workbuddy01\2026-10-12-09-19-32\.workbuddy\memory\MEMORY.md'

# ---- build_apk.sh：VERSION 拼名 -> 固定名 ----
with io.open(SH, 'r', encoding='utf-8') as f:
    sh = f.read()
old = u"""VERSION="$(grep -E '^version:' pubspec.yaml | awk '{print $2}')"
OUT="朝暮-${VERSION}.apk\""""
new = u'OUT="zhaomu.apk"   # 固定名（用户 2026-10-16 要求），版本号以 aapt2 查包为准'
assert sh.count(old) == 1, 'build_apk.sh 命名段不是唯一命中: %d' % sh.count(old)
with io.open(SH, 'w', encoding='utf-8', newline='') as f:
    f.write(sh.replace(old, new))
print('build_apk.sh: OUT 固定为 zhaomu.apk')

# ---- MEMORY.md：同步这条约定 ----
with io.open(MEM, 'r', encoding='utf-8') as f:
    mem = f.read()
old2 = u'打包：`bash tool/build_apk.sh`（同步版本号 → gradle → 核验版本号+铃声 → 复制成 `朝暮-<版本>.apk`）'
new2 = u'打包：`bash tool/build_apk.sh`（同步版本号 → gradle → 核验版本号+铃声 → 复制成**固定名 `zhaomu.apk`**，用户 2026-10-16 要求不带中文和版本号，版本以 aapt2 查包为准）'
assert mem.count(old2) == 1, 'MEMORY.md 打包行不是唯一命中: %d' % mem.count(old2)
with io.open(MEM, 'w', encoding='utf-8', newline='') as f:
    f.write(mem.replace(old2, new2))
print('MEMORY.md: 打包产物名约定已更新')
print('DONE')
