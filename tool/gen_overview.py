"""把整个工程的源码拼成一份 markdown，供 AI 一次读懂结构。

为什么需要：AI 每次都要逐个文件读，既慢又容易漏。一份全览丢进去就能看懂
目录关系、每个文件多少行、关键注释。

用法：
    python tool/gen_overview.py                 # 生成到 _source_overview.md
    python tool/gen_overview.py <输出路径>
"""

import io
import os
import re
import sys
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 收哪些非 dart 文件（配置文件对理解工程同样关键）
EXTRA = [
    'pubspec.yaml',
    'android/app/build.gradle.kts',
    'android/gradle.properties',
    'android/app/src/main/kotlin/com/xiayitian/chaomu/MainActivity.kt',
    'windows/runner/main.cpp',
]


def read(path):
    return io.open(os.path.join(ROOT, path), encoding='utf-8').read()


def lines_of(path):
    return read(path).count('\n') + 1


def collect_dart():
    out = []
    for base, dirs, files in os.walk(os.path.join(ROOT, 'lib')):
        dirs.sort()
        for f in sorted(files):
            if f.endswith('.dart'):
                full = os.path.join(base, f)
                rel = os.path.relpath(full, ROOT).replace('\\', '/')
                out.append(rel)
    # lib 根目录的排前面，pages 后面的按字母
    out.sort(key=lambda p: (p.count('/'), p))
    return out


def pubspec_version():
    m = re.search(r'(?m)^version:\s*(.+)$', read('pubspec.yaml'))
    return m.group(1).strip() if m else '未知'


def fence_for(text):
    """正文里出现三个反引号就加长围栏，避免把代码块提前截断。"""
    n = 3
    while '`' * n in text:
        n += 1
    return '`' * n


def section(path, lang):
    text = read(path)
    body = text.rstrip('\n')
    fence = fence_for(body)
    return (
        f'## {path}（{lines_of(path)} 行）\n\n'
        f'{fence}{lang}\n{body}\n{fence}\n\n'
    )


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, '_source_overview.md')

    dart = collect_dart()
    extras = [p for p in EXTRA if os.path.exists(os.path.join(ROOT, p))]

    buf = []
    buf.append('# 朝暮 · 源码全览\n\n')
    buf.append(
        f'版本 {pubspec_version()} ｜ 共 {len(dart)} 个 dart 文件'
        f' + {len(extras)} 个配置文件 ｜ 生成于 {datetime.now().strftime("%Y-%m-%d %H:%M")}\n\n'
    )
    buf.append(
        '说明：按目录顺序拼接，每节标题是文件路径和行数。'
        '用于让 AI 一次读懂整个工程结构。**这份文件由 tool/gen_overview.py 生成，不要手改。**\n\n'
    )
    buf.append('---\n\n')

    for p in dart:
        buf.append(section(p, 'dart'))

    if extras:
        buf.append('---\n\n# 配置文件\n\n')
        for p in extras:
            lang = 'yaml' if p.endswith('.yaml') else (
                'kotlin' if p.endswith('.kt') else (
                    'cpp' if p.endswith('.cpp') else 'text'))
            buf.append(section(p, lang))

    text = ''.join(buf)
    io.open(out_path, 'w', encoding='utf-8').write(text)
    print(f'已写 {out_path}')
    print(f'{len(text.encode("utf-8"))} 字节 / {text.count(chr(10)) + 1} 行')
    print(f'dart {len(dart)} 个：{", ".join(dart[:5])} ...')
    print(f'配置 {len(extras)} 个')


if __name__ == '__main__':
    main()
