"""从 CHANGELOG.md 生成 lib/updates_gen.dart（更新弹窗用的内置数据）。

为什么要有这一步：以前 kUpdates 是手写的，CHANGELOG 改了这里忘了改，
结果「版本变了但没条目」→ 弹窗被静默跳过（2.19.0、2.21.0 都栽过）。
现在只写 CHANGELOG 一处，打包前跑一遍这个脚本就不会漏。

用法：
    python tool/gen_updates.py            # 生成
    python tool/gen_updates.py --check    # 只检查，不写文件（版本对不上时退出码 1）

抽哪几版：2.13.0 及以后（2026-10-17 用户定的「更早不列」）。
每版只取第一个 ### 小节里的顶层编号条目，最多 5 条；
子项（缩进的 - xxx）、改动文件、验证步骤那些不进取。
"""

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHANGELOG = os.path.join(ROOT, 'CHANGELOG.md')
OUT = os.path.join(ROOT, 'lib', 'updates_gen.dart')
PUBSPEC = os.path.join(ROOT, 'pubspec.yaml')

# 从这里开始收，更早的版本不进更新日志
MIN_VERSION = (2, 13, 0)
MAX_ITEMS = 5

# `## 2.21.0+41 — 2026-10-25`（破折号可能写成 - 或 —）
HEADER = re.compile(
    r'^([0-9]+\.[0-9]+\.[0-9]+)\+?([0-9]+)?\s*[-—–]\s*([0-9]{4}-[0-9]{2}-[0-9]{2})'
)


def ver_tuple(v):
    parts = v.split('.')
    return tuple(int(p) if p.isdigit() else 0 for p in parts[:3])


def clean(text):
    s = text.strip()
    s = s.replace('**', '').replace('`', '')
    s = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', s)  # [文字](链接) -> 文字
    s = re.sub(r'\s+', ' ', s)
    return s.strip(' :：')


def parse():
    text = io.open(CHANGELOG, encoding='utf-8').read()
    blocks = re.split(r'(?m)^## ', text)[1:]

    out = []
    for b in blocks:
        lines = b.splitlines()
        if not lines:
            continue
        m = HEADER.match(lines[0].strip())
        if not m:
            continue
        ver, _build, date = m.group(1), m.group(2), m.group(3)
        if ver_tuple(ver) < MIN_VERSION:
            continue

        body = lines[1:]
        # 优先用「### 更新摘要」—— 那段是专门写给用户看的人话。
        # 没有的话退回第一个 ### 小节（技术细节，质量差但至少有内容）。
        seg = []
        started = False
        for ln in body:
            if ln.startswith('### '):
                if started:
                    break
                started = True
                continue
            if started:
                seg.append(ln)
        summary = []
        grab = False
        for ln in body:
            if ln.startswith('### '):
                grab = '更新摘要' in ln
                continue
            if grab:
                summary.append(ln)
        if summary:
            seg = summary
        if not seg:
            seg = body

        items = []
        for ln in seg:
            s = ln.strip()
            m2 = re.match(r'^(?:\d+\.|-)\s+', s)
            if not m2:
                continue
            # 缩进的子项（   - xxx）不算，那是细节
            if ln[:1] in (' ', '\t') and ln.lstrip().startswith('-'):
                continue
            t = clean(s[m2.end():])
            if t:
                items.append(t)
            if len(items) >= MAX_ITEMS:
                break

        if not items:
            continue
        out.append((ver, date, items))
    return out


def dart_str(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$') + "'"


def render(entries):
    buf = []
    buf.append('// 这个文件由 tool/gen_updates.py 自动生成，不要手改。')
    buf.append('// 要改内容请改 CHANGELOG.md，然后重新跑一次生成脚本。')
    buf.append('// ignore_for_file: prefer_single_quotes')
    buf.append('')
    buf.append("import 'update_model.dart';")
    buf.append('')
    buf.append('const List<AppUpdate> kUpdatesGenerated = <AppUpdate>[')
    for ver, date, items in entries:
        buf.append(f"  AppUpdate('{ver}', '{date}', <String>[")
        for it in items:
            buf.append(f'    {dart_str(it)},')
        buf.append('  ]),')
    buf.append('];')
    buf.append('')
    return '\n'.join(buf)


def pubspec_version():
    s = io.open(PUBSPEC, encoding='utf-8').read()
    m = re.search(r'(?m)^version:\s*([0-9.]+)\+([0-9]+)', s)
    return (m.group(1), m.group(2)) if m else (None, None)


def main():
    entries = parse()
    if not entries:
        print('没抽到任何条目，检查 CHANGELOG 格式')
        return 1

    ver_name, build = pubspec_version()
    latest = entries[0][0]
    ok = True
    if ver_name and ver_name != latest:
        print(f'⚠️  pubspec 版本 {ver_name} 和 CHANGELOG 最新段 {latest} 不一致')
        ok = False

    if '--check' in sys.argv:
        if ok:
            print(f'✓ 最新段 {latest} 与 pubspec 一致，共 {len(entries)} 个版本')
        return 0 if ok else 1

    io.open(OUT, 'w', encoding='utf-8').write(render(entries))
    size = os.path.getsize(OUT)
    print(f'已写 {OUT}（{size} 字节）')
    print(f'共 {len(entries)} 个版本：' + ' / '.join(v for v, _, _ in entries[:6]) + ' ...')
    for ver, date, items in entries[:3]:
        print(f'  {ver}（{date}）{len(items)} 条')
        for it in items:
            print(f'    · {it[:60]}{"…" if len(it) > 60 else ""}')
    if not ok:
        print(f'⚠️  pubspec 是 {ver_name}+{build}，最新段是 {latest} —— 记得对齐')
    return 0


if __name__ == '__main__':
    sys.exit(main())
