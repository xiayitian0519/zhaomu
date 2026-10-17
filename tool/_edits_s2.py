# -*- coding: utf-8 -*-
"""朝暮 2.7.13 第 2 批：home_page.dart（日期行 / 今日卡片 / 空行）、calendar_page.dart（当日列表补时刻）。"""
import sys, pathlib

EDITS = []


def add(path, old, new, count=1):
    EDITS.append((path, old, new, count))


H = r'D:\chaomu\lib\pages\home_page.dart'
C = r'D:\chaomu\lib\pages\calendar_page.dart'

# ---------- home_page.dart：列表第二行 ----------
add(H, """                    if (t.dueHasTime && t.due != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          '${relativeDayLabel(t.due!)} ${timeLabel(t.due!)}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF9A9A9A)),
                        ),
                      )
                    else if (t.remind != null)""", """                    // 只要设了截止就一定出这行日期（带不带时刻都出）——
                    // 用户 2026-10-16：「不带具体时刻也要显示日期」。
                    // 逾期那几条的日期行用红字。
                    if (t.due != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          listDueLabel(t.due!, t.dueHasTime),
                          style: TextStyle(
                            fontSize: 12,
                            color: t.done
                                ? const Color(0xFFB8B8B8)
                                : (dayOf(t.due!).isBefore(dayOf(DateTime.now()))
                                    ? const Color(0xFFA32D2D)
                                    : const Color(0xFF9A9A9A)),
                          ),
                        ),
                      )
                    else if (t.remind != null)""")

# ---------- home_page.dart：今日小卡片 ----------
add(H, "  Widget _tile(Todo t) {", """  /// 本月组里的「今日」小卡片（2026-10-16 用户选的方案 C）。
  ///
  /// 独立圆角卡片 + 自己的小标题，把今天的待办从本月其余里拎出来。
  /// 卡片后面由调用方补一个 [SizedBox] 当"空一行"。
  Widget _todayCard(String title, List<Todo> items) => Container(
        margin: const EdgeInsets.fromLTRB(10, 4, 10, 0),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFB5D4F4)),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: double.infinity,
              color: const Color(0xFFE8F0F8),
              padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF185FA5),
                ),
              ),
            ),
            for (final Todo t in items) _tile(t),
          ],
        ),
      );

  Widget _tile(Todo t) {""")

# ---------- home_page.dart：渲染循环 ----------
add(H, """            first = false;
            for (final Todo t in g.items) {
              children.add(_tile(t));
            }""", """            first = false;
            // 本月组：先画「今日」小卡片，空一行，再画本月其余
            final List<Todo>? pin = g.pinItems;
            if (pin != null && pin.isNotEmpty) {
              children.add(_todayCard(g.pinTitle ?? '今天', pin));
              children.add(const SizedBox(height: 10));
            }
            for (final Todo t in g.items) {
              children.add(_tile(t));
            }""")

# ---------- calendar_page.dart：当日列表补时刻 ----------
add(C, """            Expanded(
              child: Text(
                t.title,
                style: TextStyle(
                  fontSize: 15,
                  color: t.done ? const Color(0xFF9A9A9A) : const Color(0xFF1F1F1F),
                  decoration: (t.done && !st.noStrike)
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  decorationColor: const Color(0xFF9A9A9A),
                ),
              ),
            ),""", """            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    t.title,
                    style: TextStyle(
                      fontSize: 15,
                      color: t.done ? const Color(0xFF9A9A9A) : const Color(0xFF1F1F1F),
                      decoration: (t.done && !st.noStrike)
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      decorationColor: const Color(0xFF9A9A9A),
                    ),
                  ),
                  // 这一页本身就是某一天，所以不重复显示日期；
                  // 只在截止带了具体时刻时补一行时刻，没时刻就什么都不加
                  // （用户 2026-10-16 定的）。
                  if (t.dueHasTime && t.due != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        timeLabel(t.due!),
                        style: TextStyle(
                          fontSize: 12,
                          color: t.done
                              ? const Color(0xFFB8B8B8)
                              : const Color(0xFF9A9A9A),
                        ),
                      ),
                    ),
                ],
              ),
            ),""")


def main():
    bad = 0
    for path, old, new, count in EDITS:
        p = pathlib.Path(path)
        src = p.read_text(encoding='utf-8')
        n = src.count(old)
        if n != count:
            print(f'[FAIL] {p.name}: 期望命中 {count} 次，实际 {n} 次')
            print(f'       原文前 70 字：{old[:70]!r}')
            bad += 1
            continue
        src = src.replace(old, new, count)
        p.write_text(src, encoding='utf-8')
        print(f'[OK]   {p.name}: 替换 {n} 处 <- {old.strip().splitlines()[0][:48]!r}')

    if bad:
        print(f'\n共 {bad} 处未通过，已中止。')
        sys.exit(1)

    # 前置依赖核对：这两个页面都得能看到 dayOf / timeLabel / listDueLabel
    for name in ('home_page.dart', 'calendar_page.dart'):
        s = pathlib.Path(r'D:\chaomu\lib\pages', name).read_text(encoding='utf-8')
        hit = [k for k in ('dayOf(', 'timeLabel(', 'listDueLabel(') if k in s]
        imp = "import '../models.dart';" in s
        print(f'[检查] {name}: 用到 {hit} / import models = {imp}')
    print(f'\n全部 {len(EDITS)} 处替换完成。')


main()
