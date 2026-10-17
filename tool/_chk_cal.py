import re, sys, pathlib

p = pathlib.Path(r'D:\chaomu\lib\pages\calendar_page.dart')
src = p.read_text(encoding='utf-8')

# 1) 括号 / 引号配平（跳过注释与字符串）
i, n = 0, len(src)
stack = []
line = 1
ok = True
while i < n:
    ch = src[i]
    if ch == '\n':
        line += 1; i += 1; continue
    if ch == '/' and i + 1 < n and src[i+1] == '/':
        while i < n and src[i] != '\n':
            i += 1
        continue
    if ch == '/' and i + 1 < n and src[i+1] == '*':
        i += 2
        while i + 1 < n and not (src[i] == '*' and src[i+1] == '/'):
            if src[i] == '\n':
                line += 1
            i += 1
        i += 2
        continue
    if ch in "'\"":
        q = ch
        j = i + 1
        while j < n:
            if src[j] == '\\':
                j += 2; continue
            if src[j] == q:
                break
            if src[j] == '\n':
                break
            j += 1
        i = j + 1
        continue
    if ch in '([{':
        stack.append((ch, line))
    elif ch in ')]}':
        if not stack:
            print(f'[FAIL] 第 {line} 行 多余的 {ch}')
            ok = False
        else:
            o, ol = stack.pop()
            if '([{'.index(o) != ')]}'.index(ch):
                print(f'[FAIL] 第 {line} 行 {ch} 与第 {ol} 行 {o} 不匹配')
                ok = False
    i += 1
if stack:
    for o, ol in stack:
        print(f'[FAIL] 第 {ol} 行 {o} 没闭合')
    ok = False
print('[OK] 括号配平' if ok else '[FAIL] 括号有问题')

# 2) 符号存在性
need = ['_todoColors', '_weekdayBg', '_weekdaySkip', '_todoIdx', '_todoWrapLines',
        '_todoFontSize', '_todoLineHeight', '_cellUnit', '_maxSpan', '_measure',
        '_layoutCollapsed', '_linesOf', '_Placed', '_showOf', '_rowsOf',
        '_monthGrid', '_dayCell', '_pageOfMonth', '_shiftMonth', '_toggleCollapsed']
for s in need:
    d = len(re.findall(r'(?:static\s+[\w<>,\s\[\]]*|const\s+|final\s+|Widget\s+|int\s+|double\s+|void\s+|List<\w+>\s+|\w+\s+)?' + re.escape(s) + r'\s*\(', src))
    c = src.count(s)
    flag = '[OK] ' if c > 0 else '[FAIL]'
    print(f'{flag} {s:<20} 出现 {c} 次')

# 3) 旧写法残留
bad = [
    (r'_todoColors\[\s*\(items\.indexOf', '旧的待办取色（未避让底色）'),
    (r'color:\s*isSel\s*\?\s*const Color\(0xFFE8F0F8\)\s*:\s*const Color\(0xFFFFFFFF\)',
     '旧的格子底色（没收起态星期色）'),
    (r'\$\{d\.day\}', '日期用了插值 —— 检查是否带前导零'),
]
for pat, desc in bad:
    hits = [(src[:m.start()].count('\n') + 1) for m in re.finditer(pat, src)]
    print(('[FAIL] 仍存在 ' if hits else '[OK] 已清除 ') + desc + (f' @行 {hits}' if hits else ''))

# 4) 关键行核对
for pat in ['_todoColors[_todoIdx(items, show[i], i, tint)]',
            'final int tint = isSel ? 1 : d.weekday;',
            'final Color cellBg = collapsed ? _weekdayBg[tint - 1] : const Color(0xFFFFFFFF);',
            'color: isSel ? const Color(0xFFE8F0F8) : cellBg,']:
    n_ = src.count(pat)
    print(('[OK] ' if n_ == 1 else f'[WARN x{n_}] ') + pat)
