#!/usr/bin/env python3
"""切页归因:用 runloop-events 找出每次切页的主线程忙区间,再把 Time Profiler 采样按调用栈归到组件。
用法:switch_profile.py <samples.tsv> <runloop.tsv> [routes=mcps,services,calls,settings,overview] [min_ms=50] [after_s=4.5]
routes 是 bench 里"真正发生切换"的页面顺序(从 overview 启动时第一次切到 overview 是空操作,不产生窗口)。
独占归类:从栈根往叶子找第一个命中"强组件"的帧;没有则找弱组件;再没有按优先级归到通用桶(任意帧命中)。
"""
import csv, re, sys
from collections import defaultdict, OrderedDict
from statistics import median
sys.path.insert(0, __import__("os").path.dirname(__file__))
from busy_windows import busy
csv.field_size_limit(10**9)

STRONG = [
    ("工具栏+搜索框(NSToolbar)", r"NSToolbar|ToolbarBridge|AppKitToolbar|ToolbarItem|ToolbarStrategy|AppKitSearch|NSSearch|NSTitlebar|updateToolbar"),
    ("Table/List(NSTableView)", r"NSTableView|NSTableRow|NSOutlineView|AppKitOutlineTable|SwiftUITable|TableCellHosting|TableColumn|ListCoreCoordinator|NSTableHeader"),
    ("Charts", r"@Charts$|Chart"),
    ("Form(.grouped)", r"GroupedForm|FormRow|FormStyle"),
    ("Toggle(NSSwitch)", r"NSSwitch|AppKitToggle"),
    ("Picker/分段(NSSegmented/NSPopUp)", r"NSSegment|NSPopUp|AppKitPicker"),
]
WEAK = [
    ("ScrollView(含 Form 的滚动容器)", r"NSScrollView|HostingScrollView|ScrollViewLayoutComputer|NSClipView"),
    ("分栏/侧边栏", r"NSSplitView|Sidebar"),
]
GENERIC = [  # 按优先级,任意帧命中即归入
    ("CG 软件光栅化/图层绘制(未归到控件)", r"CA::Layer::display_|CABackingStore|CGDisplayList|drawRect|ripc_|-\[CALayer _display\]|NSViewBackingLayer display"),
    ("销毁旧页面(dealloc/autorelease)", r"dealloc|__deallocating_deinit|objc_autoreleasePoolPop|_finalize\]|removeFromSuperview"),
    ("挂载 AppKit 视图(addSubview/keyViewLoop/_setWindow)", r"_AppKitAddSubview|swiftui_addManagedSubview|_setSuperview|addSubview|KeyViewLoop|viewDidMoveTo|_setWindow"),
    ("SwiftUI 求值/布局(body、sizeThatFits、DisplayList)", r"AG::Graph::UpdateStack|AGGraph|ViewGraph|GraphHost|sizeThatFits|DynamicBody|DisplayList\.ViewUpdater|NSHostingView"),
    ("CA 提交其余", r"CA::Transaction::commit"),
    ("AppKit 布局/约束其余", r"_layoutSubtree|updateConstraints|NSISEngine|@CoreAutoLayout$"),
]
MARKERS = [
    ("bench 强制同步阶段(layoutSubtreeIfNeeded+displayIfNeeded)", r"Snapshotter"),
    ("随后的 runloop 收尾(CA::Transaction::commit,不在 bench 计时内)", r"CA::Transaction::commit"),
    ("工具栏(任意帧)", STRONG[0][1]),
    ("其中 搜索框", r"AppKitSearch|NSSearch|SearchPlacement"),
    ("其中 工具栏里的分段 Picker", None),  # 特判:同时命中工具栏和 NSSegment
    ("Table/List(任意帧)", STRONG[1][1]),
    ("其中 自动行高测量", r"utomaticRowHeight|noteHeightOfRows|didUpdateIdealHeight"),
    ("其中 建行/建单元格", r"_addRowViewForVisibleRow|makeViewForTableColumn|viewFor:item"),
    ("Toggle/NSSwitch(任意帧)", STRONG[4][1]),
    ("分段/弹出按钮(任意帧)", STRONG[5][1]),
    ("Form(.grouped) 布局(任意帧)", STRONG[3][1]),
    ("Charts(任意帧)", STRONG[2][1]),
    ("ScrollView(任意帧)", WEAK[0][1]),
    ("文字排版 CoreText(任意帧)", r"@CoreText$|NSCoreTypesetter|CTLine"),
    ("SF Symbol 图像(任意帧)", r"VectorGlyph|CUICatalog"),
    ("毛玻璃/VisualEffect(任意帧)", r"NSVisualEffect|GlassEffect|NSGlass"),
    ("绘制(CG/CA display,任意帧)", GENERIC[0][1]),
    ("销毁旧页面(任意帧)", GENERIC[1][1]),
]
C = lambda lst: [(n, re.compile(p) if p else None) for n, p in lst]
STRONG, WEAK, GENERIC, MARKERS = C(STRONG), C(WEAK), C(GENERIC), C(MARKERS)
_cache = {}

