# -*- coding: utf-8 -*-
"""象限盘简化 + 鲜艳色板 + 优先级方案C 批量改动"""
import io

def load(p): return io.open(p, 'r', encoding='utf-8').read()
def save(p, s): io.open(p, 'w', encoding='utf-8', newline='').write(s)
def apply(path, pairs):
    s = load(path)
    for old, new, cnt in pairs:
        n = s.count(old)
        assert n == cnt, '%s 命中 %d(期望 %d): %s...' % (path, n, cnt, old[:60])
        s = s.replace(old, new)
    save(path, s)
    print('OK %s' % path.split('\\')[-1])

# ---------------- 1. widgets.dart 象限盘简化 + PriorityBar 加粗 ----------------
W = r'D:\chaomu\lib\widgets.dart'
apply(W, [
    # 删顶部提示
    (u"""          Positioned(
            left: 0,
            right: 0,
            top: (r.top - 52).clamp(24.0, double.infinity).toDouble(),
            child: const Center(
              child: Text(
                '给这条待办打优先级',
                style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
""", u"", 1),
    # 删底部提示
    (u"""          Positioned(
            left: 0,
            right: 0,
            top: r.bottom + 24,
            child: const Center(
              child: Text(
                '滑到象限内松手打标 · 松手在盘外取消',
                style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 13),
              ),
            ),
          ),
""", u"", 1),
    # 删常驻细白线，保留滑动选中的白粗框反馈
    (u"""        decoration: BoxDecoration(
          color: st.colorOf(q),
          border: Border.all(
            color: on ? const Color(0xFFFFFFFF) : const Color(0x40FFFFFF),
            width: on ? 4 : 1,
          ),
        ),""",
     u"""        decoration: BoxDecoration(
          color: st.colorOf(q),
          // 常驻细白线已删（2026-10-17 用户要求）；滑到哪格哪格闪白粗框，是选中反馈
          border: on ? Border.all(color: const Color(0xFFFFFFFF), width: 4) : null,
        ),""", 1),
    # PriorityBar 加粗（方案 C 配套，全局统一）
    (u"""      width: 4,
      height: 24,
      decoration: BoxDecoration(
        color: none ? const Color(0xFFE0E0E0) : AppState.I.colorOf(priority),
        borderRadius: BorderRadius.circular(2),
      ),""",
     u"""      width: 6,
      height: 32,
      decoration: BoxDecoration(
        color: none ? const Color(0xFFE0E0E0) : AppState.I.colorOf(priority),
        borderRadius: BorderRadius.circular(3),
      ),""", 1),
])

# ---------------- 2. settings_page.dart 鲜艳色板 ----------------
S = r'D:\chaomu\lib\pages\settings_page.dart'
apply(S, [
    (u"""  static const List<int> _palette = <int>[""",
     u"""  /// 鲜艳色板（2026-10-17 用户要求加一组更鲜艳的，原 12 色保留）
  static const List<int> _paletteVivid = <int>[
    0xFFFF3B30,
    0xFFFF6B00,
    0xFFFFC300,
    0xFF2ECC40,
    0xFF00C8A0,
    0xFF00A8E8,
    0xFF3D5AFE,
    0xFF9C27B0,
    0xFFF5008D,
  ];

  static const List<int> _palette = <int>[""", 1),
    (u"""        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _palette
              .map(
                (int v) => GestureDetector(
                  onTap: () => Navigator.of(c).pop(v),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(v),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: v == current ? const Color(0xFF2B2B2B) : const Color(0x22000000),
                        width: v == current ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),""",
     u"""        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('鲜艳', style: TextStyle(fontSize: 12, color: Color(0xFF9A9A9A))),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 12, children: _swatches(c, _paletteVivid, current)),
              const SizedBox(height: 14),
              const Text('原有', style: TextStyle(fontSize: 12, color: Color(0xFF9A9A9A))),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 12, children: _swatches(c, _palette, current)),
            ],
          ),
        ),""", 1),
    (u"""  Future<void> _pickQuadrantColor(BuildContext context, int index) async {""",
     u"""  /// 一排色圆（点哪个选哪个）
  List<Widget> _swatches(BuildContext c, List<int> colors, int current) {
    return colors
        .map(
          (int v) => GestureDetector(
            onTap: () => Navigator.of(c).pop(v),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Color(v),
                shape: BoxShape.circle,
                border: Border.all(
                  color: v == current ? const Color(0xFF2B2B2B) : const Color(0x22000000),
                  width: v == current ? 3 : 1,
                ),
              ),
            ),
          ),
        )
        .toList();
  }

  Future<void> _pickQuadrantColor(BuildContext context, int index) async {""", 1),
])

# ---------------- 3. home_page.dart 优先级方案 C：整行浅色底 ----------------
H = r'D:\chaomu\lib\pages\home_page.dart'
apply(H, [
    (u"""        child: Container(
          color: t.done ? const Color(0xFFF4F4F5) : const Color(0xFFFFFFFF),""",
     u"""        child: Container(
          // 方案 C（2026-10-17 用户拍板）：已标优先级的整行染象限色浅底，色条配 6px 粗
          color: t.done
              ? const Color(0xFFF4F4F5)
              : (t.priority >= 0
                  ? st.colorOf(t.priority).withOpacity(0.08)
                  : const Color(0xFFFFFFFF)),""", 1),
])

print('ALL DONE')
