# -*- coding: utf-8 -*-
"""日历白屏诊断：构建/排布异常直接显示在页面上（release 可见）+ 无穷大防御"""
import io

P = r'D:\chaomu\lib\pages\calendar_page.dart'
s = io.open(P, 'r', encoding='utf-8').read()

pairs = [
    # 1. 主构建包 try/catch：构建期异常直接上屏
    (
        u"""      body: AnimatedBuilder(
        animation: st,
        builder: (BuildContext context, Widget? _) {
          final bool collapsed = st.calendarListCollapsed;""",
        u"""      body: AnimatedBuilder(
        animation: st,
        builder: (BuildContext context, Widget? _) {
          try {
            return _calBody(st);
          } catch (e) {
            return _calErrBox('日历页构建出错', e);
          }
        },
      ),
    );
  }

  /// 日历页主体（从 builder 抽出来，外面包 try/catch 做白屏诊断）
  Widget _calBody(AppState st) {
    {
          final bool collapsed = st.calendarListCollapsed;""",
        1,
    ),
    # 2. 收起态排布包 try/catch
    (
        u"""      child: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints cons) {
          final double cellW = cons.maxWidth / 7;
          final List<_Placed> placed = _layoutCollapsed(m, cellW);
          int rows = 0;
          for (final _Placed p in placed) {
            rows = math.max(rows, p.row + p.span);
          }
          return SizedBox(""",
        u"""      child: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints cons) {
          final double cellW = cons.maxWidth / 7;
          final List<_Placed> placed;
          int rows = 0;
          try {
            placed = _layoutCollapsed(m, cellW);
            for (final _Placed p in placed) {
              rows = math.max(rows, p.row + p.span);
            }
          } catch (e) {
            return _calErrBox('收起态排布出错', e);
          }
          return SizedBox(""",
        1,
    ),
    # 3. 展开态外层：无穷大防御 + try/catch
    (
        u"""    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints cons) {
        final double bodyH = cons.maxHeight;
        final double baseline = bodyH * 0.75;
        // 当日列表 + 输入栏 + 折叠行至少留 150，月历不能无限往下长
        final double cap = (bodyH - 150).clamp(200.0, double.infinity);
        final double unit = (baseline / _rowsOf(_month)).clamp(56.0, double.infinity);

        return Padding(""",
        u"""    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints cons) {
        try {
        // ⚠️ 白屏防御：万一从父级拿到无穷高（本不该发生），兜成 600 也能画出东西
        final double bodyH = cons.maxHeight.isFinite ? cons.maxHeight : 600.0;
        final double baseline = bodyH * 0.75;
        // 当日列表 + 输入栏 + 折叠行至少留 150，月历不能无限往下长
        final double cap = (bodyH - 150).clamp(200.0, double.infinity);
        final double unit = (baseline / _rowsOf(_month)).clamp(56.0, double.infinity);

        return Padding(""",
        1,
    ),
    # 4. 展开态内层 builder 包 try/catch
    (
        u"""          child: LayoutBuilder(
            builder: (BuildContext c2, BoxConstraints wCons) {
              final double cellW = wCons.maxWidth / 7;
              final (List<_Placed> placed, int rows) = _layoutExp(_month, cellW, unit);""",
        u"""          child: LayoutBuilder(
            builder: (BuildContext c2, BoxConstraints wCons) {
              final List<_Placed> placed;
              final int rows;
              try {
              final double cellW = wCons.maxWidth / 7;
              final (List<_Placed> placedTmp, int rowsTmp) = _layoutExp(_month, cellW, unit);
              placed = placedTmp;
              rows = rowsTmp;
              } catch (e) {
                return _calErrBox('展开态排布出错', e);
              }""",
        1,
    ),
    # 5. _expandedMonth 收尾：给 try 补 catch（在方法最后的 \");\n  }\" 前插）
    (
        u"""            },
          ),
        );
      },
    );
  }
}""",
        u"""            },
          ),
        );
        } catch (e) {
          return _calErrBox('展开态计算出错', e);
        }
      },
    );
  }

  /// 白屏诊断：任何构建 / 排布异常直接显示成红字（release 包也能看到）
  Widget _calErrBox(String where, Object e) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Text(
        '$where\\n\\n$e',
        style: const TextStyle(fontSize: 13, color: Color(0xFFA32D2D), height: 1.6),
      ),
    );
  }
}""",
        1,
    ),
]

for old, new, cnt in pairs:
    n = s.count(old)
    assert n == cnt, u'命中 %d(期望 %d): %s...' % (n, cnt, old[:60])
    s = s.replace(old, new)

io.open(P, 'w', encoding='utf-8', newline='').write(s)
print('OK 诊断补丁 5 处')