def classify(stack):
    if stack in _cache: return _cache[stack]
    frames = stack.split("|")
    excl = None
    for group in (STRONG, WEAK):
        for f in reversed(frames):  # 根 → 叶
            for name, rx in group:
                if rx.search(f): excl = name; break
            if excl: break
        if excl: break
    if not excl:
        for name, rx in GENERIC:
            if any(rx.search(f) for f in frames): excl = name; break
    marks = set()
    for name, rx in MARKERS:
        if rx and any(rx.search(f) for f in frames): marks.add(name)
    if "工具栏(任意帧)" in marks and any(STRONG[5][1].search(f) for f in frames):
        marks.add("其中 工具栏里的分段 Picker")
    _cache[stack] = (excl or "其他", marks)
    return _cache[stack]

def main():
    samples, runloop = sys.argv[1], sys.argv[2]
    routes = (sys.argv[3] if len(sys.argv) > 3 else "mcps,services,calls,settings,overview").split(",")
    min_ms = float(sys.argv[4]) if len(sys.argv) > 4 else 50.0
    after = float(sys.argv[5]) if len(sys.argv) > 5 else 4.5
    raw = busy(runloop, 20.0, after)
    merged = []
    for s, e in raw:  # 间隔 <5ms 的相邻忙区间并成一次
        if merged and s - merged[-1][1] < 5e6: merged[-1][1] = e
        else: merged.append([s, e])
    wins = [(s, e) for s, e in merged if (e - s) / 1e6 >= min_ms]
    print(f"# 切页窗口 {len(wins)} 个(主线程忙区间 ≥{min_ms:.0f}ms,{after}s 之后)")
    per_route = defaultdict(list)
    for i, (s, e) in enumerate(wins):
        r = routes[i % len(routes)]
        per_route[r].append((s, e))
        print(f"  {i+1:2d} {r:9s} start={s/1e9:7.3f}s  busy={(e-s)/1e6:5.0f}ms")
    excl = {r: defaultdict(float) for r in routes}
    mark = {r: defaultdict(float) for r in routes}
    tot = defaultdict(float)
    flat = [(s, e, r) for r, ws in per_route.items() for s, e in ws]
    for row in csv.DictReader(open(samples, encoding="utf-8"), delimiter="\t"):
        if not row["thread"].startswith("Main Thread"): continue
        t = int(row["time"])
        for s, e, r in flat:
            if s <= t <= e:
                w = int(row["weight"]) / 1e6
                c, ms = classify(row["stack"])
                excl[r][c] += w; tot[r] += w
                for m in ms: mark[r][m] += w
                break
    for r in routes:
        n = len(per_route[r]) or 1
        durs = [(e - s) / 1e6 for s, e in per_route[r]]
        print(f"\n## {r}:{len(durs)} 次,忙区间 {' '.join(f'{d:.0f}' for d in durs)} ms,中位数 {median(durs) if durs else 0:.0f} ms;采样 {tot[r]/n:.0f} ms/次")
        print("| 独占归类 | ms/次 | 占比 |\n|---|---:|---:|")
        for c, w in sorted(excl[r].items(), key=lambda x: -x[1]):
            print(f"| {c} | {w/n:.0f} | {100*w/tot[r]:.0f}% |")
        print("\n| 包含标记(可重叠) | ms/次 | 占比 |\n|---|---:|---:|")
        for name, _ in MARKERS:
            w = mark[r].get(name, 0)
            if w: print(f"| {name} | {w/n:.0f} | {100*w/tot[r]:.0f}% |")

if __name__ == "__main__":
    main()
