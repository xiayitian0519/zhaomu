"""一次性：把 lib/updates.dart 里手写的 15 条文案，按版本写回 CHANGELOG.md 的
「### 更新摘要」段。跑完这个脚本，CHANGELOG 就成为更新弹窗文案的唯一来源。
"""
import io
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHANGELOG = os.path.join(ROOT, 'CHANGELOG.md')
UPDATES = os.path.join(ROOT, 'lib', 'updates.dart')

src = io.open(UPDATES, encoding='utf-8').read()

# 抓 AppUpdate('2.20.1', '2026-10-24', <String>[ ... ]),
pattern = re.compile(
    r"AppUpdate\('([0-9.]+)',\s*'([0-9-]+)',\s*<String>\[(.*?)\]\)",
    re.S,
)
manual = {}
for m in pattern.finditer(src):
    ver, date, body = m.group(1), m.group(2), m.group(3)
    items = re.findall(r"'((?:[^'\\]|\\.)*)'", body)
    items = [i.replace("\\'", "'") for i in items]
    if items:
        manual[ver] = items

print(f'从 updates.dart 抽到 {len(manual)} 个版本：' + ' / '.join(manual.keys()))

text = io.open(CHANGELOG, encoding='utf-8').read()
lines = text.splitlines()

# 找每个版本的起始行和结束行
headers = []
for i, ln in enumerate(lines):
    m = re.match(r'^## ([0-9]+\.[0-9]+\.[0-9]+)', ln)
    if m:
        headers.append((i, m.group(1)))

inserted = []
out = []
for idx, (start, ver) in enumerate(headers):
    end = headers[idx + 1][0] if idx + 1 < len(headers) else len(lines)
    block = lines[start:end]

    if ver not in manual:
        out.extend(block)
        continue

    # 已经写过摘要就跳过
    if any(l.strip() == '### 更新摘要' for l in block):
        out.extend(block)
        continue

    # 插在版本标题下面的空行之后
    out.append(block[0])
    out.append('')
    out.append('### 更新摘要')
    out.append('')
    for it in manual[ver]:
        out.append(f'- {it}')
    out.append('')
    # 原块剩余部分（跳过紧跟标题的空行，避免双空行）
    rest = block[1:]
    while rest and rest[0].strip() == '':
        rest.pop(0)
    out.extend(rest)

    # 处理版本之间的分隔
    out.append('')
    inserted.append(ver)

# 修掉可能出现的三连空行
cleaned = []
for ln in out:
    if ln == '' and cleaned and cleaned[-1] == '' and len(cleaned) > 1 and cleaned[-2] == '':
        continue
    cleaned.append(ln)

io.open(CHANGELOG, 'w', encoding='utf-8').write('\n'.join(cleaned) + '\n')
print(f'已写入摘要段的版本 {len(inserted)} 个：' + ' / '.join(inserted))
print('CHANGELOG 现在', os.path.getsize(CHANGELOG), '字节')
