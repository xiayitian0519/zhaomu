# -*- coding: utf-8 -*-
"""升版本 2.7.12+6 -> 2.8.0+8（加功能升次版本）+ 追加 CHANGELOG"""
import io

PUB = r'D:\chaomu\pubspec.yaml'
LOG = r'D:\chaomu\CHANGELOG.md'

# ---- pubspec ----
with io.open(PUB, 'r', encoding='utf-8') as f:
    pub = f.read()
old_v = 'version: 2.7.12+6'
new_v = 'version: 2.8.0+8'
assert pub.count(old_v) == 1, 'pubspec 版本行不是唯一命中: %d' % pub.count(old_v)
with io.open(PUB, 'w', encoding='utf-8', newline='') as f:
    f.write(pub.replace(old_v, new_v))
print('pubspec: %s -> %s' % (old_v, new_v))

# ---- changelog：插在第一条 '---' 之后 ----
entry = u"""---

## 2.8.0+8 — 2026-10-16

### 新增

1. **主列表按月份分组**（不再按「今天/以后」）
   - 顺序：逾期（红）→ 各个月份（`2026年10月`…，本月蓝字）→ 未定日期
   - 每条待办下面显示截止日期；逾期的那条显示 `10月12日 · 逾期 4 天`（红字）
   - 带时刻的末尾补 `18:00`；不带时刻也照样显示日期
2. **「今天」独立小卡片**：本月组里今天的待办先单独成卡（浅蓝标题「今天 · 10月16日」），卡片后空一行再接本月其余
3. **详情页截止/提醒改版**：合成一张卡两行（左侧 3px 蓝竖条），点开底部胶囊面板
   - 截止面板：今天/明天/后天/下周一/月底 + 09:00/12:00/18:00/21:00 快捷胶囊，也可跳完整选择器
   - 提醒面板：提前量胶囊（跟随设置/提前1小时/30分/10分/到点/自定义/不提醒）+ 实时显示「会在 X 提醒你」+ 铃声行（带试听，不提醒时整行灰掉）
4. **「不提醒」开关**（新字段 `remindOff`）：关掉后连「截止带时刻」的兜底提醒也不响
5. **提醒默认提前 1 小时**（新装/没改过的存档；老存档保持原值不迁移）
6. **优先级 2×2 方阵**：每行两个，「不重要但紧急」在左下
7. **日历页当日列表**：带时刻的待办补一行时刻，没时刻不加

### 改进

1. **「清单」功能删除**（备注可顶替）：界面入口全删；数据层字段保留只为读老存档
2. **重复的「不重复」显示为「仅今天」**：存储值不变（老存档直接存 `'无'`），只换显示文案；每天/每周/每月/每年选项保留
3. 设置页和详情页的提前量文案统一走 `aheadLabel`（整小时说「1 小时」不说「60 分钟」）

"""
with io.open(LOG, 'r', encoding='utf-8') as f:
    log = f.read()
anchor = u'---\n\n## 2.7.12+6'
assert log.count(anchor) == 1, 'changelog 锚点不是唯一命中: %d' % log.count(anchor)
head, tail = log.split(anchor, 1)
# entry 自带开头的 '---'，去掉 anchor 里的 '---' 防重复
new_log = head + entry + u'## 2.7.12+6' + tail
with io.open(LOG, 'w', encoding='utf-8', newline='') as f:
    f.write(new_log)
print('changelog: 2.8.0+8 条目已插入')
print('DONE')
